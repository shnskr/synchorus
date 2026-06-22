import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'native_audio_sync_service.dart';

/// v3 백그라운드 재생 핸들러.
/// audio_service 플러그인과 네이티브 엔진(NativeAudioSyncService)을 연결.
/// - 잠금화면/알림바 미디어 컨트롤 → syncPlay/syncPause/syncSeek
/// - 동기화 서비스 상태 변경 → PlaybackState/MediaItem 업데이트
class NativeAudioHandler extends BaseAudioHandler with SeekHandler {
  /// 알림 카드 컬러 아트 (logo.png 복사본 file URI). main()에서 1회 세팅.
  static Uri? notifArtUri;

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

  // A-B 구간 반복 경계 (호스트, player_screen이 setAbLoop으로 주입).
  // 활성이면 effective A/B Duration, 비활성이면 둘 다 null.
  // 미니플레이어(알림/잠금화면/블루투스/오토) seek을 [A,B]로 clamp하는 데 사용.
  Duration? _loopStart;
  Duration? _loopEnd;

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
      mediaItem.add(
        duration != null
            ? MediaItem(
                id: fileName,
                title: fileName,
                duration: duration,
                artUri: notifArtUri, // 알림 카드 컬러 로고
              )
            : null,
      );
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
    _loopStart = null;
    _loopEnd = null;

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

    playbackState.add(
      PlaybackState(
        controls: _isHost
            ? [_playing ? MediaControl.pause : MediaControl.play]
            : [],
        systemActions: _isHost ? const {MediaAction.seek} : const {},
        androidCompactActionIndices: _isHost ? const [0] : const [],
        processingState: processingState,
        playing: _playing,
        updatePosition: _lastPosition,
      ),
    );
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

  /// A-B 구간 반복 경계 설정 (player_screen에서 호출).
  /// 활성이면 effective A/B Duration, 비활성이면 null/null.
  void setAbLoop(Duration? start, Duration? end) {
    _loopStart = start;
    _loopEnd = end;
  }

  /// A-B 활성 시 position을 [A,B]로 clamp. 비활성이면 그대로.
  Duration _clampToLoop(Duration position) {
    final a = _loopStart;
    final b = _loopEnd;
    if (a == null || b == null) return position;
    final ms = position.inMilliseconds.clamp(a.inMilliseconds, b.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isHost) {
      // 미니플레이어(알림/잠금화면/블루투스/오토)의 시크바는 이 경로로만 들어옴.
      // 인앱 시크바는 player_screen에서 이미 clamp하지만 여기엔 clamp가 없었음.
      // clamp 후 보정 위치를 emit해야 OS 시크바 썸이 [A,B] 경계로 스냅백한다
      // (positionStream 리스너는 _lastPosition만 갱신하고 playbackState를 재push
      //  안 하므로, 여기서 emit 안 하면 재생만 막히고 썸은 드래그 자리에 남음).
      final clamped = _clampToLoop(position);
      _lastPosition = clamped;
      _emitPlaybackState();
      await _syncService?.syncSeek(clamped);
    }
  }

  @override
  Future<void> stop() async {
    await super.stop();
  }
}
