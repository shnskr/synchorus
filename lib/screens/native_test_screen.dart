import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/native_audio_service.dart';

/// v3 네이티브 오디오 엔진 테스트 화면 (임시).
/// 파일 로드 → 재생 → seek → 타임스탬프 확인.
class NativeTestScreen extends StatefulWidget {
  const NativeTestScreen({super.key});

  @override
  State<NativeTestScreen> createState() => _NativeTestScreenState();
}

class _NativeTestScreenState extends State<NativeTestScreen> {
  final _engine = NativeAudioService();
  Timer? _pollTimer;

  String _status = 'idle';
  String? _fileName;
  Map<String, dynamic> _ts = {};
  bool _playing = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _engine.stop();
    super.dispose();
  }

  Future<void> _pickAndLoad() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    _fileName = result.files.single.name;
    setState(() => _status = 'loading...');

    final ok = await _engine.loadFile(path);
    setState(() => _status = ok ? 'loaded' : 'load failed');
  }

  Future<void> _start() async {
    final ok = await _engine.start();
    setState(() {
      _status = ok ? 'playing' : 'start failed';
      _playing = ok;
    });
    if (ok) _startPolling();
  }

  Future<void> _stop() async {
    _pollTimer?.cancel();
    await _engine.stop();
    setState(() {
      _status = 'stopped';
      _playing = false;
    });
  }

  Future<void> _seek(int deltaSec) async {
    if (_ts['sampleRate'] == null) return;
    final sr = (_ts['sampleRate'] as num).toInt();
    final vf = (_ts['virtualFrame'] as num?)?.toInt() ?? 0;
    final target = vf + deltaSec * sr;
    await _engine.seekToFrame(target.clamp(0, _totalFrames));
  }

  int get _totalFrames => (_ts['totalFrames'] as num?)?.toInt() ?? 0;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final ts = await _engine.getTimestamp();
      if (mounted) setState(() => _ts = ts);
    });
  }

  String _framesToTime(int frames, int sr) {
    if (sr <= 0) return '--:--';
    final sec = frames / sr;
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ts['ok'] == true;
    final sr = (_ts['sampleRate'] as num?)?.toInt() ?? 0;
    final vf = (_ts['virtualFrame'] as num?)?.toInt() ?? 0;
    final total = _totalFrames;
    final posStr = _framesToTime(vf, sr);
    final durStr = _framesToTime(total, sr);

    return Scaffold(
      appBar: AppBar(title: const Text('Native Engine Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File info
            Card(
              child: ListTile(
                leading: const Icon(Icons.audio_file),
                title: Text(_fileName ?? '파일 없음'),
                subtitle: Text('status: $_status'),
              ),
            ),
            const SizedBox(height: 12),

            // Load button
            ElevatedButton.icon(
              onPressed: _pickAndLoad,
              icon: const Icon(Icons.folder_open),
              label: const Text('파일 선택 + 로드'),
            ),
            const SizedBox(height: 8),

            // Play / Stop
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_playing ? _start : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('재생'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _playing ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('정지'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Seek
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _playing ? () => _seek(-10) : null,
                  icon: const Icon(Icons.replay_10),
                  iconSize: 36,
                ),
                IconButton(
                  onPressed: _playing ? () => _seek(-3) : null,
                  icon: const Icon(Icons.replay),
                  iconSize: 36,
                ),
                const SizedBox(width: 16),
                Text('$posStr / $durStr',
                    style: const TextStyle(
                        fontSize: 20, fontFamily: 'monospace')),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: _playing ? () => _seek(3) : null,
                  icon: const Icon(Icons.forward),
                  iconSize: 36,
                ),
                IconButton(
                  onPressed: _playing ? () => _seek(10) : null,
                  icon: const Icon(Icons.forward_10),
                  iconSize: 36,
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Timestamp details
            Text('getTimestamp (200ms poll)',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700])),
            const SizedBox(height: 4),
            if (ok) ...[
              _tsRow('virtualFrame', '$vf'),
              _tsRow('sampleRate', '$sr Hz'),
              _tsRow('totalFrames', '$total'),
              _tsRow('framePos', '${_ts['framePos']}'),
              _tsRow('wallAtFramePosNs',
                  '${_ts['wallAtFramePosNs']}'),
              if (_ts['totalLatencyMs'] != null)
                _tsRow('totalLatency',
                    '${(_ts['totalLatencyMs'] as num).toStringAsFixed(1)} ms'),
              if (_ts['outputLatencyMs'] != null)
                _tsRow('outputLatency',
                    '${(_ts['outputLatencyMs'] as num).toStringAsFixed(1)} ms'),
            ] else
              Text('ok: false',
                  style: TextStyle(color: Colors.red[400])),
          ],
        ),
      ),
    );
  }

  Widget _tsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
