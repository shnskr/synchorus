import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../providers/app_providers.dart';
import '../services/discovery_service.dart';
import '../services/native_audio_sync_service.dart';
import '../services/p2p_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_typography.dart';
import '../widgets/banner_ad_widget.dart';
import 'settings_screen.dart';

/// 플레이어 모드.
/// - standalone: 단독 재생. P2P 비활성. UI 컨트롤 권한 보유.
/// - host: 단독 + P2P 호스트 (방 열기/광고/게스트 수용). UI 컨트롤 동일.
/// - speaker: 호스트에 연결된 게스트 (음악 sync 수신, 재생 컨트롤 권한 없음).
enum PlayerMode { standalone, host, speaker }

class PlayerScreen extends ConsumerStatefulWidget {
  /// 진입 시 초기 모드. 보통 standalone. 디버그/측정용으로 즉시 호스트 진입 가능.
  final PlayerMode initialMode;

  const PlayerScreen({super.key, this.initialMode = PlayerMode.standalone});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  // Slider 좌우 padding 명시 — SliderTheme + 마커 위치 계산이 같은 값 공유.
  // 이 값을 SliderTheme.padding에 강제하면 thumb 가용 영역이 [padding, width-padding]
  // 으로 정해지고 마커 left = padding + ratio * (width - 2*padding) 이 정확.
  static const double _sliderHorizontalPadding = 12.0;

  // 현재 모드. standalone(단독) / host(P2P 호스트) / speaker(P2P 게스트).
  // standalone + host는 UI 컨트롤 권한 동일 (재생/시크/파일선택), speaker만 read-only.
  // P2P 활성 여부는 (_mode != standalone) 기준. 사용자가 group_add → BottomSheet에서 전환.
  late PlayerMode _mode;
  // 모드 전환 비동기 진행 중인지. true면 group_add 버튼 disable — 빠르게 다시 눌러
  // sheet 중복 진입하는 race 방지(_enterHostMode가 _startHost + discovery.startBroadcast로
  // 수십~수백ms 걸려 그 사이에 사용자가 재누름 가능).
  bool _isModeTransitioning = false;
  // BottomSheet 안 카드를 rebuild하기 위한 setState 참조. peer count 등 외부 변경 시
  // PlayerScreen setState만으로는 sheet 안 위젯이 갱신 안 됨 (별도 element tree).
  // sheet 열려있는 동안만 non-null. whenComplete에서 null로 reset.
  void Function(VoidCallback)? _setSheetState;
  // 호스트 모드 진입 실패 사유. SnackBar는 sheet에 가려서 안 보이므로 standalone
  // sheet 안에 inline 표시 (스피커 picker의 _lastError와 동일 패턴). 재진입 시 clear.
  String? _hostModeError;
  bool get _isController => _mode != PlayerMode.speaker;

  // P2P 정보 (BottomSheet 카드 + 모드 전환용).
  // 호스트 모드: _roomCode + _hostIp + _peerCount. 스피커 모드: _connectedHostIp +
  // _connectedRoomCode + _peerCount. standalone은 모두 null.
  String? _roomCode;
  String? _hostIp;
  String? _connectedHostIp;
  String? _connectedRoomCode;
  int _peerCount = 0;
  StreamSubscription? _peerJoinSub;
  StreamSubscription? _peerLeaveSub;
  StreamSubscription? _disconnectedSub;
  StreamSubscription? _rejectedSub;
  StreamSubscription? _proLimitSub;
  // 외부(스피커 모드 게스트가 호스트 broadcast로 받음 또는 호스트 본인 변경)에 의한
  // transpose/speed 값 갱신 시 PlayerScreen rebuild 트리거.
  StreamSubscription<int>? _transposeStreamSub;
  StreamSubscription<int>? _speedStreamSub;
  // (이전 다운로드 완료 트리거용 listener는 입장 즉시 sync 변경으로 제거됨.)
  StreamSubscription<bool>? _loadingSub;
  // 스피커 모드 sync 진행 중 — _buildNowPlaying에서 "동기화 중" 안내 표시.
  bool _isSyncing = false;
  // AppBar 우측에 작게 표시할 버전 (예: "v0.0.95"). 초기 빈 문자열, initState에서 load.
  String _versionLabel = '';

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

  // seek 메모리 3슬롯 (호스트만, 1회성).
  // tap: 비어있으면 현재 위치 저장, 저장됐으면 그 위치로 이동.
  // long-press: 그 슬롯만 해제 + 햅틱. 비어있으면 무동작.
  List<Duration?> _seekSlots = List<Duration?>.filled(3, null);

  // 온보딩 가이드(coach mark) 타겟 키. build에서 각 영역을 KeyedSubtree로 감싸 가리킴.
  // tutorial_coach_mark가 이 GlobalKey의 렌더 위치를 하이라이트 + 설명 말풍선 표시.
  final GlobalKey _keyP2P = GlobalKey();
  final GlobalKey _keyNowPlaying = GlobalKey();
  final GlobalKey _keySeekBar = GlobalKey();
  final GlobalKey _keyAbControls = GlobalKey();
  final GlobalKey _keySeekSlots = GlobalKey();
  final GlobalKey _keyTranspose = GlobalKey();
  final GlobalKey _keySpeed = GlobalKey();
  final GlobalKey _keyControls = GlobalKey();

  NativeAudioSyncService get _audio => ref.read(nativeAudioSyncServiceProvider);

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _loadVersion();
    // 앱 사용 중 화면 꺼짐 방지 — 음악 재생 중에도 lock screen으로 빠지지 않도록.
    WakelockPlus.enable();
    // 단독/호스트는 sync 권한 같음(isHost=true), speaker만 isHost=false.
    final audio = ref.read(nativeAudioSyncServiceProvider);
    final handler = ref.read(audioHandlerProvider);
    audio.startListening(isHost: _isController);
    handler.attachSyncService(audio, isHost: _isController);

    // P2P 정보 stream subscribe (호스트 측). standalone에선 _peers 빈 상태라 무해.
    // 게스트(speaker) 측 peerCount는 onMessage에서 welcome / peer-joined / peer-left
    // 메시지의 data.peerCount로 받음.
    final p2p = ref.read(p2pServiceProvider);
    _peerJoinSub = p2p.onPeerJoin.listen((_) {
      if (!mounted || _mode != PlayerMode.host) return;
      _setStateAndSheet(() => _peerCount = p2p.peers.length);
    });
    _peerLeaveSub = p2p.onPeerLeave.listen((_) {
      if (!mounted || _mode != PlayerMode.host) return;
      _setStateAndSheet(() => _peerCount = p2p.peers.length);
    });
    _disconnectedSub = p2p.onDisconnected.listen((_) {
      if (!mounted || _mode != PlayerMode.speaker) return;
      _exitSpeakerMode(reason: '호스트 연결이 끊겼습니다');
    });
    // 무료 호스트가 2대 제한으로 게스트를 거절했을 때 → 호스트에 업그레이드 유도.
    _proLimitSub = p2p.onProLimitReached.listen((_) {
      if (!mounted || _mode != PlayerMode.host) return;
      _showProLimitDialog();
    });
    // 게스트 측 메시지: welcome / peer-joined / peer-left → peerCount 갱신.
    // 호스트가 보낸 join-rejected는 _enterSpeakerMode에서 별도 처리.
    _rejectedSub = p2p.onMessage.listen((m) {
      if (!mounted || _mode != PlayerMode.speaker) return;
      final type = m['type'];
      if (type == 'welcome' || type == 'peer-joined' || type == 'peer-left') {
        final c = m['data']?['peerCount'];
        if (c is int) _setStateAndSheet(() => _peerCount = c);
      } else if (type == 'host-closed') {
        _exitSpeakerMode(reason: '호스트가 방을 닫았습니다');
      }
    });

    // transpose/speed 외부 변경 시 UI 갱신. 스피커 모드 게스트(audio-pitch/audio-tempo
    // 수신) + 호스트 본인 슬라이더 조정 모두 emit. listener는 단순 setState 트리거.
    _transposeStreamSub = audio.transposeCentsStream.listen((_) {
      if (mounted) setState(() {});
    });
    _speedStreamSub = audio.playbackSpeedStream.listen((_) {
      if (mounted) setState(() {});
    });

    // (이전엔 다운로드 완료 후 sync 트리거 listener 있었으나, sync 시점이 입장 즉시로
    // 변경되어 제거. _loadingSub 필드는 호환성 위해 유지 — 차후 다른 용도로 재사용 가능.)

    // A-B 반복 + seek 메모리: 컨트롤러(단독/호스트)만. 파일 변경 시 widget state reset.
    if (_isController) {
      _positionSub = audio.positionStream.listen(_onAbPositionTick);
      _durationSub = audio.durationStream.listen((_) {
        if (!mounted) return;
        setState(() {
          _abPointA = null;
          _abPointB = null;
          _seekSlots = List<Duration?>.filled(3, null);
        });
      });
    }

    // 첫 실행이면 위젯 렌더 후(GlobalKey 유효 시점) 가이드 자동 표시.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstRunGuide();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _peerJoinSub?.cancel();
    _peerLeaveSub?.cancel();
    _disconnectedSub?.cancel();
    _rejectedSub?.cancel();
    _proLimitSub?.cancel();
    _transposeStreamSub?.cancel();
    _speedStreamSub?.cancel();
    _loadingSub?.cancel();
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
      if (_abPointA != null && _abPointB != null && _abPointA! > _abPointB!) {
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

  void _onSlotTap(int idx) {
    if (_audio.currentFileName == null) return;
    final stored = _seekSlots[idx];
    if (stored == null) {
      setState(() => _seekSlots[idx] = _lastPosition);
      return;
    }
    // 저장된 위치로 이동. A-B 활성이면 [A, B]로 clamp(슬롯이 범위 밖이면 가까운 끝점).
    Duration target = stored;
    if (_abActive) {
      final aMs = _effectiveA.inMilliseconds;
      final bMs = _effectiveB!.inMilliseconds;
      final clamped = target.inMilliseconds.clamp(aMs, bMs);
      target = Duration(milliseconds: clamped);
    }
    _audio.syncSeek(target);
  }

  void _onSlotLongPress(int idx) {
    if (_seekSlots[idx] == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _seekSlots[idx] = null);
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
          _showSnack(msg);
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
    final maxMs = _effectiveB?.inMilliseconds.toDouble() ?? totalMs.toDouble();
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
      final atEnd = totalMs > 0 && _lastPosition.inMilliseconds >= totalMs - 50;
      final outside =
          _lastPosition < a || (b != null && _lastPosition >= b) || atEnd;
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
    // 프로면 배너 숨김. 구매/복원 시 proProvider 갱신 → 배너 자동 제거.
    final isPro = ref.watch(proProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 인앱 브랜드 마크 (logo.png — SVG는 글로우 filter/mask 미지원으로
            // flutter_svg에서 까맣게 깨져 PNG 사용. 검증 v0.0.131.)
            Image.asset('assets/branding/logo.png', height: 24),
            const SizedBox(width: 8),
            const Text('Synchorus'),
            const SizedBox(width: 8),
            Text(
              _versionLabel,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Symbols.settings_rounded),
            onPressed: _openSettings,
          ),
          IconButton(
            key: _keyP2P,
            tooltip: 'P2P 모드',
            icon: const Icon(Symbols.group_add_rounded),
            onPressed: _isModeTransitioning ? null : _showModeSheet,
          ),
        ],
      ),
      body: SafeArea(
        // 수익화: 무료 사용자는 하단에 고정 배너(스크롤 영역 밖). 프로면 숨김.
        // 위 Expanded가 남은 높이를 스크롤 영역에 주므로 작은 화면 대응 유지.
        child: Column(
          children: [
            Expanded(
              // 작은 화면(분할 화면·큰 글꼴·구형 폰) 대응. 아래 Column은 Spacer로
              // 남는 공간을 흡수하는데, 화면이 짧으면 고정 콘텐츠가 넘쳐 RenderFlex
              // overflow가 났음. LayoutBuilder+ConstrainedBox(minHeight)+IntrinsicHeight
              // 조합: 화면이 충분하면 minHeight로 꽉 차 Spacer가 살아 기존 레이아웃 유지,
              // 짧으면 IntrinsicHeight가 실제 콘텐츠 높이를 잡아 그만큼 스크롤.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // 파일 정보 카드 — 클릭 시 파일 선택. 별도 버튼 없음.
                            KeyedSubtree(
                              key: _keyNowPlaying,
                              child: _buildNowPlaying(),
                            ),

                            const Spacer(),

                            // 시크바 + 시간
                            KeyedSubtree(
                              key: _keySeekBar,
                              child: _buildSeekBar(),
                            ),

                            // A-B 구간 반복 + seek 메모리 + §H transpose + §I 속도.
                            // 스피커 모드에서도 표시 그대로, 내부 컨트롤만 비활성 (호스트 영향 안 줌).
                            const SizedBox(height: 8),
                            KeyedSubtree(
                              key: _keyAbControls,
                              child: _buildAbControls(),
                            ),
                            const SizedBox(height: 8),
                            KeyedSubtree(
                              key: _keySeekSlots,
                              child: _buildSeekSlots(),
                            ),
                            const SizedBox(height: 8),
                            KeyedSubtree(
                              key: _keyTranspose,
                              child: _buildTransposeControls(),
                            ),
                            const SizedBox(height: 8),
                            KeyedSubtree(
                              key: _keySpeed,
                              child: _buildSpeedControls(),
                            ),

                            const SizedBox(height: 16),

                            // 재생 컨트롤
                            KeyedSubtree(
                              key: _keyControls,
                              child: _buildControls(),
                            ),

                            // 재생 컨트롤 아래 여백. 하단 배너(무료) 또는 화면 끝과의
                            // 간격. 바깥 Padding(16)과 합쳐 ~24dp. (Sync Info는 디버그용
                            // — 사용자 요청으로 노출 안 함.)
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!isPro) const BannerAdWidget(),
          ],
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

            // 우선순위: 동기화 중 > 다운로드 중 > 파일명 > placeholder.
            // 모드 라벨(단독/호스트/스피커)은 노출 안 함 (사용자 요청).
            // 카드 자체를 탭하면 파일 선택 — 호스트 권한 + 진행 중 아닐 때만.
            final showSync = _isSyncing && _mode == PlayerMode.speaker;
            final String title;
            final Widget leading;
            if (showSync) {
              title = '동기화 중';
              leading = const SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              );
            } else if (isLoading) {
              title = (progress > 0 && progress < 1.0)
                  ? '파일 수신 중... $progressPct%'
                  : '파일 수신 중...';
              leading = SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    value: progress > 0 && progress < 1.0 ? progress : null,
                  ),
                ),
              );
            } else {
              title = fileName ?? (_isController ? '오디오를 선택하세요' : '음악 대기 중');
              // 파일 선택 시 활성(라벤더+채움), 미선택 시 비활성(흐린 외곽선).
              final hasFile = fileName != null;
              leading = Icon(
                Symbols.music_note_rounded,
                size: 40,
                fill: hasFile ? 1 : 0,
                color: hasFile ? AppColors.primary : AppColors.textLow,
              );
            }
            return Card(
              child: ListTile(
                onTap: (!isLoading && !showSync && _isController)
                    ? _pickFile
                    : null,
                leading: leading,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
            final maxMs = duration.inMilliseconds.toDouble().clamp(
              1.0,
              double.maxFinite,
            );
            // 효과적 [A, B] 범위로 clamp. 시크바 max는 곡 끝(시각적으로 전체
            // 표시)이지만 thumb은 [A, B] 안에서만 움직임. A 없으면 0, B 없으면 곡끝.
            final minSeekMs = _effectiveA.inMilliseconds.toDouble();
            final maxSeekMs = _effectiveB?.inMilliseconds.toDouble() ?? maxMs;
            return Column(
              children: [
                // A/B 마커 영역 — 모드 무관 항상 reserve해서 시크바 높이 고정.
                // 스피커 모드는 _abPointA/B가 null이라 빈 18px SizedBox만 표시.
                _buildAbMarkers(maxMs),
                SliderTheme(
                  data: Theme.of(context).sliderTheme.copyWith(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _sliderHorizontalPadding,
                    ),
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMs,
                    value: _isDragging
                        ? _dragValue.clamp(0.0, maxMs)
                        : position.inMilliseconds.toDouble().clamp(0.0, maxMs),
                    onChanged: (_isController && _audio.currentFileName != null)
                        ? (value) {
                            final clamped = value.clamp(minSeekMs, maxSeekMs);
                            setState(() {
                              _isDragging = true;
                              _dragValue = clamped;
                            });
                          }
                        : null,
                    onChangeEnd:
                        (_isController && _audio.currentFileName != null)
                        ? (value) {
                            final clamped = value.clamp(minSeekMs, maxSeekMs);
                            setState(() => _isDragging = false);
                            _audio.syncSeek(
                              Duration(milliseconds: clamped.toInt()),
                            );
                          }
                        : null,
                  ),
                ),
                // 슬롯 마커 영역 — 모드 무관 항상 reserve해서 시크바 높이 고정.
                _buildSlotMarkers(maxMs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(
                          _isDragging
                              ? Duration(milliseconds: _dragValue.toInt())
                              : position,
                        ),
                        style: AppTypography.monoStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textHi,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: AppTypography.monoStyle(
                          fontSize: 14,
                          color: AppColors.textMid,
                        ),
                      ),
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
                  onPressed: (_isController && hasAudio)
                      ? () => _skipSeconds(-5)
                      : null,
                  icon: const Icon(Symbols.replay_5_rounded),
                ),
                const SizedBox(width: 16),
                // 강조 = 라벤더 glow (디자인 시스템: 재생 버튼·방 코드에만).
                // 재생 가능할 때만 후광 — 비활성(게스트/무파일)이면 끔.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: (_isController && hasAudio)
                        ? AppShadows.glowSoft
                        : null,
                  ),
                  child: IconButton(
                    iconSize: 64,
                    onPressed: (_isController && hasAudio) ? _togglePlay : null,
                    icon: Icon(
                      playing
                          ? Symbols.pause_circle_rounded
                          : Symbols.play_circle_rounded,
                      fill: 1, // 디자인 시스템: play/pause만 채움(FILL 1)
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed: (_isController && hasAudio)
                      ? () => _skipSeconds(5)
                      : null,
                  icon: const Icon(Symbols.forward_5_rounded),
                ),
              ],
            ),
            Positioned(
              right: 0,
              child: IconButton(
                iconSize: 28,
                onPressed: hasAudio ? _toggleMute : null,
                icon: Icon(
                  _muted
                      ? Symbols.volume_off_rounded
                      : Symbols.volume_up_rounded,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 시크바 위 A/B 마커. 텍스트(위) + 막대(아래, 시크바 쪽). primary 색.
  Widget _buildAbMarkers(double maxMs) {
    return _markerRow(
      maxMs: maxMs,
      below: false,
      color: Theme.of(context).colorScheme.primary,
      points: [
        if (_abPointA != null) (point: _abPointA!, label: 'A'),
        if (_abPointB != null) (point: _abPointB!, label: 'B'),
      ],
    );
  }

  /// 시크바 아래 메모리 슬롯 마커. 막대(위, 시크바 쪽) + 텍스트(아래). tertiary 색.
  Widget _buildSlotMarkers(double maxMs) {
    return _markerRow(
      maxMs: maxMs,
      below: true,
      color: Theme.of(context).colorScheme.tertiary,
      points: [
        for (int i = 0; i < 3; i++)
          if (_seekSlots[i] != null) (point: _seekSlots[i]!, label: '${i + 1}'),
      ],
    );
  }

  /// 마커 Row 공통 헬퍼. below=true면 막대 위·텍스트 아래(시크바 아래용).
  Widget _markerRow({
    required double maxMs,
    required bool below,
    required Color color,
    required List<({Duration point, String label})> points,
  }) {
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usable = (constraints.maxWidth - _sliderHorizontalPadding * 2)
              .clamp(1.0, double.infinity);
          final bar = Container(width: 2, height: 4, color: color);
          Widget marker(Duration point, String label) {
            final ratio = (point.inMilliseconds / maxMs).clamp(0.0, 1.0);
            final left = _sliderHorizontalPadding + usable * ratio;
            final textWidget = Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            );
            return Positioned(
              left: left,
              top: 0,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: below ? [bar, textWidget] : [textWidget, bar],
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [for (final p in points) marker(p.point, p.label)],
          );
        },
      ),
    );
  }

  Widget _buildAbControls() {
    // 스피커 모드에선 hasAudio여도 컨트롤 비활성 (호스트 widget state라 의미 없음).
    final hasAudio = _audio.currentFileName != null && _isController;
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
            Symbols.cancel_rounded,
            color: _abActive
                ? Theme.of(context).colorScheme.primary
                : (_abAnySet
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).disabledColor),
          ),
          onPressed: (_abAnySet && _isController) ? _resetAb : null,
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
    // DM Mono + tabular. color는 미지정 → 버튼 foregroundColor(A-B=primary/
    // 슬롯=tertiary) 상속. label('A'/'B'/'1')도 Latin이라 DM Mono로 잘 렌더됨.
    const tabular = TextStyle(
      fontFamily: AppTypography.mono,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return OutlinedButton(
      onPressed: enabled ? () => _setAbPoint(isA: isA) : null,
      onLongPress: (enabled && hasPoint) ? () => _clearAbPoint(isA: isA) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: hasPoint
            ? Theme.of(context).colorScheme.primary
            : null,
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

  Widget _buildSeekSlots() {
    final hasAudio = _audio.currentFileName != null && _isController;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _slotButton(idx: i, point: _seekSlots[i], enabled: hasAudio),
        ],
      ],
    );
  }

  Widget _slotButton({
    required int idx,
    required Duration? point,
    required bool enabled,
  }) {
    final hasPoint = point != null;
    final dur = _audio.currentDuration ?? Duration.zero;
    final placeholderTime = dur.inHours > 0 ? '0:00:00' : '00:00';
    // DM Mono + tabular. color는 미지정 → 버튼 foregroundColor(A-B=primary/
    // 슬롯=tertiary) 상속. label('A'/'B'/'1')도 Latin이라 DM Mono로 잘 렌더됨.
    const tabular = TextStyle(
      fontFamily: AppTypography.mono,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final label = '${idx + 1}';
    return OutlinedButton(
      onPressed: enabled ? () => _onSlotTap(idx) : null,
      onLongPress: (enabled && hasPoint) ? () => _onSlotLongPress(idx) : null,
      style: OutlinedButton.styleFrom(
        // 시크바 마커와 통일 — 슬롯은 tertiary로 A/B(primary)와 시각 구분.
        foregroundColor: hasPoint
            ? Theme.of(context).colorScheme.tertiary
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0,
            child: Text('$label  $placeholderTime', style: tabular),
          ),
          Text(
            hasPoint ? '$label  ${_formatDuration(point)}' : label,
            style: tabular,
          ),
        ],
      ),
    );
  }

  Widget _buildTransposeControls() {
    final hasAudio = _audio.currentFileName != null && _isController;
    final semitone = (_audio.transposeCents / 100).round();
    final label = semitone == 0
        ? '0'
        : (semitone > 0 ? '+$semitone' : '$semitone');
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('TRANSPOSE', style: AppTypography.eyebrow),
            const SizedBox(width: 12),
            // 우측정렬 + tabularFigures: 부호(+/−) 유무·자릿수가 바뀌어도
            // 오른쪽 끝(아이콘 옆) 기준으로 값 위치가 고정됨.
            SizedBox(
              width: 36,
              // 큰 글꼴 설정에서 '+12' 등이 36px를 넘어 wrap되던 것 방지.
              // scaleDown은 폭 초과 시에만 축소(평소 무변화), centerRight 유지.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: AppTypography.monoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: semitone != 0 ? scheme.primary : AppColors.textHi,
                  ),
                ),
              ),
            ),
            // 리셋은 옆 아이콘 버튼으로만 — 값 long press 리셋은 제거.
            // 아이콘은 항상 같은 자리에 두되 기본값(0)일 땐 비활성
            // (onPressed=null → disabled 회색). 등장/소멸이 없어 흔들림 없음.
            IconButton(
              icon: const Icon(Symbols.refresh_rounded),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: '리셋',
              color: scheme.primary,
              onPressed: (hasAudio && semitone != 0) ? _resetTranspose : null,
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Symbols.remove_rounded),
              iconSize: 20,
              onPressed: hasAudio && semitone > -12
                  ? () => _adjustTranspose(-1)
                  : null,
            ),
            Expanded(
              child: Slider(
                min: -12,
                max: 12,
                divisions: 24,
                value: semitone.toDouble().clamp(-12.0, 12.0),
                onChanged: hasAudio
                    ? (v) {
                        final newCents = v.round() * 100;
                        if (newCents != _audio.transposeCents) {
                          _audio.setTransposeCents(newCents);
                          setState(() {});
                        }
                      }
                    : null,
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.add_rounded),
              iconSize: 20,
              onPressed: hasAudio && semitone < 12
                  ? () => _adjustTranspose(1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  void _adjustTranspose(int delta) {
    final current = (_audio.transposeCents / 100).round();
    final next = (current + delta).clamp(-12, 12);
    _audio.setTransposeCents(next * 100);
    setState(() {});
  }

  void _resetTranspose() {
    HapticFeedback.mediumImpact();
    _audio.setTransposeCents(0);
    setState(() {});
  }

  Widget _buildSpeedControls() {
    final hasAudio = _audio.currentFileName != null && _isController;
    final speed = _audio.playbackSpeed;
    final label = '${speed.toStringAsFixed(2)}x';
    final isDefault = _audio.playbackSpeedX1000 == 1000;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('SPEED', style: AppTypography.eyebrow),
            const SizedBox(width: 12),
            // 우측정렬 + tabularFigures: 값 폭이 바뀌어도 오른쪽 끝
            // (아이콘 옆) 기준으로 위치가 고정됨.
            SizedBox(
              width: 52,
              // 큰 글꼴 설정(textScaler)에서 '1.00x'가 52px를 넘어 2줄로
              // wrap되던 것 방지. scaleDown은 폭 초과 시에만 축소(평소 무변화),
              // centerRight로 우측정렬 유지.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: AppTypography.monoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: !isDefault ? scheme.primary : AppColors.textHi,
                  ),
                ),
              ),
            ),
            // 리셋은 옆 아이콘 버튼으로만 — 값 long press 리셋은 제거.
            // 아이콘은 항상 같은 자리에 두되 기본값(1.00x)일 땐 비활성
            // (onPressed=null → disabled 회색). 등장/소멸이 없어 흔들림 없음.
            IconButton(
              icon: const Icon(Symbols.refresh_rounded),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: '리셋',
              color: scheme.primary,
              onPressed: (hasAudio && !isDefault) ? _resetSpeed : null,
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Symbols.remove_rounded),
              iconSize: 20,
              onPressed: hasAudio && _audio.playbackSpeedX1000 > 500
                  ? () => _adjustSpeed(-50)
                  : null,
            ),
            Expanded(
              child: Slider(
                min: 500,
                max: 2000,
                divisions: 30, // 5% step
                value: _audio.playbackSpeedX1000.toDouble().clamp(
                  500.0,
                  2000.0,
                ),
                onChanged: hasAudio
                    ? (v) {
                        final newVal = (v / 50).round() * 50;
                        if (newVal != _audio.playbackSpeedX1000) {
                          _audio.setPlaybackSpeedX1000(newVal);
                          setState(() {});
                        }
                      }
                    : null,
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.add_rounded),
              iconSize: 20,
              onPressed: hasAudio && _audio.playbackSpeedX1000 < 2000
                  ? () => _adjustSpeed(50)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  void _adjustSpeed(int deltaX1000) {
    final current = _audio.playbackSpeedX1000;
    final next = (current + deltaX1000).clamp(500, 2000);
    _audio.setPlaybackSpeedX1000(next);
    setState(() {});
  }

  void _resetSpeed() {
    HapticFeedback.mediumImpact();
    _audio.setPlaybackSpeedX1000(1000);
    setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2P 모드 진입/종료 — Phase 4(호스트) + Phase 5(스피커, 일부 stub)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _versionLabel = 'v${info.version}');
  }

  /// 게스트 표시명. Android: model, iOS: 사용자 설정명. (home_screen.dart 동일 로직)
  /// stale 매칭은 _resolveDeviceId UUID로 하므로 충돌 무관.
  Future<String> _resolveDeviceName() async {
    String base = 'Guest';
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        base = info.model;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        base = info.name;
      }
    } catch (_) {}
    if (base.isEmpty) base = 'Guest';
    if (base.length > 24) base = base.substring(0, 24);
    return base;
  }

  /// 영구 디바이스 식별자 (32자 hex). SharedPreferences 영속.
  /// _enterSpeakerMode 스피커 입장 시 사용 (게스트 고유 식별 → 호스트 stale peer 정리).
  Future<String> _resolveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_uuid');
    if (id != null && id.length == 32) return id;
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('device_uuid', id);
    return id;
  }

  /// SnackBar 표시 헬퍼. hideCurrentSnackBar()로 이전 메시지를 즉시 치우고 새로
  /// 표시 → 연속 호출 시 큐에 쌓여 옛 메시지가 끝나길 기다리는 적체 방지.
  void _showSnack(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 온보딩 가이드 (coach mark, tutorial_coach_mark) ──────────────────
  // 첫 실행 자동 + AppBar ? 버튼. 각 영역(GlobalKey) 단계별 하이라이트 + 한국어 설명.
  static const String _guidePrefsKey = 'hasSeenGuide_v1';
  // 오버레이 탭 시 next() 호출용 인스턴스 보관.
  TutorialCoachMark? _coachMark;

  /// 첫 실행이면(플래그 없음) 가이드 자동 표시. initState의 postFrame에서 호출.
  Future<void> _maybeShowFirstRunGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_guidePrefsKey) ?? false) return;
    if (!mounted) return;
    _showGuide();
  }

  Future<void> _markGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guidePrefsKey, true);
  }

  /// 가이드 말풍선 내용 (제목 + 설명 + 다음/완료 버튼). 오버레이가 어두우므로 흰 글씨.
  /// 버튼 onPressed에서 _coachMark.next() — 하이라이트 탭 없이 버튼으로 명확히 진행.
  Widget _guideText(String title, String body, {bool isLast = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textHi,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: AppColors.textHi,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _coachMark?.next(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.primarySoft,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            ),
            child: Text(
              isLast ? '완료 ✓' : '다음 →',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// coach mark 타겟 helper. 가로로 긴 위젯도 적절히 감싸도록 RRect(사각) 하이라이트
  /// + 오버레이 아무 곳이나 탭해도 다음 단계로(enableOverlayTab).
  TargetFocus _guideTarget(
    String id,
    GlobalKey key,
    ContentAlign align,
    String title,
    String body, {
    bool isLast = false,
  }) {
    return TargetFocus(
      identify: id,
      keyTarget: key,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      // 다크 UI라 포커스 구멍이 배경과 잘 구분 안 됨 → 라벤더 테두리로 강조.
      // pulseEnable(기본 on)과 합쳐 깜빡이며 "여기!"가 또렷하게 보임.
      borderSide: const BorderSide(color: AppColors.primary, width: 3),
      contents: [
        TargetContent(
          align: align,
          child: _guideText(title, body, isLast: isLast),
        ),
      ],
    );
  }

  /// 단계별 coach mark 표시 (첫 실행 자동 / ? 버튼 수동 공용).
  // 2대 제한 팝업 중복 방지(게스트가 연속 접속 시도 시 다이얼로그 쌓임 방지).
  bool _proDialogOpen = false;

  /// 무료 호스트가 게스트 거절(2대 초과) 시 표시. 결제(설정)로 유도.
  Future<void> _showProLimitDialog() async {
    if (_proDialogOpen || !mounted) return;
    _proDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기기 제한 도달'),
        content: const Text(
          '무료 버전은 2대(내 기기 + 1대)까지 동기화할 수 있어요.\n'
          '프로로 업그레이드하면 기기 제한 없이 연결하고 광고도 사라져요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openSettings();
            },
            child: const Text('업그레이드'),
          ),
        ],
      ),
    );
    _proDialogOpen = false;
  }

  /// 게스트가 2대 제한으로 거절됐을 때 안내 팝업. 게스트는 결제 주체가 아니라
  /// (호스트가 프로 결제해야 풀림) 상황만 명확히 알림.
  Future<void> _showGuestRejectedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('연결할 수 없어요'),
        content: const Text(
          '호스트가 무료 버전이라 2대(호스트 + 1대)까지만 연결할 수 있어요.\n'
          '호스트가 프로로 업그레이드하면 함께 들을 수 있어요.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 설정 화면 열기. 가이드는 GlobalKey가 이 화면에 있어 SettingsScreen이 직접
  /// 못 띄움 → pop('showGuide') 신호를 받아 여기서 _showGuide() 실행.
  Future<void> _openSettings() async {
    // PlayerScreen route의 secondaryAnimation = 위에 덮이는 SettingsScreen 전환을
    // 반영(0=설정 없음, 1=완전히 덮임). pop 후 dismissed(0) 도달 = 전환 완료 신호.
    final route = ModalRoute.of(context);
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (result != 'showGuide' || !mounted) return;

    // 설정 화면 pop 전환이 완전히 끝나고 메인 레이아웃이 정착한 뒤 가이드 표시.
    // `await push`는 pop이 '호출'되는 순간 반환되어 전환 애니메이션이 아직 진행
    // 중일 수 있음 → 그 사이 _showGuide가 GlobalKey renderBox를 읽으면 첫 타겟(카드)
    // highlight가 좁게 좌측으로 잡힘(전환 중 레이아웃 미정착). 첫 실행 가이드는 전환이
    // 없어 정상이라 이 경로에서만 발생.
    //
    // 고정 delay는 기기/애니메이션 배율마다 전환 시간이 달라 부정확 → secondaryAnimation
    // 이 dismissed될 때까지 리스너로 대기(애니메이션 꺼진 환경은 즉시 dismissed라 대기 0).
    final anim = route?.secondaryAnimation;
    if (anim != null && anim.status != AnimationStatus.dismissed) {
      final completer = Completer<void>();
      void onStatus(AnimationStatus s) {
        if (s == AnimationStatus.dismissed) {
          anim.removeStatusListener(onStatus);
          if (!completer.isCompleted) completer.complete();
        }
      }

      anim.addStatusListener(onStatus);
      // 안전장치: 전환이 비정상적으로 안 끝나도 최대 1초 후 진행.
      await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => anim.removeStatusListener(onStatus),
      );
    }
    // 전환 완료 후 한 프레임 더 — 최종 레이아웃 정착 보장.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) _showGuide();
  }

  void _showGuide() {
    final targets = <TargetFocus>[
      _guideTarget(
        'nowPlaying',
        _keyNowPlaying,
        ContentAlign.bottom,
        '음악 선택',
        '여기를 눌러 재생할 음악을 골라요. 선택한 곡 이름이 여기 표시돼요.',
      ),
      _guideTarget(
        'seekBar',
        _keySeekBar,
        ContentAlign.top,
        '재생 위치',
        '지금 재생 중인 위치예요. 좌우로 드래그하면 원하는 지점으로 이동해요.',
      ),
      _guideTarget(
        'abControls',
        _keyAbControls,
        ContentAlign.top,
        'A-B 구간 반복',
        'A·B로 시작과 끝을 찍으면 그 구간만 반복돼요. A·B를 길게 누르면 그 지점만, Ⓧ로 전체를 해제해요.',
      ),
      _guideTarget(
        'seekSlots',
        _keySeekSlots,
        ContentAlign.top,
        '위치 저장',
        '1·2·3에 현재 위치를 저장하고, 다시 누르면 그 위치로 이동해요. 길게 누르면 해제돼요.',
      ),
      _guideTarget(
        'transpose',
        _keyTranspose,
        ContentAlign.top,
        '음정',
        '음 높낮이를 반음씩 바꿔요. ↻로 원래 음으로 되돌려요.',
      ),
      _guideTarget(
        'speed',
        _keySpeed,
        ContentAlign.top,
        '재생 속도',
        '빠르기를 0.5~2.0배로 바꿔요. ↻로 원래 속도로 되돌려요.',
      ),
      _guideTarget(
        'controls',
        _keyControls,
        ContentAlign.top,
        '재생 컨트롤',
        '가운데로 재생·일시정지하고, 양옆 화살표로 5초씩 이동해요. 맨 오른쪽은 음소거예요.',
      ),
      _guideTarget(
        'p2p',
        _keyP2P,
        ContentAlign.bottom,
        '싱크 모드',
        '여러 폰을 동기화된 스피커로 묶어 같은 음악을 함께 들어요. 이 버튼으로 시작해요.',
        isLast: true,
      ),
    ];
    _coachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: AppColors.ink950, // violet-tinted near-black scrim
      opacityShadow: 0.85,
      textSkip: '건너뛰기',
      paddingFocus: 8,
      // 오버레이(타겟 밖) 탭해도 다음 단계로. enableOverlayTab은 환경에 따라
      // 닫힘으로 동작 → onClickOverlay에서 next() 명시 호출이 확실.
      onClickOverlay: (target) {
        _coachMark?.next();
      },
      onFinish: () {
        _markGuideSeen();
      },
      onSkip: () {
        _markGuideSeen();
        return true;
      },
    );
    _coachMark!.show(context: context);
  }

  void _showModeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            _setSheetState = setSheetState;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                // 배경 탭으로도 닫히지만 일부 사용자는 직관적이지 않아 해 우측
                // 상단에 명시적 X 버튼 추가. switch 바깥 공통 위치라 모드 선택·
                // 호스트·스피커 sheet 모두 동일하게 적용 (사용자 요청).
                child: Stack(
                  // Positioned가 음수 offset(패딩 영역으로 X 버튼을 빼냄)이라
                  // 기본 Clip.hardEdge면 잘림 → Clip.none.
                  clipBehavior: Clip.none,
                  children: [
                    switch (_mode) {
                      PlayerMode.standalone => _buildStandaloneSheet(
                        sheetContext,
                      ),
                      PlayerMode.host => _buildHostSheet(sheetContext),
                      PlayerMode.speaker => _buildSpeakerSheet(sheetContext),
                    },
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        icon: const Icon(Symbols.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                        tooltip: '닫기',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _setSheetState = null;
      // sheet 닫히면 호스트 진입 에러도 비움 — 다음에 열 때 깨끗한 상태.
      if (mounted && _hostModeError != null) {
        setState(() => _hostModeError = null);
      }
    });
  }

  /// state 변경 시 PlayerScreen + (sheet 열려있으면) sheet도 함께 rebuild.
  /// peer count, mode, hostIp 등 sheet에 표시되는 정보 갱신 시 사용.
  void _setStateAndSheet(VoidCallback fn) {
    setState(fn);
    _setSheetState?.call(() {});
  }

  Widget _buildStandaloneSheet(BuildContext sheetContext) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '모드 선택',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            // sheet 닫지 않고 호스트 진입 — _enterHostMode 안 _setStateAndSheet
            // (_mode=host)이 sheet rebuild → switch에서 _buildHostSheet으로 전환.
            // OutlinedButton — 스피커 검색 버튼과 시각 통일 (사용자 요청).
            onPressed: () => _enterHostMode(),
            icon: const Icon(Symbols.cast_connected_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('호스트 모드'),
            ),
          ),
          // 호스트 진입 실패(WiFi 없음/서버 시작 실패)는 inline 표시 — SnackBar는
          // 이 sheet에 가려서 안 보임 (스피커 picker _lastError와 동일 패턴).
          if (_hostModeError != null) ...[
            const SizedBox(height: 8),
            _buildInlineError(context, _hostModeError!),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Symbols.speaker_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                '스피커 모드',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SpeakerModePicker(
            discovery: ref.read(discoveryServiceProvider),
            onConnect: (ip, port, code) =>
                _enterSpeakerMode(ip: ip, port: port, roomCode: code),
            onPing: (ip, port) =>
                ref.read(p2pServiceProvider).pingHost(ip, port),
            onSuccess: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    );
  }

  Widget _buildHostSheet(BuildContext sheetContext) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '호스트 모드',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        // 방 코드 카드 — 라벤더 glow로 강조 (디자인 시스템).
        DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: AppRadii.cardBorder,
            boxShadow: AppShadows.glowPrimary,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('입장 코드', _roomCode ?? '—', emphasize: true),
                  const SizedBox(height: 8),
                  _infoRow('IP', _hostIp ?? '—', mono: true),
                  const SizedBox(height: 8),
                  _infoRow('접속자', '${_peerCount + 1}명'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(sheetContext);
            await _exitHostMode();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.ink950,
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('호스트 모드 종료'),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeakerSheet(BuildContext sheetContext) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '스피커 모드',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('호스트 IP', _connectedHostIp ?? '—', mono: true),
                const SizedBox(height: 8),
                _infoRow('입장 코드', _connectedRoomCode ?? '—', mono: true),
                const SizedBox(height: 8),
                _infoRow('접속자', '${_peerCount + 1}명'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(sheetContext);
            await _exitSpeakerMode();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.ink950,
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('스피커 모드 종료'),
          ),
        ),
      ],
    );
  }

  /// 정보 행. [emphasize]=방 코드(hero mono+라벤더), [mono]=IP 등 숫자값.
  /// 한글이 섞인 값('3명' 등)은 mono를 켜지 말 것 (DM Mono엔 한글 글리프 없음).
  Widget _infoRow(
    String label,
    String value, {
    bool emphasize = false,
    bool mono = false,
  }) {
    final TextStyle valueStyle;
    if (emphasize) {
      valueStyle = AppTypography.monoStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
        letterSpacing: 2,
      );
    } else if (mono) {
      valueStyle = AppTypography.monoStyle(
        fontSize: 14,
        color: AppColors.textHi,
      );
    } else {
      valueStyle = const TextStyle(fontSize: 14, color: AppColors.textHi);
    }
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMid),
          ),
        ),
        Expanded(child: Text(value, style: valueStyle)),
      ],
    );
  }

  Future<void> _enterHostMode() async {
    if (_isModeTransitioning) return;
    // 재진입 시 이전 에러 비움 + transitioning 표시. sheet도 rebuild돼 에러가 사라짐.
    _setStateAndSheet(() {
      _isModeTransitioning = true;
      _hostModeError = null;
    });
    try {
      final ip = await NativeAudioSyncService.getLocalIP();
      if (ip == null) {
        if (mounted) {
          _setStateAndSheet(() => _hostModeError = 'WiFi 연결이 필요합니다');
        }
        return;
      }

      final p2p = ref.read(p2pServiceProvider);
      final discovery = ref.read(discoveryServiceProvider);

      // 현재 프로 상태 주입(앱 시작 시 이미 프로면 ref.listen 변경 이벤트가 없어
      // 누락될 수 있어 호스트 시작 시 한 번 명시적으로 push). 무료면 2대 제한.
      p2p.setProStatus(ref.read(proProvider));

      int port;
      try {
        port = await p2p.startHost();
      } catch (e) {
        // startHost는 disconnect()로 기존 소켓 정리 + ServerSocket.bind(shared:true)라
        // 포트 점유 충돌은 사실상 안 남. 여기 도달은 드문 예외(권한 등) — 원인을
        // 단정하지 않고 일반 문구로. 안전망 catch는 유지(예외 시 앱 안 죽게).
        if (mounted) {
          _setStateAndSheet(() => _hostModeError = '서버를 시작할 수 없습니다');
        }
        return;
      }

      final roomCode = p2p.generateRoomCode();
      final hostName = await _resolveDeviceName();
      await discovery.startBroadcast(
        hostName: hostName,
        tcpPort: port,
        roomCode: roomCode,
      );

      if (!mounted) return;
      _setStateAndSheet(() {
        _mode = PlayerMode.host;
        _hostIp = ip;
        _roomCode = roomCode;
        _peerCount = 0;
      });

      // 호스트 측 sync-ping 응답 listener 등록 — 게스트가 sync.syncWithHost 호출 시
      // 호스트가 sync-pong 응답해야 sync 완료됨. 누락 시 게스트 무한 await.
      // (이전 RoomScreen이 했던 호출, PlayerScreen 이식 누락 fix.)
      ref.read(syncServiceProvider).startHostHandler();

      // HISTORY (105) audio-url 미전파 fix. 단독 모드에서 파일 로드된 상태로 호스트
      // 전환 시 _currentUrl이 null이면 HTTP 서버 재바인딩 + audio-url broadcast.
      await _audio.rebindFileServerIfNeeded();
    } finally {
      if (mounted) setState(() => _isModeTransitioning = false);
    }
  }

  Future<void> _exitHostMode() async {
    if (_isModeTransitioning) return;
    setState(() => _isModeTransitioning = true);
    try {
      final p2p = ref.read(p2pServiceProvider);
      final discovery = ref.read(discoveryServiceProvider);

      // host-closed broadcast best-effort. 게스트는 RoomLifecycleCoordinator 또는
      // 본인 onMessage host-closed 핸들러에서 단독 모드 복귀.
      try {
        p2p.broadcastToAll({'type': 'host-closed'});
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));

      await discovery.stop();
      await p2p.disconnect();

      if (!mounted) return;
      _setStateAndSheet(() {
        _mode = PlayerMode.standalone;
        _hostIp = null;
        _roomCode = null;
        _peerCount = 0;
      });
    } finally {
      if (mounted) setState(() => _isModeTransitioning = false);
    }
  }

  /// 스피커 모드 진입. 호스트에 connect + welcome/join-rejected 응답 처리.
  /// 반환: null=성공(mode=speaker 전환), string=실패 사유(BottomSheet picker가 inline
  /// 표시 — SnackBar는 sheet에 가려서 안 보임).
  Future<String?> _enterSpeakerMode({
    required String ip,
    required int port,
    required String roomCode,
  }) async {
    if (_isModeTransitioning) return '진행 중입니다';
    setState(() => _isModeTransitioning = true);
    try {
      final p2p = ref.read(p2pServiceProvider);
      await p2p.disconnect();

      final guestName = await _resolveDeviceName();
      final deviceId = await _resolveDeviceId();

      // welcome 또는 join-rejected 둘 중 먼저 도착 대기 (5초 timeout).
      final replyFuture = p2p.onMessage
          .where((m) => m['type'] == 'welcome' || m['type'] == 'join-rejected')
          .first
          .timeout(const Duration(seconds: 5));

      try {
        await p2p.connectToHost(
          ip,
          port,
          guestName,
          deviceId: deviceId,
          roomCode: roomCode,
        );
      } catch (e) {
        return e is SocketException ? '호스트에 연결할 수 없습니다' : '연결 실패';
      }

      Map<String, dynamic> reply;
      try {
        reply = await replyFuture;
      } on TimeoutException {
        await p2p.disconnect();
        return '호스트 응답 없음 (시간 초과)';
      }

      if (reply['type'] == 'join-rejected') {
        await p2p.disconnect();
        final reason = reply['data']?['reason'] as String?;
        if (reason == 'pro-required') {
          // 게스트는 코드 재입력으로 풀 수 없음(호스트가 무료) → 시트 닫고 팝업 안내.
          // null 반환 시 picker가 시트만 닫음(_mode는 standalone 유지, 연결 안 됨).
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showGuestRejectedDialog();
            });
          }
          return null;
        }
        return '입장 코드가 맞지 않습니다';
      }

      // welcome 수신
      final peerCount = (reply['data']?['peerCount'] as int?) ?? 1;

      if (!mounted) return null;
      _setStateAndSheet(() {
        _mode = PlayerMode.speaker;
        _connectedHostIp = ip;
        _connectedRoomCode = roomCode;
        _peerCount = peerCount;
      });

      // sync 권한 변경 (호스트 → 게스트). startListening 재호출은 안전 (이미 구독되어 있어도 재구독).
      final audio = ref.read(nativeAudioSyncServiceProvider);
      final handler = ref.read(audioHandlerProvider);
      audio.startListening(isHost: false);
      handler.attachSyncService(audio, isHost: false);

      // 직렬 흐름: sync 먼저 완료 → audio-request → 다운로드.
      // 다운로드와 sync 병렬 시 WiFi 채널 점유로 RTT jitter 발생, sync 정확도
      // 떨어져 결국 싱크에 영향 (사용자 합의).
      unawaited(_runGuestStartupSequence());

      return null;
    } finally {
      if (mounted) setState(() => _isModeTransitioning = false);
    }
  }

  /// 게스트 입장 startup 시퀀스: sync 먼저 → 완료 후 audio-request로 다운로드 트리거.
  /// 직렬 처리로 다운로드의 WiFi 채널 점유가 sync RTT를 망치는 영향 회피.
  Future<void> _runGuestStartupSequence() async {
    if (!mounted || _mode != PlayerMode.speaker) return;

    // 1. sync 먼저 (다운로드 시작 전)
    setState(() => _isSyncing = true);
    debugPrint('[GUEST-STARTUP] sync begin');
    try {
      final sync = ref.read(syncServiceProvider);
      sync.reset();
      final result = await sync.syncWithHost();
      debugPrint(
        '[GUEST-STARTUP] sync done: offset=${result.offsetMs}ms RTT=${result.rttMs}ms isSynced=${sync.isSynced}',
      );
      sync.startPeriodicSync();
      debugPrint('[GUEST-STARTUP] startPeriodicSync OK');
    } catch (e) {
      debugPrint('[GUEST-STARTUP] sync FAILED: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }

    // 2. sync 완료 후 audio-request → 호스트가 audio-url 응답 → 다운로드.
    if (!mounted || _mode != PlayerMode.speaker) return;
    debugPrint('[GUEST-STARTUP] audio-request');
    ref.read(p2pServiceProvider).sendToHost({
      'type': 'audio-request',
      'data': <String, dynamic>{},
    });
  }

  /// 스피커 모드 종료 — disconnect + 단독 복귀 (재생 상태 유지).
  /// [reason]이 있으면 SnackBar 안내 (호스트 끊김 등).
  Future<void> _exitSpeakerMode({String? reason}) async {
    if (_isModeTransitioning) return;
    setState(() => _isModeTransitioning = true);
    try {
      final sync = ref.read(syncServiceProvider);
      sync.stopPeriodicSync();
      sync.reset();

      final audio = ref.read(nativeAudioSyncServiceProvider);
      audio.cleanupSync();

      final p2p = ref.read(p2pServiceProvider);
      await p2p.disconnect();

      if (!mounted) return;
      _setStateAndSheet(() {
        _mode = PlayerMode.standalone;
        _connectedHostIp = null;
        _connectedRoomCode = null;
        _peerCount = 0;
      });

      // 단독 모드로 sync 권한 회복 (isHost: true 재attach).
      final handler = ref.read(audioHandlerProvider);
      audio.startListening(isHost: true);
      handler.attachSyncService(audio, isHost: true);

      if (reason != null) {
        _showSnack(reason);
      }
    } finally {
      if (mounted) setState(() => _isModeTransitioning = false);
    }
  }
}

/// BottomSheet 안 inline 에러 박스 (errorContainer 배경 + error_outline 아이콘).
/// 호스트 모드 진입 실패 + 스피커 picker 연결 실패 공용 — SnackBar는 sheet에
/// 가려서 안 보이므로 sheet 안에 직접 표시.
Widget _buildInlineError(BuildContext context, String message) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Icon(
          Symbols.error_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// _SpeakerModePicker — Phase 5
//
// BottomSheet 안 스피커 모드 영역. 검색 토글 + 결과 리스트(이름/IP만, 코드 숨김)
// + IP 직접 입력. 검색은 자동 시작 X (사용자가 버튼 누름). 중단 조건: 검색 버튼
// 재누름, 방 입장 성공, sheet/picker dispose.
//
// 코드 검증: 결과 탭 또는 IP 연결 누름 → 코드 입력 다이얼로그 → onConnect 콜백
// 호출. onConnect=Future<bool>으로 호스트 측 reject 처리 후 성공 시 onSuccess
// (PlayerScreen sheet 닫기).
// ═══════════════════════════════════════════════════════════════════════════

class _SpeakerModePicker extends StatefulWidget {
  final DiscoveryService discovery;
  // onConnect: null=성공, string=실패 사유(picker가 inline 표시).
  final Future<String?> Function(String ip, int port, String code) onConnect;
  // onPing: 호스트 존재 확인. 코드 다이얼로그 띄우기 전 검증용.
  final Future<bool> Function(String ip, int port) onPing;
  final VoidCallback onSuccess;

  const _SpeakerModePicker({
    required this.discovery,
    required this.onConnect,
    required this.onPing,
    required this.onSuccess,
  });

  @override
  State<_SpeakerModePicker> createState() => _SpeakerModePickerState();
}

class _SpeakerModePickerState extends State<_SpeakerModePicker> {
  bool _isSearching = false;
  bool _isConnecting = false;
  String? _lastError;
  final List<DiscoveredHost> _hosts = [];
  StreamSubscription<DiscoveredHost>? _hostSub;
  StreamSubscription<String>? _hostLeftSub;
  final TextEditingController _ipController = TextEditingController();

  @override
  void dispose() {
    // sheet 닫힘/widget 해제 시 검색 중단 — 사용자 요청.
    _stopSearch();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _toggleSearch() async {
    if (_isSearching) {
      await _stopSearch();
    } else {
      await _startSearch();
    }
  }

  Future<void> _startSearch() async {
    setState(() {
      _isSearching = true;
      _hosts.clear();
    });
    _hostSub = widget.discovery.discoverHosts().listen(
      (host) {
        if (!mounted) return;
        setState(() {
          _hosts.removeWhere((h) => h.ip == host.ip && h.port == host.port);
          _hosts.add(host);
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isSearching = false);
      },
    );
    _hostLeftSub = widget.discovery.hostLeftStream.listen((code) {
      if (!mounted) return;
      setState(() => _hosts.removeWhere((h) => h.roomCode == code));
    });
  }

  Future<void> _stopSearch() async {
    await _hostSub?.cancel();
    _hostSub = null;
    await _hostLeftSub?.cancel();
    _hostLeftSub = null;
    // stop()이 아니라 stopDiscovery()만 — 호스트 모드 진입 직후 standalone sheet의
    // picker가 dispose되며 호스트 광고까지 같이 정지되던 회귀 fix.
    await widget.discovery.stopDiscovery();
    if (mounted) setState(() => _isSearching = false);
  }

  Future<void> _promptCodeAndConnect({
    required String ip,
    required int port,
  }) async {
    // 1) IP에 호스트가 실제로 있는지 사전 확인 (사용자 요청: IP → 호스트 확인 → 코드).
    setState(() {
      _isConnecting = true;
      _lastError = null;
    });
    bool hostAlive;
    try {
      hostAlive = await widget.onPing(ip, port);
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
    if (!hostAlive) {
      if (mounted) setState(() => _lastError = '호스트를 찾을 수 없습니다');
      return;
    }
    // 2) 호스트 확인 OK — 코드 입력 받기
    final code = await _askCode();
    if (code == null || code.isEmpty) return;
    setState(() {
      _isConnecting = true;
      _lastError = null;
    });
    try {
      // 검색이 돌고 있었다면 중단 (방 입장 시 검색 중단 — 사용자 요청).
      await _stopSearch();
      final error = await widget.onConnect(ip, port, code);
      // sheet 닫기를 다음 frame으로 미룸 — 같은 frame에 PlayerScreen setState
      // (mode=speaker)와 Navigator.pop(sheetContext)이 동시 발생 시 'child.owner
      // == owner' BuildOwner mismatch가 났던 사례(사용자 실측) 회피.
      if (error == null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSuccess();
        });
      } else if (error != null && mounted) {
        // inline 표시 — SnackBar는 BottomSheet에 가려서 안 보임(사용자 실측).
        setState(() => _lastError = error);
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  bool _isValidIPv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  Future<String?> _askCode() async {
    // _CodeInputDialog StatefulWidget으로 controller 자체 관리 → dispose 시점
    // _dependents.isEmpty assertion 회피. pop 직전 unfocus로 키보드 layer 정리.
    return showDialog<String>(
      context: context,
      builder: (ctx) => const _CodeInputDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 검색 버튼 토글 + 결과 리스트
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isConnecting ? null : _toggleSearch,
                icon: Icon(
                  _isSearching ? Symbols.stop_rounded : Symbols.search_rounded,
                ),
                label: Text(_isSearching ? '검색 중단' : '호스트 검색'),
              ),
            ),
          ],
        ),
        if (_isSearching || _hosts.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 결과 영역 고정 높이 — 1개 검색되었다고 갑자기 작아지지 않도록.
          // 여러 개 시 ListView 자체 스크롤.
          SizedBox(
            height: 180,
            child: _hosts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        _isSearching ? '주변 방을 찾는 중...' : '방을 찾을 수 없습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _hosts.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final h = _hosts[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Symbols.cast_rounded),
                        title: Text(h.name, maxLines: 1),
                        subtitle: Text(h.ip, maxLines: 1),
                        onTap: _isConnecting
                            ? null
                            : () =>
                                  _promptCodeAndConnect(ip: h.ip, port: h.port),
                      );
                    },
                  ),
          ),
        ],
        const SizedBox(height: 12),
        const Text('또는 IP 직접 입력', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ipController,
                enabled: !_isConnecting,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '192.168.x.x',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isConnecting
                  ? null
                  : () async {
                      final ip = _ipController.text.trim();
                      if (ip.isEmpty) return;
                      // IP 형식 검증 후에만 코드 다이얼로그 띄움 — 잘못된 IP에 코드
                      // 입력하는 번거로움 회피 (사용자 요청).
                      if (!_isValidIPv4(ip)) {
                        setState(() => _lastError = '올바른 IP 주소를 입력하세요');
                        return;
                      }
                      await _promptCodeAndConnect(
                        ip: ip,
                        port: P2PService.defaultPort,
                      );
                    },
              child: const Text('연결'),
            ),
          ],
        ),
        if (_isConnecting) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_lastError != null) ...[
          const SizedBox(height: 8),
          _buildInlineError(context, _lastError!),
        ],
      ],
    );
  }
}

class _CodeInputDialog extends StatefulWidget {
  const _CodeInputDialog();

  @override
  State<_CodeInputDialog> createState() => _CodeInputDialogState();
}

class _CodeInputDialogState extends State<_CodeInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 키보드 unfocus 후 pop — focus layer가 남은 채 dialog가 unmount되면
    // InheritedElement의 _dependents가 비지 않은 상태로 dispose되어 framework
    // assertion 발생 (사용자 실측). 명시적 unfocus로 회피.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('입장 코드'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(hintText: '4자리 숫자', counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
          child: const Text('취소'),
        ),
        TextButton(onPressed: _submit, child: const Text('연결')),
      ],
    );
  }
}
