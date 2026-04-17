import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import '../models/audio_obs.dart';
import 'native_audio_service.dart';
import 'p2p_service.dart';
import 'sync_service.dart';

// ── drift / seek 파라미터 (PoC Phase 4 검증 완료) ──────────────
const double _driftSeekThresholdMs = 20.0;
const double _seekCorrectionGain = 0.8;
const Duration _seekCooldown = Duration(milliseconds: 1000);
const double _defaultFramesPerMs = 48.0; // fallback (실제 sampleRate 미확인 시)
const double _reAnchorThresholdMs = 200.0;

/// v3 오디오 동기화 서비스.
/// 호스트: 네이티브 엔진 재생 + audio-obs broadcast + HTTP 파일 서빙.
/// 게스트: 파일 다운로드 + 네이티브 엔진 재생 + drift 계산 + seek 보정.
class NativeAudioSyncService {
  final P2PService _p2p;
  final SyncService _sync;
  final NativeAudioService _engine = NativeAudioService();

  StreamSubscription? _messageSub;
  Timer? _obsBroadcastTimer;
  StreamSubscription? _timestampSub;
  HttpServer? _httpServer;

  bool _isHost = false;
  bool _playing = false;
  bool _audioReady = false;
  bool _isLoading = false;
  String? _currentFileName;
  String? _storedSafeName;
  String? _currentUrl;
  int _obsBroadcastSeq = 0;

  // ── 게스트: drift 보정 상태 ────────────────────────────────
  AudioObs? _latestObs;
  // 앵커: drift=0 기준선
  int? _anchorHostFrame;
  int? _anchorGuestFrame;
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

  Future<void> startListening({required bool isHost}) async {
    _isHost = isHost;
    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen(_onMessage);

    if (isHost) {
      await _cleanupTempDir();
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
    final ip = await NetworkInfo().getWifiIP();
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
    bool ok;
    final sw = Stopwatch()..start();
    try {
      ok = await _engine.loadFile(stableFile.path);
    } on PlatformException catch (e) {
      _isLoading = false;
      _loadingController.add(false);
      _errorController.add(NativeAudioService.errorToMessage(e.message ?? ''));
      return;
    }
    sw.stop();
    debugPrint('[DECODE-HOST] loadFile took ${sw.elapsedMilliseconds}ms');
    if (!ok) {
      _isLoading = false;
      _loadingController.add(false);
      _errorController.add('파일 로드 실패');
      return;
    }

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

    // duration 전파
    final ts = await _engine.getTimestamp();
    if (ts != null && ts.sampleRate > 0) {
      _currentDuration = Duration(
          milliseconds: (ts.totalFrames * 1000 / ts.sampleRate).round());
      _durationController.add(_currentDuration);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 호스트: 재생 제어
  // ═══════════════════════════════════════════════════════════

  Future<void> syncPlay() async {
    if (!_audioReady) return;

    // play 직전 position 캡처 (start 직후 첫 poll까지 seek bar 0:00 점프 방지)
    final ts = _engine.latest;
    final vf = await _engine.getVirtualFrame();
    final sr = ts?.sampleRate ?? 0;
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
    final currentVf = ts.virtualFrame;
    final deltaFrames = targetFrame - currentVf;

    await _engine.seekToFrame(targetFrame.clamp(0, ts.totalFrames));

    // seek-notify 전송
    _p2p.broadcastToAll({
      'type': 'seek-notify',
      'data': {'deltaFrames': deltaFrames},
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
    if (ts == null || !ts.ok) return;

    final obs = AudioObs(
      seq: _obsBroadcastSeq++,
      // hostTimeMs는 framePos가 측정된 시각 (네이티브에서 원자적 캡처)
      hostTimeMs: ts.wallMs,
      framePos: ts.framePos,
      timeNs: ts.timeNs,
      virtualFrame: ts.virtualFrame,
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

    // HTTP 다운로드 → temp 파일
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = _currentFileName ?? 'audio_download';
      final tempFile = File('${tempDir.path}/$safeName');

      final swDownload = Stopwatch()..start();
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final totalBytes = response.contentLength; // -1 if unknown
      int receivedBytes = 0;
      final sink = tempFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgressController.add(receivedBytes / totalBytes);
        }
      }
      await sink.close();
      client.close();
      swDownload.stop();
      debugPrint('[DOWNLOAD-GUEST] took ${swDownload.elapsedMilliseconds}ms'
          ' ($receivedBytes bytes)');

      // 네이티브 엔진에 로드
      final swDecode = Stopwatch()..start();
      final ok = await _engine.loadFile(tempFile.path);
      swDecode.stop();
      debugPrint('[DECODE-GUEST] loadFile took ${swDecode.elapsedMilliseconds}ms');
      if (!ok) {
        _errorController.add('파일 로드 실패');
        _isLoading = false;
        _loadingController.add(false);
        return;
      }

      _audioReady = true;
      _isLoading = false;
      _loadingController.add(false);

      // 엔진 폴링 시작 (drift 계산 + UI position)
      _engine.startPolling();
      _startTimestampWatch();

      // duration 전파
      final ts = await _engine.getTimestamp();
      if (ts != null && ts.sampleRate > 0) {
        _currentDuration = Duration(
            milliseconds: (ts.totalFrames * 1000 / ts.sampleRate).round());
        _durationController.add(_currentDuration);
      }

      // 호스트가 재생 중이면 엔진 시작
      debugPrint('[GUEST] loadFile done, hostPlaying=$hostPlaying, audioReady=$_audioReady');
      if (hostPlaying) {
        await _startGuestPlayback();
      }
    } catch (e) {
      debugPrint('Audio download/load error: $e');
      _errorController.add('오디오 다운로드 실패');
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
    final delta = (message['data']?['deltaFrames'] as num?)?.toInt();
    if (delta == null || !_playing) return;
    unawaited(_applyHostSeek(delta));
  }

  Future<void> _applyHostSeek(int deltaFrames) async {
    try {
      final vf = await _engine.getVirtualFrame();
      await _engine.seekToFrame(vf + deltaFrames);
    } catch (_) {}
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

      // 게스트: 정밀 drift 보정 (HAL framePos 기반)
      if (!_isHost && _playing) {
        if (_anchorHostFrame == null) {
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
    final obs = _latestObs;
    if (obs == null || !obs.playing) return;
    if (ts.wallMs < _fallbackAlignCooldownMs) return;

    final offset = _sync.filteredOffsetMs;
    final hostWallNow = ts.wallMs + offset;
    final expectedHostVf = obs.virtualFrame +
        ((hostWallNow - obs.hostTimeMs) * _framesPerMs).round();

    final diff = (expectedHostVf - ts.virtualFrame).abs();
    // 2400 frames (50ms) 이상 차이나면 보정, 쿨다운 2초
    if (diff > 2400) {
      unawaited(_engine.seekToFrame(expectedHostVf));
      _fallbackAlignCooldownMs = ts.wallMs + 2000;
      debugPrint('[FALLBACK] align: diff=$diff, seekTo=$expectedHostVf');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 게스트: drift 계산 (PoC Phase 4 알고리즘)
  // ═══════════════════════════════════════════════════════════

  /// 앵커 설정: clock sync 완료 + playing obs 수신 + ok sample 시.
  /// obs를 앵커 시점으로 외삽하여 시간축 정합.
  void _tryEstablishAnchor(NativeTimestamp ts) {
    if (!_sync.isSynced) return;
    final offset = _sync.filteredOffsetMs;
    final obs = _latestObs;
    if (obs == null || !obs.playing) return;

    // 앵커 순간의 호스트 wall clock = 게스트 wall + offset
    final anchorHostWall = ts.wallMs + offset;
    // obs는 최대 500ms 오래된 값 → 앵커 시점으로 외삽
    final anchorHostFrame = obs.framePos +
        ((anchorHostWall - obs.hostTimeMs) * _framesPerMs).round();

    // 콘텐츠 정렬: 게스트를 호스트 virtualFrame 위치로 점프
    final hostContentFrame = obs.virtualFrame +
        ((anchorHostWall - obs.hostTimeMs) * _framesPerMs).round();
    final currentEffective = ts.framePos + _seekCorrectionAccum;
    final initialCorrection = anchorHostFrame - currentEffective;
    unawaited(_engine.seekToFrame(hostContentFrame));
    _seekCorrectionAccum += initialCorrection;

    _anchorHostFrame = anchorHostFrame;
    // 초기 정렬 후 anchorGF == anchorHF
    _anchorGuestFrame = ts.framePos + _seekCorrectionAccum;

    // HAL 버퍼 안정화 쿨다운
    _seekCooldownUntilMs = ts.wallMs + _seekCooldown.inMilliseconds;
  }

  /// 매 poll마다 drift(ms) 재계산.
  void _recomputeDrift(NativeTimestamp ts) {
    final obs = _latestObs;
    final anchorHF = _anchorHostFrame;
    final anchorGF = _anchorGuestFrame;
    final offset = _sync.filteredOffsetMs;
    if (obs == null || anchorHF == null || anchorGF == null) return;

    // 호스트의 현재 예상 frame (obs 외삽)
    final hostWallNow = ts.wallMs + offset;
    final expectedHostFrameNow =
        obs.framePos + (hostWallNow - obs.hostTimeMs) * _framesPerMs;
    final dH = expectedHostFrameNow - anchorHF;

    // 게스트의 effective frame (seek 보정 포함)
    final effectiveGuestFrame = ts.framePos + _seekCorrectionAccum;
    final dG = (effectiveGuestFrame - anchorGF).toDouble();

    final driftFrame = dG - dH; // 양수: 게스트 앞섬
    final driftMs = driftFrame / _framesPerMs;

    _latestDriftMs = driftMs;
    _driftSampleCount++;

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
    _isLoading = false;
    _loadingController.add(false);
    _audioReady = false;
    _playing = false;
    _playingController.add(false);
    _engine.stopPolling();
    await _engine.stop();
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
    _resetDriftState();
    _storedSafeName = null;
    _currentFileName = null;
    _currentUrl = null;
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
    await _engine.dispose();
  }
}
