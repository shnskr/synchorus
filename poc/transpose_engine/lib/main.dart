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

  String _status = 'idle';

  Future<void> _init() async {
    try {
      await _channel.invokeMethod('init');
      setState(() => _status = 'init OK — check logcat TransposeEngine tag');
    } catch (e) {
      setState(() => _status = 'init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('§H Transpose PoC')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _init,
              child: const Text('1. Init (SoundTouch + Oboe symbol check)'),
            ),
            const SizedBox(height: 24),
            Text(_status, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
