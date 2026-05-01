import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audio_obs.dart';
import 'native_audio_service.dart';
import 'p2p_service.dart';
import 'sync_service.dart';
import 'sync_measurement_logger.dart';

// ── drift / seek 파라미터 (PoC Phase 4 검증 완료) ──────────────
const double _driftSeekThresholdMs = 20.0;
const double _seekCorrectionGain = 0.8;
const Duration _seekCooldown = Duration(milliseconds: 1000);
const double _defaultFramesPerMs = 48.0; // fallback (실제 sampleRate 미확인 시)
const double _reAnchorThresholdMs = 200.0;
const double _offsetDriftThresholdMs = 5.0; // 앵커 후 offset 변화 허용치
// ── v0.0.24: drift 노이즈 완화 ──────────────────────────────
// 단일 ts 샘플로 seek 판단하면 순간 노이즈에 불필요 seek 발생.
// 최근 N개 샘플 중앙값으로 판단하되, 큰 drift(re-anchor 임계)는 즉시 처리.
const int _driftMedianWindow = 5;        // ~500ms (poll 100ms 기준)
// B(200ms) 롤백: 파일 선택창 등 paused 복귀 시 heartbeat Timer와 경쟁하며 끊김 유발 의심.
// 500ms 유지로 원상복구 후 재현 여부 확인. 재현 안 되면 B가 원인, 재현 시 C/A 의심.
const double _obsBroadcastIntervalMs = 500.0;
// v0.0.47: NTP-style 예약 재생 buffer (ms). 호스트 syncPlay/syncSeek 시점부터 양쪽
// 동시 출력 시작까지의 여유. broadcast RTT(~10~20ms) + 메시지 처리 + native 예약 등록 +
// stream 시작 latency(저가형 oboe ~100~수백ms 가능) + 마진. 200ms은 일반 LAN에서 안전.
// 사용자 체감 "버튼 누르고 잠깐 후 재생"이지만 음악 동기 앱 특성상 무시 수준.
const int _scheduleBufferMs = 200;

/// v3 오디오 동기화 서비스.
/// 호스트: 네이티브 엔진 재생 + audio-obs broadcast + HTTP 파일 서빙.
/// 게스트: 파일 다운로드 + 네이티브 엔진 재생 + drift 계산 + seek 보정.
class NativeAudioSyncService {
  final P2PService _p2p;
  final SyncService _sync;
  final NativeAudioService _engine = NativeAudioService();
  final SyncMeasurementLogger _logger = SyncMeasurementLogger();

  StreamSubscription? _messageSub;
  Timer? _obsBroadcastTimer;
  StreamSubscription? _timestampSub;
  HttpServer? _httpServer;

  bool _isHost = false;
  bool _playing = false;
  bool _audioReady = false;
  bool _isLoading = false;
  bool _downloadAborted = false;
  String? _currentFileName;
  String? _storedSafeName;
  String? _currentUrl;
  int _obsBroadcastSeq = 0;

  /// 게스트: 현재 다운로드 세션 ID. 새 audio-url마다 증가, 이전 다운로드 무효화용.
  int _downloadSessionId = 0;
  /// 게스트: 진행 중인 HttpClient (취소용)
  HttpClient? _activeHttpClient;

  // ── 게스트: drift report 전송 주기 ────────────────────────
  int _lastDriftReportMs = 0;

  // ── 게스트: drift 보정 상태 ────────────────────────────────
  AudioObs? _latestObs;
  // 앵커: drift=0 기준선
  int? _anchorHostFrame;
  int? _anchorGuestFrame;
  double? _offsetAtAnchor; // 앵커 설정 시점의 filteredOffsetMs
  // v0.0.38: 앵커 설정 시점의 outputLatency 비대칭(게스트-호스트, ms).
  // anchor의 콘텐츠 정렬 seek에 이 값을 베이크인 → framePos 기준 drift는 0
  // 으로 시작. 이후 _recomputeDrift는 (현재 - 앵커) 변화분만 보정.
  double _anchoredOutLatDeltaMs = 0;
  // 최신 drift
  double? _latestDriftMs;
  // v0.0.24: 최근 drift 샘플 윈도우 (중앙값 기반 seek 판단용)
  final List<double> _driftSamples = [];
  // 누적 seek 보정 (HAL framePos는 seek 영향 없음 → accum으로 복원)
  int _seekCorrectionAccum = 0;
  int _seekCount = 0;
  int _seekCooldownUntilMs = 0;

  // ── seek 후 position 점프 방지 ──────────────────────────────
  // seek 직후 폴링이 아직 이전 위치를 반환 → UI에 순간 점프 발생.
  // seek 시 즉시 target position을 emit하고, 일정 시간 폴링 position을 무시.
  Duration? _seekOverridePosition;
  Timer? _seekOverrideTimer;

  // ── UI 스트림 ─────────────────────────────────────────────
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  Duration? _currentDuration;
  final _playingController = StreamController<bool>.broadcast();
  final _loadingController = StreamController<bool>.broadcast();
  final _downloadProgressController = StreamController<double>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Duration? get currentDuration => _currentDuration;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<bool> get loadingStream => _loadingController.stream;
  /// 다운로드 진행률 (0.0 ~ 1.0). 호스트는 emit 없음.
  Stream<double> get downloadProgressStream =>
      _downloadProgressController.stream;
  Stream<String> get errorStream => _errorController.stream;

  String? get currentFileName => _currentFileName;
  bool get playing => _playing;
  bool get isLoading => _isLoading;
  double? get latestDriftMs => _latestDriftMs;
  int get seekCount => _seekCount;
  NativeAudioService get engine => _engine;

  /// 현재 파일의 frames/ms (실제 sampleRate 기반, 미확인 시 48.0 fallback)
  double get _framesPerMs {
    final sr = _engine.latest?.sampleRate ?? 0;
    return sr > 0 ? sr / 1000.0 : _defaultFramesPerMs;
  }

  NativeAudioSyncService(this._p2p, this._sync);

  // ═══════════════════════════════════════════════════════════
  // 초기화
  // ═══════════════════════════════════════════════════════════

  /// 측정 로그 파일 경로 (호스트 전용).
  String? get measurementLogPath => _logger.logFilePath;

  Future<void> startListening({required bool isHost}) async {
    _isHost = isHost;
    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen(_onMessage);

    // 이전 세션의 잔여 temp 파일 정리 (호스트: audio_*, 게스트: dl_*)
    await _cleanupTempDir();

    if (isHost) {
      await _logger.start();
    }
  }

  Future<void> _onMessage(Map<String, dynamic> message) async {
    try {
      final type = message['type'];
      if (type == 'audio-obs' && !_isHost) {
        _handleAudioObs(message);
      } else if (type == 'audio-url' && !_isHost) {
        await _handleAudioUrl(message['data']);
      } else if (type == 'seek-notify' && !_isHost) {
        _handleSeekNotify(message);
      } else if (type == 'schedule-play' && !_isHost) {
        await _handleSchedulePlay(message['data']);
      } else if (type == 'schedule-pause' && !_isHost) {
        await _handleSchedulePause(message['data']);
      } else if (type == 'audio-request' && _isHost) {
        _handleAudioRequest(message['_from']);
      } else if (type == 'state-request' && _isHost) {
        _handleStateRequest(message['_from']);
      } else if (type == 'drift-report' && _isHost) {
        _handleDriftReport(message);
      } else if (type == 'download-report' && _isHost) {
        _handleDownloadReport(message);
      }
    } catch (e) {
      debugPrint('Error handling message ${message['type']}: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: HTTP 파일 서버
  // ═══════════════════════════════════════════════════════════

  Future<String?> _startFileServer(String dirPath, String fileName) async {
    await _stopFileServer();
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 41236);
    } catch (_) {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    // chunked transfer encoding 회피를 위해 매 요청에서 Content-Length를 설정하고
    // bufferOutput=false로 TCP 패킷 즉시 flush. 256KB 청크로 직접 raw write.
    _httpServer!.listen(
      (request) => _serveFile(request, dirPath),
      onError: (e) => debugPrint('HTTP server error: $e'),
    );
    final ip = await _getLocalIP();
    if (ip == null) {
      await _stopFileServer();
      return null;
    }
    final encodedName = Uri.encodeComponent(fileName);
    return 'http://$ip:${_httpServer!.port}/$encodedName';
  }

  static const int _fileServerChunkSize = 1024 * 1024; // 1MB

  Future<void> _serveFile(HttpRequest request, String dirPath) async {
    try {
      if (request.uri.pathSegments.isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final name = Uri.decodeComponent(request.uri.pathSegments.last);
      // 디렉토리 이탈 방지
      if (name.contains('/') || name.contains('..')) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final file = File('$dirPath/$name');
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final length = await file.length();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('application', 'octet-stream')
        ..headers.contentLength = length;
      final raf = await file.open();
      try {
        final buffer = Uint8List(_fileServerChunkSize);
        int offset = 0;
        while (offset < length) {
          final toRead = (length - offset) < _fileServerChunkSize
              ? length - offset
              : _fileServerChunkSize;
          final read = await raf.readInto(buffer, 0, toRead);
          if (read <= 0) break;
          // 매 청크마다 새 Uint8List로 복사 (버퍼 재사용에 따른 race 방지)
          request.response.add(Uint8List.fromList(
            read == buffer.length ? buffer : buffer.sublist(0, read),
          ));
          offset += read;
        }
      } finally {
        await raf.close();
      }
      await request.response.close();
    } catch (e) {
      debugPrint('HTTP serve error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _stopFileServer() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  /// WiFi IP 조회. NetworkInterface.list()에서 WiFi 인터페이스명(wlan/en) + 사설 IP 우선.
  static Future<String?> _getLocalIP() async {
    try {
      String? privateAddr;
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final name = iface.name.toLowerCase();
          if (name.startsWith('wlan') || name.startsWith('en')) {
            if (_isPrivateIP(addr.address)) return addr.address;
          }
          if (privateAddr == null && _isPrivateIP(addr.address)) {
            privateAddr = addr.address;
          }
        }
      }
      return privateAddr;
    } catch (_) {}
    return null;
  }

  /// 사설 IP 대역 확인 (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
  static bool _isPrivateIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: 파일 로드
  // ═══════════════════════════════════════════════════════════

  String _safeFileName(String original) {
    final dotIndex = original.lastIndexOf('.');
    final ext = (dotIndex >= 0 && dotIndex < original.length - 1)
        ? original.substring(dotIndex)
        : '';
    final bytes = original.codeUnits;
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    return 'audio_${hash.toRadixString(16)}${ext.toLowerCase()}';
  }

  Future<void> loadFile(File file) async {
    final originalName = file.uri.pathSegments.last;
    final safeName = _safeFileName(originalName);

    // 이전 재생 상태 정리 + UI 리셋
    if (_playing) {
      _playing = false;
      _playingController.add(false);
      await _engine.stop();
      _stopObsBroadcast();
    }
    _positionController.add(Duration.zero);
    _currentDuration = null;
    _durationController.add(null);

    _audioReady = false;
    _currentFileName = originalName;
    _isLoading = true;
    _loadingController.add(true);

    // UI 프레임이 로딩 인디케이터를 렌더링할 시간 확보.
    // 없으면 네이티브 디코딩이 즉시 시작되어 화면이 멈춘 것처럼 보임.
    await Future.delayed(Duration.zero);

    final tempDir = await getTemporaryDirectory();

    // 이전 파일 삭제
    if (_storedSafeName != null && _storedSafeName != safeName) {
      final old = File('${tempDir.path}/$_storedSafeName');
      if (await old.exists()) await old.delete();
    }

    final stableFile = File('${tempDir.path}/$safeName');
    // rename(이동)은 같은 파일시스템이면 즉시 완료 + 추가 용량 0.
    // 다른 파일시스템이면 fallback으로 copy.
    try {
      await file.rename(stableFile.path);
    } on FileSystemException {
      await file.copy(stableFile.path);
    }

    // HTTP 서버 시작
    final httpUrl = await _startFileServer(tempDir.path, safeName);
    if (httpUrl == null) {
      _isLoading = false;
      _loadingController.add(false);
      _errorController.add('WiFi IP를 가져올 수 없습니다');
      return;
    }

    // 네이티브 엔진에 로드
    LoadResult loadResult;
    final sw = Stopwatch()..start();
    try {
      loadResult = await _engine.loadFile(stableFile.path);
    } on PlatformException catch (e) {
      _isLoading = false;
      _loadingController.add(false);
      _errorController.add(NativeAudioService.errorToMessage(e.message ?? ''));
      return;
    }
    sw.stop();
    debugPrint('[DECODE-HOST] loadFile took ${sw.elapsedMilliseconds}ms');
    if (!loadResult.ok) {
      _isLoading = false;
      _loadingController.add(false);
      _errorController.add('파일 로드 실패');
      return;
    }

    // loadFile 반환값에서 duration 즉시 계산 (iOS: 반환값 포함, Android: getTimestamp fallback)
    _setDurationFromLoadResult(loadResult);

    _storedSafeName = safeName;
    _currentFileName = originalName;
    final urlWithCacheBust =
        '$httpUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    _currentUrl = urlWithCacheBust;
    _audioReady = true;
    _isLoading = false;
    _loadingController.add(false);

    // 게스트에게 URL 전달
    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {
        'url': urlWithCacheBust,
        'playing': _playing,
        'fileName': originalName,
      },
    });

    // 엔진 폴링 시작 (UI position 업데이트용)
    _engine.startPolling();
    _startTimestampWatch();

    await _resolveDurationFromTimestampIfNeeded();
    // v0.0.44 prewarm 호출 제거 (v0.0.45 롤백): prewarm으로 호스트·게스트 양쪽
    // framePos가 hardware sample 누적값으로 어긋나 anchor establishment 식이 깨짐
    // → 곡 전체에 걸쳐 ±5~7ms 게스트 앞섬 회귀. v0.0.43 baseline 회복.
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: 재생 제어
  // ═══════════════════════════════════════════════════════════

  Future<void> syncPlay() async {
    if (!_audioReady) return;

    // 재생 완료 상태에서 play → 처음으로 되돌리기
    var ts = _engine.latest;
    var vf = await _engine.getVirtualFrame();
    final sr = ts?.sampleRate ?? 0;
    if (ts != null && ts.totalFrames > 0 && vf >= ts.totalFrames) {
      await syncSeek(Duration.zero);
      vf = 0;
    }

    // play 직전 position 캡처 (scheduleStart 후 첫 poll까지 seek bar 0:00 점프 방지)
    if (sr > 0) {
      final pos = Duration(milliseconds: (vf * 1000 / sr).round());
      _seekOverridePosition = pos;
      _positionController.add(pos);
      _seekOverrideTimer?.cancel();
      _seekOverrideTimer = Timer(const Duration(milliseconds: 500), () {
        _seekOverridePosition = null;
      });
    }

    // v0.0.48 롤백: NTP 예약 재생 보류, v0.0.45 동작 회복.
    // (NTP 코드 인프라는 보존 — 다음 세션 재활용. _engine.scheduleStart / cancelSchedule
    // 와 schedule-play/schedule-pause 메시지 핸들러 모두 dead path로 남김.)
    final ok = await _engine.start();
    if (!ok) return;
    _playing = true;
    _playingController.add(true);
    debugPrint('[SYNCPLAY-HOST] engine.start ok');

    _broadcastObs();
    _startObsBroadcast();

    _logHostEvent(event: 'host_play');
  }

  Future<void> syncPause() async {
    _playing = false;
    _playingController.add(false);
    // v0.0.48 롤백: 직접 stop (oboe pause/resume 모델은 v0.0.46 그대로 유지)
    await _engine.stop();

    _broadcastObs();
    _stopObsBroadcast();

    _logHostEvent(event: 'host_pause');
  }

  Future<void> syncSeek(Duration position) async {
    if (!_audioReady) return;
    final ts = _engine.latest;
    if (ts == null || ts.sampleRate <= 0) return;

    _seekOverridePosition = position;
    _positionController.add(position);
    _seekOverrideTimer?.cancel();
    _seekOverrideTimer = Timer(const Duration(milliseconds: 500), () {
      _seekOverridePosition = null;
    });

    final targetFrame =
        (position.inMilliseconds * ts.sampleRate / 1000).round();
    final clampedTarget = targetFrame.clamp(0, ts.totalFrames);

    // v0.0.48 롤백: 재생 중/정지 모두 seekToFrame 직접 (NTP schedule 사용 안 함).
    await _engine.seekToFrame(clampedTarget);
    _p2p.broadcastToAll({
      'type': 'seek-notify',
      'data': {'targetMs': position.inMilliseconds},
    });

    _broadcastObs();

    _logHostEvent(
      event: 'host_seek',
      hostVf: clampedTarget,
      targetMs: position.inMilliseconds,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: audio-obs broadcast (500ms 주기)
  // ═══════════════════════════════════════════════════════════

  void _startObsBroadcast() {
    _obsBroadcastTimer?.cancel();
    _obsBroadcastTimer = Timer.periodic(
      Duration(milliseconds: _obsBroadcastIntervalMs.round()),
      (_) => _broadcastObs(),
    );
  }

  void _stopObsBroadcast() {
    _obsBroadcastTimer?.cancel();
    _obsBroadcastTimer = null;
  }

  void _broadcastObs() {
    final ts = _engine.latest;
    if (ts == null) return;

    // ok=false (HAL timestamp 실패)여도 virtualFrame + wallMs는 유효
    // → 게스트가 fallback alignment으로 싱크 가능
    final obs = AudioObs(
      seq: _obsBroadcastSeq++,
      hostTimeMs: ts.wallMs,
      framePos: ts.ok ? ts.framePos : -1,
      timeNs: ts.ok ? ts.timeNs : -1,
      virtualFrame: ts.virtualFrame,
      sampleRate: ts.sampleRate,
      playing: _playing,
      hostOutputLatencyMs: ts.safeOutputLatencyMs,
    );

    _p2p.broadcastToAll(obs.toJson());
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: 피어 요청 처리
  // ═══════════════════════════════════════════════════════════

  void _handleAudioRequest(String? fromId) {
    if (fromId == null || _currentUrl == null) return;
    _p2p.sendToPeer(fromId, {
      'type': 'audio-url',
      'data': {
        'url': _currentUrl,
        'playing': _playing,
        'fileName': _currentFileName,
      },
    });
  }

  void _handleStateRequest(String? fromId) {
    if (fromId == null) return;
    final ts = _engine.latest;
    _p2p.sendToPeer(fromId, {
      'type': 'state-response',
      'data': {
        'playing': _playing,
        'virtualFrame': ts?.virtualFrame ?? 0,
        'sampleRate': ts?.sampleRate ?? 0,
      },
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: drift-report 수신 → 측정 로그 기록
  // ═══════════════════════════════════════════════════════════

  void _handleDownloadReport(Map<String, dynamic> message) {
    final from = message['_from'] as String?;
    final data = message['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final bytes = (data['bytes'] as num?)?.toInt() ?? 0;
    final totalMs = (data['totalMs'] as num?)?.toInt() ?? 0;
    final firstByteMs = (data['firstByteMs'] as num?)?.toInt() ?? 0;
    final transferMs = (data['transferMs'] as num?)?.toInt() ?? 0;
    final mbps = (data['mbps'] as num?)?.toDouble() ?? 0;
    final fileName = data['fileName'] as String? ?? '';
    final mb = bytes / (1024.0 * 1024.0);
    debugPrint(
      '[DOWNLOAD-REPORT] from=$from file="$fileName" '
      '${mb.toStringAsFixed(2)}MB total=${totalMs}ms '
      'TTFB=${firstByteMs}ms transfer=${transferMs}ms '
      '${mbps.toStringAsFixed(2)}MB/s',
    );
  }

  /// 호스트 자기 이벤트(syncPlay/Pause/Seek)를 logger에 직접 기록.
  /// guestId는 'host'로 박아 게스트 보고와 구분. drift_ms/vf_diff_ms 등은
  /// 호스트 이벤트엔 의미 없어 0으로 둠. host_seek 시 hostVf에 target frame,
  /// guestVf에 targetMs 표기 (게스트 컬럼 재활용).
  void _logHostEvent({
    required String event,
    int hostVf = 0,
    int targetMs = 0,
  }) {
    if (!_isHost) return;
    final ts = _engine.latest;
    final wallMs = DateTime.now().millisecondsSinceEpoch;
    _logger.log(
      wallMs: wallMs,
      guestId: 'host',
      driftMs: 0,
      vfDiffMs: 0,
      hostObsWall: ts?.wallMs ?? wallMs,
      offsetMs: 0,
      hostVf: hostVf != 0 ? hostVf : (ts?.virtualFrame ?? 0),
      guestVf: targetMs,
      seekCount: 0,
      event: event,
    );
    debugPrint('[HOST-EVENT] $event vf=${hostVf != 0 ? hostVf : ts?.virtualFrame} targetMs=$targetMs');
  }

  void _handleDriftReport(Map<String, dynamic> message) {
    final from = message['_from'] as String?;
    final data = message['data'] as Map<String, dynamic>?;
    if (from == null || data == null) return;

    final driftMs = (data['driftMs'] as num?)?.toDouble() ?? 0;
    final vfDiffMs = (data['vfDiffMs'] as num?)?.toDouble() ?? 0;
    final hostObsWall = (data['hostObsWall'] as num?)?.toInt() ?? 0;
    final offsetMs = (data['offsetMs'] as num?)?.toDouble() ?? 0;
    final seekCount = (data['seekCount'] as num?)?.toInt() ?? 0;
    final event = data['event'] as String? ?? 'drift';
    // v0.0.52 진단 컬럼 4개
    final outLatHostRaw = (data['outLatHostRaw'] as num?)?.toDouble() ?? 0;
    final outLatGuestRaw = (data['outLatGuestRaw'] as num?)?.toDouble() ?? 0;
    final outLatDeltaCurrent = (data['outLatDeltaCurrent'] as num?)?.toDouble() ?? 0;
    final outLatDeltaAnchored = (data['outLatDeltaAnchored'] as num?)?.toDouble() ?? 0;

    // wall_ms는 호스트 받은 시점으로 통일 (단조 증가 보장).
    // guest_wall은 게스트가 보낸 원본 wallMs — TCP lag + clock offset 분석용.
    final hostRecvWall = DateTime.now().millisecondsSinceEpoch;
    final guestWall = (data['wallMs'] as num?)?.toInt() ?? 0;
    _logger.log(
      wallMs: hostRecvWall,
      guestWall: guestWall,
      guestId: from,
      driftMs: driftMs,
      vfDiffMs: vfDiffMs,
      hostObsWall: hostObsWall,
      offsetMs: offsetMs,
      hostVf: (data['hostVf'] as num?)?.toInt() ?? 0,
      guestVf: (data['guestVf'] as num?)?.toInt() ?? 0,
      seekCount: seekCount,
      outLatHostRaw: outLatHostRaw,
      outLatGuestRaw: outLatGuestRaw,
      outLatDeltaCurrent: outLatDeltaCurrent,
      outLatDeltaAnchored: outLatDeltaAnchored,
      event: event,
    );
    // 실시간 관측용 logcat 출력 (v0.0.24+)
    debugPrint(
      '[DRIFT-REPORT] from=$from event=$event '
      'drift=${driftMs.toStringAsFixed(2)}ms '
      'vfDiff=${vfDiffMs.toStringAsFixed(2)}ms '
      'offset=${offsetMs.toStringAsFixed(1)}ms '
      'seekCount=$seekCount',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: audio-url 수신 → 파일 다운로드 → 네이티브 엔진 로드
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleAudioUrl(Map<String, dynamic> data) async {
    var url = data['url'] as String;
    final hostPlaying = data['playing'] as bool? ?? false;

    // ── 이전 다운로드 취소 ──────────────────────────────────────
    _downloadAborted = true;
    _activeHttpClient?.close(force: true);
    final mySession = ++_downloadSessionId;

    // URL의 호스트를 실제 연결 IP로 치환 (에뮬레이터 등)
    final connectedIp = _p2p.connectedHostIp;
    if (connectedIp != null) {
      url = url.replaceFirst(RegExp(r'http://[^:/]+'), 'http://$connectedIp');
    }

    // 새 파일 로드 전 기존 재생 상태 정리
    // _audioReady를 먼저 false로 해야 _handleAudioObs가 start()를 호출하지 않음
    _audioReady = false;
    if (_playing) {
      _playing = false;
      _playingController.add(false);
      await _engine.stop();
    }
    _resetDriftState();

    _isLoading = true;
    _loadingController.add(true);

    try {
      // 호스트가 보낸 원본 파일명 사용 (없으면 URL에서 추출)
      final hostFileName = data['fileName'] as String?;
      if (hostFileName != null && hostFileName.isNotEmpty) {
        _currentFileName = hostFileName;
      } else {
        final pathPart = url.split('/').last;
        final cleanPath = pathPart.split('?').first;
        _currentFileName = Uri.decodeComponent(cleanPath);
      }
    } catch (_) {
      _currentFileName = url.split('/').last;
    }

    _currentUrl = url;
    _downloadAborted = false;

    // HTTP 다운로드 → temp 파일 (세션별 고유 파일명)
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = _currentFileName ?? 'audio_download';
      tempFile = File('${tempDir.path}/dl_${mySession}_$safeName');

      final swDownload = Stopwatch()..start();
      int receivedBytes = 0;
      int firstByteMs = -1;
      int transferMs = 0;
      final client = HttpClient();
      _activeHttpClient = client;
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final totalBytes = response.contentLength; // -1 if unknown
        final swTransfer = Stopwatch();
        final sink = tempFile.openWrite();
        try {
          await for (final chunk in response) {
            if (_downloadAborted || _downloadSessionId != mySession) break;
            if (firstByteMs < 0) {
              firstByteMs = swDownload.elapsedMilliseconds;
              swTransfer.start();
            }
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _downloadProgressController.add(receivedBytes / totalBytes);
            }
          }
        } finally {
          await sink.close();
        }
        swTransfer.stop();
        transferMs = swTransfer.elapsedMilliseconds;
      } finally {
        client.close();
        if (_activeHttpClient == client) _activeHttpClient = null;
      }
      swDownload.stop();
      final totalMs = swDownload.elapsedMilliseconds;
      final mbytes = receivedBytes / (1024.0 * 1024.0);
      final transferMBps =
          transferMs > 0 ? mbytes * 1000 / transferMs : 0.0;
      debugPrint(
        '[DOWNLOAD-GUEST] ${mbytes.toStringAsFixed(2)}MB in ${totalMs}ms '
        '(TTFB=${firstByteMs}ms, transfer=${transferMs}ms, '
        '${transferMBps.toStringAsFixed(2)} MB/s)',
      );
      // 호스트에 측정값 보고 — 호스트 logcat에서 확인 가능
      if (_downloadSessionId == mySession && !_downloadAborted) {
        _p2p.sendToHost({
          'type': 'download-report',
          'data': {
            'bytes': receivedBytes,
            'totalMs': totalMs,
            'firstByteMs': firstByteMs,
            'transferMs': transferMs,
            'mbps': transferMBps,
            'fileName': _currentFileName ?? '',
          },
        });
      }

      // 다운로드 중 새 파일 요청이 들어온 경우 → 이 세션은 무효
      if (_downloadAborted || _downloadSessionId != mySession) {
        debugPrint('[GUEST] download stale (session=$mySession, current=$_downloadSessionId)');
        try { tempFile.deleteSync(); } catch (_) {}
        if (_downloadSessionId != mySession) return; // 새 세션이 UI 상태 관리
        _isLoading = false;
        _loadingController.add(false);
        return;
      }

      // 네이티브 엔진에 로드
      final swDecode = Stopwatch()..start();
      final loadResult = await _engine.loadFile(tempFile.path);
      swDecode.stop();
      debugPrint('[DECODE-GUEST] loadFile took ${swDecode.elapsedMilliseconds}ms');

      // 디코드 완료 후 세션 유효성 재확인
      if (_downloadSessionId != mySession) {
        debugPrint('[GUEST] decode done but session stale ($mySession != $_downloadSessionId)');
        try { tempFile.deleteSync(); } catch (_) {}
        return;
      }

      if (!loadResult.ok || _downloadAborted) {
        if (!_downloadAborted) _errorController.add('파일 로드 실패');
        try { tempFile.deleteSync(); } catch (_) {}
        _isLoading = false;
        _loadingController.add(false);
        return;
      }

      // loadFile 반환값에서 duration 즉시 계산
      _setDurationFromLoadResult(loadResult);

      _audioReady = true;
      _isLoading = false;
      _loadingController.add(false);

      // 엔진 폴링 시작 (drift 계산 + UI position)
      _engine.startPolling();
      _startTimestampWatch();

      if (_downloadSessionId == mySession) {
        await _resolveDurationFromTimestampIfNeeded();
      }

      // 호스트가 재생 중이면 엔진 시작
      // hostPlaying은 audio-url broadcast 시점 호스트 상태로 stale 가능성 있음.
      // 다운로드 + loadFile 동안 (수 초) 호스트가 syncPause 눌렀으면 _latestObs.playing
      // 이 false → 게스트만 재생 시작 방지. (v0.0.46 fix — 사용자 보고 케이스)
      final currentHostPlaying = _latestObs?.playing ?? hostPlaying;
      debugPrint(
          '[GUEST] loadFile done, urlHostPlaying=$hostPlaying, '
          'currentHostPlaying=$currentHostPlaying, audioReady=$_audioReady');
      if (currentHostPlaying) {
        await _startGuestPlayback();
      }
    } catch (e) {
      debugPrint('Audio download/load error: $e');
      // 에러 시 temp 파일 정리
      if (tempFile != null) {
        try { tempFile.deleteSync(); } catch (_) {}
      }
      if (_downloadSessionId == mySession && !_downloadAborted) {
        _errorController.add('오디오 다운로드 실패');
      }
      if (_downloadSessionId == mySession) {
        _isLoading = false;
        _loadingController.add(false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: audio-obs 수신
  // ═══════════════════════════════════════════════════════════

  void _handleAudioObs(Map<String, dynamic> message) {
    try {
      final obs = AudioObs.fromJson(message);
      final isFirstObs = _latestObs == null;
      final transitionToPlaying = _latestObs != null &&
          !_latestObs!.playing && obs.playing;
      _latestObs = obs;

      if (isFirstObs || transitionToPlaying) {
        final fpMs = obs.sampleRate > 0
            ? obs.framePos * 1000.0 / obs.sampleRate
            : -1.0;
        final vfMs = obs.sampleRate > 0
            ? obs.virtualFrame * 1000.0 / obs.sampleRate
            : -1.0;
        final tag = isFirstObs ? '[OBS-FIRST]' : '[OBS-PLAYSTART]';
        debugPrint(
          '$tag fp=${obs.framePos} vf=${obs.virtualFrame} '
          'sr=${obs.sampleRate} fp_ms=${fpMs.toStringAsFixed(1)} '
          'vf_ms=${vfMs.toStringAsFixed(1)} '
          'fpVfDiff_ms=${(fpMs - vfMs).toStringAsFixed(1)} '
          'hostOutLat=${obs.hostOutputLatencyMs.toStringAsFixed(1)} '
          'hostTimeMs=${obs.hostTimeMs} playing=${obs.playing}',
        );
      }

      // v0.0.48 롤백: schedule-play 호스트 broadcast 안 함 → audio-obs 기반으로만
      // 게스트 재생 시작/정지. v0.0.45 동작.
      if (obs.playing) {
        if (!_playing && _audioReady) {
          debugPrint('[GUEST] obs→startPlayback');
          unawaited(_startGuestPlayback());
        }
      } else {
        if (_playing) {
          unawaited(_stopGuestPlayback());
        }
      }
    } catch (e) {
      debugPrint('audio-obs parse error: $e');
    }
  }

  // v0.0.47: schedule 진행 중 race 방지. _handleSchedulePlay와 _scheduleFromObs가
  // 동시 호출되면 둘 다 scheduleStart → 호스트와 다른 fromVf로 시작 → 큰 drift.
  bool _scheduleInProgress = false;

  /// v0.0.47: 합류 게스트의 자체 schedule 계산. (v0.0.48에서 호출 비활성화 — NTP 재도입 시 재활용)
  /// 호스트 obs로부터 현재 호스트 콘텐츠 위치 외삽 → 200ms 후 양쪽 시작 위치 계산.
  // ignore: unused_element
  Future<void> _scheduleFromObs() async {
    if (_playing || _scheduleInProgress) return;
    final obs = _latestObs;
    if (obs == null || !_sync.isSynced) return;
    _scheduleInProgress = true;

    // _playing은 schedule 등록 직전 set — race 방지 (await yield 동안 다른 메시지가
    // _scheduleFromObs/_handleSchedulePlay 다시 호출 못 함).
    _playing = true;
    _playingController.add(true);

    try {
      final guestNowMs = DateTime.now().millisecondsSinceEpoch;
      final hostNowMs = guestNowMs + _sync.filteredOffsetMs.round();
      final hostFpMs =
          obs.sampleRate > 0 ? obs.sampleRate / 1000.0 : _framesPerMs;
      final hostContentFrameNow = obs.virtualFrame +
          ((hostNowMs - obs.hostTimeMs) * hostFpMs).round();
      final hostContentFrameAtStart =
          hostContentFrameNow + (_scheduleBufferMs * hostFpMs).round();
      final startGuestWallMs = guestNowMs + _scheduleBufferMs;

      debugPrint(
          '[GUEST] scheduleFromObs startWallMs=$startGuestWallMs '
          'fromVf=$hostContentFrameAtStart hostOffset=${_sync.filteredOffsetMs.round()}');

      final ok = await _engine.scheduleStart(
          startGuestWallMs, hostContentFrameAtStart);
      if (!ok) {
        _playing = false;
        _playingController.add(false);
        return;
      }
      _resetDriftState();
    } finally {
      _scheduleInProgress = false;
    }
  }

  /// v0.0.47: 호스트의 schedule-play 메시지 처리. wall time 변환 후 native schedule 등록.
  /// 호스트가 정확한 fromVf 보내므로 _scheduleFromObs보다 정확. race 시 우선.
  Future<void> _handleSchedulePlay(Map<String, dynamic>? data) async {
    if (data == null || !_audioReady) return;
    final hostStartWallMs = (data['startWallMs'] as num?)?.toInt();
    final fromVf = (data['fromVf'] as num?)?.toInt();
    if (hostStartWallMs == null || fromVf == null) return;

    // 진행 중이면 잠깐 대기 — 마지막 schedule-play가 이김 (멱등). 단순화 위해 reentrant 허용.
    _scheduleInProgress = true;
    // _playing을 await 전 set — _handleAudioObs의 _scheduleFromObs 호출 차단
    _playing = true;
    _playingController.add(true);

    try {
      final guestStartWallMs =
          hostStartWallMs - _sync.filteredOffsetMs.round();
      debugPrint(
          '[GUEST] schedule-play hostWallMs=$hostStartWallMs '
          'guestWallMs=$guestStartWallMs fromVf=$fromVf '
          'offset=${_sync.filteredOffsetMs.round()}');

      final ok = await _engine.scheduleStart(guestStartWallMs, fromVf);
      if (!ok) {
        _playing = false;
        _playingController.add(false);
        return;
      }
      _resetDriftState();
    } finally {
      _scheduleInProgress = false;
    }
  }

  /// v0.0.47: 호스트의 schedule-pause 메시지 처리. 즉시 정지.
  Future<void> _handleSchedulePause(Map<String, dynamic>? data) async {
    debugPrint('[GUEST] schedule-pause');
    if (!_playing) return;
    _playing = false;
    _playingController.add(false);
    await _engine.cancelSchedule();
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: seek-notify 수신
  // ═══════════════════════════════════════════════════════════

  void _handleSeekNotify(Map<String, dynamic> message) {
    final targetMs = (message['data']?['targetMs'] as num?)?.toDouble();
    if (targetMs == null || !_audioReady) return;
    // 절대 위치 → 게스트 frame 변환. 몇 번 와도 같은 위치 (멱등)
    final targetGuestVf = (targetMs * _framesPerMs).round();
    unawaited(_engine.seekToFrame(targetGuestVf));
    // UI 즉시 반영. 재생 중이 아니면 폴링이 이전 위치를 계속 emit하므로
    // override로 덮어야 "처음 재생" 시 끝 위치(4:55) 잔상이 사라짐.
    final pos = Duration(milliseconds: targetMs.round());
    _seekOverridePosition = pos;
    _positionController.add(pos);
    _seekOverrideTimer?.cancel();
    _seekOverrideTimer = Timer(const Duration(milliseconds: 500), () {
      _seekOverridePosition = null;
    });
    // 앵커 무효화 + 쿨다운: fresh obs 도착 대기 후 re-anchor
    _anchorHostFrame = null;
    _anchorGuestFrame = null;
    _seekCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 1000;
    _logGuestEvent(event: 'anchor_reset_seek_notify');
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: 재생 시작/정지
  // ═══════════════════════════════════════════════════════════

  // v0.0.48 롤백: v0.0.45 동작 — engine.start 직접 호출 + _resetDriftState.
  Future<void> _startGuestPlayback() async {
    if (_playing) {
      debugPrint('[GUEST] _startGuestPlayback: already playing, skip');
      return;
    }
    debugPrint('[GUEST] _startGuestPlayback: calling engine.start()');
    final ok = await _engine.start();
    debugPrint('[GUEST] _startGuestPlayback: engine.start() → $ok');
    if (!ok) return;
    _playing = true;
    _playingController.add(true);
    _resetDriftState();
    _logGuestEvent(event: 'guest_start');
  }

  Future<void> _stopGuestPlayback() async {
    if (!_playing) return;
    _playing = false;
    _playingController.add(false);
    await _engine.stop();
    _logGuestEvent(event: 'guest_stop');
  }

  /// 게스트 측 이벤트(start/stop/anchor_set/anchor_reset)를 호스트로 보내
  /// csv에 별도 row로 기록. drift_ms/vf_diff_ms는 그 시점 마지막 값(있으면)
  /// 또는 0. anchor 관련 이벤트엔 _latestObs 신선도 추적 위해 hostObsWall 채움.
  void _logGuestEvent({required String event}) {
    if (_isHost) return;
    final ts = _engine.latest;
    _sendDriftReport(
      wallMs: ts?.wallMs ?? DateTime.now().millisecondsSinceEpoch,
      driftMs: _latestDriftMs ?? 0,
      vfDiffMs: 0,
      hostObsWall: _latestObs?.hostTimeMs ?? 0,
      offsetMs: _sync.filteredOffsetMs,
      hostVf: _latestObs?.virtualFrame ?? 0,
      guestVf: ts?.virtualFrame ?? 0,
      event: event,
    );
  }

  void _resetDriftState() {
    _anchorHostFrame = null;
    _anchorGuestFrame = null;
    _offsetAtAnchor = null;
    _seekCorrectionAccum = 0;
    _seekCooldownUntilMs = 0;
    // anchor가 무효화됐으면 베이크인 값도 같이 0으로. 다음 anchor establish
    // 시점에 새 outLatDelta가 저장되므로 동작은 동일하지만, 의미적 일관성
    // 위해 명시 리셋 (anchor null인 동안 _recomputeDrift는 early return).
    _anchoredOutLatDeltaMs = 0;
    _fallbackAlignCooldownMs = 0;
    _latestDriftMs = null;
    _driftSamples.clear();
  }

  // ═══════════════════════════════════════════════════════════
  // 타임스탬프 감시 (호스트/게스트 공통)
  // ═══════════════════════════════════════════════════════════

  int _tsFailCount = 0;
  int _fallbackAlignCooldownMs = 0;

  void _startTimestampWatch() {
    _tsFailCount = 0;
    _timestampSub?.cancel();
    _timestampSub = _engine.timestampStream.listen((ts) {
      // UI position 업데이트 — virtualFrame은 ok 여부와 무관하게 유효
      if (ts.sampleRate > 0 && _seekOverridePosition == null) {
        _positionController.add(
          Duration(
              milliseconds:
                  (ts.virtualFrame * 1000 / ts.sampleRate).round()),
        );
      }

      // 재생 완료 감지: VF가 totalFrames 이상이면 자동 정지 (호스트만)
      if (_isHost && _playing && ts.totalFrames > 0 &&
          ts.virtualFrame >= ts.totalFrames) {
        debugPrint('[HOST] end of file reached (vf=${ts.virtualFrame}, total=${ts.totalFrames})');
        unawaited(syncPause());
      }

      if (!ts.ok) {
        _tsFailCount++;
        if (_tsFailCount <= 3 || _tsFailCount % 50 == 0) {
          debugPrint('[TS] ok=false (count=$_tsFailCount, playing=$_playing, host=$_isHost)');
        }
        // fallback: virtualFrame 기반 간단 정렬
        if (!_isHost && _playing) {
          _fallbackAlignment(ts);
        }
        return;
      }
      if (_tsFailCount > 0) {
        debugPrint('[TS] ok recovered after $_tsFailCount failures (vf=${ts.virtualFrame})');
        _tsFailCount = 0;
      }

      // 게스트: drift 보정
      if (!_isHost && _playing) {
        if (!_sync.isOffsetStable) {
          // 수렴 전: fallback으로 즉시 대략 정렬
          _fallbackAlignment(ts);
        } else if (_anchorHostFrame == null) {
          _tryEstablishAnchor(ts);
        } else {
          _recomputeDrift(ts);
        }
      }
    });
  }

  /// HAL timestamp 없을 때 virtualFrame으로 간단 정렬 (에뮬레이터, 블루투스 등)
  void _fallbackAlignment(NativeTimestamp ts) {
    if (!_sync.isSynced) return;
    // stability gate 없음 — 초기 offset으로도 즉시 대략 정렬 (±8ms)
    // 정밀 보정은 anchor 경로(isOffsetStable 필요)가 담당
    final obs = _latestObs;
    if (obs == null || !obs.playing) return;

    final offset = _sync.filteredOffsetMs;
    final hostWallNow = ts.wallMs + offset;
    final hostFpMs = obs.sampleRate > 0 ? obs.sampleRate / 1000.0 : _framesPerMs;

    // ms 단위로 통일하여 cross-rate 비교 (호스트 48kHz ↔ 게스트 44.1kHz 등)
    final elapsedMs = (hostWallNow - obs.hostTimeMs).toDouble();
    final expectedPositionMs = obs.virtualFrame / hostFpMs + elapsedMs;
    final guestPositionMs = ts.virtualFrame / _framesPerMs;
    // _recomputeDrift와 동일하게 outputLatency 비대칭 보정 (v0.0.38).
    final outLatDelta = ts.safeOutputLatencyMs - obs.hostOutputLatencyMs;
    final driftMs = guestPositionMs - expectedPositionMs - outLatDelta;

    // 500ms마다 drift report (fallback mode)
    // fallback의 driftMs는 이미 vf 기반 (framePos 미사용) → vfDiffMs == driftMs.
    if (ts.wallMs - _lastDriftReportMs >= 500) {
      _lastDriftReportMs = ts.wallMs;
      _sendDriftReport(
        wallMs: ts.wallMs,
        driftMs: driftMs,
        vfDiffMs: driftMs,
        hostObsWall: obs.hostTimeMs,
        offsetMs: offset,
        hostVf: obs.virtualFrame,
        guestVf: ts.virtualFrame,
        // v0.0.52 진단 — fallback 모드도 outLat 측정값 기록 (anchor 잡히기 전 baseline)
        outLatHostRaw: obs.hostOutputLatencyMs,
        outLatGuestRaw: ts.safeOutputLatencyMs,
        outLatDeltaCurrent: outLatDelta,
        outLatDeltaAnchored: 0, // anchor 없음
        event: 'fallback',
      );
    }

    // v0.0.48 롤백: 30ms 이상 차이나면 보정, 쿨다운 1초. (v0.0.45 동작 회복)
    if (ts.wallMs < _fallbackAlignCooldownMs) return;
    if (driftMs.abs() > 30) {
      final targetGuestVf = (expectedPositionMs * _framesPerMs).round();
      unawaited(_engine.seekToFrame(targetGuestVf));
      _fallbackAlignCooldownMs = ts.wallMs + 1000;
      debugPrint('[FALLBACK] align: drift=${driftMs.toStringAsFixed(1)}ms, seekTo=$targetGuestVf');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: drift 계산 (PoC Phase 4 알고리즘)
  // ═══════════════════════════════════════════════════════════

  /// 앵커 설정: clock sync 완료 + playing obs 수신 + ok sample 시.
  /// obs를 앵커 시점으로 외삽하여 시간축 정합.
  void _tryEstablishAnchor(NativeTimestamp ts) {
    if (!_sync.isSynced) return;
    if (!_sync.isOffsetStable) return; // offset 수렴 전 앵커 설정 방지
    if (ts.wallMs < _seekCooldownUntilMs) return; // seek 직후 stale obs 방지
    final offset = _sync.filteredOffsetMs;
    final obs = _latestObs;
    if (obs == null || !obs.playing) return;
    // 호스트 HAL timestamp 없으면 정밀 앵커 불가 → fallback에 맡김
    if (obs.framePos < 0) return;

    // 앵커 순간의 호스트 wall clock = 게스트 wall + offset
    final anchorHostWall = ts.wallMs + offset;
    // obs는 최대 500ms 오래된 값 → 앵커 시점으로 외삽
    // 호스트 frame 외삽은 호스트의 sampleRate 사용
    final hostFpMs = obs.sampleRate > 0 ? obs.sampleRate / 1000.0 : _framesPerMs;
    final anchorHostFrame = obs.framePos +
        ((anchorHostWall - obs.hostTimeMs) * hostFpMs).round();

    // 콘텐츠 정렬: 호스트 콘텐츠 위치(ms)를 게스트 frame으로 변환하여 seek
    final hostContentFrame = obs.virtualFrame +
        ((anchorHostWall - obs.hostTimeMs) * hostFpMs).round();
    final hostContentMs = hostContentFrame / hostFpMs;
    // v0.0.38: outputLatency 비대칭을 anchor seek에 베이크인.
    // 게스트가 BT(+200ms), 호스트가 내장(+5ms)이면 outLatDelta = +195ms.
    // 게스트 콘텐츠를 호스트보다 195ms 앞선 위치로 seek해야 음향 시각 정렬.
    final outLatDelta = ts.safeOutputLatencyMs - obs.hostOutputLatencyMs;
    final targetGuestVf = (hostContentMs * _framesPerMs).round() +
        (outLatDelta * _framesPerMs).round();
    final currentEffective = ts.framePos + _seekCorrectionAccum;
    final initialCorrection = targetGuestVf - currentEffective;
    // v0.0.53: anchor 중복 호출 버그 fix.
    // 이전 코드는 seekToFrame + accum을 두 번 호출 (v0.0.48 롤백 시 v0.0.45와
    // 합쳐지면서 발생한 잠재 버그, CLAUDE.md "다음 세션 후보 6번" 명시).
    // 결과: _seekCorrectionAccum이 의도(initialCorrection 한 번)의 두 배로 누적
    // → anchor baseline (_anchorGuestFrame = ts.framePos + accum)이 의도보다
    // initialCorrection 만큼 앞에 박힘 → vfDiff -20ms 같은 베이크인 잔재의
    // 잠재 root cause. seekToFrame 1번만 호출 + accum 1번만 누적으로 fix.
    unawaited(_engine.seekToFrame(targetGuestVf));
    _seekCorrectionAccum += initialCorrection;

    _anchorHostFrame = anchorHostFrame;
    _anchorGuestFrame = ts.framePos + _seekCorrectionAccum;
    _offsetAtAnchor = offset; // 앵커 시점의 offset 기록
    _anchoredOutLatDeltaMs = outLatDelta;

    // HAL 버퍼 안정화 쿨다운
    _seekCooldownUntilMs = ts.wallMs + _seekCooldown.inMilliseconds;

    // v0.0.44 진단: prewarm으로 framePos/vf 비대칭이 anchor에 잘못 베이크되는지
    // 확인용. hostFpVfDiff_ms·guestFpVfDiff_ms가 크면 framePos가 콘텐츠 frame이
    // 아니라 prewarm 누적 → 가설 H1 확정.
    final guestFpMs = _framesPerMs;
    debugPrint(
      '[ANCHOR] establish wall=${ts.wallMs} '
      'host[fp=${obs.framePos} vf=${obs.virtualFrame} '
      'fp_ms=${(obs.framePos / hostFpMs).toStringAsFixed(1)} '
      'vf_ms=${(obs.virtualFrame / hostFpMs).toStringAsFixed(1)} '
      'fpVfDiff_ms=${((obs.framePos - obs.virtualFrame) / hostFpMs).toStringAsFixed(1)}] '
      'guest[fp=${ts.framePos} vf=${ts.virtualFrame} '
      'fp_ms=${(ts.framePos / guestFpMs).toStringAsFixed(1)} '
      'vf_ms=${(ts.virtualFrame / guestFpMs).toStringAsFixed(1)} '
      'fpVfDiff_ms=${((ts.framePos - ts.virtualFrame) / guestFpMs).toStringAsFixed(1)}] '
      'outLat[host=${obs.hostOutputLatencyMs.toStringAsFixed(1)} '
      'guest=${ts.safeOutputLatencyMs.toStringAsFixed(1)} '
      'delta=${outLatDelta.toStringAsFixed(1)}] '
      'targetGuestVf=$targetGuestVf initialCorrection=$initialCorrection',
    );

    _logGuestEvent(event: 'anchor_set');
  }

  /// 게스트 → 호스트로 drift report 전송 (500ms 주기).
  /// [vfDiffMs] 외삽 + outputLatency 보정 후 콘텐츠 절대 위치 차이.
  /// [hostObsWall] 이 보고가 사용한 호스트 obs의 측정 시각 (외삽 신선도 추적).
  /// v0.0.52 진단 컬럼: outLat* 4개 추가 옵셔널.
  void _sendDriftReport({
    required int wallMs,
    required double driftMs,
    required double vfDiffMs,
    required int hostObsWall,
    required double offsetMs,
    required int hostVf,
    required int guestVf,
    required String event,
    double outLatHostRaw = 0,
    double outLatGuestRaw = 0,
    double outLatDeltaCurrent = 0,
    double outLatDeltaAnchored = 0,
  }) {
    _p2p.sendToHost({
      'type': 'drift-report',
      'data': {
        'wallMs': wallMs,
        'driftMs': driftMs,
        'vfDiffMs': vfDiffMs,
        'hostObsWall': hostObsWall,
        'offsetMs': offsetMs,
        'hostVf': hostVf,
        'guestVf': guestVf,
        'seekCount': _seekCount,
        'event': event,
        'outLatHostRaw': outLatHostRaw,
        'outLatGuestRaw': outLatGuestRaw,
        'outLatDeltaCurrent': outLatDeltaCurrent,
        'outLatDeltaAnchored': outLatDeltaAnchored,
      },
    });
  }

  /// 매 poll마다 drift(ms) 재계산.
  void _recomputeDrift(NativeTimestamp ts) {
    final obs = _latestObs;
    final anchorHF = _anchorHostFrame;
    final anchorGF = _anchorGuestFrame;
    final offset = _sync.filteredOffsetMs;
    if (obs == null || anchorHF == null || anchorGF == null) return;

    // offset이 앵커 시점에서 크게 변했으면 앵커 무효화 (EMA 수렴 중)
    if (_offsetAtAnchor != null &&
        (offset - _offsetAtAnchor!).abs() > _offsetDriftThresholdMs) {
      debugPrint('[DRIFT] anchor invalidated: offset drifted '
          '${(offset - _offsetAtAnchor!).toStringAsFixed(1)}ms since anchor');
      _anchorHostFrame = null;
      _anchorGuestFrame = null;
      _offsetAtAnchor = null;
      _driftSamples.clear();
      _logGuestEvent(event: 'anchor_reset_offset_drift');
      return;
    }

    // 호스트의 현재 예상 frame (obs 외삽) — 호스트 sampleRate 사용
    final hostWallNow = ts.wallMs + offset;
    final hostFpMs = obs.sampleRate > 0 ? obs.sampleRate / 1000.0 : _framesPerMs;
    final expectedHostFrameNow =
        obs.framePos + (hostWallNow - obs.hostTimeMs) * hostFpMs;
    final dH = expectedHostFrameNow - anchorHF;

    // 게스트의 effective frame (seek 보정 포함)
    final effectiveGuestFrame = ts.framePos + _seekCorrectionAccum;
    final dG = (effectiveGuestFrame - anchorGF).toDouble();

    // 각각의 sampleRate로 ms 변환 후 비교 (cross-rate 안전)
    final dHms = dH / hostFpMs;
    final dGms = dG / _framesPerMs;
    // v0.0.38: anchor에 outputLatency 비대칭이 베이크인되어 있으므로,
    // 여기선 (현재 - 앵커) 변화분만 보정. BT 분 단위 30~70ms 변동만 잡힘.
    // 큰 비대칭(150~250ms)은 anchor establishment 시점에 이미 처리됨.
    final currentOutLatDelta =
        ts.safeOutputLatencyMs - obs.hostOutputLatencyMs;
    final dynLatDeltaMs = currentOutLatDelta - _anchoredOutLatDeltaMs;
    final driftMs = dGms - dHms - dynLatDeltaMs; // 양수: 게스트 음향이 앞섬

    // vfDiffMs: 콘텐츠 절대 위치 차이 (외삽 + outputLatency 보정 후).
    // driftMs는 framePos 변화율(rate)만 비교 → anchor 시점의 잘못된 콘텐츠 차이를
    // 못 잡는 "거짓말 패턴" 발생. vfDiffMs는 매 poll virtualFrame을 직접 비교해
    // 절대 위치 어긋남을 노출. 두 값이 어긋나면 anchor가 잘못 박혔다는 신호.
    final expectedHostVfMs =
        obs.virtualFrame / hostFpMs + (hostWallNow - obs.hostTimeMs);
    final guestVfMs = ts.virtualFrame / _framesPerMs;
    final vfDiffMs = guestVfMs - expectedHostVfMs - currentOutLatDelta;

    _latestDriftMs = driftMs;

    // v0.0.24: 최근 N개 샘플 윈도우에 push (중앙값으로 seek 판단)
    _driftSamples.add(driftMs);
    if (_driftSamples.length > _driftMedianWindow) {
      _driftSamples.removeAt(0);
    }

    // 500ms마다 drift report 전송
    if (ts.wallMs - _lastDriftReportMs >= 500) {
      _lastDriftReportMs = ts.wallMs;
      _sendDriftReport(
        wallMs: ts.wallMs,
        driftMs: driftMs,
        vfDiffMs: vfDiffMs,
        hostObsWall: obs.hostTimeMs,
        offsetMs: offset,
        hostVf: obs.virtualFrame,
        guestVf: ts.virtualFrame,
        // v0.0.52 진단 컬럼 4개 — vfDiff 잔재 root cause 분해용
        outLatHostRaw: obs.hostOutputLatencyMs,
        outLatGuestRaw: ts.safeOutputLatencyMs,
        outLatDeltaCurrent: currentOutLatDelta,
        outLatDeltaAnchored: _anchoredOutLatDeltaMs,
        event: 'drift',
      );
    }

    // seek 판단 — 큰 drift(≥re-anchor)는 즉시, 중소 drift는 중앙값으로
    _maybeTriggerSeek(ts.wallMs, driftMs);
  }

  /// 정렬된 복사본의 중앙값.
  double _median(List<double> samples) {
    final sorted = List<double>.from(samples)..sort();
    final n = sorted.length;
    if (n == 0) return 0.0;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// |drift| ≥ 200ms → 앵커 리셋 (호스트 seek 등 큰 점프, 즉시 처리).
  /// |중앙값| ≥ 20ms → seek 보정 (노이즈 완화 위해 최근 N개 중앙값 기준).
  void _maybeTriggerSeek(int wallMs, double driftMs) {
    if (driftMs.abs() >= _reAnchorThresholdMs) {
      // 큰 drift → 앵커 리셋. 다음 poll에서 _tryEstablishAnchor가 재정렬.
      _anchorHostFrame = null;
      _anchorGuestFrame = null;
      _driftSamples.clear(); // 앵커 리셋 시 노이즈 윈도우도 초기화
      _seekCooldownUntilMs = 0;
      _logGuestEvent(event: 'anchor_reset_large_drift');
      return;
    }
    if (wallMs < _seekCooldownUntilMs) return;
    if (_driftSamples.length < _driftMedianWindow) return; // 충분한 샘플 확보 후 판단
    final medianDrift = _median(_driftSamples);
    if (medianDrift.abs() < _driftSeekThresholdMs) return;
    unawaited(_performSeek(wallMs, medianDrift));
  }

  Future<void> _performSeek(int wallMs, double driftMs) async {
    int currentVf;
    try {
      currentVf = await _engine.getVirtualFrame();
    } catch (_) {
      return;
    }

    // drift > 0 (게스트 앞섬) → correction < 0 (뒤로)
    final correctionFrames =
        (-driftMs * _seekCorrectionGain * _framesPerMs).round();
    final newVf = currentVf + correctionFrames;

    try {
      final ok = await _engine.seekToFrame(newVf);
      if (!ok) return;
    } catch (_) {
      return;
    }

    _seekCount++;
    _seekCooldownUntilMs = wallMs + _seekCooldown.inMilliseconds;
    _seekCorrectionAccum += correctionFrames;

    // seek 이벤트 report (seek 직후 vf 재계산 비용 큼 → driftMs 재사용,
    // hostObsWall만 obs 신선도 추적)
    _sendDriftReport(
      wallMs: wallMs,
      driftMs: driftMs,
      vfDiffMs: driftMs,
      hostObsWall: _latestObs?.hostTimeMs ?? 0,
      offsetMs: _sync.filteredOffsetMs,
      hostVf: _latestObs?.virtualFrame ?? 0,
      guestVf: currentVf + correctionFrames,
      event: 'seek',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 정리
  // ═══════════════════════════════════════════════════════════

  Future<void> _cleanupTempDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (final f in files) {
        if (f is File) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith('audio_') || name.startsWith('dl_')) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> clearTempFiles() async {
    _downloadAborted = true;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    _isLoading = false;
    _loadingController.add(false);
    _audioReady = false;
    _playing = false;
    _playingController.add(false);
    _engine.stopPolling();
    await _engine.stop();
    await _engine.unload();
    _stopObsBroadcast();
    await _stopFileServer();

    // 호스트 파일 + 게스트 dl_* 파일 모두 정리
    await _cleanupTempDir();
    _storedSafeName = null;
    _currentFileName = null;
    _currentUrl = null;
  }

  void cleanupSync() {
    _downloadAborted = true;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    _isLoading = false;
    _audioReady = false;
    _playing = false;
    _seekOverrideTimer?.cancel();
    _seekOverridePosition = null;
    _messageSub?.cancel();
    _messageSub = null;
    _timestampSub?.cancel();
    _timestampSub = null;
    _stopObsBroadcast();
    _engine.stopPolling();
    unawaited(_engine.stop());
    unawaited(_engine.unload());
    _resetDriftState();
    _storedSafeName = null;
    _currentFileName = null;
    _currentUrl = null;
    unawaited(_logger.stop());
  }

  void _setDurationFromLoadResult(LoadResult lr) {
    final frames = lr.totalFrames;
    final rate = lr.sampleRate;
    if (frames != null && frames > 0 && rate != null && rate > 0) {
      _currentDuration = _calcDuration(frames, rate);
      _durationController.add(_currentDuration);
    }
  }

  // Android fallback: loadFile이 totalFrames를 안 줬으면 getTimestamp에서 복원.
  Future<void> _resolveDurationFromTimestampIfNeeded() async {
    if (_currentDuration != null) return;
    final ts = await _engine.getTimestamp();
    if (ts != null && ts.sampleRate > 0 && ts.totalFrames > 0) {
      _currentDuration = _calcDuration(ts.totalFrames, ts.sampleRate.toDouble());
      _durationController.add(_currentDuration);
    }
  }

  /// totalFrames/sampleRate → Duration (ms 정밀도, 초 단위 반올림)
  static Duration _calcDuration(int totalFrames, double sampleRate) {
    final ms = (totalFrames * 1000 / sampleRate).round();
    // 초 단위 반올림: 299980ms → 300s, 300020ms → 300s (표시 통일)
    final seconds = ((ms + 500) ~/ 1000);
    return Duration(seconds: seconds);
  }

  Future<void> dispose() async {
    cleanupSync();
    _positionController.close();
    _durationController.close();
    _playingController.close();
    _loadingController.close();
    _downloadProgressController.close();
    _errorController.close();
    await _stopFileServer();
    await _engine.unload();
    await _engine.dispose();
    await _logger.dispose();
  }
}
