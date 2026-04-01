import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/discovery_service.dart';
import '../services/p2p_service.dart';
import 'room_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _codeController = TextEditingController();
  List<DiscoveredHost> _discoveredHosts = [];
  StreamSubscription? _discoverySub;
  bool _isSearching = false;
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    _discoverySub?.cancel();
    super.dispose();
  }

  /// 방 만들기 (호스트)
  Future<void> _createRoom() async {
    final p2p = ref.read(p2pServiceProvider);
    final discovery = ref.read(discoveryServiceProvider);

    int port;
    try {
      port = await p2p.startHost();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버 시작 실패: 포트가 이미 사용 중입니다')),
        );
      }
      return;
    }

    final roomCode = p2p.generateRoomCode();

    await discovery.startBroadcast(
      hostName: 'Host',
      tcpPort: port,
      roomCode: roomCode,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomScreen(roomCode: roomCode, isHost: true),
        ),
      );
    }
  }

  /// 주변 방 검색
  void _startDiscovery() {
    setState(() {
      _isSearching = true;
      _discoveredHosts = [];
    });

    final discovery = ref.read(discoveryServiceProvider);
    _discoverySub = discovery.discoverHosts().listen((host) {
      setState(() {
        // 중복 제거
        _discoveredHosts.removeWhere((h) => h.roomCode == host.roomCode);
        _discoveredHosts.add(host);
      });
    });
  }

  /// 검색 취소
  void _stopDiscovery() {
    _discoverySub?.cancel();
    _discoverySub = null;
    ref.read(discoveryServiceProvider).stop();
    setState(() {
      _isSearching = false;
    });
  }

  /// 방 참가 (코드 입력 or 자동 감지)
  Future<void> _joinRoom(DiscoveredHost host) async {
    if (_isJoining) return;
    setState(() => _isJoining = true);

    final p2p = ref.read(p2pServiceProvider);
    await p2p.disconnect();
    await p2p.connectToHost(host.ip, host.port, 'Guest');

    _discoverySub?.cancel();
    ref.read(discoveryServiceProvider).stop();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomScreen(roomCode: host.roomCode, isHost: false),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchorus'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 방 만들기 버튼
            ElevatedButton.icon(
              onPressed: _createRoom,
              icon: const Icon(Icons.speaker_group),
              label: const Text('방 만들기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 방 참가 버튼
            ElevatedButton.icon(
              onPressed: _isSearching ? _stopDiscovery : _startDiscovery,
              icon: Icon(_isSearching ? Icons.stop : Icons.search),
              label: Text(_isSearching ? '검색 중단' : '주변 방 찾기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 16),

            // 검색 중 표시
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _discoveredHosts.isEmpty
                          ? '주변 방을 검색하고 있습니다...'
                          : '${_discoveredHosts.length}개의 방을 찾았습니다',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

            // 발견된 방 목록
            ..._discoveredHosts.map((host) => Card(
              child: ListTile(
                leading: const Icon(Icons.wifi),
                title: Text('방 코드: ${host.roomCode}'),
                subtitle: Text('${host.name} (${host.ip})'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => _joinRoom(host),
              ),
            )),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // IP 직접 입력으로 참가
            const Text('IP 직접 입력', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: '호스트 IP (예: 192.168.0.10)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _joinByIp(),
                  child: const Text('참가'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinByIp() async {
    final ip = _codeController.text.trim();
    if (ip.isEmpty || _isJoining) return;

    setState(() => _isJoining = true);

    try {
      final p2p = ref.read(p2pServiceProvider);
      await p2p.disconnect();
      await p2p.connectToHost(ip, P2PService.defaultPort, 'Guest');

      // welcome 메시지에서 roomCode 받기
      String roomCode = '----';
      try {
        final welcome = await p2p.onMessage
            .firstWhere((m) => m['type'] == 'welcome')
            .timeout(const Duration(seconds: 5));
        roomCode = welcome['data']?['roomCode'] ?? '----';
      } catch (_) {}

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomScreen(roomCode: roomCode, isHost: false),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('연결 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }
}
