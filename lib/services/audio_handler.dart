import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final bool Function() _isHost;
  final Future<void> Function()? _onPlay;
  final Future<void> Function()? _onPause;
  final Future<void> Function(Duration)? _onSeek;
  StreamSubscription? _playerSub;

  AudioPlayerHandler(
    this._player, {
    required bool Function() isHost,
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function(Duration)? onSeek,
  })  : _isHost = isHost,
        _onPlay = onPlay,
        _onPause = onPause,
        _onSeek = onSeek {
    _playerSub = _player.playbackEventStream.map(_transformEvent).listen(
      (state) => playbackState.add(state),
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        _player.playing ? MediaControl.pause : MediaControl.play,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() async {
    if (_isHost()) {
      await _onPlay?.call();
    }
  }

  @override
  Future<void> pause() async {
    if (_isHost()) {
      await _onPause?.call();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isHost()) {
      await _onSeek?.call(position);
    }
  }

  @override
  Future<void> stop() async {
    // _playerSub은 취소하지 않음 (#6): 이후 재로드/재생 시 PlaybackState 업데이트가 끊기는 문제 방지
    // 구독은 dispose 시점에만 정리
    await _player.stop();
    return super.stop();
  }

  Future<void> dispose() async {
    await _playerSub?.cancel();
    _playerSub = null;
  }
}
