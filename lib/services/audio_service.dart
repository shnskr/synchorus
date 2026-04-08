import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'audio_handler.dart';
import 'p2p_service.dart';
import 'sync_service.dart';

class AudioSyncService {
  final P2PService _p2p;
  final SyncService _sync;
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription? _messageSub;
  StreamSubscription? _bufferingSub;
  Timer? _syncPositionTimer;
  HttpServer? _httpServer;
  AudioPlayerHandler? _audioHandler;

  String? _currentFileName;
  // 디스크/HTTP 서빙용 ASCII-safe 파일명 (UI 표시용 _currentFileName과 분리)
  String? _storedSafeName;
  String? _currentUrl;
  bool _audioReady = false;

  // 호스트 재생 상태 추적 (게스트 전용)
  bool _hostPlaying = false;

  // 명령 직렬화: 빠른 재생/정지 반복 시 꼬임 방지
  int _commandSeq = 0;

  // 엔진 출력 레이턴시 보정
  // totalMs: 보정 계산에 쓰는 값 (양쪽 buffer만 잡힘 → Android와 측정 방식 통일)
  // rawOutputMs: iOS만 의미 있음 (AVAudioSession.outputLatency 원본값, 디버그 표시용)
  int _engineLatencyMs = 0;
  int _engineRawOutputMs = 0;
  int _engineBufferMs = 0;
  int _hostEngineLatencyMs = 0;
  int get _latencyCompensation => _engineLatencyMs - _hostEngineLatencyMs;

  int get engineLatencyMs => _engineLatencyMs;
  int get engineRawOutputMs => _engineRawOutputMs;
  int get engineBufferMs => _engineBufferMs;
  int get hostEngineLatencyMs => _hostEngineLatencyMs;
  int get latencyCompensation => _latencyCompensation;

  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  AudioPlayer get player => _player;
  String? get currentFileName => _currentFileName;
  String? get currentUrl => _currentUrl;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;

  AudioSyncService(this._p2p, this._sync);

  bool _isHost = false;

  // ─── 초기화 ───

  Future<void> startListening({required bool isHost}) async {
    _isHost = isHost;
    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen(_onMessage);

    await _initAudioHandler();
    await _measureEngineLatency();

    if (isHost) {
      await _cleanupTempDir();
      _startPositionBroadcast();
    } else {
      _startBufferingWatch();
    }
  }

  Future<void> _measureEngineLatency() async {
    try {
      const channel = MethodChannel('com.synchorus/audio_latency');
      final result = await channel.invokeMethod<Map>('getOutputLatency');
      if (result != null) {
        _engineLatencyMs = (result['totalMs'] as int?) ?? 0;
        _engineRawOutputMs = (result['outputLatencyMs'] as int?) ?? 0;
        _engineBufferMs = (result['bufferMs'] as int?) ?? 0;
        debugPrint('Engine latency: total=${_engineLatencyMs}ms '
            '(rawOutput=${_engineRawOutputMs}ms, buffer=${_engineBufferMs}ms)');
      }
    } catch (e) {
      debugPrint('Engine latency measurement failed: $e');
      _engineLatencyMs = 0;
      _engineRawOutputMs = 0;
      _engineBufferMs = 0;
    }
  }

  Future<void> _initAudioHandler() async {
    if (_audioHandler != null) return;
    try {
      _audioHandler = await AudioService.init(
        builder: () => AudioPlayerHandler(
          _player,
          isHost: () => _isHost,
          onPlay: () => syncPlay(),
          onPause: () => syncPause(),
          onSeek: (pos) => syncSeek(pos),
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.synchorus.audio',
          androidNotificationChannelName: 'Synchorus',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('AudioService init failed: $e');
    }
  }

  void _updateMediaItem() {
    _audioHandler?.mediaItem.add(MediaItem(
      id: _currentUrl ?? '',
      title: _currentFileName ?? 'Unknown',
      album: 'Synchorus',
      duration: _player.duration,
    ));
  }

  Future<void> _onMessage(Map<String, dynamic> message) async {
    try {
      switch (message['type']) {
        case 'audio-url':
          if (!_isHost) await _handleAudioUrl(message['data']);
          break;
        case 'play':
          if (!_isHost) await _handlePlay(message['data']);
          break;
        case 'pause':
          if (!_isHost) _handlePause(message['data']);
          break;
        case 'seek':
          if (!_isHost) await _handleSeek(message['data']);
          break;
        case 'sync-position':
          if (!_isHost) await _handleSyncPosition(message['data']);
          break;
        case 'audio-request':
          if (_isHost) _handleAudioRequest(message['_from']);
          break;
        case 'state-request':
          if (_isHost) _handleStateRequest(message['_from']);
          break;
        case 'state-response':
          if (!_isHost) await _handleStateResponse(message['data']);
          break;
      }
    } catch (e) {
      debugPrint('Error handling message ${message['type']}: $e');
    }
  }

  // ─── HTTP 파일 서버 ───

  Future<String?> _startFileServer(String dirPath, String fileName) async {
    await _stopFileServer();
    final handler = createStaticHandler(dirPath);
    try {
      _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, 41236);
    } catch (_) {
      // 포트 충돌 시 랜덤 포트로 fallback
      _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
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

  // ─── 호스트: 오디오 로드 ───

  Future<void> loadUrl(String url) async {
    _currentUrl = url;
    _currentFileName = null;
    _audioReady = false;
    await _stopFileServer();
    try {
      await _player.setUrl(url);
    } catch (e) {
      debugPrint('loadUrl failed: $e');
      _errorController.add('URL을 불러올 수 없습니다');
      return;
    }
    _audioReady = true;
    _updateMediaItem();

    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': url, 'playing': _player.playing},
    });
  }

  /// 원본 파일명을 ASCII-safe 해시명으로 변환 (한글/공백/특수문자 → AVPlayer 호환성)
  String _safeFileName(String original) {
    final dotIndex = original.lastIndexOf('.');
    final ext = (dotIndex >= 0 && dotIndex < original.length - 1)
        ? original.substring(dotIndex)
        : '';
    // 원본 파일명 기반 결정적 해시 (같은 파일이면 같은 이름)
    final bytes = original.codeUnits;
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    final extLower = ext.toLowerCase();
    return 'audio_${hash.toRadixString(16)}$extLower';
  }

  Future<void> loadFile(File file) async {
    final originalName = file.uri.pathSegments.last;
    final safeName = _safeFileName(originalName);
    _audioReady = false;
    _isLoading = true;
    _loadingController.add(true);

    final tempDir = await getTemporaryDirectory();

    // 이전 파일 삭제 (디스크에는 safeName으로 저장됨)
    if (_storedSafeName != null && _storedSafeName != safeName) {
      final old = File('${tempDir.path}/$_storedSafeName');
      if (await old.exists()) await old.delete();
    }

    final stableFile = File('${tempDir.path}/$safeName');
    await file.copy(stableFile.path);

    // HTTP 서버 시작
    final httpUrl = await _startFileServer(tempDir.path, safeName);
    if (httpUrl == null) {
      _isLoading = false;
      _loadingController.add(false);
      return;
    }

    _storedSafeName = safeName;
    _currentFileName = originalName; // UI 표시용은 원본 파일명 유지
    // 캐시 무효화용 timestamp 쿼리 (#8): AVPlayer가 같은 URL을 캐시해서 이전 데이터 재사용하는 문제 방지
    final urlWithCacheBust =
        '$httpUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    _currentUrl = urlWithCacheBust;
    await _player.setFilePath(stableFile.path);
    _audioReady = true;
    _updateMediaItem();

    // 게스트에게 URL 전달
    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': urlWithCacheBust, 'playing': _player.playing},
    });

    _isLoading = false;
    _loadingController.add(false);
  }

  /// 시작 시 호스트 temp 디렉토리 청소 (#16-b): 이전 세션 좀비 파일 제거
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

  // ─── 호스트: 재생 제어 ───

  Future<void> syncPlay() async {
    final hostTime = _sync.nowAsHostTime;
    final positionMs = _player.position.inMilliseconds;

    _p2p.broadcastToAll({
      'type': 'play',
      'data': {
        'hostTime': hostTime,
        'positionMs': positionMs,
        'engineLatencyMs': _engineLatencyMs,
      },
    });

    // 호스트도 seek → play 경로를 타서 게스트와 seek 비용을 대칭으로 맞춤
    await _player.seek(_player.position);
    await _player.play();
  }

  Future<void> syncPause() async {
    await _player.pause();
    final positionMs = _player.position.inMilliseconds;

    _p2p.broadcastToAll({
      'type': 'pause',
      'data': {'positionMs': positionMs},
    });
  }

  Future<void> syncSeek(Duration position) async {
    final wasPlaying = _player.playing;
    final hostTime = wasPlaying ? _sync.nowAsHostTime : null;

    _p2p.broadcastToAll({
      'type': 'seek',
      'data': {
        'positionMs': position.inMilliseconds,
        'hostTime': hostTime,
        'engineLatencyMs': _engineLatencyMs,
      },
    });

    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  // ─── 호스트: 피어에게 현재 오디오 전송 ───

  void sendCurrentAudioToPeer(String peerId) {
    if (_currentUrl == null) return;
    _p2p.sendToPeer(peerId, {
      'type': 'audio-url',
      'data': {
        'url': _currentUrl,
        'playing': _player.playing,
      },
    });
    // 게스트가 오디오 로드 완료 후 _hostPlaying 체크 → state-request로 최신 상태 요청
  }

  void _handleAudioRequest(String? fromId) {
    if (fromId == null) return;
    sendCurrentAudioToPeer(fromId);
  }

  // ─── 호스트: state-request 처리 ───

  void _handleStateRequest(String? fromId) {
    if (fromId == null) return;
    _p2p.sendToPeer(fromId, {
      'type': 'state-response',
      'data': {
        'hostTime': _sync.nowAsHostTime,
        'positionMs': _player.position.inMilliseconds,
        'playing': _player.playing,
        'engineLatencyMs': _engineLatencyMs,
      },
    });
  }

  // ─── 호스트: 5초마다 position 브로드캐스트 ───

  void _startPositionBroadcast() {
    _syncPositionTimer?.cancel();
    _syncPositionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing) {
        _p2p.broadcastToAll({
          'type': 'sync-position',
          'data': {
            'hostTime': _sync.nowAsHostTime,
            'positionMs': _player.position.inMilliseconds,
            'engineLatencyMs': _engineLatencyMs,
          },
        });
      }
    });
  }

  // ─── 게스트: 메시지 처리 ───

  Future<void> _handleAudioUrl(Map<String, dynamic> data) async {
    var url = data['url'] as String;

    // audio-url에 재생 상태가 포함되어 있으면 _hostPlaying 업데이트
    final playing = data['playing'] as bool?;
    if (playing != null) _hostPlaying = playing;

    // 게스트: URL의 호스트를 실제 연결한 IP로 치환 (에뮬레이터 등 네트워크 경로가 다른 경우)
    final connectedIp = _p2p.connectedHostIp;
    if (connectedIp != null) {
      // 정규식으로 호스트 부분만 치환 (Uri.parse 이중 인코딩 방지)
      url = url.replaceFirst(RegExp(r'http://[^:/]+'), 'http://$connectedIp');
      debugPrint('Audio URL rewritten: $url');
    }

    // 새 audio-url 진입 시 stale 상태 리셋 (#4)
    _awaitingStateResponse = false;

    // 새 URL 처리는 이전 명령보다 우선 → seq 증가로 in-flight 작업 무효화
    final seq = ++_commandSeq;

    await _player.stop();
    _audioReady = false;

    _currentUrl = url;
    try {
      final pathPart = url.split('/').last;
      // 쿼리스트링 제거 (캐시 무효화용 ?v=... 떼기)
      final cleanPath = pathPart.split('?').first;
      final decoded = Uri.decodeComponent(cleanPath);
      _currentFileName = decoded.isNotEmpty ? decoded : null;
    } catch (_) {
      _currentFileName = url.split('/').last;
    }

    _isLoading = true;
    _loadingController.add(true);

    bool loaded = false;
    try {
      await _player.setUrl(url);
      if (seq != _commandSeq) return; // stale
      loaded = true;
    } catch (e) {
      debugPrint('Audio URL load error: $e');
      // 로드 실패 시 2초 후 한 번 재시도 (PLAN 125, stale check 포함)
      await Future.delayed(const Duration(seconds: 2));
      if (seq != _commandSeq) return; // 그 사이 새 URL 왔으면 포기
      try {
        await _player.setUrl(url);
        if (seq != _commandSeq) return;
        loaded = true;
        debugPrint('Audio URL retry succeeded');
      } catch (e2) {
        debugPrint('Audio URL retry failed: $e2');
        _errorController.add('오디오를 불러올 수 없습니다');
      }
    }

    if (loaded) {
      _audioReady = true;
      _updateMediaItem();
    }

    _isLoading = false;
    _loadingController.add(false);

    // 오디오 로드 완료 + 호스트가 재생 중이면 최신 상태 요청
    if (_audioReady && _hostPlaying && seq == _commandSeq) {
      _requestHostState();
    }
  }

  Future<void> _handlePlay(Map<String, dynamic> data) async {
    _hostPlaying = true;

    if (!_audioReady) {
      // 준비 안 됨 → 플래그만 저장, 준비 완료 후 state-request로 최신 상태 받음
      debugPrint('SYNC_PLAY: not ready, flagging _hostPlaying=true');
      return;
    }

    final seq = ++_commandSeq;

    final hostTime = data['hostTime'] as int;
    final positionMs = data['positionMs'] as int;
    _hostEngineLatencyMs = (data['engineLatencyMs'] as int?) ?? 0;

    // 에러 상태면 오디오 재로드 (먼저 처리 → reload 시간이 elapsed에 포함되도록)
    if (_player.processingState == ProcessingState.idle && _currentUrl != null) {
      debugPrint('Player in error/idle state, reloading audio...');
      await _reloadAudio();
      if (seq != _commandSeq || !_audioReady) return;
    }

    // hostTime 기준 elapsed는 reload 후 시점에 다시 계산해야 정확
    final elapsed = _sync.nowAsHostTime - hostTime;
    final targetPosition = positionMs + elapsed + _latencyCompensation;
    final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;

    debugPrint('SYNC_PLAY: hostTime=$hostTime, positionMs=$positionMs, '
        'elapsed=$elapsed, target=$targetPosition, '
        'engineComp=$_latencyCompensation (my=$_engineLatencyMs, host=$_hostEngineLatencyMs)');

    await _internalSeek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
    if (seq != _commandSeq) return;

    if (!_player.playing) {
      await _player.play();
    }
  }

  Future<void> _handlePause(Map<String, dynamic> data) async {
    _hostPlaying = false;
    ++_commandSeq;

    if (!_audioReady) return;

    await _player.pause();
    final positionMs = data['positionMs'] as int?;
    if (positionMs != null) {
      await _internalSeek(Duration(milliseconds: positionMs));
    }
  }

  Future<void> _handleSeek(Map<String, dynamic> data) async {
    if (!_audioReady) return;
    final seq = ++_commandSeq;
    final positionMs = data['positionMs'] as int;
    final hostTime = data['hostTime'];
    final hostLatency = (data['engineLatencyMs'] as int?) ?? _hostEngineLatencyMs;
    if (hostLatency > 0) _hostEngineLatencyMs = hostLatency;

    if (hostTime != null) {
      final elapsed = _sync.nowAsHostTime - (hostTime as int);
      final targetPosition = positionMs + elapsed + _latencyCompensation;
      final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;
      await _internalSeek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
      if (seq != _commandSeq) return;
      if (!_player.playing) {
        await _player.play();
      }
    } else {
      await _internalSeek(Duration(milliseconds: positionMs));
    }
  }

  // ─── 게스트: 재생 중 싱크 보정 ───

  bool _syncSeeking = false;

  Future<void> _handleSyncPosition(Map<String, dynamic> data) async {
    final hostTime = data['hostTime'] as int;
    final hostPositionMs = data['positionMs'] as int;
    final hostLatency = (data['engineLatencyMs'] as int?) ?? _hostEngineLatencyMs;
    if (hostLatency > 0) _hostEngineLatencyMs = hostLatency;

    if (!_player.playing) return;
    if (_player.processingState != ProcessingState.ready) return;
    if (_syncSeeking) return;

    final elapsed = _sync.nowAsHostTime - hostTime;
    final expectedPosition = hostPositionMs + elapsed + _latencyCompensation;
    final myPosition = _player.position.inMilliseconds;
    final diff = expectedPosition - myPosition;

    debugPrint('SYNC_POS: expected=$expectedPosition, my=$myPosition, diff=$diff');

    // 100ms 미만은 무시 (seek로 인한 추가 버퍼링 비용을 피하기 위해 임계값 상향)
    if (diff.abs() < 100) return;

    _syncSeeking = true;
    final maxPosition = _player.duration?.inMilliseconds ?? expectedPosition;
    try {
      await _internalSeek(Duration(milliseconds: expectedPosition.clamp(0, maxPosition)));
    } catch (e) {
      debugPrint('Sync seek error: $e, reloading audio...');
      await _reloadAudio();
    }
    _syncSeeking = false;

    debugPrint('Sync: ${diff}ms → seek to ${expectedPosition}ms');
  }

  // ─── 게스트: 오디오 에러 시 재로드 ───

  bool _reloadInProgress = false;

  Future<void> _reloadAudio() async {
    if (_currentUrl == null) return;
    if (_reloadInProgress) return;
    _reloadInProgress = true;
    debugPrint('Reloading audio from $_currentUrl');
    try {
      await _player.setUrl(_currentUrl!);
      _audioReady = true;
      // ready 상태까지 대기 (#14): 직후 seek/play가 buffering 단계에서 호출되어 흔들리는 것 방지
      await _waitUntilReady();
    } catch (e) {
      debugPrint('Audio reload failed: $e');
      // 호스트에게 다시 요청
      requestCurrentAudio();
    } finally {
      _reloadInProgress = false;
    }
  }

  /// 플레이어가 ready/completed 상태가 될 때까지 최대 [timeout]ms 대기
  Future<void> _waitUntilReady({int timeoutMs = 3000}) async {
    if (_player.processingState == ProcessingState.ready ||
        _player.processingState == ProcessingState.completed) {
      return;
    }
    try {
      await _player.processingStateStream
          .firstWhere((s) =>
              s == ProcessingState.ready || s == ProcessingState.completed)
          .timeout(Duration(milliseconds: timeoutMs));
    } catch (_) {
      // 타임아웃이면 그냥 진행 (호출 측에서 후속 처리)
    }
  }

  // ─── 게스트: 버퍼링 복구 감지 ───

  ProcessingState? _lastProcessingState;

  bool _awaitingStateResponse = false;

  /// 내부 seek 진행 중 표시. true인 동안은 buffering 전환을 자연 발생으로 보지 않고 무시.
  bool _internalSeeking = false;

  void _startBufferingWatch() {
    _bufferingSub?.cancel();
    _bufferingSub = _player.processingStateStream.listen((state) {
      // 내부 seek로 인한 buffering 전환은 무시 (recovery 루프 방지)
      if (_internalSeeking) {
        _lastProcessingState = state;
        return;
      }
      if (_lastProcessingState == ProcessingState.buffering &&
          state == ProcessingState.ready &&
          _player.playing) {
        if (_awaitingStateResponse) {
          debugPrint('Buffering recovery: skipped (awaiting state-response)');
          _lastProcessingState = state;
          return;
        }
        _awaitingStateResponse = true;
        debugPrint('Buffering recovery: requesting host state');
        _requestHostState();
      }
      _lastProcessingState = state;
    });
  }

  /// 내부 seek 래퍼: buffering watch가 무시하도록 플래그 설정
  Future<void> _internalSeek(Duration position) async {
    _internalSeeking = true;
    try {
      await _player.seek(position);
    } finally {
      // 약간 여유 두고 해제 (seek 직후 발생하는 buffering→ready 전환까지 무시)
      Future.delayed(const Duration(milliseconds: 500), () {
        _internalSeeking = false;
      });
    }
  }

  // ─── 게스트: state-response 처리 ───

  Future<void> _handleStateResponse(Map<String, dynamic> data) async {
    _awaitingStateResponse = false;

    final playing = data['playing'] as bool? ?? false;
    if (!playing || !_audioReady || !_hostPlaying) return;

    final seq = ++_commandSeq;

    final hostTime = data['hostTime'] as int;
    final positionMs = data['positionMs'] as int;
    _hostEngineLatencyMs = (data['engineLatencyMs'] as int?) ?? 0;

    // 에러 상태면 먼저 재로드 (그 사이 시간은 elapsed에 포함되어야 함)
    if (_player.processingState == ProcessingState.idle && _currentUrl != null) {
      await _reloadAudio();
      if (seq != _commandSeq || !_audioReady) return;
    }

    final elapsed = _sync.nowAsHostTime - hostTime;
    final targetPosition = positionMs + elapsed + _latencyCompensation;
    final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;

    debugPrint('STATE_RESPONSE: hostTime=$hostTime, positionMs=$positionMs, '
        'elapsed=$elapsed, target=$targetPosition');

    // 현재 위치와 목표 위치 차이가 작으면 seek 생략 (불필요한 재버퍼링 방지)
    final myPosition = _player.position.inMilliseconds;
    if ((targetPosition - myPosition).abs() >= 200) {
      await _internalSeek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
      if (seq != _commandSeq) return;
    }

    if (!_player.playing) {
      await _player.play();
    }
  }

  // ─── 게스트: 상태 요청 ───

  void _requestHostState() {
    _p2p.sendToHost({
      'type': 'state-request',
      'data': {},
    });
  }

  // ─── 게스트: 오디오 요청 ───

  void requestCurrentAudio() {
    _p2p.sendToHost({
      'type': 'audio-request',
      'data': {},
    });
  }

  // ─── 정리 ───

  Future<void> clearTempFiles() async {
    _isLoading = false;
    _loadingController.add(false);
    _audioReady = false;
    _hostPlaying = false;
    await _audioHandler?.stop();
    await _player.stop();
    _syncPositionTimer?.cancel();
    _bufferingSub?.cancel();
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

  /// 동기적으로 가능한 정리만 수행 (dispose에서 호출용)
  void cleanupSync() {
    _isLoading = false;
    _audioReady = false;
    _hostPlaying = false;
    _awaitingStateResponse = false;
    _syncPositionTimer?.cancel();
    _bufferingSub?.cancel();
    _messageSub?.cancel();
    _messageSub = null;
    _storedSafeName = null;
    _currentFileName = null;
    _currentUrl = null;
  }

  Future<void> dispose() async {
    cleanupSync();
    _loadingController.close();
    _errorController.close();
    await _stopFileServer();
    await _player.dispose();
  }
}
