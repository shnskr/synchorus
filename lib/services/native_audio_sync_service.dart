import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

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

  // ── 게스트: drift report 전송 주기 ────────────────────────
  int _lastDriftReportMs = 0;

  // ── 게스트: drift 보정 상태 ────────────────────────────────
  AudioObs? _latestObs;
  // 앵커: drift=0 기준선
  int? _anchorHostFrame;
  int? _anchorGuestFrame;
  double? _offsetAtAnchor; // 앵커 설정 시점의 filteredOffsetMs
  // 최신 drift
  double? _latestDriftMs;
  // ignore: unused_field
  int _driftSampleCount = 0;
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

    if (isHost) {
      await _cleanupTempDir();
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
      } else if (type == 'audio-request' && _isHost) {
        _handleAudioRequest(message['_from']);
      } else if (type == 'state-request' && _isHost) {
        _handleStateRequest(message['_from']);
      } else if (type == 'drift-report' && _isHost) {
        _handleDriftReport(message);
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
    final handler = createStaticHandler(dirPath);
    try {
      _httpServer =
          await shelf_io.serve(handler, InternetAddress.anyIPv4, 41236);
    } catch (_) {
      _httpServer =
          await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    }
    final ip = await _getLocalIP();
    if (ip == null) {
      await _stopFileServer();
      return null;
    }
    final encodedName = Uri.encodeComponent(fileName);
    return 'http://$ip:${_httpServer!.port}/$encodedName';
  }

  Future<void> _stopFileServer() async {
    await _httpServer?.close();
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

    // Android fallback: loadFile이 totalFrames를 안 줬으면 getTimestamp에서
    if (_currentDuration == null) {
      final ts = await _engine.getTimestamp();
      if (ts != null && ts.sampleRate > 0 && ts.totalFrames > 0) {
        _currentDuration = _calcDuration(ts.totalFrames, ts.sampleRate.toDouble());
        _durationController.add(_currentDuration);
      }
    }
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

    // play 직전 position 캡처 (start 직후 첫 poll까지 seek bar 0:00 점프 방지)
    if (sr > 0) {
      final pos = Duration(milliseconds: (vf * 1000 / sr).round());
      _seekOverridePosition = pos;
      _positionController.add(pos);
      _seekOverrideTimer?.cancel();
      _seekOverrideTimer = Timer(const Duration(milliseconds: 500), () {
        _seekOverridePosition = null;
      });
    }

    final ok = await _engine.start();
    if (!ok) return;
    _playing = true;
    _playingController.add(true);

    // 즉시 audio-obs broadcast (playing 상태 변경 알림)
    _broadcastObs();
    _startObsBroadcast();
  }

  Future<void> syncPause() async {
    _playing = false;
    _playingController.add(false);
    await _engine.stop();

    // 정지 상태 broadcast 후 주기 broadcast 중단
    _broadcastObs();
    _stopObsBroadcast();
  }

  Future<void> syncSeek(Duration position) async {
    if (!_audioReady) return;
    final ts = _engine.latest;
    if (ts == null || ts.sampleRate <= 0) return;

    // 즉시 UI에 target position 반영 (폴링이 이전 위치를 덮어쓰는 것 방지)
    _seekOverridePosition = position;
    _positionController.add(position);
    _seekOverrideTimer?.cancel();
    _seekOverrideTimer = Timer(const Duration(milliseconds: 500), () {
      _seekOverridePosition = null;
    });

    final targetFrame =
        (position.inMilliseconds * ts.sampleRate / 1000).round();

    await _engine.seekToFrame(targetFrame.clamp(0, ts.totalFrames));

    // seek-notify 전송 (절대 위치 ms — 몇 번 수신해도 같은 위치로 seek)
    _p2p.broadcastToAll({
      'type': 'seek-notify',
      'data': {'targetMs': position.inMilliseconds},
    });

    // 즉시 obs broadcast (seek 후 위치 알림)
    _broadcastObs();
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: audio-obs broadcast (500ms 주기)
  // ═══════════════════════════════════════════════════════════

  void _startObsBroadcast() {
    _obsBroadcastTimer?.cancel();
    _obsBroadcastTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      _broadcastObs();
    });
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

  void _handleDriftReport(Map<String, dynamic> message) {
    final from = message['_from'] as String?;
    final data = message['data'] as Map<String, dynamic>?;
    if (from == null || data == null) return;

    _logger.log(
      wallMs: (data['wallMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      guestId: from,
      driftMs: (data['driftMs'] as num?)?.toDouble() ?? 0,
      offsetMs: (data['offsetMs'] as num?)?.toDouble() ?? 0,
      hostVf: (data['hostVf'] as num?)?.toInt() ?? 0,
      guestVf: (data['guestVf'] as num?)?.toInt() ?? 0,
      seekCount: (data['seekCount'] as num?)?.toInt() ?? 0,
      event: data['event'] as String? ?? 'drift',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: audio-url 수신 → 파일 다운로드 → 네이티브 엔진 로드
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleAudioUrl(Map<String, dynamic> data) async {
    var url = data['url'] as String;
    final hostPlaying = data['playing'] as bool? ?? false;

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

    // HTTP 다운로드 → temp 파일
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = _currentFileName ?? 'audio_download';
      final tempFile = File('${tempDir.path}/$safeName');

      final swDownload = Stopwatch()..start();
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final totalBytes = response.contentLength; // -1 if unknown
        int receivedBytes = 0;
        final sink = tempFile.openWrite();
        try {
          await for (final chunk in response) {
            if (_downloadAborted) break;
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _downloadProgressController.add(receivedBytes / totalBytes);
            }
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }
      swDownload.stop();

      // cleanup 중 다운로드가 중단된 경우 로드 스킵
      if (_downloadAborted) {
        debugPrint('[GUEST] download aborted, skipping load');
        _isLoading = false;
        _loadingController.add(false);
        return;
      }

      debugPrint('[DOWNLOAD-GUEST] took ${swDownload.elapsedMilliseconds}ms');

      // 네이티브 엔진에 로드
      final swDecode = Stopwatch()..start();
      final loadResult = await _engine.loadFile(tempFile.path);
      swDecode.stop();
      debugPrint('[DECODE-GUEST] loadFile took ${swDecode.elapsedMilliseconds}ms');
      if (!loadResult.ok || _downloadAborted) {
        if (!_downloadAborted) _errorController.add('파일 로드 실패');
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

      // Android fallback: loadFile이 totalFrames를 안 줬으면 getTimestamp에서
      if (_currentDuration == null) {
        final ts = await _engine.getTimestamp();
        if (ts != null && ts.sampleRate > 0 && ts.totalFrames > 0) {
          _currentDuration = Duration(
              milliseconds: (ts.totalFrames * 1000 / ts.sampleRate).round());
          _durationController.add(_currentDuration);
        }
      }

      // 호스트가 재생 중이면 엔진 시작
      debugPrint('[GUEST] loadFile done, hostPlaying=$hostPlaying, audioReady=$_audioReady');
      if (hostPlaying) {
        await _startGuestPlayback();
      }
    } catch (e) {
      debugPrint('Audio download/load error: $e');
      if (!_downloadAborted) {
        _errorController.add('오디오 다운로드 실패');
      }
      _isLoading = false;
      _loadingController.add(false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: audio-obs 수신
  // ═══════════════════════════════════════════════════════════

  void _handleAudioObs(Map<String, dynamic> message) {
    try {
      final obs = AudioObs.fromJson(message);
      _latestObs = obs;

      if (obs.playing) {
        if (!_playing && _audioReady) {
          debugPrint('[GUEST] obs→startPlayback (playing=$_playing, ready=$_audioReady)');
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

  // ═══════════════════════════════════════════════════════════
  // 게스트: seek-notify 수신
  // ═══════════════════════════════════════════════════════════

  void _handleSeekNotify(Map<String, dynamic> message) {
    final targetMs = (message['data']?['targetMs'] as num?)?.toDouble();
    if (targetMs == null || !_playing) return;
    // 절대 위치 → 게스트 frame 변환. 몇 번 와도 같은 위치 (멱등)
    final targetGuestVf = (targetMs * _framesPerMs).round();
    unawaited(_engine.seekToFrame(targetGuestVf));
    // 앵커 무효화 + 쿨다운: fresh obs 도착 대기 후 re-anchor
    _anchorHostFrame = null;
    _anchorGuestFrame = null;
    _seekCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 1000;
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: 재생 시작/정지
  // ═══════════════════════════════════════════════════════════

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

    // 앵커/보정 상태 리셋 (엔진 재시작 시 mVirtualFrame=0)
    _resetDriftState();
  }

  Future<void> _stopGuestPlayback() async {
    if (!_playing) return;
    _playing = false;
    _playingController.add(false);
    await _engine.stop();
  }

  void _resetDriftState() {
    _anchorHostFrame = null;
    _anchorGuestFrame = null;
    _offsetAtAnchor = null;
    _seekCorrectionAccum = 0;
    _seekCooldownUntilMs = 0;
    _fallbackAlignCooldownMs = 0;
    _latestDriftMs = null;
    _driftSampleCount = 0;
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
    final driftMs = guestPositionMs - expectedPositionMs;

    // 500ms마다 drift report (fallback mode)
    if (ts.wallMs - _lastDriftReportMs >= 500) {
      _lastDriftReportMs = ts.wallMs;
      _sendDriftReport(
        wallMs: ts.wallMs,
        driftMs: driftMs,
        offsetMs: offset,
        hostVf: obs.virtualFrame,
        guestVf: ts.virtualFrame,
        event: 'fallback',
      );
    }

    if (ts.wallMs < _fallbackAlignCooldownMs) return;

    // 30ms 이상 차이나면 보정, 쿨다운 1초
    if (driftMs.abs() > 30) {
      // 게스트 frame 공간으로 변환하여 seek
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
    final targetGuestVf = (hostContentMs * _framesPerMs).round();
    final currentEffective = ts.framePos + _seekCorrectionAccum;
    final initialCorrection = targetGuestVf - currentEffective;
    unawaited(_engine.seekToFrame(targetGuestVf));
    _seekCorrectionAccum += initialCorrection;

    _anchorHostFrame = anchorHostFrame;
    _anchorGuestFrame = ts.framePos + _seekCorrectionAccum;
    _offsetAtAnchor = offset; // 앵커 시점의 offset 기록

    // HAL 버퍼 안정화 쿨다운
    _seekCooldownUntilMs = ts.wallMs + _seekCooldown.inMilliseconds;
  }

  /// 게스트 → 호스트로 drift report 전송 (500ms 주기).
  void _sendDriftReport({
    required int wallMs,
    required double driftMs,
    required double offsetMs,
    required int hostVf,
    required int guestVf,
    required String event,
  }) {
    _p2p.sendToHost({
      'type': 'drift-report',
      'data': {
        'wallMs': wallMs,
        'driftMs': driftMs,
        'offsetMs': offsetMs,
        'hostVf': hostVf,
        'guestVf': guestVf,
        'seekCount': _seekCount,
        'event': event,
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
    final driftMs = dGms - dHms; // 양수: 게스트 앞섬

    _latestDriftMs = driftMs;
    _driftSampleCount++;

    // 500ms마다 drift report 전송
    if (ts.wallMs - _lastDriftReportMs >= 500) {
      _lastDriftReportMs = ts.wallMs;
      _sendDriftReport(
        wallMs: ts.wallMs,
        driftMs: driftMs,
        offsetMs: offset,
        hostVf: obs.virtualFrame,
        guestVf: ts.virtualFrame,
        event: 'drift',
      );
    }

    // seek 판단
    _maybeTriggerSeek(ts.wallMs, driftMs);
  }

  /// |drift| ≥ 200ms → 앵커 리셋 (호스트 seek 등 큰 점프).
  /// |drift| ≥ 20ms → seek 보정.
  void _maybeTriggerSeek(int wallMs, double driftMs) {
    if (driftMs.abs() >= _reAnchorThresholdMs) {
      // 큰 drift → 앵커 리셋. 다음 poll에서 _tryEstablishAnchor가 재정렬.
      _anchorHostFrame = null;
      _anchorGuestFrame = null;
      _seekCooldownUntilMs = 0;
      return;
    }
    if (wallMs < _seekCooldownUntilMs) return;
    if (driftMs.abs() < _driftSeekThresholdMs) return;
    unawaited(_performSeek(wallMs, driftMs));
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

    // seek 이벤트 report
    _sendDriftReport(
      wallMs: wallMs,
      driftMs: driftMs,
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
          if (name.startsWith('audio_')) {
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

    if (_storedSafeName != null) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$_storedSafeName');
      if (await file.exists()) await file.delete();
    }
    _storedSafeName = null;
    _currentFileName = null;
    _currentUrl = null;
  }

  void cleanupSync() {
    _downloadAborted = true;
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
