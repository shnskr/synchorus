import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _nativeChannel =
    MethodChannel('com.synchorus.poc/native_audio');
const Duration _pollInterval = Duration(milliseconds: 100);
const int _maxSamples = 1000;

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'iOS Audio Engine PoC',
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: const PocPage(),
      );
}

// ---------- Data ----------

class _Sample {
  final int framePos;
  final int timeNs;
  final int wallAtFramePosNs;
  final int virtualFrame;
  final int wallMs; // DateTime.now().millisecondsSinceEpoch at capture
  _Sample({
    required this.framePos,
    required this.timeNs,
    required this.wallAtFramePosNs,
    required this.virtualFrame,
    required this.wallMs,
  });
}

// ---------- Page ----------

class PocPage extends StatefulWidget {
  const PocPage({super.key});
  @override
  State<PocPage> createState() => _PocPageState();
}

class _PocPageState extends State<PocPage> {
  bool _playing = false;
  Timer? _pollTimer;
  final List<_Sample> _samples = [];
  int _totalPolls = 0;
  int _okCount = 0;
  String _error = '';

  // ---- lifecycle ----

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ---- actions ----

  Future<void> _toggle() async {
    if (_playing) {
      _pollTimer?.cancel();
      _pollTimer = null;
      final ok = await _nativeChannel.invokeMethod<bool>('stop') ?? false;
      setState(() => _playing = !ok);
    } else {
      _samples.clear();
      _totalPolls = 0;
      _okCount = 0;
      _error = '';
      final ok = await _nativeChannel.invokeMethod<bool>('start') ?? false;
      if (ok) {
        _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
      } else {
        _error = 'start() returned false';
      }
      setState(() => _playing = ok);
    }
  }

  Future<void> _pollOnce() async {
    _totalPolls++;
    try {
      final result = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getTimestamp',
      );
      if (result == null) return;

      final ok = result['ok'] as bool? ?? false;
      if (!ok) return;

      _okCount++;
      _samples.add(_Sample(
        framePos: (result['framePos'] as num).toInt(),
        timeNs: (result['timeNs'] as num).toInt(),
        wallAtFramePosNs: (result['wallAtFramePosNs'] as num).toInt(),
        virtualFrame: (result['virtualFrame'] as num).toInt(),
        wallMs: DateTime.now().millisecondsSinceEpoch,
      ));
      if (_samples.length > _maxSamples) _samples.removeAt(0);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('pollOnce error: $e');
    }
  }

  // ---- stats ----

  String _computeStats() {
    if (_samples.length < 2) {
      return _samples.isEmpty
          ? 'Waiting for samples...'
          : '1 sample collected';
    }

    final buf = StringBuffer();
    final okPct = (_okCount * 100 / _totalPolls).toStringAsFixed(1);
    buf.writeln('Polls: $_totalPolls  OK: $_okCount ($okPct%)');

    // avg polling interval
    double sumInterval = 0;
    for (int i = 1; i < _samples.length; i++) {
      sumInterval += _samples[i].wallMs - _samples[i - 1].wallMs;
    }
    final avgInterval = sumInterval / (_samples.length - 1);
    buf.writeln('Avg poll interval: ${avgInterval.toStringAsFixed(1)} ms');

    // frames/ms (전체 구간)
    final first = _samples.first;
    final last = _samples.last;
    final dFrames = last.framePos - first.framePos;
    final dTimeMs = (last.timeNs - first.timeNs) / 1e6;
    if (dTimeMs > 0) {
      final framesPerMs = dFrames / dTimeMs;
      buf.writeln(
          'frames/ms: ${framesPerMs.toStringAsFixed(4)}  (expect 48.0)');
    }

    // monotonicity
    bool monoFP = true, monoTN = true;
    for (int i = 1; i < _samples.length; i++) {
      if (_samples[i].framePos <= _samples[i - 1].framePos) monoFP = false;
      if (_samples[i].timeNs <= _samples[i - 1].timeNs) monoTN = false;
    }
    buf.writeln('Monotonic framePos: ${monoFP ? "✓" : "✗"}  '
        'timeNs: ${monoTN ? "✓" : "✗"}');

    // latest sample
    buf.writeln('');
    buf.writeln('--- Latest ---');
    buf.writeln('framePos:     ${last.framePos}');
    buf.writeln('timeNs:       ${last.timeNs}');
    buf.writeln('wallAtFPNs:   ${last.wallAtFramePosNs}');
    buf.writeln('virtualFrame: ${last.virtualFrame}');
    buf.writeln('wallMs:       ${last.wallMs}');

    return buf.toString();
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('iOS Audio PoC — Phase 0+1')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // play/stop
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _toggle,
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow,
                        size: 32),
                    label: Text(_playing ? 'Stop' : 'Play',
                        style: const TextStyle(fontSize: 20)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _playing ? '♪ Playing (scale beeps C4→C5)' : 'Stopped',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error,
                      style: const TextStyle(color: Colors.red, fontSize: 14)),
                ],

                const SizedBox(height: 16),
                const Divider(),

                // timestamp stats
                Text('Timestamp Statistics (100ms poll)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _computeStats(),
                      style:
                          const TextStyle(fontFamily: 'Courier', fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
