import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/app_providers.dart';
import '../services/audio_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final bool isHost;

  const PlayerScreen({super.key, required this.isHost});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final _urlController = TextEditingController();
  double _volume = 1.0;

  AudioSyncService get _audio => ref.read(audioSyncServiceProvider);

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result != null && result.files.single.path != null) {
      try {
        await _audio.loadFile(File(result.files.single.path!));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('파일 로드 실패: $e')),
          );
        }
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    try {
      await _audio.loadUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 로드 실패: 올바른 오디오 URL인지 확인해주세요')),
        );
      }
    }
    if (!mounted) return;
    setState(() {});
    FocusScope.of(context).unfocus();
  }

  void _skipSeconds(int seconds) {
    final current = _audio.player.position;
    final duration = _audio.player.duration ?? Duration.zero;
    final newPosition = current + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    _audio.syncSeek(clamped);
  }

  void _togglePlay() {
    final state = _audio.player.playerState;
    if (state.playing) {
      _audio.syncPause();
    } else {
      _audio.syncPlay();
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플레이어'),
      ),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 호스트 전용: 오디오 소스 선택
            if (widget.isHost) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('파일 선택'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        hintText: '오디오 URL 입력',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loadUrl,
                    child: const Text('로드'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
            ],

            // 현재 재생 정보
            _buildNowPlaying(),

            const Spacer(),

            // 시크바 + 시간
            _buildSeekBar(),

            const SizedBox(height: 16),

            // 재생 컨트롤
            _buildControls(),

            const SizedBox(height: 24),

            // 볼륨
            _buildVolumeSlider(),

            const SizedBox(height: 16),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildNowPlaying() {
    return StreamBuilder<bool>(
      stream: _audio.loadingStream,
      initialData: _audio.isLoading,
      builder: (context, loadingSnap) {
        final isLoading = loadingSnap.data ?? false;
        final fileName = _audio.currentFileName;
        final url = _audio.currentUrl;
        final title = isLoading
            ? '파일 수신 중...'
            : fileName ?? url ?? (widget.isHost ? '오디오를 선택하세요' : '음악 대기 중');

        return Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: isLoading
                    ? const SizedBox(
                        width: 40, height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      )
                    : const Icon(Icons.music_note, size: 40),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(widget.isHost ? '호스트' : '참가자'),
              ),
              _buildLatencyInfo(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLatencyInfo() {
    final my = _audio.engineLatencyMs;
    final myRaw = _audio.engineRawOutputMs;
    final myBuf = _audio.engineBufferMs;
    final host = _audio.hostEngineLatencyMs;
    final comp = _audio.latencyCompensation;

    final myLabel = Platform.isIOS
        ? 'My: ${my}ms (buf=$myBuf, rawOut=$myRaw)'
        : 'My: ${my}ms (buf=$myBuf)';
    final compSign = comp >= 0 ? '+' : '';
    final hostLabel = widget.isHost ? '' : '  Host: ${host}ms  Comp: $compSign${comp}ms';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$myLabel$hostLabel',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<Duration?>(
      stream: _audio.durationStream,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _audio.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            return Column(
              children: [
                Slider(
                  min: 0,
                  max: duration.inMilliseconds.toDouble().clamp(1, double.maxFinite),
                  value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble().clamp(1, double.maxFinite)),
                  onChanged: widget.isHost ? (value) {} : null,
                  onChangeEnd: widget.isHost
                      ? (value) {
                          _audio.syncSeek(Duration(milliseconds: value.toInt()));
                        }
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position)),
                      Text(_formatDuration(duration)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<PlayerState>(
      stream: _audio.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;
        final hasAudio = _audio.currentFileName != null || _audio.currentUrl != null;

        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  onPressed: (widget.isHost && hasAudio) ? () => _skipSeconds(-5) : null,
                  icon: const Icon(Icons.replay_5),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 64,
                  onPressed: (widget.isHost && hasAudio) ? _togglePlay : null,
                  icon: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed: (widget.isHost && hasAudio) ? () => _skipSeconds(5) : null,
                  icon: const Icon(Icons.forward_5),
                ),
              ],
            ),
            Positioned(
              left: 0,
              child: IconButton(
                iconSize: 28,
                onPressed: _toggleMute,
                icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _muted = false;
  double _volumeBeforeMute = 1.0;

  void _toggleMute() {
    setState(() {
      if (_muted) {
        _volume = _volumeBeforeMute;
        _muted = false;
      } else {
        _volumeBeforeMute = _volume;
        _volume = 0;
        _muted = true;
      }
    });
    _audio.setVolume(_volume);
  }

  Widget _buildVolumeSlider() {
    return Row(
      children: [
        const Icon(Icons.volume_down),
        Expanded(
          child: Slider(
            min: 0,
            max: 1,
            value: _volume,
            onChanged: (value) {
              setState(() {
                _volume = value;
                _muted = value == 0;
              });
              _audio.setVolume(value);
            },
          ),
        ),
        const Icon(Icons.volume_up),
      ],
    );
  }
}