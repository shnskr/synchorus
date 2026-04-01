import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/discovery_service.dart';
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

  /// 방 참가 (코드 입력 or 자동 감지)
  Future<void> _joinRoom(DiscoveredHost host) async {
    final p2p = ref.read(p2pServiceProvider);
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
              onPressed: _isSearching ? null : _startDiscovery,
              icon: const Icon(Icons.search),
              label: Text(_isSearching ? '검색 중...' : '주변 방 찾기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 16),

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
          ],
        ),
      ),
    );
  }
}
