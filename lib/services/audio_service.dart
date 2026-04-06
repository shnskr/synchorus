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
  String? _currentUrl;
  bool _audioReady = false;

  // 호스트 재생 상태 추적 (게스트 전용)
  bool _hostPlaying = false;

  // 명령 직렬화: 빠른 재생/정지 반복 시 꼬임 방지
  int _commandSeq = 0;

  // 엔진 출력 레이턴시 보정
  int _engineLatencyMs = 0;
  int _hostEngineLatencyMs = 0;
  int get _latencyCompensation => _engineLatencyMs - _hostEngineLatencyMs;

  // 마지막 수신한 sync-position (버퍼링 복구용)
  int? _lastSyncHostTime;
  int? _lastSyncPositionMs;

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
        debugPrint('Engine latency: ${_engineLatencyMs}ms');
      }
    } catch (e) {
      debugPrint('Engine latency measurement failed: $e');
      _engineLatencyMs = 0;
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
          if (!_isHost) _handlePlay(message['data']);
          break;
        case 'pause':
          if (!_isHost) _handlePause(message['data']);
          break;
        case 'seek':
          if (!_isHost) _handleSeek(message['data']);
          break;
        case 'sync-position':
          if (!_isHost) _handleSyncPosition(message['data']);
          break;
        case 'audio-request':
          if (_isHost) _handleAudioRequest(message['_from']);
          break;
        case 'state-request':
          if (_isHost) _handleStateRequest(message['_from']);
          break;
        case 'state-response':
          if (!_isHost) _handleStateResponse(message['data']);
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
    if (ip == null) return null;
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
    await _player.setUrl(url);
    _audioReady = true;
    _updateMediaItem();

    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': url, 'playing': _player.playing},
    });
  }

  Future<void> loadFile(File file) async {
    final fileName = file.uri.pathSegments.last;
    _audioReady = false;
    _isLoading = true;
    _loadingController.add(true);

    final tempDir = await getTemporaryDirectory();

    // 이전 파일 삭제
    if (_currentFileName != null && _currentFileName != fileName) {
      final old = File('${tempDir.path}/$_currentFileName');
      if (await old.exists()) await old.delete();
    }

    final stableFile = File('${tempDir.path}/$fileName');
    await file.copy(stableFile.path);

    // HTTP 서버 시작
    final httpUrl = await _startFileServer(tempDir.path, fileName);
    if (httpUrl == null) {
      _isLoading = false;
      _loadingController.add(false);
      return;
    }

    _currentFileName = fileName;
    _currentUrl = httpUrl;
    await _player.setFilePath(stableFile.path);
    _audioReady = true;
    _updateMediaItem();

    // 게스트에게 URL 전달
    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': httpUrl, 'playing': _player.playing},
    });

    _isLoading = false;
    _loadingController.add(false);
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
    await _player.seek(position);

    _p2p.broadcastToAll({
      'type': 'seek',
      'data': {
        'positionMs': position.inMilliseconds,
        'hostTime': wasPlaying ? _sync.nowAsHostTime : null,
        'engineLatencyMs': _engineLatencyMs,
      },
    });
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

    await _player.stop();
    _audioReady = false;

    _currentUrl = url;
    try {
      final pathPart = url.split('/').last;
      final decoded = Uri.decodeComponent(pathPart);
      _currentFileName = decoded.isNotEmpty ? decoded : null;
    } catch (_) {
      _currentFileName = url.split('/').last;
    }

    _isLoading = true;
    _loadingController.add(true);

    try {
      await _player.setUrl(url);
      _audioReady = true;
      _updateMediaItem();
    } catch (e) {
      debugPrint('Audio URL load error: $e');
      // 로드 실패 시 2초 후 한 번 재시도
      await Future.delayed(const Duration(seconds: 2));
      try {
        await _player.setUrl(url);
        _audioReady = true;
        _updateMediaItem();
        debugPrint('Audio URL retry succeeded');
      } catch (e2) {
        debugPrint('Audio URL retry failed: $e2');
        _errorController.add('오디오를 불러올 수 없습니다');
      }
    }

    _isLoading = false;
    _loadingController.add(false);

    // 오디오 로드 완료 + 호스트가 재생 중이면 최신 상태 요청
    if (_audioReady && _hostPlaying) {
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

    final elapsed = _sync.nowAsHostTime - hostTime;
    final targetPosition = positionMs + elapsed + _latencyCompensation;
    final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;

    debugPrint('SYNC_PLAY: hostTime=$hostTime, positionMs=$positionMs, '
        'elapsed=$elapsed, target=$targetPosition, '
        'engineComp=$_latencyCompensation (my=$_engineLatencyMs, host=$_hostEngineLatencyMs)');

    // 에러 상태면 오디오 재로드
    if (_player.processingState == ProcessingState.idle && _currentUrl != null) {
      debugPrint('Player in error/idle state, reloading audio...');
      await _reloadAudio();
      if (seq != _commandSeq || !_audioReady) return;
    }

    _lastBufferingRecovery = DateTime.now();
    await _player.seek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
    if (seq != _commandSeq) return;

    if (!_player.playing) {
      await _player.play();
    }
  }

  void _handlePause(Map<String, dynamic> data) {
    _hostPlaying = false;
    ++_commandSeq;

    if (!_audioReady) return;

    _player.pause();
    final positionMs = data['positionMs'] as int?;
    if (positionMs != null) {
      _player.seek(Duration(milliseconds: positionMs));
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
      await _player.seek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
      if (seq != _commandSeq) return;
      if (!_player.playing) {
        await _player.play();
      }
    } else {
      await _player.seek(Duration(milliseconds: positionMs));
    }
  }

  // ─── 게스트: 재생 중 싱크 보정 ───

  bool _syncSeeking = false;

  Future<void> _handleSyncPosition(Map<String, dynamic> data) async {
    final hostTime = data['hostTime'] as int;
    final hostPositionMs = data['positionMs'] as int;
    final hostLatency = (data['engineLatencyMs'] as int?) ?? _hostEngineLatencyMs;
    if (hostLatency > 0) _hostEngineLatencyMs = hostLatency;

    _lastSyncHostTime = hostTime;
    _lastSyncPositionMs = hostPositionMs;

    if (!_player.playing) return;
    if (_player.processingState != ProcessingState.ready) return;
    if (_syncSeeking) return;

    final elapsed = _sync.nowAsHostTime - hostTime;
    final expectedPosition = hostPositionMs + elapsed + _latencyCompensation;
    final myPosition = _player.position.inMilliseconds;
    final diff = expectedPosition - myPosition;

    debugPrint('SYNC_POS: expected=$expectedPosition, my=$myPosition, diff=$diff');

    if (diff.abs() < 30) return; // 30ms 미만: 무시

    // 30ms 이상: seek로 보정
    _syncSeeking = true;
    _lastBufferingRecovery = DateTime.now();
    final nowElapsed = _sync.nowAsHostTime - hostTime;
    final adjustedPosition = hostPositionMs + nowElapsed + _latencyCompensation;
    final maxPosition = _player.duration?.inMilliseconds ?? adjustedPosition;
    try {
      await _player.seek(Duration(milliseconds: adjustedPosition.clamp(0, maxPosition)));
    } catch (e) {
      debugPrint('Sync seek error: $e, reloading audio...');
      await _reloadAudio();
    }
    _syncSeeking = false;

    debugPrint('Sync: ${diff}ms → seek to ${adjustedPosition}ms');
  }

  // ─── 게스트: 오디오 에러 시 재로드 ───

  Future<void> _reloadAudio() async {
    if (_currentUrl == null) return;
    debugPrint('Reloading audio from $_currentUrl');
    try {
      await _player.setUrl(_currentUrl!);
      _audioReady = true;
    } catch (e) {
      debugPrint('Audio reload failed: $e');
      // 호스트에게 다시 요청
      requestCurrentAudio();
    }
  }

  // ─── 게스트: 버퍼링 복구 감지 ───

  ProcessingState? _lastProcessingState;

  DateTime? _lastBufferingRecovery;

  void _startBufferingWatch() {
    _bufferingSub?.cancel();
    _bufferingSub = _player.processingStateStream.listen((state) {
      if (_lastProcessingState == ProcessingState.buffering &&
          state == ProcessingState.ready &&
          _player.playing &&
          _lastSyncHostTime != null) {
        final now = DateTime.now();
        if (_lastBufferingRecovery != null &&
            now.difference(_lastBufferingRecovery!).inMilliseconds < 2000) {
          debugPrint('Buffering recovery: skipped (too soon)');
          _lastProcessingState = state;
          return;
        }
        _lastBufferingRecovery = now;

        final elapsed = _sync.nowAsHostTime - _lastSyncHostTime!;
        final expectedPosition = _lastSyncPositionMs! + elapsed + _latencyCompensation;
        final maxPosition = _player.duration?.inMilliseconds ?? expectedPosition;
        _player.seek(Duration(milliseconds: expectedPosition.clamp(0, maxPosition)));

        debugPrint('Buffering recovery: seek to ${expectedPosition}ms');
      }
      _lastProcessingState = state;
    });
  }

  // ─── 게스트: state-response 처리 ───

  Future<void> _handleStateResponse(Map<String, dynamic> data) async {
    final playing = data['playing'] as bool? ?? false;
    if (!playing || !_audioReady) return;

    final seq = ++_commandSeq;

    final hostTime = data['hostTime'] as int;
    final positionMs = data['positionMs'] as int;
    _hostEngineLatencyMs = (data['engineLatencyMs'] as int?) ?? 0;

    final elapsed = _sync.nowAsHostTime - hostTime;
    final targetPosition = positionMs + elapsed + _latencyCompensation;
    final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;

    debugPrint('STATE_RESPONSE: hostTime=$hostTime, positionMs=$positionMs, '
        'elapsed=$elapsed, target=$targetPosition');

    // 에러 상태면 오디오 재로드
    if (_player.processingState == ProcessingState.idle && _currentUrl != null) {
      await _reloadAudio();
      if (seq != _commandSeq || !_audioReady) return;
    }

    _lastBufferingRecovery = DateTime.now();
    await _player.seek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
    if (seq != _commandSeq) return;

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

    if (_currentFileName != null) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$_currentFileName');
      if (await file.exists()) await file.delete();
    }
    _currentFileName = null;
    _currentUrl = null;
    _lastSyncHostTime = null;
    _lastSyncPositionMs = null;
  }

  /// 동기적으로 가능한 정리만 수행 (dispose에서 호출용)
  void cleanupSync() {
    _isLoading = false;
    _audioReady = false;
    _hostPlaying = false;
    _syncPositionTimer?.cancel();
    _bufferingSub?.cancel();
    _messageSub?.cancel();
    _messageSub = null;
    _currentFileName = null;
    _currentUrl = null;
    _lastSyncHostTime = null;
    _lastSyncPositionMs = null;
  }

  Future<void> dispose() async {
    cleanupSync();
    _loadingController.close();
    _errorController.close();
    await _stopFileServer();
    await _player.dispose();
  }
}
