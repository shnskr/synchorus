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
  Uint8List? _cachedFileBytes;

  final _loadingController = StreamController<bool>.broadcast();
  Stream<bool> get loadingStream => _loadingController.stream;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  AudioPlayer get player => _player;
  String? get currentFileName => _currentFileName;
  String? get currentUrl => _currentUrl;

  /// 오디오 상태 스트림
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;

  AudioSyncService(this._p2p, this._sync);

  bool _isHost = false;
  int _sendGeneration = 0;

  /// 호스트/참가자 공통: P2P 메시지 리스닝 시작
  void startListening({required bool isHost}) {
    _isHost = isHost;
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
    });
  }

  // ─── 호스트 전용: 오디오 소스 설정 및 명령 전송 ───

  /// 호스트: URL로 오디오 로드 + 참가자에게 URL 전달
  Future<void> loadUrl(String url) async {
    _currentUrl = url;
    _currentFileName = null;
    _cachedFileBytes = null;
    await _player.setUrl(url);

    _p2p.broadcastToAll({
      'type': 'audio-url',
      'data': {'url': url},
    });
  }

  /// 호스트: 로컬 파일 로드 + 참가자에게 파일 전송
  Future<void> loadFile(File file) async {
    _sendGeneration++; // 진행 중인 전송 모두 취소
    final fileName = file.uri.pathSegments.last;
    _currentFileName = fileName;
    _currentUrl = null;
    _isLoading = true;
    _loadingController.add(true);

    await _player.setFilePath(file.path);

    final bytes = await file.readAsBytes();
    _cachedFileBytes = bytes;

    await _sendFileChunks(fileName, bytes, broadcast: true);

    _isLoading = false;
    _loadingController.add(false);
  }

  /// 파일 청크 전송 (broadcast: 전체, false: 특정 피어)
  Future<void> _sendFileChunks(String fileName, Uint8List bytes, {required bool broadcast, String? peerId}) async {
    final gen = _sendGeneration;
    final meta = {
      'type': 'audio-meta',
      'data': {'fileName': fileName, 'fileSize': bytes.length},
    };
    if (broadcast) {
      _p2p.broadcastToAll(meta);
    } else {
      _p2p.sendToPeer(peerId!, meta);
    }

    const chunkSize = 32768;
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      if (_sendGeneration != gen) return; // 새 전송이 시작됨 → 중단
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      final msg = {
        'type': 'audio-data',
        'data': {
          'fileName': fileName,
          'offset': offset,
          'totalSize': bytes.length,
          'chunk': base64Encode(chunk),
        },
      };
      if (broadcast) {
        _p2p.broadcastToAll(msg);
      } else {
        _p2p.sendToPeer(peerId!, msg);
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// 호스트: 특정 피어에게 현재 오디오 전송
  Future<void> sendCurrentAudioToPeer(String peerId) async {
    if (_currentUrl != null) {
      _p2p.sendToPeer(peerId, {
        'type': 'audio-url',
        'data': {'url': _currentUrl},
      });
    } else if (_currentFileName != null && _cachedFileBytes != null) {
      await _sendFileChunks(_currentFileName!, _cachedFileBytes!, broadcast: false, peerId: peerId);
    }
  }

  /// 게스트: 호스트에게 현재 오디오 요청
  void requestCurrentAudio() {
    _p2p.sendToHost({
      'type': 'audio-request',
      'data': {},
    });
  }

  /// 호스트: 오디오 요청 처리
  void _handleAudioRequest(String? fromId) {
    if (fromId == null) return;
    sendCurrentAudioToPeer(fromId);
  }

  /// 호스트: 동기화 재생 명령 (현재 position도 함께 전송)
  Future<void> syncPlay() async {
    final startAt = _sync.nowAsHostTime + _syncDelayMs;
    final positionMs = _player.position.inMilliseconds;

    _p2p.broadcastToAll({
      'type': 'play',
      'data': {
        'startAt': startAt,
        'positionMs': positionMs,
      },
    });

    // 호스트도 동일하게 예약 재생
    _schedulePlay(startAt, positionMs: positionMs);
  }

  /// 호스트: 동기화 일시정지 명령 (현재 position도 함께 전송)
  Future<void> syncPause() async {
    _cancelScheduledPlay();
    await _player.pause();
    final positionMs = _player.position.inMilliseconds;

    _p2p.broadcastToAll({
      'type': 'pause',
      'data': {
        'positionMs': positionMs,
      },
    });
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

  void _handleAudioMeta(Map<String, dynamic> data) async {
    final fileName = data['fileName'] as String;
    final fileSize = data['fileSize'] as int;

    // 새 파일 전송 시작 → 이전 임시 파일 삭제 + 상태 초기화
    if (_currentFileName != null && _currentFileName != fileName) {
      final tempDir = await getTemporaryDirectory();
      final oldFile = File('${tempDir.path}/$_currentFileName');
      if (await oldFile.exists()) oldFile.delete();
    }
    _currentFileName = null;
    _currentUrl = null;
    _cancelScheduledPlay();
    _player.stop();
    _transferBuffers.clear();
    _isLoading = true;
    _loadingController.add(true);

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
      _isLoading = false;
      _loadingController.add(false);

      // 파일 로드 완료 → 호스트에게 현재 상태 요청
      if (!_isHost) {
        _p2p.sendToHost({
          'type': 'state-request',
          'data': {},
        });
      }
    }
  }

  bool get _hasAudioLoaded => _currentFileName != null || _currentUrl != null;

  void _handlePlay(Map<String, dynamic> data) {
    if (!_hasAudioLoaded) return; // 로드 완료 후 state-request로 동기화됨
    final startAt = data['startAt'] as int;
    final positionMs = data['positionMs'] as int?;
    _schedulePlay(startAt, positionMs: positionMs);
  }

  void _handlePause(Map<String, dynamic> data) {
    _cancelScheduledPlay();
    _player.pause();
    final positionMs = data['positionMs'] as int?;
    if (positionMs != null) {
      _player.seek(Duration(milliseconds: positionMs));
    }
  }

  void _handleSeek(Map<String, dynamic> data) async {
    final positionMs = data['positionMs'] as int;
    final startAt = data['startAt'];

    await _player.seek(Duration(milliseconds: positionMs));
    if (startAt != null) {
      _schedulePlay(startAt as int);
    }
  }

  /// 호스트: 상태 요청에 현재 재생 상태 응답
  void _handleStateRequest(String? fromId) {
    if (fromId == null) return;
    _p2p.sendToPeer(fromId, {
      'type': 'state-response',
      'data': {
        'playing': _player.playing,
        'positionMs': _player.position.inMilliseconds,
        'hostTime': _sync.nowAsHostTime,
      },
    });
  }

  /// 게스트: 호스트의 현재 상태에 맞춰 동기화
  void _handleStateResponse(Map<String, dynamic> data) async {
    final playing = data['playing'] as bool;
    final positionMs = data['positionMs'] as int;
    final hostTime = data['hostTime'] as int;

    if (!_hasAudioLoaded) return;

    if (playing) {
      // 응답이 올 때까지의 지연 보정
      final elapsed = _sync.nowAsHostTime - hostTime;
      final adjustedPosition = positionMs + elapsed;
      await _player.seek(Duration(milliseconds: adjustedPosition));
      await _player.play();
    } else {
      await _player.seek(Duration(milliseconds: positionMs));
      await _player.pause();
    }
  }

  // ─── 내부 헬퍼 ───

  /// startAt(호스트 시간)에 맞춰 재생 예약 + position 동기화
  void _schedulePlay(int startAtHostTime, {int? positionMs}) {
    _cancelScheduledPlay();

    // position 먼저 맞추기
    if (positionMs != null) {
      _player.seek(Duration(milliseconds: positionMs));
    }

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

  /// 임시 오디오 파일 삭제
  Future<void> clearTempFiles() async {
    _isLoading = false;
    _loadingController.add(false);
    _cancelScheduledPlay();
    _player.stop();

    final tempDir = await getTemporaryDirectory();
    for (final fileName in _transferBuffers.keys) {
      final file = File('${tempDir.path}/$fileName');
      if (await file.exists()) await file.delete();
    }
    // 이미 로드 완료된 파일도 삭제
    if (_currentFileName != null) {
      final file = File('${tempDir.path}/$_currentFileName');
      if (await file.exists()) await file.delete();
    }
    _currentFileName = null;
    _currentUrl = null;
    _cachedFileBytes = null;
    _transferBuffers.clear();
  }

  Future<void> dispose() async {
    _cancelScheduledPlay();
    _messageSub?.cancel();
    _messageSub = null;
    _loadingController.close();
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