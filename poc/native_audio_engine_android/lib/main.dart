// PoC Phase 2~4: audio-obs + clock sync + 게스트 재생 + drift/seek 보정 실험
//
// Phase 3까지: 네트워크 지연 분리 (sync-ping/pong), 게스트 자체 재생,
//   드리프트 시계열 원시 수집.
// Phase 4 (현 단계): 게스트가 호스트 대비 drift를 ms 단위로 계산하고, 20ms 넘으면
//   네이티브 seekToFrame(virtual playhead) 호출로 실시간 보정. 목표는 "seek로
//   실제로 수렴이 일어나는지 + 몇 ms 안에 들어오는지" 측정.
//
// Phase 4 알고리즘:
//   1) 앵커: 첫 (audio-obs 수신 + 게스트 ok 샘플) 시점에 드리프트=0 기준선을
//      설정. ⚠️ 호스트 frame은 obs.framePos 그대로가 아니라, 앵커 순간의 host
//      wall clock(=guestWall+offset)까지 선형 외삽한 값을 저장 (1차 실측에서
//      앵커 시점 obs 나이 때문에 초기 offset 수백 ms가 붙던 버그 수정).
//   2) 매 게스트 poll마다 drift 재계산:
//        host_wall_now = guest_wall_now + filteredOffsetMs  (offset>0: host 앞섬)
//        expected_host_frame_now = latestObs.framePos
//            + (host_wall_now - latestObs.hostTimeMs) * 48.0
//        dH = expected_host_frame_now - anchorHostFrame
//        effective_guest_frame = guest_HAL_framePos + seekCorrectionAccum
//        dG = effective_guest_frame - anchorGuestFrame
//        drift_frame = dG - dH   (양수: 게스트 앞섬)
//        drift_ms = drift_frame / 48.0
//      ⚠️ seekToFrame은 mVirtualFrame만 덮어쓰고 HAL framePos에는 영향 없음.
//      1차 실측에서 seek를 해도 drift가 전혀 줄지 않은 원인 → 과거 seek 보정을
//      seekCorrectionAccum에 누적해서 HAL framePos에 더해 "seek 효과 복원".
//   3) |drift_ms| > 20 && 쿨다운 아닐 때 seek 발동:
//        correction_frames = (-drift_ms * 0.8) * 48   (0.8 = 오버슈팅 방지)
//        new_vf = getVirtualFrame() + correction_frames
//        seekToFrame(new_vf); seekCorrectionAccum += correction_frames
//   4) seek 후 1초 쿨다운 + post-seek 시계열 기록(100/300/500/1000/2000ms 지점의 drift).
//      추적 끝나면 앵커 재설정 (현재 상태를 새 drift=0 기준으로, 동일하게 외삽).
//
// Clock sync 알고리즘 (Phase 3):
//   - 초기 핸드셰이크: 10회 빠른 ping (100ms 간격) → RTT 최소 샘플의
//     raw offset = t2 − (t1+t3)/2 을 초기값으로 확정
//   - 주기 단계: 1s마다 ping, 최근 5개 sliding window, 창 내 RTT 최소 샘플의
//     raw offset을 new로 보고 filtered = old*0.9 + new*0.1 (EMA α=0.1)
//
// CSV 5종 (오프라인 분석용):
//   - audio_obs_*.csv:   호스트 obs 수신 시계열
//   - sync_*.csv:        ping/pong 샘플 (raw + filtered offset)
//   - guest_ts_*.csv:    게스트 Oboe 폴링 시계열
//   - drift_*.csv:       매 poll마다 drift_ms (Phase 4)
//   - seek_events_*.csv: seek 이벤트 + post-seek 수렴 시계열 (Phase 4)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _nativeChannel =
    MethodChannel('com.synchorus.poc/native_audio');
const int _tcpPort = 7777;
const Duration _obsInterval = Duration(milliseconds: 500);
const Duration _pollInterval = Duration(milliseconds: 100);
const int _maxSamples = 1000;

// ── Phase 3: clock sync 파라미터 ─────────────────────────────
// 초기 핸드셰이크: 10번 빠르게 → RTT 최소 샘플의 offset을 초기값으로 채택.
// 주기 단계: 매 1초 1회 ping, 최근 5개 sliding window 유지.
//   최근 5개 중 RTT 최소 샘플의 raw offset을 new로 보고,
//   filteredOffset = old * 0.9 + new * 0.1 (EMA, α=0.1)
const int _syncInitialCount = 10;
const Duration _syncInitialGap = Duration(milliseconds: 100);
const Duration _syncInitialSettleDelay = Duration(milliseconds: 500);
const Duration _syncInterval = Duration(seconds: 1);
const int _syncWindowSize = 5;
const double _syncEmaAlpha = 0.1; // new 비중 (old 0.9 + new 0.1)

// ── Phase 4: drift / seek 파라미터 ───────────────────────────
// |drift| > 20ms 넘으면 seek 발동. 20ms는 v2와 동일 기준.
const double _driftSeekThresholdMs = 20.0;
// 오버슈팅 방지용 proportional gain. 1.0이면 "정확히 보정", 0.8이면
// "벗어난 양의 80%만 당겨옴". 반동 줄이기 위해 1 미만.
const double _seekCorrectionGain = 0.8;
// seek 호출 후 이 시간 동안은 측정만 하고 추가 seek 판단 금지.
// HAL 버퍼가 새 위치 반영할 시간 + post-seek 수렴 관찰 창.
const Duration _seekCooldown = Duration(milliseconds: 1000);
// 48kHz 가정. (실측 drift가 ±수 ppm 수준이라 계산용 상수로 충분)
const double _idealFramesPerMs = 48.0;
// post-seek 시점에 drift를 찍을 오프셋(ms). seek 이후 경과시간이 이 값을
// 넘으면 해당 시점의 drift를 CSV에 한 줄 기록.
const List<int> _postSeekProbeMs = [100, 300, 500, 1000, 2000];

void main() {
  runApp(const PocApp());
}

class PocApp extends StatelessWidget {
  const PocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Audio PoC — Phase 2',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const RoleSelectionPage(),
    );
  }
}

// ======================================================================
// 역할 선택
// ======================================================================

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PoC Phase 2 · 역할 선택')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이 기기의 역할을 선택하세요',
              style: t.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HostPage()),
              ),
              icon: const Icon(Icons.cell_tower),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('호스트 시작', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GuestConnectPage()),
              ),
              icon: const Icon(Icons.headset),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('게스트로 연결', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '호스트는 오디오 재생 + audio-obs 브로드캐스트.\n'
              '게스트는 호스트 IP 입력 후 수신 로그 기록.',
              style: t.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 데이터 모델
// ======================================================================

class Sample {
  final int framePos;
  final int timeNs;
  final bool ok;
  // ⚠️ 이 wallMs는 "framePos가 DAC에 나간 순간의 CLOCK_REALTIME"이어야 함.
  // 네이티브 쪽에서 getTimestamp 직후 clock_gettime 두 개(mono, realtime)를 찍어
  // wallAtFramePosNs = wallNow - (monoNow - timeNs_oboe) 로 계산해 반환한 값을 ms
  // 단위로 저장. Dart에서 DateTime.now()를 쓰면 네이티브 호출 이전/이후 jitter로
  // 샘플마다 편차(최대 수십 ms)가 생겨 drift 계산에 직접 오차로 누적됨.
  final int wallMs;

  Sample({
    required this.framePos,
    required this.timeNs,
    required this.ok,
    required this.wallMs,
  });
}

/// v3 `audio-obs` 페이로드 (PLAN.md §8).
class AudioObs {
  final int seq;
  final int hostTimeMs;
  final int anchorFramePos;
  final int anchorTimeNs;
  final int framePos;
  final int timeNs;
  final bool playing;
  /// 호스트의 virtual playhead (seek 반영). HAL framePos와 달리
  /// seekToFrame 시 즉시 점프하므로, 게스트는 이 값으로 drift를 계산해야
  /// 호스트 seek을 감지할 수 있음.
  final int virtualFrame;

  const AudioObs({
    required this.seq,
    required this.hostTimeMs,
    required this.anchorFramePos,
    required this.anchorTimeNs,
    required this.framePos,
    required this.timeNs,
    required this.playing,
    required this.virtualFrame,
  });

  Map<String, dynamic> toJson() => {
        'type': 'audio-obs',
        'seq': seq,
        'hostTimeMs': hostTimeMs,
        'anchorFramePos': anchorFramePos,
        'anchorTimeNs': anchorTimeNs,
        'framePos': framePos,
        'timeNs': timeNs,
        'playing': playing,
        'virtualFrame': virtualFrame,
      };

  factory AudioObs.fromJson(Map<String, dynamic> m) => AudioObs(
        seq: (m['seq'] as num).toInt(),
        hostTimeMs: (m['hostTimeMs'] as num).toInt(),
        anchorFramePos: (m['anchorFramePos'] as num).toInt(),
        anchorTimeNs: (m['anchorTimeNs'] as num).toInt(),
        framePos: (m['framePos'] as num).toInt(),
        timeNs: (m['timeNs'] as num).toInt(),
        playing: m['playing'] as bool,
        virtualFrame: (m['virtualFrame'] as num).toInt(),
      );

  /// '\n' 붙인 송신용 라인.
  String encodeLine() => '${jsonEncode(toJson())}\n';
}

/// Phase 3: clock sync — 게스트→호스트 ping.
/// `t1`은 게스트가 송신 직전에 찍은 wall clock (millisecondsSinceEpoch).
class SyncPing {
  final int seq;
  final int t1;

  const SyncPing({required this.seq, required this.t1});

  Map<String, dynamic> toJson() => {
        'type': 'sync-ping',
        'seq': seq,
        't1': t1,
      };

  String encodeLine() => '${jsonEncode(toJson())}\n';
}

/// Phase 3: clock sync — 호스트→게스트 pong.
/// `t1`은 ping의 echo, `t2`는 호스트가 수신 직후 찍은 wall clock.
class SyncPong {
  final int seq;
  final int t1;
  final int t2;

  const SyncPong({required this.seq, required this.t1, required this.t2});

  Map<String, dynamic> toJson() => {
        'type': 'sync-pong',
        'seq': seq,
        't1': t1,
        't2': t2,
      };

  factory SyncPong.fromJson(Map<String, dynamic> m) => SyncPong(
        seq: (m['seq'] as num).toInt(),
        t1: (m['t1'] as num).toInt(),
        t2: (m['t2'] as num).toInt(),
      );

  String encodeLine() => '${jsonEncode(toJson())}\n';
}

/// Phase 3: 게스트 쪽 ping/pong 한 쌍.
/// RTT = t3 - t1
/// rawOffsetMs = t2 - (t1 + t3) / 2  (양수면 "호스트 시계가 게스트보다 앞섬")
class _SyncSample {
  final int seq;
  final int t1;
  final int t2;
  final int t3;

  const _SyncSample({
    required this.seq,
    required this.t1,
    required this.t2,
    required this.t3,
  });

  int get rttMs => t3 - t1;

  int get rawOffsetMs => t2 - ((t1 + t3) ~/ 2);
}

/// Phase 4: seek 이벤트 한 건. CSV에는 event row(pre) + 여러 probe row로 저장됨.
class _SeekEvent {
  final int eventId;
  final int tSeekMs; // 게스트 wall clock
  final double preDriftMs; // seek 직전 drift
  final int correctionFrames; // virtual frame delta (부호 포함)
  final int oldVirtualFrame;
  final int newVirtualFrame;

  const _SeekEvent({
    required this.eventId,
    required this.tSeekMs,
    required this.preDriftMs,
    required this.correctionFrames,
    required this.oldVirtualFrame,
    required this.newVirtualFrame,
  });
}

// ======================================================================
// 호스트
// ======================================================================

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  // ── Oboe 재생 / 폴링 (Phase 1 그대로) ─────────────────────
  bool _playing = false;
  String _lastLog = '준비됨';
  final List<Sample> _samples = [];
  Timer? _pollTimer;
  int _totalPolls = 0;

  // ── Phase 2: anchor (재생 시작 후 첫 ok 샘플) ─────────────
  int? _anchorFramePos;
  int? _anchorTimeNs;

  // ── 호스트 virtual frame 캐시 (broadcast용) ──────────────
  int _cachedVirtualFrame = 0;

  // ── Phase 2: TCP 서버 + broadcast ────────────────────────
  ServerSocket? _server;
  final List<Socket> _clients = [];
  // 대표 IP: wlan* 인터페이스 우선. 못 찾으면 첫 non-loopback.
  String _hostIp = '탐색 중...';
  // 모든 non-loopback IPv4 후보 (디버깅용. clat4 등도 포함).
  final List<({String iface, String ip})> _ipCandidates = [];
  String _serverStatus = '시작 중...';
  Timer? _broadcastTimer;
  int _seq = 0;
  int _lastSentSeq = -1;

  // ── Phase 3: sync-pong 송신 통계 ─────────────────────────
  int _pongSentCount = 0;
  int _lastPongSeq = -1;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  // ── 서버 ──────────────────────────────────────────────────

  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort);
      _server!.listen(
        _onClient,
        onError: (Object e) {
          if (mounted) setState(() => _serverStatus = 'listen 에러: $e');
        },
      );
      await _refreshIps();
      if (!mounted) return;
      setState(() => _serverStatus = 'listening on $_tcpPort');
    } catch (e) {
      if (mounted) setState(() => _serverStatus = 'bind 실패: $e');
    }
  }

  void _onClient(Socket client) {
    setState(() => _clients.add(client));
    // Phase 3: 게스트→호스트 sync-ping 수신 처리.
    // Socket을 line stream으로 변환. listen 구독은 서버가 유지만 하면 되고,
    // 취소할 필요는 없음 (client 종료 시 onDone으로 _removeClient 호출).
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) => _handleClientLine(client, line),
      onError: (Object _) => _removeClient(client),
      onDone: () => _removeClient(client),
      cancelOnError: true,
    );
  }

  /// 게스트가 보낸 sync-ping 처리. 다른 타입은 무시.
  ///
  /// 주의: t2는 **수신 직후 즉시** 찍어야 정확. 파싱 후가 아니라
  /// 파싱 직후 바로 찍는 것이 호스트 측 처리 지연을 최소화.
  void _handleClientLine(Socket client, String line) {
    if (line.isEmpty) return;
    try {
      final m = jsonDecode(line);
      if (m is! Map<String, dynamic>) return;
      if (m['type'] != 'sync-ping') return;
      final t2 = DateTime.now().millisecondsSinceEpoch;
      final seq = (m['seq'] as num).toInt();
      final t1 = (m['t1'] as num).toInt();
      final pong = SyncPong(seq: seq, t1: t1, t2: t2);
      try {
        client.write(pong.encodeLine());
      } catch (_) {
        _removeClient(client);
      }
      setState(() {
        _lastPongSeq = seq;
        _pongSentCount++;
      });
    } catch (_) {
      // parse 실패는 조용히 무시 (PoC)
    }
  }

  void _removeClient(Socket client) {
    try {
      client.destroy();
    } catch (_) {}
    if (mounted) {
      setState(() => _clients.remove(client));
    } else {
      _clients.remove(client);
    }
  }

  /// 모든 non-loopback IPv4를 후보로 수집.
  /// 대표 IP는 `wlan*` 인터페이스를 우선, 없으면 첫 후보.
  /// 한국 통신사 환경에서 `clat4` (192.0.0.4) 같은 NAT64 가상 인터페이스가
  /// 먼저 뽑히는 것을 방지.
  Future<void> _refreshIps() async {
    final candidates = <({String iface, String ip})>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          candidates.add((iface: iface.name, ip: addr.address));
        }
      }
    } catch (_) {}
    String best = '—';
    final wifi = candidates.where((c) => c.iface.startsWith('wlan'));
    if (wifi.isNotEmpty) {
      best = wifi.first.ip;
    } else if (candidates.isNotEmpty) {
      best = candidates.first.ip;
    }
    if (!mounted) return;
    setState(() {
      _ipCandidates
        ..clear()
        ..addAll(candidates);
      _hostIp = best;
    });
  }

  // ── 재생 / 폴링 (Phase 1) ──────────────────────────────────

  Future<void> _toggle() async {
    final method = _playing ? 'stop' : 'start';
    try {
      final ok = await _nativeChannel.invokeMethod<bool>(method) ?? false;
      if (!mounted) return;
      setState(() {
        if (ok) {
          _playing = !_playing;
          if (_playing) {
            _anchorFramePos = null;
            _anchorTimeNs = null;
            _startPolling();
            _startBroadcastLoop();
          } else {
            _stopPolling();
            _stopBroadcastLoop();
            // 정지도 한 번 알리기 위해 마지막 샘플 기반 playing=false broadcast.
            _broadcastOnce();
          }
        }
        _lastLog = '$method → $ok';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastLog = '$method 에러: $e');
    }
  }

  /// 호스트 수동 seek: 현재 virtual frame에서 deltaSeconds초만큼 점프.
  /// 게스트가 다음 audio-obs에서 큰 drift를 감지 → seek 보정 작동 확인용.
  Future<void> _seekBy(int deltaSeconds) async {
    if (!_playing) return;
    final frames = deltaSeconds * mSampleRate;
    try {
      final vf = await _nativeChannel.invokeMethod<int>('getVirtualFrame') ?? 0;
      final newVf = vf + frames;
      final ok = await _nativeChannel.invokeMethod<bool>('seekToFrame', newVf) ?? false;
      if (!mounted) return;
      setState(() => _lastLog = 'seek ${deltaSeconds > 0 ? "+" : ""}${deltaSeconds}s → $ok (vf: $vf→$newVf)');
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastLog = 'seek 에러: $e');
    }
  }

  /// PoC에서는 48000 고정이지만, 네이티브 sampleRate와 일치시키는 게 정확.
  /// 간단 PoC라 하드코딩.
  static const int mSampleRate = 48000;

  void _startPolling() {
    _pollTimer?.cancel();
    _samples.clear();
    _totalPolls = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    try {
      final result = await _nativeChannel
          .invokeMethod<Map<dynamic, dynamic>>('getTimestamp');
      if (!mounted || result == null) return;
      // virtual frame도 같이 캐싱 (broadcastOnce에서 사용).
      final vf = await _nativeChannel.invokeMethod<int>('getVirtualFrame') ?? 0;
      _cachedVirtualFrame = vf;
      // Phase 5 fix: wallMs는 네이티브에서 clock_gettime으로 찍은
      // "framePos가 DAC에 나간 순간의 wall clock". Dart DateTime.now()와 달리
      // framePos와 정합되는 값이라 drift 외삽에 안전.
      final wallAtFramePosNs = (result['wallAtFramePosNs'] as num).toInt();
      final s = Sample(
        framePos: (result['framePos'] as num).toInt(),
        timeNs: (result['timeNs'] as num).toInt(),
        ok: result['ok'] as bool,
        wallMs: wallAtFramePosNs ~/ 1000000,
      );
      // 첫 ok 샘플을 anchor로 기록.
      if (s.ok && _anchorFramePos == null) {
        _anchorFramePos = s.framePos;
        _anchorTimeNs = s.timeNs;
      }
      setState(() {
        _samples.add(s);
        if (_samples.length > _maxSamples) {
          _samples.removeAt(0);
        }
        _totalPolls++;
      });
    } catch (_) {
      // 다음 poll에서 재시도
    }
  }

  // ── broadcast (500ms 주기) ─────────────────────────────────

  void _startBroadcastLoop() {
    _broadcastTimer?.cancel();
    _seq = 0;
    _lastSentSeq = -1;
    _broadcastTimer = Timer.periodic(_obsInterval, (_) => _broadcastOnce());
  }

  void _stopBroadcastLoop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  void _broadcastOnce() {
    if (_clients.isEmpty) return;
    if (_samples.isEmpty) return;
    // 가장 최근 ok 샘플 선택.
    Sample? latest;
    for (int i = _samples.length - 1; i >= 0; i--) {
      if (_samples[i].ok) {
        latest = _samples[i];
        break;
      }
    }
    if (latest == null) return;
    if (_anchorFramePos == null || _anchorTimeNs == null) {
      _anchorFramePos = latest.framePos;
      _anchorTimeNs = latest.timeNs;
    }
    final obs = AudioObs(
      seq: _seq++,
      // ⚠️ hostTimeMs는 "framePos가 측정된 시각"이어야 함.
      // 예전엔 DateTime.now() (= 브로드캐스트 순간)을 썼는데, latest는 최대 100ms
      // 전 poll 결과라 framePos와 hostTimeMs가 0~100ms 어긋남. 이 불일치가
      // 게스트 drift 계산에 그대로 수백 frames 오차로 들어가 ±100ms 스파이크를
      // 만들었음 (2차 실측 스파이크 원인). → latest.wallMs로 맞춤.
      hostTimeMs: latest.wallMs,
      anchorFramePos: _anchorFramePos!,
      anchorTimeNs: _anchorTimeNs!,
      framePos: latest.framePos,
      timeNs: latest.timeNs,
      playing: _playing,
      virtualFrame: _cachedVirtualFrame,
    );
    final line = obs.encodeLine();
    // 복사본으로 순회 (removeClient가 목록을 변경할 수 있음).
    for (final c in List<Socket>.from(_clients)) {
      try {
        c.write(line);
      } catch (_) {
        _removeClient(c);
      }
    }
    setState(() => _lastSentSeq = obs.seq);
  }

  // ── 통계 (Phase 1) ─────────────────────────────────────────

  _Stats _computeStats() {
    final ok = _samples.where((s) => s.ok).toList();
    if (ok.length < 2) {
      return _Stats(okCount: ok.length);
    }
    int totalInterval = 0;
    for (int i = 1; i < ok.length; i++) {
      totalInterval += ok[i].wallMs - ok[i - 1].wallMs;
    }
    final avgIntervalMs = totalInterval ~/ (ok.length - 1);
    final dFrame = ok.last.framePos - ok.first.framePos;
    final dTimeMs = (ok.last.timeNs - ok.first.timeNs) ~/ 1000000;
    final framesPerMs = dTimeMs > 0 ? dFrame / dTimeMs : null;
    bool frameMonotonic = true;
    bool timeMonotonic = true;
    for (int i = 1; i < ok.length; i++) {
      if (ok[i].framePos < ok[i - 1].framePos) frameMonotonic = false;
      if (ok[i].timeNs < ok[i - 1].timeNs) timeMonotonic = false;
    }
    return _Stats(
      okCount: ok.length,
      avgIntervalMs: avgIntervalMs,
      framesPerMs: framesPerMs,
      frameMonotonic: frameMonotonic,
      timeMonotonic: timeMonotonic,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _broadcastTimer?.cancel();
    for (final c in _clients) {
      try {
        c.destroy();
      } catch (_) {}
    }
    _clients.clear();
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final stats = _computeStats();
    final validRate = _totalPolls > 0
        ? '${(stats.okCount * 100 / _totalPolls).toStringAsFixed(1)}%'
        : '—';

    return Scaffold(
      appBar: AppBar(title: const Text('Host · Phase 2')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 네트워크 상태
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('네트워크', style: t.textTheme.titleSmall),
                        IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.refresh),
                          tooltip: 'IP 재탐색',
                          onPressed: _refreshIps,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _kvRow(t, '내 IP (wlan 우선)', _hostIp),
                    _kvRow(t, '포트', '$_tcpPort'),
                    _kvRow(t, '서버', _serverStatus),
                    _kvRow(t, '연결된 클라이언트', '${_clients.length}'),
                    _kvRow(
                      t,
                      '마지막 송신 seq',
                      _lastSentSeq >= 0 ? '$_lastSentSeq' : '—',
                    ),
                    _kvRow(
                      t,
                      'sync-pong 응답 수',
                      '$_pongSentCount'
                      '${_lastPongSeq >= 0 ? ' (last=$_lastPongSeq)' : ''}',
                    ),
                    if (_ipCandidates.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('후보 (디버깅)', style: t.textTheme.bodySmall),
                      for (final c in _ipCandidates)
                        Text(
                          '  ${c.iface}: ${c.ip}',
                          style: t.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 재생 컨트롤
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _playing ? Icons.graphic_eq : Icons.volume_off,
                  size: 40,
                  color: _playing ? t.colorScheme.primary : t.disabledColor,
                ),
                const SizedBox(width: 12),
                Text(
                  _playing ? '재생 중' : '정지',
                  style: t.textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? '정지' : '재생'),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _playing ? () => _seekBy(-10) : null,
                  child: const Text('-10s'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _playing ? () => _seekBy(-3) : null,
                  child: const Text('-3s'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _playing ? () => _seekBy(3) : null,
                  child: const Text('+3s'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _playing ? () => _seekBy(10) : null,
                  child: const Text('+10s'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_lastLog,
                style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            const Divider(height: 20),
            // 통계
            Text('Phase 1 통계', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            _kvRow(t, '총 polls', '$_totalPolls'),
            _kvRow(t, 'ok 샘플', '${stats.okCount}'),
            _kvRow(t, '유효율', validRate),
            _kvRow(
              t,
              '평균 폴링 주기',
              stats.avgIntervalMs > 0 ? '${stats.avgIntervalMs} ms' : '—',
            ),
            _kvRow(
              t,
              'frames/ms',
              stats.framesPerMs != null
                  ? stats.framesPerMs!.toStringAsFixed(2)
                  : '—',
            ),
            _kvRow(
              t,
              'framePos 단조',
              stats.okCount >= 2 ? (stats.frameMonotonic ? '✓' : '✗') : '—',
            ),
            _kvRow(
              t,
              'timeNs 단조',
              stats.okCount >= 2 ? (stats.timeMonotonic ? '✓' : '✗') : '—',
            ),
            const Divider(height: 20),
            Text('anchor', style: t.textTheme.titleSmall),
            _kvRow(
              t,
              'anchorFramePos',
              _anchorFramePos?.toString() ?? '—',
            ),
            _kvRow(
              t,
              'anchorTimeNs',
              _anchorTimeNs?.toString() ?? '—',
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 게스트 · IP 입력
// ======================================================================

class GuestConnectPage extends StatefulWidget {
  const GuestConnectPage({super.key});

  @override
  State<GuestConnectPage> createState() => _GuestConnectPageState();
}

class _GuestConnectPageState extends State<GuestConnectPage> {
  final _ipController = TextEditingController(text: '192.168.');

  void _connect() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GuestPage(hostIp: ip)),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest · 호스트 IP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: '호스트 IP',
                hintText: '예: 192.168.0.42',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _connect,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('연결', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 게스트 · 수신 + 로그
// ======================================================================

class GuestPage extends StatefulWidget {
  final String hostIp;

  const GuestPage({super.key, required this.hostIp});

  @override
  State<GuestPage> createState() => _GuestPageState();
}

class _GuestPageState extends State<GuestPage> {
  Socket? _socket;
  StreamSubscription<String>? _lineSub;

  String _status = '연결 중...';
  String _logPath = '—';

  // ── audio-obs 수신 통계 ─────────────────────────────────
  int _receivedCount = 0;
  int? _lastSeq;
  int _seqGaps = 0;
  int _lastRxMs = 0;
  int _lastIntervalMs = 0;
  final List<AudioObs> _recent = [];

  // ── Phase 3: CSV 3종 ─────────────────────────────────────
  File? _obsFile;
  IOSink? _obsSink;
  File? _syncFile;
  IOSink? _syncSink;
  File? _guestFile;
  IOSink? _guestSink;

  // ── Phase 3: clock sync ─────────────────────────────────
  Timer? _syncTimer;
  int _syncSeqNext = 0;
  // 송신 시점의 t1을 seq로 찾을 수 있게 보관 (pong 매칭용).
  final Map<int, int> _pendingPingT1 = {};
  // 초기 10회 수집 버퍼. 10개 모이면 min-RTT로 초기 offset 확정.
  final List<_SyncSample> _initialSamples = [];
  // 주기 단계 sliding window (최근 _syncWindowSize개 유지).
  final List<_SyncSample> _recentSyncWindow = [];
  bool _syncInitialized = false;
  int? _initialOffsetMs; // 초기 확정값 (고정)
  double? _filteredOffsetMs; // 주기 EMA 필터링 값
  int _latestRttMs = 0;
  int _syncPongReceived = 0;

  // ── Phase 3: 게스트 자체 Oboe 재생 ────────────────────────
  bool _guestPlaying = false;
  Timer? _guestPollTimer;
  int _guestPolls = 0;
  int _guestOkCount = 0;
  int? _guestLastFramePos;
  int? _guestLastTimeNs;
  int? _guestLastWallMs;

  // ── Phase 4: drift / seek 보정 ────────────────────────────
  // 가장 최근 audio-obs (drift 계산 시 expected host frame 외삽용)
  AudioObs? _latestObs;
  // 앵커: drift=0 기준선
  int? _anchorHostObsFrame;
  int? _anchorHostObsWallMs;
  int? _anchorGuestFrame;
  int? _anchorGuestWallMs;
  // 최신 drift 값 (UI + 판단용)
  double? _latestDriftMs;
  int _driftSampleCount = 0;
  // 누적 seek 보정: 과거 seek가 mVirtualFrame을 건드린 총량 (frames).
  // HAL framePos는 seek의 영향을 받지 않으므로, drift 계산 시
  //   effectiveGuestFrame = guestFramePos + _seekCorrectionAccum
  // 으로 "seek 영향을 포함한 게스트 sine 위치"를 복원.
  int _seekCorrectionAccum = 0;
  // seek 통계
  int _seekCount = 0;
  int _seekCooldownUntilMs = 0;
  int _seekNextEventId = 0;
  _SeekEvent? _latestSeek;
  // post-seek 추적 중인 이벤트 (하나만 동시 진행)
  int? _trackingEventId;
  int? _trackingStartMs;
  final Set<int> _probedIndexes = {};
  // Phase 4 로그 파일
  File? _driftFile;
  IOSink? _driftSink;
  File? _seekFile;
  IOSink? _seekSink;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _openLogFiles();
    await _connect();
    if (_socket != null) {
      // fire-and-forget: 초기 핸드셰이크 10회 → 끝나면 주기 단계 시작.
      unawaited(_startInitialSync());
    }
  }

  /// Phase 3: CSV 3종을 연다.
  /// - audio_obs_*.csv: 호스트로부터 수신한 audio-obs 시계열
  /// - sync_*.csv:      clock sync (ping/pong) 샘플 시계열
  /// - guest_ts_*.csv:  게스트 자체 Oboe 폴링 시계열
  /// 같은 timestamp 접미사를 써서 오프라인 분석 시 짝짓기 쉬움.
  Future<void> _openLogFiles() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        if (mounted) setState(() => _logPath = '외부 저장소 없음');
        return;
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');

      _obsFile = File('${dir.path}/audio_obs_$stamp.csv');
      _obsSink = _obsFile!.openWrite();
      _obsSink!.writeln(
        'seq,hostTimeMs,rxWallMs,anchorFramePos,anchorTimeNs,'
        'framePos,timeNs,playing',
      );

      _syncFile = File('${dir.path}/sync_$stamp.csv');
      _syncSink = _syncFile!.openWrite();
      _syncSink!.writeln(
        'seq,t1,t2,t3,rttMs,rawOffsetMs,filteredOffsetMs,phase',
      );

      _guestFile = File('${dir.path}/guest_ts_$stamp.csv');
      _guestSink = _guestFile!.openWrite();
      _guestSink!.writeln('wallMs,framePos,timeNs,ok');

      // Phase 4: drift 시계열. 매 게스트 poll마다 한 줄.
      _driftFile = File('${dir.path}/drift_$stamp.csv');
      _driftSink = _driftFile!.openWrite();
      _driftSink!.writeln(
        'wallMs,obsHostFrame,obsHostTimeMs,guestFrame,seekAccum,'
        'filteredOffsetMs,expectedHostFrame,driftMs',
      );

      // Phase 4: seek 이벤트. kind=pre는 seek 직전 한 줄,
      // kind=probe는 seek 이후 경과 시점마다 한 줄.
      _seekFile = File('${dir.path}/seek_events_$stamp.csv');
      _seekSink = _seekFile!.openWrite();
      _seekSink!.writeln(
        'eventId,wallMs,msSinceSeek,driftMs,'
        'correctionFrames,oldVf,newVf,kind',
      );

      if (mounted) setState(() => _logPath = dir.path);
    } catch (e) {
      if (mounted) setState(() => _logPath = '파일 열기 실패: $e');
    }
  }

  Future<void> _connect() async {
    try {
      _socket = await Socket.connect(
        widget.hostIp,
        _tcpPort,
        timeout: const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() => _status = '연결됨 (${widget.hostIp}:$_tcpPort)');
      _lineSub = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _onLine,
        onError: (Object e) {
          if (mounted) setState(() => _status = '수신 에러: $e');
        },
        onDone: () {
          if (mounted) setState(() => _status = '연결 종료됨');
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) setState(() => _status = '연결 실패: $e');
    }
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    // sync-pong의 t3는 수신 직후 즉시 찍는 것이 중요 (파싱 지연 배제).
    final rxWallMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final m = jsonDecode(line);
      if (m is! Map<String, dynamic>) return;
      final type = m['type'];
      if (type == 'audio-obs') {
        _handleAudioObs(AudioObs.fromJson(m), rxWallMs);
      } else if (type == 'sync-pong') {
        _handlePong(SyncPong.fromJson(m), rxWallMs);
      }
    } catch (e) {
      debugPrint('parse error: $e line=$line');
    }
  }

  void _handleAudioObs(AudioObs obs, int rxWallMs) {
    final interval = _lastRxMs > 0 ? rxWallMs - _lastRxMs : 0;
    int newGaps = _seqGaps;
    if (_lastSeq != null && obs.seq > _lastSeq! + 1) {
      newGaps += obs.seq - _lastSeq! - 1;
    }
    setState(() {
      _receivedCount++;
      _lastSeq = obs.seq;
      _seqGaps = newGaps;
      _lastRxMs = rxWallMs;
      _lastIntervalMs = interval;
      _recent.insert(0, obs);
      if (_recent.length > 10) _recent.removeLast();
      // Phase 4: drift 계산에 쓸 최신 obs 저장
      _latestObs = obs;
    });
    _obsSink?.writeln(
      '${obs.seq},${obs.hostTimeMs},$rxWallMs,'
      '${obs.anchorFramePos},${obs.anchorTimeNs},'
      '${obs.framePos},${obs.timeNs},${obs.playing ? 1 : 0}',
    );
    // 게스트 자체 엔진 자동 시작/정지.
    if (obs.playing) {
      unawaited(_ensureGuestStarted());
    } else {
      unawaited(_stopGuest());
    }
  }

  // ── clock sync ────────────────────────────────────────────

  /// 초기 핸드셰이크: 10번 빠르게 ping 보내고, 다 도착할 때까지
  /// 잠깐(_syncInitialSettleDelay) 기다린 뒤 RTT 최소 샘플로 offset 확정.
  /// 이후 주기 단계 시작.
  Future<void> _startInitialSync() async {
    for (int i = 0; i < _syncInitialCount; i++) {
      if (!mounted || _socket == null) return;
      _sendPing();
      await Future.delayed(_syncInitialGap);
    }
    // orphan pong이 일부 남지 않도록 여유 시간.
    await Future.delayed(_syncInitialSettleDelay);
    if (!mounted) return;
    if (_initialSamples.isNotEmpty) {
      // RTT 최소 샘플 채택 (단방향 지연 대칭 가정이 가장 잘 성립).
      final minSample = _initialSamples
          .reduce((a, b) => a.rttMs < b.rttMs ? a : b);
      setState(() {
        _initialOffsetMs = minSample.rawOffsetMs;
        _filteredOffsetMs = minSample.rawOffsetMs.toDouble();
        _syncInitialized = true;
      });
    }
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) => _sendPing());
  }

  void _sendPing() {
    final socket = _socket;
    if (socket == null) return;
    final seq = _syncSeqNext++;
    final t1 = DateTime.now().millisecondsSinceEpoch;
    _pendingPingT1[seq] = t1;
    try {
      socket.write(SyncPing(seq: seq, t1: t1).encodeLine());
    } catch (_) {
      _pendingPingT1.remove(seq);
    }
  }

  void _handlePong(SyncPong pong, int rxWallMs) {
    final t1 = _pendingPingT1.remove(pong.seq);
    if (t1 == null) return; // orphan
    final sample = _SyncSample(
      seq: pong.seq,
      t1: t1,
      t2: pong.t2,
      t3: rxWallMs,
    );
    _syncPongReceived++;
    _latestRttMs = sample.rttMs;

    if (!_syncInitialized) {
      _initialSamples.add(sample);
    } else {
      _recentSyncWindow.add(sample);
      if (_recentSyncWindow.length > _syncWindowSize) {
        _recentSyncWindow.removeAt(0);
      }
      // 최근 창에서 RTT 최소 샘플의 offset을 "이번 측정값"으로 보고
      // EMA로 기존 filtered와 혼합.
      final min = _recentSyncWindow
          .reduce((a, b) => a.rttMs < b.rttMs ? a : b);
      final current = _filteredOffsetMs ?? min.rawOffsetMs.toDouble();
      _filteredOffsetMs =
          current * (1 - _syncEmaAlpha) + min.rawOffsetMs * _syncEmaAlpha;
    }
    _syncSink?.writeln(
      '${sample.seq},${sample.t1},${sample.t2},${sample.t3},'
      '${sample.rttMs},${sample.rawOffsetMs},'
      '${_filteredOffsetMs?.toStringAsFixed(3) ?? ''},'
      '${_syncInitialized ? "steady" : "init"}',
    );
    if (mounted) setState(() {});
  }

  // ── 게스트 자체 재생 ───────────────────────────────────────

  Future<void> _ensureGuestStarted() async {
    if (_guestPlaying) return;
    try {
      final ok = await _nativeChannel.invokeMethod<bool>('start') ?? false;
      if (!ok || !mounted) return;
      // 네이티브 재시작 시 mVirtualFrame은 0으로 리셋됨. Dart 앵커/누적 보정도
      // stale 상태 방지를 위해 초기화 → 다음 poll에서 _tryEstablishAnchor 재실행.
      _anchorHostObsFrame = null;
      _anchorHostObsWallMs = null;
      _anchorGuestFrame = null;
      _anchorGuestWallMs = null;
      _seekCorrectionAccum = 0;
      _seekCooldownUntilMs = 0;
      _trackingEventId = null;
      _trackingStartMs = null;
      _probedIndexes.clear();
      setState(() => _guestPlaying = true);
      _startGuestPolling();
    } catch (e) {
      debugPrint('guest start error: $e');
    }
  }

  Future<void> _stopGuest() async {
    if (!_guestPlaying) return;
    _guestPollTimer?.cancel();
    _guestPollTimer = null;
    try {
      await _nativeChannel.invokeMethod<bool>('stop');
    } catch (_) {}
    if (mounted) setState(() => _guestPlaying = false);
  }

  void _startGuestPolling() {
    _guestPollTimer?.cancel();
    _guestPollTimer = Timer.periodic(_pollInterval, (_) => _guestPollOnce());
  }

  Future<void> _guestPollOnce() async {
    try {
      final result = await _nativeChannel
          .invokeMethod<Map<dynamic, dynamic>>('getTimestamp');
      if (result == null) return;
      final framePos = (result['framePos'] as num).toInt();
      final timeNs = (result['timeNs'] as num).toInt();
      // Phase 5 fix: wallMs는 네이티브에서 framePos와 원자적으로 캡처한 값.
      // DateTime.now()와 달리 timeNs와 정합되어 drift 외삽 정확도 ↑.
      final wallAtFramePosNs = (result['wallAtFramePosNs'] as num).toInt();
      final wallMs = wallAtFramePosNs ~/ 1000000;
      final ok = result['ok'] as bool;
      _guestPolls++;
      if (ok) {
        _guestOkCount++;
        _guestLastFramePos = framePos;
        _guestLastTimeNs = timeNs;
        _guestLastWallMs = wallMs;
        // Phase 4: 앵커 없으면 설정 시도, 있으면 drift 재계산.
        if (_anchorHostObsFrame == null) {
          _tryEstablishAnchor(wallMs, framePos);
        } else {
          _recomputeDrift(wallMs, framePos);
        }
      }
      _guestSink?.writeln('$wallMs,$framePos,$timeNs,${ok ? 1 : 0}');
      if (mounted) setState(() {});
    } catch (_) {
      // 다음 poll 재시도
    }
  }

  // ── Phase 4: drift / seek ─────────────────────────────────

  /// 앵커 설정 조건:
  ///  - 아직 앵커 없음
  ///  - clock sync 초기화 완료 (_syncInitialized && filtered offset 있음)
  ///  - 호스트가 재생 중인 audio-obs 최소 1건 수신
  ///
  /// ⚠️ 앵커 순간의 호스트 frame은 obs.framePos를 **그대로 쓰면 안 됨**.
  /// obs는 호스트가 500ms 주기로 송출하므로 앵커 시점에 최대 500ms 오래된 값임.
  /// 그대로 저장하면 anchorHF는 과거 시점, anchorGF는 현재 시점이 되어 시간축이
  /// 불일치하고, 그만큼 초기 drift에 상수 오프셋이 붙음 (1차 실측 -315ms의 원인).
  /// → 앵커 순간의 host wall clock (= guestWall + offset) 까지 obs를 선형 외삽해서
  ///    "앵커 시점에 호스트가 만들고 있을 frame"을 저장.
  void _tryEstablishAnchor(int wallMs, int framePos) {
    if (!_syncInitialized) return;
    final offset = _filteredOffsetMs;
    if (offset == null) return;
    final obs = _latestObs;
    if (obs == null || !obs.playing) return;
    final anchorHostWall = wallMs + offset;
    final anchorHostFrameExtrapolated = obs.virtualFrame +
        (anchorHostWall - obs.hostTimeMs) * _idealFramesPerMs;
    final anchorHF = anchorHostFrameExtrapolated.round();

    // ⚠️ 2차 실측 후 발견한 버그: 현재 drift 식은 (dG - dH)로 단순 rate drift만
    // 측정함. 즉 "anchorGF와 anchorHF 사이의 초기 오프셋"이 보존됨. 연속 sine일
    // 때는 phase만 어긋나서 귀로 모르지만, 1초 주기 비프로 바꾸면 초기 오프셋
    // (ex: 770ms)이 그대로 들림. 3차 실측에서 드리프트 78% within 20ms인데 귀로는
    // "아예 안 맞음"이었던 원인이 이것.
    //
    // 해결: 앵커 설정 시점에 게스트 mVirtualFrame을 호스트의 frame 좌표계로 즉시
    // 점프. 이후 anchorGF == anchorHF이므로 drift = dG - dH =
    // (effective - expected) + (anchorHF - anchorGF) = effective - expected로
    // 절대 오정렬을 측정하게 됨.
    //
    // 주의: HAL 버퍼에 이미 들어간 샘플(~10-30ms)은 이전 vf로 재생됨 →
    // 속도적 전환. 완전한 정렬은 HAL latency만큼 지연 후.
    final currentEffective = framePos + _seekCorrectionAccum;
    final initialCorrection = anchorHF - currentEffective;
    unawaited(
      _nativeChannel.invokeMethod<bool>('seekToFrame', anchorHF),
    );
    _seekCorrectionAccum += initialCorrection;

    _anchorHostObsFrame = anchorHF;
    _anchorHostObsWallMs = anchorHostWall.round();
    // 초기 정렬 seek 후 anchorGF == anchorHF가 되도록 기록.
    _anchorGuestFrame = framePos + _seekCorrectionAccum;
    _anchorGuestWallMs = wallMs;

    // HAL 버퍼 안정화 + 큰 seek로 인한 측정 노이즈 방지를 위해 초기 쿨다운.
    _seekCooldownUntilMs = wallMs + _seekCooldown.inMilliseconds;
  }

  /// 매 게스트 poll마다 호출. 앵커 이후 drift(ms)를 재계산 + CSV 기록 +
  /// post-seek probe + seek 판단.
  void _recomputeDrift(int guestWallMs, int guestFramePos) {
    final obs = _latestObs;
    final anchorHF = _anchorHostObsFrame;
    final anchorHW = _anchorHostObsWallMs;
    final anchorGF = _anchorGuestFrame;
    final anchorGW = _anchorGuestWallMs;
    final offset = _filteredOffsetMs;
    if (obs == null ||
        anchorHF == null ||
        anchorHW == null ||
        anchorGF == null ||
        anchorGW == null ||
        offset == null) {
      return;
    }
    // "지금 이 게스트 wall 시각"에 해당하는 호스트 wall 시각.
    // offset > 0 = 호스트가 게스트보다 앞섬 → host_wall = guest_wall + offset.
    final hostWallNow = guestWallMs + offset;
    // 가장 최근 obs의 virtualFrame(seek 반영) 기준으로 호스트 프레임을 선형 외삽.
    // HAL framePos는 seek에 무관하게 단조 증가하므로 drift 계산에 쓰면 안 됨.
    final expectedHostFrameNow = obs.virtualFrame +
        (hostWallNow - obs.hostTimeMs) * _idealFramesPerMs;
    final dH = expectedHostFrameNow - anchorHF;
    // ⚠️ seekToFrame은 mVirtualFrame만 건드리고 HAL framePos는 영향 없음.
    // 1차 실측에서 seek를 해도 drift가 전혀 줄지 않은 원인이 이것.
    // → 과거 seek가 mVirtualFrame에 가한 총 correction을 HAL framePos에 더해서
    //    "만약 seek가 없었다면 있어야 할 frame 위치"를 복원한 뒤 비교.
    final effectiveGuestFrame = guestFramePos + _seekCorrectionAccum;
    final dG = (effectiveGuestFrame - anchorGF).toDouble();
    final driftFrame = dG - dH; // 양수: 게스트 앞섬
    final driftMs = driftFrame / _idealFramesPerMs;

    _latestDriftMs = driftMs;
    _driftSampleCount++;
    _driftSink?.writeln(
      '$guestWallMs,${obs.framePos},${obs.hostTimeMs},'
      '$guestFramePos,$_seekCorrectionAccum,'
      '${offset.toStringAsFixed(3)},'
      '${expectedHostFrameNow.toStringAsFixed(1)},'
      '${driftMs.toStringAsFixed(3)}',
    );

    // 진행 중인 seek 이벤트가 있으면 post-seek probe 기록.
    _maybeProbePostSeek(guestWallMs, driftMs, guestFramePos);

    // seek 판단 (쿨다운 중이면 알아서 skip).
    _maybeTriggerSeek(guestWallMs, driftMs, guestFramePos);
  }

  /// 200ms 이상 drift는 호스트 seek이나 재생 재시작으로 판단 → 앵커 재설정.
  /// 점진적 gain=0.8 보정으로는 타겟이 움직이는 상황에서 수렴 불가.
  static const double _reAnchorThresholdMs = 200.0;

  void _maybeTriggerSeek(int wallMs, double driftMs, int guestFramePos) {
    if (driftMs.abs() >= _reAnchorThresholdMs) {
      // 큰 drift (호스트 seek 등) → 쿨다운 무시, 즉시 앵커 리셋.
      // _latestObs는 유지 — 감지 시점의 obs가 이미 호스트 seek 후 값이므로
      // 다음 poll에서 바로 _tryEstablishAnchor가 이 obs로 재정렬 가능.
      _anchorHostObsFrame = null;
      _anchorHostObsWallMs = null;
      _anchorGuestFrame = null;
      _anchorGuestWallMs = null;
      _seekCooldownUntilMs = 0;
      return;
    }
    if (wallMs < _seekCooldownUntilMs) return;
    if (driftMs.abs() < _driftSeekThresholdMs) return;
    unawaited(_performSeek(wallMs, driftMs));
  }

  Future<void> _performSeek(int wallMs, double driftMs) async {
    int currentVf;
    try {
      final res = await _nativeChannel.invokeMethod<dynamic>('getVirtualFrame');
      if (res is num) {
        currentVf = res.toInt();
      } else {
        return;
      }
    } catch (_) {
      return;
    }
    // drift > 0 (게스트 앞섬) → 뒤로 이동 (프레임 감소) 필요 → correction < 0
    // drift < 0 (게스트 뒤처짐) → 앞으로 이동 (프레임 증가) 필요 → correction > 0
    final correctionFrames =
        (-driftMs * _seekCorrectionGain * _idealFramesPerMs).round();
    final newVf = currentVf + correctionFrames;
    try {
      final ok = await _nativeChannel
          .invokeMethod<bool>('seekToFrame', newVf) ?? false;
      if (!ok) return;
    } catch (_) {
      return;
    }

    _seekCount++;
    _seekCooldownUntilMs = wallMs + _seekCooldown.inMilliseconds;
    // 다음 drift 계산부터 이 보정을 반영.
    _seekCorrectionAccum += correctionFrames;
    final eventId = _seekNextEventId++;
    _trackingEventId = eventId;
    _trackingStartMs = wallMs;
    _probedIndexes.clear();

    _latestSeek = _SeekEvent(
      eventId: eventId,
      tSeekMs: wallMs,
      preDriftMs: driftMs,
      correctionFrames: correctionFrames,
      oldVirtualFrame: currentVf,
      newVirtualFrame: newVf,
    );

    _seekSink?.writeln(
      '$eventId,$wallMs,0,${driftMs.toStringAsFixed(3)},'
      '$correctionFrames,$currentVf,$newVf,pre',
    );

    if (mounted) setState(() {});
  }

  /// seek 이후 _postSeekProbeMs에 정의된 시점들마다 drift를 seek_events CSV에 찍음.
  /// ⚠️ 3차 실측 후 변경: 앵커 재설정 제거. 초기 정렬 fix 이후, 앵커는
  /// "effective == expected"를 의미하므로 drift는 절대 오정렬. gain=0.8이면
  /// 매 seek 후 20% 잔차가 남는데, 재설정하면 잔차가 "새 기준선"으로 흡수되어
  /// 오디오가 여전히 어긋나 있는데도 drift=0으로 보임. 재설정 없이 잔차는 다음
  /// poll에서 다시 측정되어 다음 seek가 추가 보정.
  void _maybeProbePostSeek(int wallMs, double driftMs, int guestFramePos) {
    final eventId = _trackingEventId;
    final startMs = _trackingStartMs;
    if (eventId == null || startMs == null) return;
    final elapsed = wallMs - startMs;
    for (int idx = 0; idx < _postSeekProbeMs.length; idx++) {
      if (_probedIndexes.contains(idx)) continue;
      if (elapsed >= _postSeekProbeMs[idx]) {
        _seekSink?.writeln(
          '$eventId,$wallMs,$elapsed,${driftMs.toStringAsFixed(3)},'
          ',,,probe',
        );
        _probedIndexes.add(idx);
      }
    }
    if (_probedIndexes.length >= _postSeekProbeMs.length) {
      _trackingEventId = null;
      _trackingStartMs = null;
      _probedIndexes.clear();
    }
  }

  @override
  void dispose() {
    _lineSub?.cancel();
    _syncTimer?.cancel();
    _guestPollTimer?.cancel();
    // 게스트 엔진이 돌고 있다면 정지 신호만 던짐 (비동기 응답 안 기다림).
    if (_guestPlaying) {
      _nativeChannel.invokeMethod('stop').ignore();
    }
    try {
      _socket?.destroy();
    } catch (_) {}
    // IOSink는 close()가 pending write를 flush함.
    _obsSink?.close();
    _syncSink?.close();
    _guestSink?.close();
    _driftSink?.close();
    _seekSink?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Guest · Phase 2')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('연결', style: t.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    _kvRow(t, '호스트', widget.hostIp),
                    _kvRow(t, '상태', _status),
                    _kvRow(
                      t,
                      '로그 파일',
                      _logPath,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('수신 통계', style: t.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    _kvRow(t, '수신 count', '$_receivedCount'),
                    _kvRow(
                      t,
                      '마지막 seq',
                      _lastSeq?.toString() ?? '—',
                    ),
                    _kvRow(
                      t,
                      'seq gap 누적',
                      '$_seqGaps ${_seqGaps == 0 ? '✓' : '✗'}',
                    ),
                    _kvRow(
                      t,
                      '마지막 수신 간격',
                      _lastIntervalMs > 0 ? '$_lastIntervalMs ms' : '—',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Phase 3: clock sync 상태
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('clock sync', style: t.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    _kvRow(
                      t,
                      '단계',
                      _syncInitialized
                          ? 'steady (주기)'
                          : 'init (${_initialSamples.length}/$_syncInitialCount)',
                    ),
                    _kvRow(t, 'pong 수신', '$_syncPongReceived'),
                    _kvRow(
                      t,
                      '최근 RTT',
                      _latestRttMs > 0 ? '$_latestRttMs ms' : '—',
                    ),
                    _kvRow(
                      t,
                      '초기 offset',
                      _initialOffsetMs != null
                          ? '${_initialOffsetMs!} ms'
                          : '—',
                    ),
                    _kvRow(
                      t,
                      'filtered offset',
                      _filteredOffsetMs != null
                          ? '${_filteredOffsetMs!.toStringAsFixed(1)} ms'
                          : '—',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Phase 3: 게스트 자체 재생 상태
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('게스트 재생', style: t.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    _kvRow(t, '재생 상태', _guestPlaying ? '재생 중 ✓' : '정지'),
                    _kvRow(t, '폴링', '$_guestPolls'),
                    _kvRow(
                      t,
                      'ok',
                      '$_guestOkCount'
                      '${_guestPolls > 0 ? ' (${(_guestOkCount * 100 / _guestPolls).toStringAsFixed(0)}%)' : ''}',
                    ),
                    _kvRow(
                      t,
                      'last framePos',
                      _guestLastFramePos?.toString() ?? '—',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Phase 4: drift / seek 상태
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('drift / seek (Phase 4)',
                        style: t.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    _kvRow(
                      t,
                      '앵커 설정',
                      _anchorHostObsFrame != null ? '✓' : '대기 중',
                    ),
                    _kvRow(
                      t,
                      '현재 drift',
                      _latestDriftMs != null
                          ? '${_latestDriftMs!.toStringAsFixed(2)} ms'
                              '${_latestDriftMs! > 0 ? ' (게스트 앞섬)' : ' (게스트 뒤처짐)'}'
                          : '—',
                    ),
                    _kvRow(t, 'drift 샘플', '$_driftSampleCount'),
                    _kvRow(t, 'seek 횟수', '$_seekCount'),
                    if (_latestSeek != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '마지막 seek: '
                        'id=${_latestSeek!.eventId} '
                        'pre=${_latestSeek!.preDriftMs.toStringAsFixed(1)}ms '
                        'Δ=${_latestSeek!.correctionFrames} frames',
                        style: t.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    _kvRow(
                      t,
                      '쿨다운',
                      _seekCooldownUntilMs >
                              DateTime.now().millisecondsSinceEpoch
                          ? '진행 중'
                          : '—',
                    ),
                    _kvRow(
                      t,
                      'post-seek probe',
                      _trackingEventId != null
                          ? '${_probedIndexes.length}/${_postSeekProbeMs.length}'
                          : '—',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('최근 수신 (최신순)', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            // SingleChildScrollView 안이라 Expanded 못 씀 → 고정 높이.
            for (final o in _recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'seq=${o.seq}  host=${o.hostTimeMs}  '
                  'frame=${o.framePos}  play=${o.playing ? 1 : 0}',
                  style: t.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 공용
// ======================================================================

Widget _kvRow(ThemeData t, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: t.textTheme.bodyMedium),
        Flexible(
          child: Text(
            value,
            style:
                t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class _Stats {
  final int okCount;
  final int avgIntervalMs;
  final double? framesPerMs;
  final bool frameMonotonic;
  final bool timeMonotonic;

  _Stats({
    required this.okCount,
    this.avgIntervalMs = 0,
    this.framesPerMs,
    this.frameMonotonic = true,
    this.timeMonotonic = true,
  });
}
