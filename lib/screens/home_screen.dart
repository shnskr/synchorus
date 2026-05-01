import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/app_providers.dart';
import '../services/discovery_service.dart';
import '../services/p2p_service.dart';
import 'native_test_screen.dart';
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
  StreamSubscription? _hostLeftSub;
  bool _isSearching = false;
  bool _isJoining = false;
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _versionLabel = 'v${info.version}');
    }
  }

  /// 게스트 join 시 사용할 디바이스 이름.
  /// Android: model (예 "SM-S908N"), iOS: 사용자 설정명 (예 "홍길동의 iPhone").
  /// 끝에 4자리 hex 접미사를 붙여 같은 모델 2대 이상 충돌까지 방지.
  Future<String> _resolveDeviceName() async {
    String base = 'Guest';
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        base = info.model;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        base = info.name;
      }
    } catch (_) {}
    if (base.isEmpty) base = 'Guest';
    if (base.length > 24) base = base.substring(0, 24);
    final suffix = (DateTime.now().microsecondsSinceEpoch & 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0');
    return '$base#$suffix';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _discoverySub?.cancel();
    _hostLeftSub?.cancel();
    super.dispose();
  }

  /// 방 만들기 (호스트)
  Future<void> _createRoom() async {
    _stopDiscovery();

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
  Future<void> _startDiscovery() async {
    setState(() {
      _isSearching = true;
      _discoveredHosts = [];
    });

    final discovery = ref.read(discoveryServiceProvider);
    _discoverySub = discovery.discoverHosts().listen((host) {
      setState(() {
        _discoveredHosts.removeWhere((h) => h.roomCode == host.roomCode);
        _discoveredHosts.add(host);
      });
    });
    // mDNS lost(호스트 종료/TTL 만료) 신호 → 리스트에서 제거.
    // 없으면 stale 방이 검색에 계속 남음 (#35-2).
    _hostLeftSub = discovery.hostLeftStream.listen((roomCode) {
      setState(() {
        _discoveredHosts.removeWhere((h) => h.roomCode == roomCode);
      });
    });
  }

  /// 검색 취소
  void _stopDiscovery() {
    _discoverySub?.cancel();
    _discoverySub = null;
    _hostLeftSub?.cancel();
    _hostLeftSub = null;
    ref.read(discoveryServiceProvider).stop();
    setState(() {
      _isSearching = false;
    });
  }

  /// 방 참가 (자동 감지)
  Future<void> _joinRoom(DiscoveredHost host) async {
    if (_isJoining) return;
    setState(() => _isJoining = true);

    try {
      final p2p = ref.read(p2pServiceProvider);
      await p2p.disconnect();

      final welcomeFuture = p2p.onMessage
          .firstWhere((m) => m['type'] == 'welcome')
          .timeout(const Duration(seconds: 5));

      // 1:N 멀티 게스트 환경에서 모두 같은 이름으로 join하면 호스트 측 stale
      // peer 정리(p2p_service.dart `_handleNewPeer`)가 다른 디바이스를 stale로
      // 오인해 무한 ping-pong을 일으킨다. 디바이스 모델명 + 4자리 hex 접미사로
      // 같은 모델 충돌까지 방지. (v0.0.54, HISTORY (51))
      final guestName = await _resolveDeviceName();
      await p2p.connectToHost(host.ip, host.port, guestName);

      int peerCount = 1;
      try {
        final welcome = await welcomeFuture;
        peerCount = welcome['data']?['peerCount'] ?? 1;
      } catch (_) {}

      _discoverySub?.cancel();
      _hostLeftSub?.cancel();
      ref.read(discoveryServiceProvider).stop();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomScreen(
              roomCode: host.roomCode,
              isHost: false,
              initialPeerCount: peerCount,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException
            ? '호스트 응답 없음 (시간 초과)'
            : e is SocketException
            ? '호스트에 연결할 수 없습니다'
            : '연결 실패: $e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchorus'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _versionLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // [임시] v3 네이티브 엔진 테스트
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NativeTestScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.science),
                      label: const Text('Native Engine Test'),
                    ),
                    const SizedBox(height: 16),

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
                      onPressed: _isSearching
                          ? _stopDiscovery
                          : _startDiscovery,
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
                              width: 16,
                              height: 16,
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
                    ..._discoveredHosts.map(
                      (host) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.wifi),
                          title: Text('방 코드: ${host.roomCode}'),
                          subtitle: Text('${host.name} (${host.ip})'),
                          trailing: _isJoining
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          onTap: _isJoining ? null : () => _joinRoom(host),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),

                    // IP 직접 입력으로 참가
                    const Text(
                      'IP 직접 입력',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isJoining ? null : () => _joinByIp(),
                          child: _isJoining
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('참가'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
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

      final welcomeFuture = p2p.onMessage
          .firstWhere((m) => m['type'] == 'welcome')
          .timeout(const Duration(seconds: 5));

      await p2p.connectToHost(ip, P2PService.defaultPort, 'Guest');

      String roomCode = '----';
      int peerCount = 1;
      try {
        final welcome = await welcomeFuture;
        roomCode = welcome['data']?['roomCode'] ?? '----';
        peerCount = welcome['data']?['peerCount'] ?? 1;
      } catch (_) {}

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomScreen(
              roomCode: roomCode,
              isHost: false,
              initialPeerCount: peerCount,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException
            ? '호스트 응답 없음 (시간 초과)'
            : e is SocketException
            ? '호스트에 연결할 수 없습니다'
            : '연결 실패: $e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }
}
