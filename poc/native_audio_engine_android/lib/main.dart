// PoC Phase 2: audio-obs P2P 송수신 (호스트 → 게스트, TCP)
//
// Phase 2 통과 기준 (게스트 로그):
//   - seq 연속성 (gap = 0)
//   - 수신 간격 ≈ 500ms
//   - hostTimeMs 단조 증가
//
// 설계 (PLAN.md §6, §8):
//   - PoC 격리 원칙: 디스커버리/join/welcome 없음. IP 수동 입력, TCP 다이렉트.
//   - 메시지 1개: audio-obs (호스트 → 게스트, '\n' 구분 JSON line)
//   - anchor = 재생 시작 이후 첫 ok 샘플의 (framePos, timeNs)
//     (Phase 3 drift 계산의 기준점. 재생 중 재앵커 없음.)

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

  const AudioObs({
    required this.seq,
    required this.hostTimeMs,
    required this.anchorFramePos,
    required this.anchorTimeNs,
    required this.framePos,
    required this.timeNs,
    required this.playing,
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
      };

  factory AudioObs.fromJson(Map<String, dynamic> m) => AudioObs(
        seq: (m['seq'] as num).toInt(),
        hostTimeMs: (m['hostTimeMs'] as num).toInt(),
        anchorFramePos: (m['anchorFramePos'] as num).toInt(),
        anchorTimeNs: (m['anchorTimeNs'] as num).toInt(),
        framePos: (m['framePos'] as num).toInt(),
        timeNs: (m['timeNs'] as num).toInt(),
        playing: m['playing'] as bool,
      );

  /// '\n' 붙인 송신용 라인.
  String encodeLine() => '${jsonEncode(toJson())}\n';
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
    // 클라이언트가 끊기면 목록에서 제거.
    client.listen(
      (_) {}, // 게스트→호스트 메시지는 Phase 2에서 없음
      onError: (Object _) => _removeClient(client),
      onDone: () => _removeClient(client),
      cancelOnError: true,
    );
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
    final wallMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final result = await _nativeChannel
          .invokeMethod<Map<dynamic, dynamic>>('getTimestamp');
      if (!mounted || result == null) return;
      final s = Sample(
        framePos: (result['framePos'] as num).toInt(),
        timeNs: (result['timeNs'] as num).toInt(),
        ok: result['ok'] as bool,
        wallMs: wallMs,
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
      hostTimeMs: DateTime.now().millisecondsSinceEpoch,
      anchorFramePos: _anchorFramePos!,
      anchorTimeNs: _anchorTimeNs!,
      framePos: latest.framePos,
      timeNs: latest.timeNs,
      playing: _playing,
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
  int _receivedCount = 0;
  int? _lastSeq;
  int _seqGaps = 0;
  int _lastRxMs = 0;
  int _lastIntervalMs = 0;
  final List<AudioObs> _recent = [];

  File? _logFile;
  IOSink? _logSink;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _openLogFile();
    await _connect();
  }

  Future<void> _openLogFile() async {
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
      _logFile = File('${dir.path}/audio_obs_$stamp.csv');
      _logSink = _logFile!.openWrite();
      _logSink!.writeln(
        'seq,hostTimeMs,rxWallMs,anchorFramePos,anchorTimeNs,'
        'framePos,timeNs,playing',
      );
      if (mounted) setState(() => _logPath = _logFile!.path);
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
    try {
      final m = jsonDecode(line);
      if (m is! Map<String, dynamic>) return;
      if (m['type'] != 'audio-obs') return;
      final obs = AudioObs.fromJson(m);
      final now = DateTime.now().millisecondsSinceEpoch;
      final interval = _lastRxMs > 0 ? now - _lastRxMs : 0;
      // seq gap 검출.
      int newGaps = _seqGaps;
      if (_lastSeq != null && obs.seq > _lastSeq! + 1) {
        newGaps += obs.seq - _lastSeq! - 1;
      }
      setState(() {
        _receivedCount++;
        _lastSeq = obs.seq;
        _seqGaps = newGaps;
        _lastRxMs = now;
        _lastIntervalMs = interval;
        _recent.insert(0, obs);
        if (_recent.length > 10) _recent.removeLast();
      });
      _logSink?.writeln(
        '${obs.seq},${obs.hostTimeMs},$now,'
        '${obs.anchorFramePos},${obs.anchorTimeNs},'
        '${obs.framePos},${obs.timeNs},${obs.playing ? 1 : 0}',
      );
    } catch (e) {
      debugPrint('parse error: $e line=$line');
    }
  }

  @override
  void dispose() {
    _lineSub?.cancel();
    try {
      _socket?.destroy();
    } catch (_) {}
    // IOSink는 close()가 pending write를 flush함.
    _logSink?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Guest · Phase 2')),
      body: Padding(
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
            Text('최근 수신 (최신순)', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: _recent.length,
                itemBuilder: (_, i) {
                  final o = _recent[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'seq=${o.seq}  host=${o.hostTimeMs}  '
                      'frame=${o.framePos}  play=${o.playing ? 1 : 0}',
                      style: t.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  );
                },
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
