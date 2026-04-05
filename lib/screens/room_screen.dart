import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../providers/app_providers.dart';
import 'player_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomCode;
  final bool isHost;
  final int initialPeerCount;

  const RoomScreen({
    super.key,
    required this.roomCode,
    required this.isHost,
    this.initialPeerCount = 0,
  });

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final Map<String, String> _peerMap = {}; // peerId → name
  final List<String> _logs = [];
  StreamSubscription? _joinSub;
  StreamSubscription? _leaveSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _disconnectSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _audioErrorSub;
  bool _syncing = false;
  bool _syncDone = false;
  bool _syncFailed = false;
  String? _hostIp;
  late int _guestPeerCount;

  @override
  void initState() {
    super.initState();
    _guestPeerCount = widget.initialPeerCount;
    final p2p = ref.read(p2pServiceProvider);

    if (widget.isHost) {
      _loadHostIp();
    }
    final sync = ref.read(syncServiceProvider);

    final audio = ref.read(audioSyncServiceProvider);

    if (widget.isHost) {
      _addLog('방 생성 완료 (코드: ${widget.roomCode})');
      _addLog('참가자를 기다리는 중...');

      // 호스트: sync-ping 응답 핸들러 시작
      sync.startHostHandler();
      audio.startListening(isHost: true);
      _syncDone = true;

      _joinSub = p2p.onPeerJoin.listen((peer) {
        setState(() {
          _peerMap[peer.id] = peer.name;
        });
        _addLog('${peer.name} 입장');
      });

      _leaveSub = p2p.onPeerLeave.listen((peerId) {
        final name = _peerMap.remove(peerId);
        if (mounted) setState(() {});
        _addLog('${name ?? "참가자"} 퇴장');
      });
    } else {
      _addLog('방 참가 완료 (코드: ${widget.roomCode})');
      audio.startListening(isHost: false);
      _startSync();

      // 게스트: 호스트 연결 끊김 감지 → 자동 재연결 시도
      _disconnectSub = p2p.onDisconnected.listen((_) async {
        if (!mounted) return;
        _addLog('호스트와 연결이 끊어졌습니다. 재연결 시도 중...');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결이 끊어졌습니다. 재연결 시도 중...')),
        );

        final reconnected = await p2p.reconnectToHost();
        if (!mounted) return;

        if (reconnected) {
          _addLog('재연결 성공!');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('재연결되었습니다')),
          );
          // 재동기화 (엔진 레이턴시는 이미 측정했으므로 스킵)
          final sync = ref.read(syncServiceProvider);
          sync.reset();
          await _reconnectSync();
        } else {
          _addLog('재연결 실패. 방을 나갑니다.');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('호스트에 재연결할 수 없습니다')),
          );
          _leaveRoom();
        }
      });
    }

    // WiFi 끊김 감지 (stale/일시적 이벤트 필터링)
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) async {
      if (!result.contains(ConnectivityResult.wifi)) {
        // 잠시 대기 후 실제 상태 재확인 (stale/일시적 이벤트 방지)
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final current = await Connectivity().checkConnectivity();
        if (!current.contains(ConnectivityResult.wifi) && mounted) {
          if (widget.isHost) {
            // 호스트: WiFi 끊기면 방 유지 불가
            _addLog('WiFi 연결이 끊어졌습니다');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('WiFi 연결이 끊어졌습니다. 방을 나갑니다.')),
            );
            _leaveRoom();
          } else {
            // 게스트: WiFi 복구 대기 후 재연결 시도
            _addLog('WiFi 연결이 끊어졌습니다. 복구 대기 중...');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('WiFi 연결이 끊어졌습니다. 복구 대기 중...')),
            );
            await _waitForWifiAndReconnect();
          }
        }
      }
    });

    // 오디오 에러 알림
    _audioErrorSub = audio.errorStream.listen((error) {
      if (mounted) {
        _addLog('오디오 에러: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    });

    _messageSub = p2p.onMessage.listen((message) {
      final type = message['type'] as String;

      // 게스트: 참가자 입퇴장 추적
      if (!widget.isHost) {
        if (type == 'peer-joined') {
          final name = message['data']?['name'] as String? ?? '참가자';
          setState(() => _guestPeerCount++);
          _addLog('$name 입장');
        } else if (type == 'peer-left') {
          setState(() => _guestPeerCount = (_guestPeerCount - 1).clamp(0, 999));
          _addLog('참가자 퇴장');
        }
      }

      // 대량 메시지는 로그에서 제외
      const hiddenTypes = {'sync-ping', 'sync-pong', 'sync-position', 'audio-request', 'welcome', 'peer-joined', 'peer-left'};
      if (!hiddenTypes.contains(type)) {
        _addLog('메시지: $type');
      }
    });
  }

  Future<void> _loadHostIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (mounted && ip != null) {
        setState(() => _hostIp = ip);
      }
    } catch (_) {}
  }

  /// 참가자: 시간 동기화 수행
  Future<void> _startSync() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    _addLog('시간 동기화 중...');

    try {
      final sync = ref.read(syncServiceProvider);
      final result = await sync.syncWithHost();
      _addLog('동기화 완료! offset: ${result.offsetMs}ms, RTT: ${result.rttMs}ms');
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncDone = true;
      });

      // 주기적 재동기화 시작 (클럭 드리프트 보정)
      sync.startPeriodicSync();

      // 엔진 레이턴시 측정
      final audio = ref.read(audioSyncServiceProvider);
      final latency = await audio.measureEngineLatency();
      _addLog('엔진 레이턴시: ${latency}ms');

      // 동기화 완료 후 호스트에게 현재 오디오 요청
      audio.requestCurrentAudio();
    } catch (e) {
      _addLog('동기화 실패: $e');
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncFailed = true;
      });
    }
  }

  /// 게스트: WiFi 복구 대기 (최대 15초) 후 재연결
  Future<void> _waitForWifiAndReconnect() async {
    // 최대 15초간 WiFi 복구 대기 (3초 간격 체크)
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final current = await Connectivity().checkConnectivity();
      if (current.contains(ConnectivityResult.wifi)) {
        _addLog('WiFi 복구됨. 재연결 시도 중...');
        final p2p = ref.read(p2pServiceProvider);
        final reconnected = await p2p.reconnectToHost();
        if (!mounted) return;

        if (reconnected) {
          _addLog('재연결 성공!');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('재연결되었습니다')),
          );
          final sync = ref.read(syncServiceProvider);
          sync.reset();
          await _reconnectSync();
          return;
        }
        break; // WiFi는 복구됐지만 호스트 연결 실패
      }
    }

    if (!mounted) return;
    _addLog('재연결 실패. 방을 나갑니다.');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('재연결할 수 없습니다')),
    );
    _leaveRoom();
  }

  /// 재연결 후 동기화 (엔진 레이턴시 측정 스킵, 오디오 상태 복원)
  Future<void> _reconnectSync() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    _addLog('재동기화 중...');

    try {
      final sync = ref.read(syncServiceProvider);
      final result = await sync.syncWithHost();
      _addLog('재동기화 완료! offset: ${result.offsetMs}ms, RTT: ${result.rttMs}ms');
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncDone = true;
      });

      sync.startPeriodicSync();

      // 호스트에게 현재 오디오+재생 상태 요청 → 자동 복원
      final audio = ref.read(audioSyncServiceProvider);
      audio.requestCurrentAudio();
    } catch (e) {
      _addLog('재동기화 실패: $e');
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncFailed = true;
      });
    }
  }

  void _retrySync() {
    setState(() => _syncFailed = false);
    _startSync();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  void _goToPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(isHost: widget.isHost),
      ),
    );
  }

  Future<void> _confirmAndLeave() async {
    if (!widget.isHost) {
      _leaveRoom();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방 나가기'),
        content: const Text('호스트가 나가면 모든 참가자의 연결이 끊어집니다.\n정말 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (result == true) _leaveRoom();
  }

  Future<void> _leaveRoom() async {
    // 구독 먼저 취소 (cleanup 중 콜백 방지)
    _joinSub?.cancel();
    _leaveSub?.cancel();
    _messageSub?.cancel();
    _disconnectSub?.cancel();
    _connectivitySub?.cancel();
    _audioErrorSub?.cancel();

    final p2p = ref.read(p2pServiceProvider);
    final discovery = ref.read(discoveryServiceProvider);
    final audio = ref.read(audioSyncServiceProvider);
    final sync = ref.read(syncServiceProvider);

    // 정리 완료 후 이동 (구독 취소했으므로 블로킹 없음)
    sync.reset();
    discovery.stop();
    await p2p.disconnect();
    await audio.clearTempFiles();

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _joinSub?.cancel();
    _leaveSub?.cancel();
    _messageSub?.cancel();
    _disconnectSub?.cancel();
    _connectivitySub?.cancel();
    _audioErrorSub?.cancel();

    // 앱 종료/화면 파괴 시 동기적 정리 (dispose는 sync라 await 불가)
    final audio = ref.read(audioSyncServiceProvider);
    audio.cleanupSync();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAndLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('방 ${widget.roomCode}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmAndLeave,
          ),
        ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 역할 표시
            Card(
              child: ListTile(
                leading: Icon(
                  widget.isHost ? Icons.star : Icons.person,
                  color: widget.isHost ? Colors.amber : Colors.blue,
                ),
                title: Text(widget.isHost ? '호스트' : '참가자'),
                subtitle: Text(
                  widget.isHost && _hostIp != null
                      ? '방 코드: ${widget.roomCode}  |  IP: $_hostIp'
                      : '방 코드: ${widget.roomCode}',
                ),
                trailing: widget.isHost && _hostIp != null
                    ? IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'IP 복사',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _hostIp!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('IP가 복사되었습니다'), duration: Duration(seconds: 1)),
                          );
                        },
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 16),

            // 접속자 수
            Text(
              '접속자: ${widget.isHost ? _peerMap.length + 1 : _guestPeerCount + 1}명',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            // 플레이어 이동 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncDone
                    ? _goToPlayer
                    : _syncFailed
                        ? _retrySync
                        : null,
                icon: Icon(_syncFailed ? Icons.refresh : Icons.play_arrow),
                label: Text(_syncing
                    ? '동기화 중...'
                    : _syncDone
                        ? '플레이어 열기'
                        : _syncFailed
                            ? '동기화 재시도'
                            : '동기화 대기 중'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 연결 로그
            const Text(
              '로그',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (_, index) => Text(
                      _logs[index],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}