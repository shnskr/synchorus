import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/native_audio_sync_service.dart';
import 'home_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final bool isHost;

  const PlayerScreen({super.key, required this.isHost});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  // Slider 좌우 padding 명시 — SliderTheme + 마커 위치 계산이 같은 값 공유.
  // 이 값을 SliderTheme.padding에 강제하면 thumb 가용 영역이 [padding, width-padding]
  // 으로 정해지고 마커 left = padding + ratio * (width - 2*padding) 이 정확.
  static const double _sliderHorizontalPadding = 12.0;

  bool _isDragging = false;
  double _dragValue = 0;
  bool _muted = false;

  // A-B 구간 반복 (호스트만, 1회성 — 파일 변경/앱 재시작 시 리셋).
  // A 없으면 효과적 A=0, B 없으면 효과적 B=duration. 간격 100ms 미만이면 비활성.
  static const int _abMinGapMs = 100;
  Duration? _abPointA;
  Duration? _abPointB;
  Duration _lastPosition = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  Duration get _effectiveA => _abPointA ?? Duration.zero;
  Duration? get _effectiveB => _abPointB ?? _audio.currentDuration;
  bool get _abAnySet => _abPointA != null || _abPointB != null;
  bool get _abActive {
    if (!_abAnySet) return false;
    final b = _effectiveB;
    if (b == null) return false;
    return (b.inMilliseconds - _effectiveA.inMilliseconds) >= _abMinGapMs;
  }

  NativeAudioSyncService get _audio =>
      ref.read(nativeAudioSyncServiceProvider);

  @override
  void initState() {
    super.initState();
    // 단독 진입(main → PlayerScreen) 경로에서도 audio listen / handler attach 보장.
    // RoomScreen 경유 진입 시엔 이미 호출됐지만 재호출 안전(startListening은
    // _messageSub 재구독, attachSyncService는 detach 먼저).
    final audio = ref.read(nativeAudioSyncServiceProvider);
    final handler = ref.read(audioHandlerProvider);
    audio.startListening(isHost: widget.isHost);
    handler.attachSyncService(audio, isHost: widget.isHost);

    // A-B 반복: 호스트만. B 도달 감지 + 파일 변경 reset.
    if (widget.isHost) {
      _positionSub = audio.positionStream.listen(_onAbPositionTick);
      _durationSub = audio.durationStream.listen((_) {
        if (_abPointA != null || _abPointB != null) {
          setState(() {
            _abPointA = null;
            _abPointB = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  void _onAbPositionTick(Duration position) {
    // 정지 중에는 jump 안 함 — B와 같은 위치에 정지된 상태에서도 무한 jump 방지.
    final b = _effectiveB;
    if (_abActive && _audio.playing && b != null && position >= b) {
      _audio.syncSeek(_effectiveA);
    }
    _lastPosition = position;
  }

  void _setAbPoint({required bool isA}) {
    final fileName = _audio.currentFileName;
    if (fileName == null) return; // 파일 없으면 무동작
    final newPoint = _lastPosition;
    setState(() {
      if (isA) {
        // A를 새로 지정 — 기존 B와 100ms 이내로 가까우면 B 해제 (새 지정 우선).
        if (_abPointB != null &&
            (newPoint.inMilliseconds - _abPointB!.inMilliseconds).abs() <
                _abMinGapMs) {
          _abPointB = null;
        }
        _abPointA = newPoint;
      } else {
        if (_abPointA != null &&
            (newPoint.inMilliseconds - _abPointA!.inMilliseconds).abs() <
                _abMinGapMs) {
          _abPointA = null;
        }
        _abPointB = newPoint;
      }
      // 둘 다 지정됐고 순서가 뒤집혔으면 swap.
      if (_abPointA != null &&
          _abPointB != null &&
          _abPointA! > _abPointB!) {
        final tmp = _abPointA;
        _abPointA = _abPointB;
        _abPointB = tmp;
      }
    });
  }

  void _resetAb() {
    setState(() {
      _abPointA = null;
      _abPointB = null;
    });
  }

  void _clearAbPoint({required bool isA}) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (isA) {
        _abPointA = null;
      } else {
        _abPointB = null;
      }
    });
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
    // 효과적 A/B로 clamp. A 없으면 0, B 없으면 곡끝.
    final minMs = _effectiveA.inMilliseconds.toDouble();
    final maxMs =
        _effectiveB?.inMilliseconds.toDouble() ?? totalMs.toDouble();
    final newMs = (currentMs + seconds * 1000).clamp(minMs, maxMs);
    _audio.syncSeek(Duration(milliseconds: newMs.round()));
  }

  void _togglePlay() {
    if (_audio.playing) {
      _audio.syncPause();
      return;
    }
    // A/B 중 하나라도 지정됐으면 [효과적 A, 효과적 B] 범위 검사. 밖이면 A에서 시작.
    Duration? startFrom;
    if (_abAnySet) {
      final a = _effectiveA;
      final b = _effectiveB;
      final ts = _audio.engine.latest;
      final totalMs = ts != null && ts.sampleRate > 0
          ? ts.totalFrames * 1000 / ts.sampleRate
          : 0.0;
      final atEnd =
          totalMs > 0 && _lastPosition.inMilliseconds >= totalMs - 50;
      final outside = _lastPosition < a ||
          (b != null && _lastPosition >= b) ||
          atEnd;
      if (outside) startFrom = a;
    }
    _audio.syncPlay(startFrom: startFrom);
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
        actions: [
          // [임시] 방 만들기/참가 동선. 사용자가 UI 위치 정해줄 때까지 AppBar에 둠.
          IconButton(
            tooltip: '방 만들기 / 참가',
            icon: const Icon(Icons.group_add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
        ],
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

              // A-B 구간 반복 (호스트만)
              if (widget.isHost) ...[
                const SizedBox(height: 8),
                _buildAbControls(),
              ],

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
            // 효과적 [A, B] 범위로 clamp. 시크바 max는 곡 끝(시각적으로 전체
            // 표시)이지만 thumb은 [A, B] 안에서만 움직임. A 없으면 0, B 없으면 곡끝.
            final minSeekMs = _effectiveA.inMilliseconds.toDouble();
            final maxSeekMs =
                _effectiveB?.inMilliseconds.toDouble() ?? maxMs;
            return Column(
              children: [
                // A/B 마커 overlay (시크바 위)
                if (widget.isHost && (_abPointA != null || _abPointB != null))
                  _buildAbMarkers(maxMs),
                SliderTheme(
                  data: Theme.of(context).sliderTheme.copyWith(
                        padding: const EdgeInsets.symmetric(
                            horizontal: _sliderHorizontalPadding),
                      ),
                  child: Slider(
                  min: 0,
                  max: maxMs,
                  value: _isDragging
                      ? _dragValue.clamp(0.0, maxMs)
                      : position.inMilliseconds.toDouble().clamp(0.0, maxMs),
                  onChanged: widget.isHost
                      ? (value) {
                          final clamped = value.clamp(minSeekMs, maxSeekMs);
                          setState(() {
                            _isDragging = true;
                            _dragValue = clamped;
                          });
                        }
                      : null,
                  onChangeEnd: widget.isHost
                      ? (value) {
                          final clamped = value.clamp(minSeekMs, maxSeekMs);
                          setState(() => _isDragging = false);
                          _audio.syncSeek(
                              Duration(milliseconds: clamped.toInt()));
                        }
                      : null,
                ),
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

  /// 시크바 위 A/B 위치 마커. SliderTheme.padding과 같은 _sliderHorizontalPadding으로
  /// thumb 가용 영역을 동일 가정 + FractionalTranslation(-0.5)로 자기 너비 절반만큼
  /// 왼쪽 이동 → thumb 중심과 마커 중심 정렬.
  Widget _buildAbMarkers(double maxMs) {
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usable = (constraints.maxWidth - _sliderHorizontalPadding * 2)
              .clamp(1.0, double.infinity);
          Widget marker(Duration point, String label) {
            final ratio = (point.inMilliseconds / maxMs).clamp(0.0, 1.0);
            final left = _sliderHorizontalPadding + usable * ratio;
            return Positioned(
              left: left,
              top: 0,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (_abPointA != null) marker(_abPointA!, 'A'),
              if (_abPointB != null) marker(_abPointB!, 'B'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAbControls() {
    final hasAudio = _audio.currentFileName != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _abButton(label: 'A', point: _abPointA, enabled: hasAudio, isA: true),
        const SizedBox(width: 8),
        _abButton(label: 'B', point: _abPointB, enabled: hasAudio, isA: false),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'A-B 해제',
          icon: Icon(
            Icons.cancel_outlined,
            color: _abActive
                ? Theme.of(context).colorScheme.primary
                : (_abAnySet
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor),
          ),
          onPressed: _abAnySet ? _resetAb : null,
        ),
      ],
    );
  }

  Widget _abButton({
    required String label,
    required Duration? point,
    required bool enabled,
    required bool isA,
  }) {
    final hasPoint = point != null;
    // duration이 1시간 넘는 곡이면 placeholder도 HH:MM:SS 길이로 reserve.
    final dur = _audio.currentDuration ?? Duration.zero;
    final placeholderTime = dur.inHours > 0 ? '0:00:00' : '00:00';
    const tabular = TextStyle(
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return OutlinedButton(
      onPressed: enabled ? () => _setAbPoint(isA: isA) : null,
      onLongPress:
          (enabled && hasPoint) ? () => _clearAbPoint(isA: isA) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            hasPoint ? Theme.of(context).colorScheme.primary : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 너비 reserve (보이지 않음)
          Opacity(
            opacity: 0,
            child: Text('$label  $placeholderTime', style: tabular),
          ),
          // 실제 표시
          Text(
            hasPoint ? '$label  ${_formatDuration(point)}' : label,
            style: tabular,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncInfo() {
    // v0.0.81: positionStream(100ms 주기 native poll) 구독으로 매번 rebuild —
    // drift / seekCount / offset / RTT 실시간 표시. 기존엔 한 번 read만 해서 갱신 안 됨.
    return StreamBuilder<Duration>(
      stream: _audio.positionStream,
      builder: (context, _) {
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
                  '  |  RTT: ${sync.bestRtt}ms'
                  '  |  stable: ${sync.isOffsetStable ? "✓" : "✗"}',
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
      },
    );
  }
}
