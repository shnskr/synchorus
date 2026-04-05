import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
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
  Map<String, dynamic>? _pendingPlay;

  int _engineLatencyMs = 0;
  int _lastSeekTime = 0; // seek 쿨다운용
  int get engineLatencyMs => _engineLatencyMs;

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

    if (isHost) {
      _startPositionBroadcast();
    } else {
      _startBufferingWatch();
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
          if (!_isHost) await _handlePause(message['data']);
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
      'data': {'url': url},
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
      'data': {'url': httpUrl},
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
      },
    });

    // 호스트: 즉시 재생
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
      'data': {'url': _currentUrl},
    });
    if (_player.playing) {
      _p2p.sendToPeer(peerId, {
        'type': 'play',
        'data': {
          'hostTime': _sync.nowAsHostTime,
          'positionMs': _player.position.inMilliseconds,
        },
      });
    }
  }

  void _handleAudioRequest(String? fromId) {
    if (fromId == null) return;
    sendCurrentAudioToPeer(fromId);
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
          },
        });
      }
    });
  }

  // ─── 게스트: 메시지 처리 ───

  Future<void> _handleAudioUrl(Map<String, dynamic> data) async {
    var url = data['url'] as String;

    // 게스트: URL의 호스트를 실제 연결한 IP로 치환 (에뮬레이터 등 네트워크 경로가 다른 경우)
    final connectedIp = _p2p.connectedHostIp;
    if (connectedIp != null) {
      final uri = Uri.parse(url);
      if (uri.host != connectedIp) {
        url = uri.replace(host: connectedIp).toString();
        debugPrint('Audio URL rewritten: $url');
      }
    }

    await _player.stop();
    _pendingPlay = null;
    _audioReady = false;

    _currentUrl = url;
    final decoded = Uri.decodeComponent(
      Uri.parse(url).pathSegments.lastOrNull ?? '',
    );
    _currentFileName = decoded.isNotEmpty ? decoded : null;

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

    if (_pendingPlay != null && _audioReady) {
      await _handlePlay(_pendingPlay!);
      _pendingPlay = null;
    }
  }

  Future<void> _handlePlay(Map<String, dynamic> data) async {
    if (!_audioReady) {
      _pendingPlay = data;
      return;
    }

    final hostTime = data['hostTime'] as int;
    final positionMs = data['positionMs'] as int;

    final elapsed = _sync.nowAsHostTime - hostTime;
    final targetPosition = positionMs + elapsed + _engineLatencyMs;
    final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;

    await _player.seek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
    _lastSeekTime = DateTime.now().millisecondsSinceEpoch;
    if (!_player.playing) {
      await _player.play();
    }
  }

  Future<void> _handlePause(Map<String, dynamic> data) async {
    await _player.pause();
    final positionMs = data['positionMs'] as int?;
    if (positionMs != null) {
      await _player.seek(Duration(milliseconds: positionMs));
    }
  }

  Future<void> _handleSeek(Map<String, dynamic> data) async {
    final positionMs = data['positionMs'] as int;
    final hostTime = data['hostTime'];

    if (hostTime != null) {
      // seek while playing
      final elapsed = _sync.nowAsHostTime - (hostTime as int);
      final targetPosition = positionMs + elapsed;
      final maxPosition = _player.duration?.inMilliseconds ?? targetPosition;
      await _player.seek(Duration(milliseconds: targetPosition.clamp(0, maxPosition)));
      if (!_player.playing) {
        await _player.play();
      }
    } else {
      // seek while paused
      await _player.seek(Duration(milliseconds: positionMs));
    }
  }

  // ─── 게스트: 재생 중 싱크 보정 ───

  Future<void> _handleSyncPosition(Map<String, dynamic> data) async {
    final hostTime = data['hostTime'] as int;
    final hostPositionMs = data['positionMs'] as int;

    // 버퍼링 복구용으로 저장
    _lastSyncHostTime = hostTime;
    _lastSyncPositionMs = hostPositionMs;

    if (!_player.playing) return;

    // seek 후 1초간 보정 스킵 (seek 안정화 대기)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSeekTime < 1000) return;

    // 호스트의 현재 position 추정
    final elapsed = _sync.nowAsHostTime - hostTime;
    final expectedPosition = hostPositionMs + elapsed;
    final myPosition = _player.position.inMilliseconds;
    final diff = expectedPosition - myPosition; // 양수 = 내가 뒤처짐

    if (diff.abs() < 20) return; // 20ms 미만은 무시

    // seek로 즉시 보정
    final nowElapsed = _sync.nowAsHostTime - hostTime;
    final adjustedPosition = hostPositionMs + nowElapsed;
    final maxPosition = _player.duration?.inMilliseconds ?? adjustedPosition;
    await _player.seek(Duration(milliseconds: adjustedPosition.clamp(0, maxPosition)));
    _lastSeekTime = DateTime.now().millisecondsSinceEpoch;

    debugPrint('Sync: ${diff}ms → seek to ${adjustedPosition}ms');
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
        // 2초 이내 반복 복구 방지 (무한 루프 차단)
        final now = DateTime.now();
        if (_lastBufferingRecovery != null &&
            now.difference(_lastBufferingRecovery!).inMilliseconds < 2000) {
          debugPrint('Buffering recovery: skipped (too soon)');
          _lastProcessingState = state;
          return;
        }
        _lastBufferingRecovery = now;

        final elapsed = _sync.nowAsHostTime - _lastSyncHostTime!;
        final expectedPosition = _lastSyncPositionMs! + elapsed;
        final maxPosition = _player.duration?.inMilliseconds ?? expectedPosition;
        _player.seek(Duration(milliseconds: expectedPosition.clamp(0, maxPosition)));
        _lastSeekTime = DateTime.now().millisecondsSinceEpoch;
        debugPrint('Buffering recovery: seek to ${expectedPosition}ms');
      }
      _lastProcessingState = state;
    });
  }

  // ─── 엔진 레이턴시 측정 ───

  Future<int> measureEngineLatency({int samples = 5}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final silentFile = File('${tempDir.path}/_silent_test.wav');
      await silentFile.writeAsBytes(_generateSilentWav());

      final results = <int>[];
      for (int i = 0; i < samples; i++) {
        final testPlayer = AudioPlayer();
        try {
          await testPlayer.setFilePath(silentFile.path);
          await testPlayer.setVolume(0);

          final stopwatch = Stopwatch()..start();
          testPlayer.play();

          await testPlayer.positionStream
              .firstWhere((pos) => pos > Duration.zero)
              .timeout(const Duration(seconds: 2));
          stopwatch.stop();

          results.add(stopwatch.elapsedMilliseconds);
        } finally {
          await testPlayer.stop();
          await testPlayer.dispose();
        }
      }

      if (await silentFile.exists()) await silentFile.delete();

      // 중앙값 사용
      results.sort();
      _engineLatencyMs = results[results.length ~/ 2];

      debugPrint('Engine latency: ${_engineLatencyMs}ms (samples: $results)');
      return _engineLatencyMs;
    } catch (e) {
      debugPrint('Engine latency measurement failed: $e');
      _engineLatencyMs = 0;
      return 0;
    }
  }

  static Uint8List _generateSilentWav() {
    const sampleRate = 44100;
    const numSamples = 4410; // 100ms
    const dataSize = numSamples * 2;

    final bytes = ByteData(44 + dataSize);

    final riff = 'RIFF'.codeUnits;
    final wave = 'WAVE'.codeUnits;
    final fmt = 'fmt '.codeUnits;
    final dataTag = 'data'.codeUnits;

    for (int i = 0; i < 4; i++) { bytes.setUint8(i, riff[i]); }
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    for (int i = 0; i < 4; i++) { bytes.setUint8(8 + i, wave[i]); }
    for (int i = 0; i < 4; i++) { bytes.setUint8(12 + i, fmt[i]); }
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    for (int i = 0; i < 4; i++) { bytes.setUint8(36 + i, dataTag[i]); }
    bytes.setUint32(40, dataSize, Endian.little);

    return bytes.buffer.asUint8List();
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
    _pendingPlay = null;
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
    _pendingPlay = null;
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
