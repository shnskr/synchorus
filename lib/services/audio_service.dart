import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'p2p_service.dart';
import 'sync_service.dart';

/// 동기화 재생 명령을 전달할 때 사용하는 딜레이 (모든 디바이스가 준비할 시간)
const int _syncDelayMs = 2000;

class AudioSyncService {
  final P2PService _p2p;
  final SyncService _sync;
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription? _messageSub;
  Timer? _scheduledPlayTimer;

  /// 현재 로드된 오디오 소스 정보
  String? _currentFileName;
  String? _currentUrl;

  AudioPlayer get player => _player;
  String? get currentFileName => _currentFileName;
  String? get currentUrl => _currentUrl;

  /// 오디오 상태 스트림
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;

  AudioSyncService(this._p2p, this._sync);

  /// 호스트/참가자 공통: P2P 메시지 리스닝 시작
  void startListening({required bool isHost}) {
    _messageSub?.cancel();
    _messageSub = _p2p.onMessage.listen((message) {
      switch (message['type']) {
        case 'audio-url':
          _handleAudioUrl(message['data']);
          break;
        case 'audio-meta':
          _handleAudioMeta(message['data']);
          break;
        case 'audio-data':
          _handleAudioData(message['data']);
          break;
        case 'play':
          _handlePlay(message['data']);
          break;
        case 'pause':
          _handlePause(message['data']);
          break;
        case 'seek':
          _handleSeek(message['data']);
          break;
      }
    });
  }

  // ─── 호스트 전용: 오디오 소스 설정 및 명령 전송 ───

  /// 호스트: URL로 오디오 로드 + 참가자에게 URL 전달
  Future<void> loadUrl(String url) async {
    _currentUrl = url;
    _currentFileName = null;
    await _player.setUrl(url);

    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': url},
    });
  }

  /// 호스트: 로컬 파일 로드 + 참가자에게 파일 전송
  Future<void> loadFile(File file) async {
    final fileName = file.uri.pathSegments.last;
    _currentFileName = fileName;
    _currentUrl = null;

    await _player.setFilePath(file.path);

    // 파일 데이터를 참가자에게 전송
    final bytes = await file.readAsBytes();

    // 메타 정보 먼저 전송
    _p2p.broadcastToAll({
      'type': 'audio-meta',
      'data': {
        'fileName': fileName,
        'fileSize': bytes.length,
      },
    });

    // 청크 단위로 파일 전송 (48KB → Base64로 ~64KB)
    const chunkSize = 49152;
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      _p2p.broadcastToAll({
        'type': 'audio-data',
        'data': {
          'fileName': fileName,
          'offset': offset,
          'totalSize': bytes.length,
          'chunk': base64Encode(chunk),
        },
      });
      // 소켓 부하 방지를 위한 짧은 딜레이
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 호스트: 동기화 재생 명령
  Future<void> syncPlay() async {
    final startAt = _sync.nowAsHostTime + _syncDelayMs;

    _p2p.broadcastToAll({
      'type': 'play',
      'data': {'startAt': startAt},
    });

    // 호스트도 동일하게 예약 재생
    _schedulePlay(startAt);
  }

  /// 호스트: 동기화 일시정지 명령
  Future<void> syncPause() async {
    final pauseAt = _sync.nowAsHostTime;

    _p2p.broadcastToAll({
      'type': 'pause',
      'data': {'pauseAt': pauseAt},
    });

    _cancelScheduledPlay();
    await _player.pause();
  }

  /// 호스트: 동기화 탐색 명령
  Future<void> syncSeek(Duration position) async {
    final wasPlaying = _player.playing;
    final startAt = _sync.nowAsHostTime + _syncDelayMs;

    _p2p.broadcastToAll({
      'type': 'seek',
      'data': {
        'positionMs': position.inMilliseconds,
        'startAt': wasPlaying ? startAt : null,
      },
    });

    await _player.seek(position);
    if (wasPlaying) {
      _schedulePlay(startAt);
    }
  }

  /// 볼륨 조절 (로컬 전용)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  // ─── 참가자: 호스트로부터 받은 명령 처리 ───

  void _handleAudioUrl(Map<String, dynamic> data) async {
    final url = data['url'] as String;
    _currentUrl = url;
    _currentFileName = null;
    await _player.setUrl(url);
  }

  /// 파일 전송 버퍼: fileName → 누적 바이트
  final Map<String, _FileTransferBuffer> _transferBuffers = {};

  void _handleAudioMeta(Map<String, dynamic> data) {
    final fileName = data['fileName'] as String;
    final fileSize = data['fileSize'] as int;
    _transferBuffers[fileName] = _FileTransferBuffer(
      fileName: fileName,
      totalSize: fileSize,
    );
  }

  void _handleAudioData(Map<String, dynamic> data) async {
    final fileName = data['fileName'] as String;
    final offset = data['offset'] as int;
    final totalSize = data['totalSize'] as int;
    final chunk = base64Decode(data['chunk'] as String);

    final buffer = _transferBuffers[fileName];
    if (buffer == null) return;

    buffer.addChunk(offset, chunk);

    if (buffer.isComplete) {
      // 임시 파일로 저장 후 로드
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(buffer.bytes);

      _currentFileName = fileName;
      _currentUrl = null;
      await _player.setFilePath(tempFile.path);
      _transferBuffers.remove(fileName);
    }
  }

  void _handlePlay(Map<String, dynamic> data) {
    final startAt = data['startAt'] as int;
    _schedulePlay(startAt);
  }

  void _handlePause(Map<String, dynamic> data) {
    _cancelScheduledPlay();
    _player.pause();
  }

  void _handleSeek(Map<String, dynamic> data) async {
    final positionMs = data['positionMs'] as int;
    final startAt = data['startAt'];

    await _player.seek(Duration(milliseconds: positionMs));
    if (startAt != null) {
      _schedulePlay(startAt as int);
    }
  }

  // ─── 내부 헬퍼 ───

  /// startAt(호스트 시간)에 맞춰 재생 예약
  void _schedulePlay(int startAtHostTime) {
    _cancelScheduledPlay();
    final localPlayTime = _sync.hostTimeToLocal(startAtHostTime);
    final delayMs = localPlayTime - DateTime.now().millisecondsSinceEpoch;

    if (delayMs <= 0) {
      _player.play();
    } else {
      _scheduledPlayTimer = Timer(Duration(milliseconds: delayMs), () {
        _player.play();
      });
    }
  }

  void _cancelScheduledPlay() {
    _scheduledPlayTimer?.cancel();
    _scheduledPlayTimer = null;
  }

  Future<void> dispose() async {
    _cancelScheduledPlay();
    _messageSub?.cancel();
    _messageSub = null;
    await _player.dispose();
  }
}

/// 파일 청크 전송을 위한 버퍼
class _FileTransferBuffer {
  final String fileName;
  final int totalSize;
  final Uint8List _data;
  int _received = 0;

  _FileTransferBuffer({required this.fileName, required this.totalSize})
      : _data = Uint8List(totalSize);

  void addChunk(int offset, Uint8List chunk) {
    _data.setRange(offset, offset + chunk.length, chunk);
    _received += chunk.length;
  }

  bool get isComplete => _received >= totalSize;
  Uint8List get bytes => _data;
}