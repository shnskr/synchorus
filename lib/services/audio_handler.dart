import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'native_audio_sync_service.dart';

/// v3 백그라운드 재생 핸들러.
/// audio_service 플러그인과 네이티브 엔진(NativeAudioSyncService)을 연결.
/// - 잠금화면/알림바 미디어 컨트롤 → syncPlay/syncPause/syncSeek
/// - 동기화 서비스 상태 변경 → PlaybackState/MediaItem 업데이트
class NativeAudioHandler extends BaseAudioHandler with SeekHandler {
  NativeAudioSyncService? _syncService;
  bool _isHost = false;
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _loadingSub;

  bool _playing = false;
  bool _audioReady = false;
  bool _loading = false;
  Duration _lastPosition = Duration.zero;

  /// 동기화 서비스 연결 (방 입장 시)
  void attachSyncService(
    NativeAudioSyncService service, {
    required bool isHost,
  }) {
    detachSyncService();
    _syncService = service;
    _isHost = isHost;

    _playingSub = service.playingStream.listen((playing) {
      _playing = playing;
      _emitPlaybackState();
    });

    // positionStream 구독: _lastPosition을 항상 최신으로 유지.
    // syncPlay/syncSeek의 override 위치도 이 스트림으로 전달되므로
    // 상태 변경(playing 등) 시 _emitPlaybackState()가 정확한 위치를 사용.
    _positionSub = service.positionStream.listen((position) {
      _lastPosition = position;
    });

    _durationSub = service.durationStream.listen((duration) {
      _audioReady = duration != null;
      final fileName = service.currentFileName ?? 'Unknown';
      mediaItem.add(duration != null
          ? MediaItem(id: fileName, title: fileName, duration: duration)
          : null);
      _emitPlaybackState();
    });

    _loadingSub = service.loadingStream.listen((loading) {
      _loading = loading;
      _emitPlaybackState();
    });
  }

  /// 동기화 서비스 분리 (방 퇴장 시)
  void detachSyncService() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _loadingSub?.cancel();
    _syncService = null;
    _playing = false;
    _audioReady = false;
    _loading = false;
    _lastPosition = Duration.zero;

    playbackState.add(PlaybackState());
    mediaItem.add(null);
  }

  void _emitPlaybackState() {
    AudioProcessingState processingState;
    if (_loading) {
      processingState = AudioProcessingState.loading;
    } else if (_audioReady) {
      processingState = AudioProcessingState.ready;
    } else {
      processingState = AudioProcessingState.idle;
    }

    playbackState.add(PlaybackState(
      controls: _isHost
          ? [_playing ? MediaControl.pause : MediaControl.play]
          : [],
      systemActions: _isHost ? const {MediaAction.seek} : const {},
      androidCompactActionIndices: _isHost ? const [0] : const [],
      processingState: processingState,
      playing: _playing,
      updatePosition: _lastPosition,
    ));
  }

  @override
  Future<void> play() async {
    if (_isHost) {
      await _syncService?.syncPlay();
    } else {
      _emitPlaybackState(); // 게스트: 시스템이 토글한 아이콘을 실제 상태로 복원
    }
  }

  @override
  Future<void> pause() async {
    if (_isHost) {
      await _syncService?.syncPause();
    } else {
      _emitPlaybackState();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isHost) {
      _lastPosition = position;
      _emitPlaybackState();
      await _syncService?.syncSeek(position);
    }
  }

  @override
  Future<void> stop() async {
    await super.stop();
  }
}
