// PoC Phase 0: Oboe 래퍼 + 단순 재생
//
// 통과 기준: 440Hz 톤이 디바이스에서 들림

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
      title: 'Native Audio PoC — Phase 0',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
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
  static const _channel = MethodChannel('com.synchorus.poc/native_audio');

  bool _playing = false;
  String _lastLog = '준비됨';

  Future<void> _toggle() async {
    final method = _playing ? 'stop' : 'start';
    try {
      final ok = await _channel.invokeMethod<bool>(method) ?? false;
      if (!mounted) return;
      setState(() {
        if (ok) _playing = !_playing;
        _lastLog = '$method → $ok';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastLog = '$method 에러: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PoC Phase 0 · Oboe sine')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _playing ? Icons.graphic_eq : Icons.volume_off,
              size: 96,
              color: _playing ? t.colorScheme.primary : t.disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              _playing ? '재생 중 (440 Hz)' : '정지',
              style: t.textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? '정지' : '재생'),
            ),
            const SizedBox(height: 12),
            Text(_lastLog, style: t.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
