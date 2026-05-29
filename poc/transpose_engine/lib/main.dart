import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const TransposePocApp());

class TransposePocApp extends StatelessWidget {
  const TransposePocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transpose PoC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _channel = MethodChannel('com.synchorus/transpose');

  bool _playing = false;
  int _cents = 0;
  String _status = 'idle';

  Future<void> _init() async {
    try {
      await _channel.invokeMethod('init');
      setState(() => _status = 'init OK');
    } catch (e) {
      setState(() => _status = 'init error: $e');
    }
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _channel.invokeMethod('stop');
        setState(() {
          _playing = false;
          _status = 'stopped';
        });
      } else {
        final ok = await _channel.invokeMethod<bool>('start') ?? false;
        setState(() {
          _playing = ok;
          _status = ok ? 'playing 1kHz sine' : 'start failed';
        });
      }
    } catch (e) {
      setState(() => _status = 'toggle error: $e');
    }
  }

  Future<void> _onCentsChanged(double v) async {
    final cents = v.round();
    if (cents == _cents) return;
    _cents = cents;
    setState(() {});
    try {
      await _channel.invokeMethod('setCents', cents * 100);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final semitone = _cents;
    final label = semitone == 0
        ? '0'
        : (semitone > 0 ? '+$semitone' : '$semitone');
    return Scaffold(
      appBar: AppBar(title: const Text('§H Transpose PoC')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _init,
              child: const Text('Init'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _toggle,
              child: Text(_playing ? 'Stop' : 'Start 1kHz sine'),
            ),
            const SizedBox(height: 24),
            const Text('TRANSPOSE (semitone)',
                style: TextStyle(fontSize: 12, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Center(
              child: Text(label,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  )),
            ),
            Slider(
              min: -12,
              max: 12,
              divisions: 24,
              value: semitone.toDouble(),
              onChanged: _onCentsChanged,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 16),
            const Text(
              '✅ step 3: Worker thread + lock-free SPSC ring.\n'
              'cents=0 → callback bypass (음질 손실 0).\n'
              'cents≠0 → worker가 4096 batch로 SoundTouch process,\n'
              'callback은 ring에서 pop만 (RT-safe).',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final n = await _channel.invokeMethod<int>('getUnderrunCount') ?? 0;
                setState(() => _status = 'underrun count: $n');
              },
              child: const Text('Check underrun count'),
            ),
          ],
        ),
      ),
    );
  }
}
