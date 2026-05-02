// 자동 측정 모드 — `--dart-define=AUTO_MEASURE_MODE=host|guest` 빌드 시에만 실행.
// 출시 빌드는 entry에서 미참조라 무관.
//
// HOST: 방 자동 생성 → 게스트 1명 입장 대기 (60s timeout) → assets mp3 자동 로드 →
//   5s 안정 대기 → syncPlay → durationSec 후 syncPause → 앱 종료
// GUEST: discovery → 첫 발견 방 자동 입장 → 호스트 재생 따라가기 → durationSec+30s 후 종료

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/app_providers.dart';
import '../services/discovery_service.dart';

class AutoMeasureScreen extends ConsumerStatefulWidget {
  final String mode; // 'host' or 'guest'
  final int durationSec;

  const AutoMeasureScreen({
    super.key,
    required this.mode,
    required this.durationSec,
  });

  @override
  ConsumerState<AutoMeasureScreen> createState() => _AutoMeasureScreenState();
}

class _AutoMeasureScreenState extends ConsumerState<AutoMeasureScreen> {
  String _status = '초기화 중...';
  String? _error;
  StreamSubscription? _discoverySub;
  Timer? _stopTimer;
  Timer? _exitTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.mode == 'host') {
        _runHost();
      } else if (widget.mode == 'guest') {
        _runGuest();
      } else {
        _setError('unknown mode: ${widget.mode}');
      }
    });
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _stopTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s);
    debugPrint('[AUTO_MEASURE] $s');
  }

  void _setError(String e) {
    if (!mounted) return;
    setState(() => _error = e);
    debugPrint('[AUTO_MEASURE] ERROR: $e');
    _scheduleExit(seconds: 5);
  }

  void _scheduleExit({int seconds = 3}) {
    _exitTimer?.cancel();
    _exitTimer = Timer(Duration(seconds: seconds), () {
      SystemNavigator.pop();
    });
  }

  // ═══════════════════════════════════════════════════════════
  // HOST mode
  // ═══════════════════════════════════════════════════════════

  Future<void> _runHost() async {
    try {
      final p2p = ref.read(p2pServiceProvider);
      final discovery = ref.read(discoveryServiceProvider);
      final sync = ref.read(syncServiceProvider);
      final audio = ref.read(nativeAudioSyncServiceProvider);
      final handler = ref.read(audioHandlerProvider);

      _setStatus('호스트 시작 중...');
      final port = await p2p.startHost();
      final roomCode = p2p.generateRoomCode();
      await discovery.startBroadcast(
        hostName: 'AutoMeasureHost',
        tcpPort: port,
        roomCode: roomCode,
      );

      handler.attachSyncService(audio, isHost: true);
      sync.startHostHandler();
      audio.startListening(isHost: true);

      _setStatus('방 생성 완료 ($roomCode). 게스트 대기 중 (60s timeout)...');

      final peerJoined = p2p.onPeerJoin.first.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('게스트 입장 timeout'),
      );
      final peer = await peerJoined;
      _setStatus('게스트 입장: ${peer.name}. 파일 로드 중...');

      // assets mp3 → temp 파일 복사 (NativeAudioService.loadFile은 path 필요)
      final tempPath = await _copyAssetToTemp();
      await audio.loadFile(File(tempPath));
      _setStatus('파일 로드 완료. 5초 안정 대기...');
      await Future.delayed(const Duration(seconds: 5));

      _setStatus('재생 시작. ${widget.durationSec}초 측정 중...');
      _started = true;
      audio.syncPlay();

      _stopTimer = Timer(Duration(seconds: widget.durationSec), () async {
        _setStatus('측정 종료. 정지 중...');
        try {
          audio.syncPause();
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
        _setStatus('완료. 5초 후 앱 종료');
        _scheduleExit(seconds: 5);
      });
    } catch (e, st) {
      debugPrint('[AUTO_MEASURE] host error: $e\n$st');
      _setError('host: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // GUEST mode
  // ═══════════════════════════════════════════════════════════

  Future<void> _runGuest() async {
    try {
      final p2p = ref.read(p2pServiceProvider);
      final discovery = ref.read(discoveryServiceProvider);
      final audio = ref.read(nativeAudioSyncServiceProvider);
      final handler = ref.read(audioHandlerProvider);

      _setStatus('방 검색 중 (60s timeout)...');

      final completer = Completer<DiscoveredHost>();
      _discoverySub = discovery.discoverHosts().listen((host) {
        if (!completer.isCompleted) {
          completer.complete(host);
        }
      });

      final host = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('방 발견 timeout'),
      );
      _discoverySub?.cancel();
      _discoverySub = null;
      await discovery.stop();

      _setStatus('방 발견: ${host.roomCode} (${host.ip}:${host.port}). 입장 중...');

      final guestName =
          'AutoMeasureGuest#${DateTime.now().microsecondsSinceEpoch & 0xFFFF}';
      final welcomeFuture = p2p.onMessage
          .firstWhere((m) => m['type'] == 'welcome')
          .timeout(const Duration(seconds: 10));
      await p2p.connectToHost(host.ip, host.port, guestName);
      try {
        await welcomeFuture;
      } catch (_) {}

      handler.attachSyncService(audio, isHost: false);
      audio.startListening(isHost: false);

      _setStatus('입장 완료. 호스트 재생 따라가기 (${widget.durationSec + 30}s)...');
      _started = true;

      // 호스트보다 30초 더 기다려 종료 시점 여유. 호스트가 syncPause 보내면
      // 자동 정지하지만 측정 종료 후 호스트 종료 race 방지용.
      _stopTimer = Timer(Duration(seconds: widget.durationSec + 30), () {
        _setStatus('측정 시간 종료. 5초 후 앱 종료');
        _scheduleExit(seconds: 5);
      });
    } catch (e, st) {
      debugPrint('[AUTO_MEASURE] guest error: $e\n$st');
      _setError('guest: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // helpers
  // ═══════════════════════════════════════════════════════════

  Future<String> _copyAssetToTemp() async {
    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/measure_audio.mp3';
    final outFile = File(outPath);
    if (!await outFile.exists()) {
      final bytes = await rootBundle.load('assets/measure_audio.mp3');
      await outFile.writeAsBytes(bytes.buffer.asUint8List());
    }
    return outPath;
  }

  // ═══════════════════════════════════════════════════════════
  // UI (minimal — adb logcat이 메인 채널)
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'AUTO_MEASURE: ${widget.mode}',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            if (_started) ...[
              const SizedBox(height: 16),
              Text(
                'duration: ${widget.durationSec}s',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
