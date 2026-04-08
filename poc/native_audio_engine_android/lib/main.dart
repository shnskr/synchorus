// PoC Phase 1: getTimestamp 폴링 + 시계열 확보
//
// 통과 기준 (육안):
//   - framePos / timeNs 단조 증가
//   - 재생 중 ok 유효율 > 95%
//   - 평균 폴링 주기 ≈ 100ms
//   - frames/ms ≈ 44~48 (44.1kHz 또는 48kHz sampleRate)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const PocApp());
}

class PocApp extends StatelessWidget {
  const PocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Audio PoC — Phase 1',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class Sample {
  final int framePos;
  final int timeNs;
  final bool ok;
  final int wallMs; // Flutter 호출 시점의 wall clock

  Sample({
    required this.framePos,
    required this.timeNs,
    required this.ok,
    required this.wallMs,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _channel = MethodChannel('com.synchorus.poc/native_audio');
  static const _pollInterval = Duration(milliseconds: 100);
  static const _maxSamples = 1000; // rolling window

  bool _playing = false;
  String _lastLog = '준비됨';

  final List<Sample> _samples = [];
  Timer? _pollTimer;
  int _totalPolls = 0;

  Future<void> _toggle() async {
    final method = _playing ? 'stop' : 'start';
    try {
      final ok = await _channel.invokeMethod<bool>(method) ?? false;
      if (!mounted) return;
      setState(() {
        if (ok) {
          _playing = !_playing;
          if (_playing) {
            _startPolling();
          } else {
            _stopPolling();
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
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getTimestamp');
      if (!mounted || result == null) return;
      final s = Sample(
        framePos: (result['framePos'] as num).toInt(),
        timeNs: (result['timeNs'] as num).toInt(),
        ok: result['ok'] as bool,
        wallMs: wallMs,
      );
      setState(() {
        _samples.add(s);
        if (_samples.length > _maxSamples) {
          _samples.removeAt(0);
        }
        _totalPolls++;
      });
    } catch (_) {
      // silent — 에러 나도 다음 poll 시도
    }
  }

  // ok=true 샘플만 대상으로 통계
  _Stats _computeStats() {
    final ok = _samples.where((s) => s.ok).toList();
    if (ok.length < 2) {
      return _Stats(okCount: ok.length);
    }

    // wall clock 기반 평균 폴링 주기
    int totalInterval = 0;
    for (int i = 1; i < ok.length; i++) {
      totalInterval += ok[i].wallMs - ok[i - 1].wallMs;
    }
    final avgIntervalMs = totalInterval ~/ (ok.length - 1);

    // framePos / timeNs 기반 frames/ms
    final dFrame = ok.last.framePos - ok.first.framePos;
    final dTimeMs = (ok.last.timeNs - ok.first.timeNs) ~/ 1000000;
    final framesPerMs = dTimeMs > 0 ? dFrame / dTimeMs : null;

    // 단조 증가 검증
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final stats = _computeStats();
    final recent = _samples.reversed.take(5).toList();
    final validRate = _totalPolls > 0
        ? '${(stats.okCount * 100 / _totalPolls).toStringAsFixed(1)}%'
        : '—';

    return Scaffold(
      appBar: AppBar(title: const Text('PoC Phase 1 · getTimestamp')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _playing ? Icons.graphic_eq : Icons.volume_off,
                  size: 48,
                  color: _playing ? t.colorScheme.primary : t.disabledColor,
                ),
                const SizedBox(width: 12),
                Text(
                  _playing ? '재생 중' : '정지',
                  style: t.textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? '정지' : '재생'),
            ),
            const SizedBox(height: 4),
            Text(_lastLog,
                style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            const Divider(height: 24),
            Text('통계', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            _statRow(t, '총 polls', '$_totalPolls'),
            _statRow(t, 'ok 샘플', '${stats.okCount}'),
            _statRow(t, '유효율', validRate),
            _statRow(
              t,
              '평균 폴링 주기',
              stats.avgIntervalMs > 0 ? '${stats.avgIntervalMs} ms' : '—',
            ),
            _statRow(
              t,
              'frames/ms (기대 44~48)',
              stats.framesPerMs != null
                  ? stats.framesPerMs!.toStringAsFixed(2)
                  : '—',
            ),
            _statRow(
              t,
              'framePos 단조',
              stats.okCount >= 2 ? (stats.frameMonotonic ? '✓' : '✗') : '—',
            ),
            _statRow(
              t,
              'timeNs 단조',
              stats.okCount >= 2 ? (stats.timeMonotonic ? '✓' : '✗') : '—',
            ),
            const Divider(height: 24),
            Text('최근 5개 (최신순)', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: recent.length,
                itemBuilder: (_, i) {
                  final s = recent[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${s.ok ? '✓' : '✗'} frame=${s.framePos}  t_ns=${s.timeNs}',
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

  Widget _statRow(ThemeData t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: t.textTheme.bodyMedium),
          Text(
            value,
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
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
