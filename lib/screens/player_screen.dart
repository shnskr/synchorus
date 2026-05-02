import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/native_audio_sync_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final bool isHost;

  const PlayerScreen({super.key, required this.isHost});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _isDragging = false;
  double _dragValue = 0;
  bool _muted = false;

  NativeAudioSyncService get _audio =>
      ref.read(nativeAudioSyncServiceProvider);

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickFile() async {
    // file_picker iOS는 FileType.audio일 때 MPMediaPickerController를 띄워
    // Music 앱 라이브러리만 보여줌 → Files/iCloud/On My iPhone의 mp3가
    // 안 보임. custom + allowedExtensions로 UIDocumentPickerViewController
    // 사용 → 모든 source 표시. Android는 동일 인터페이스로 mime 필터.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'],
    );
    if (result != null && result.files.single.path != null) {
      try {
        await _audio.loadFile(File(result.files.single.path!));
      } catch (e) {
        if (mounted) {
          final msg = e.toString().contains('No space left')
              ? '저장 공간이 부족합니다. 기기 용량을 확인해주세요.'
              : '파일을 불러올 수 없습니다';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
      if (mounted) setState(() {});
    }
  }

  void _skipSeconds(int seconds) {
    final ts = _audio.engine.latest;
    if (ts == null || ts.sampleRate <= 0) return;
    final currentMs = ts.virtualFrame * 1000 / ts.sampleRate;
    final totalMs = ts.totalFrames * 1000 / ts.sampleRate;
    final newMs = (currentMs + seconds * 1000).clamp(0, totalMs);
    _audio.syncSeek(Duration(milliseconds: newMs.round()));
  }

  void _togglePlay() {
    if (_audio.playing) {
      _audio.syncPause();
    } else {
      _audio.syncPlay();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _audio.engine.setMuted(_muted);
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

              // 싱크 정보 (디버그)
              if (!widget.isHost) _buildSyncInfo(),

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

        return StreamBuilder<double>(
          stream: _audio.downloadProgressStream,
          initialData: 0.0,
          builder: (context, progressSnap) {
            final progress = progressSnap.data ?? 0.0;
            final progressPct = (progress * 100).round();

            final title = isLoading
                ? (progress > 0 && progress < 1.0
                    ? '파일 수신 중... $progressPct%'
                    : '파일 수신 중...')
                : fileName ??
                    (widget.isHost ? '오디오를 선택하세요' : '음악 대기 중');

        return Card(
          child: ListTile(
            leading: isLoading
                ? SizedBox(
                    width: 40,
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        value: progress > 0 && progress < 1.0
                            ? progress
                            : null,
                      ),
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
        );
          },
        );
      },
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<Duration?>(
      stream: _audio.durationStream,
      initialData: _audio.currentDuration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _audio.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final maxMs =
                duration.inMilliseconds.toDouble().clamp(1.0, double.maxFinite);
            return Column(
              children: [
                Slider(
                  min: 0,
                  max: maxMs,
                  value: _isDragging
                      ? _dragValue.clamp(0.0, maxMs)
                      : position.inMilliseconds.toDouble().clamp(0.0, maxMs),
                  onChanged: widget.isHost
                      ? (value) {
                          setState(() {
                            _isDragging = true;
                            _dragValue = value;
                          });
                        }
                      : null,
                  onChangeEnd: widget.isHost
                      ? (value) {
                          setState(() => _isDragging = false);
                          _audio
                              .syncSeek(Duration(milliseconds: value.toInt()));
                        }
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_isDragging
                          ? Duration(milliseconds: _dragValue.toInt())
                          : position)),
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
    return StreamBuilder<bool>(
      stream: _audio.playingStream,
      initialData: _audio.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        final hasAudio = _audio.currentFileName != null;

        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  onPressed:
                      (widget.isHost && hasAudio) ? () => _skipSeconds(-5) : null,
                  icon: const Icon(Icons.replay_5),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 64,
                  onPressed: (widget.isHost && hasAudio) ? _togglePlay : null,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed:
                      (widget.isHost && hasAudio) ? () => _skipSeconds(5) : null,
                  icon: const Icon(Icons.forward_5),
                ),
              ],
            ),
            Positioned(
              right: 0,
              child: IconButton(
                iconSize: 28,
                onPressed: hasAudio ? _toggleMute : null,
                icon: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSyncInfo() {
    final drift = _audio.latestDriftMs;
    final seeks = _audio.seekCount;
    final sync = ref.read(syncServiceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync Info',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              'drift: ${drift != null ? "${drift.toStringAsFixed(1)}ms" : "—"}'
              '  |  seeks: $seeks'
              '  |  offset: ${sync.filteredOffsetMs.toStringAsFixed(1)}ms'
              '  |  RTT: ${sync.bestRtt}ms',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
