import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _RoomScreenState extends ConsumerState<RoomScreen>
    with WidgetsBindingObserver {
  final Map<String, String> _peerMap = {}; // peerId → name
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _autoScroll = true;
  StreamSubscription? _joinSub;
  StreamSubscription? _leaveSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _disconnectSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _audioErrorSub;
  bool _syncing = false;
  bool _syncDone = false;
  bool _syncFailed = false;
  bool _leaving = false; // _leaveRoom 중복 호출 방지 (#13)
  bool _hostClosed = false; // 호스트가 host-closed 보내고 나간 상태
  bool _hostAway = false; // 게스트 측: 호스트가 host-paused 보낸 상태
  Timer? _awayReconnectTimer; // _hostAway 중 주기적 재접속 타이머
  bool _awayReconnecting = false; // 재접속 시도 중 중복 방지
  int _awayReconnectAttempts = 0; // 실패 누적 (N회 초과 시 호스트 사라짐 판정)
  static const int _awayReconnectMaxAttempts = 12; // 약 60초 (5초 주기 × 12)
  String? _hostIp;
  late int _guestPeerCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _guestPeerCount = widget.initialPeerCount;
    final p2p = ref.read(p2pServiceProvider);

    if (widget.isHost) {
      _loadHostIp();
    }
    final sync = ref.read(syncServiceProvider);

    final audio = ref.read(nativeAudioSyncServiceProvider);

    // 백그라운드 재생 핸들러 연결 (알림바/잠금화면 미디어 컨트롤)
    // 호스트: 재생/정지/seek 컨트롤 표시, 게스트: 곡 정보+재생 상태만 표시
    final handler = ref.read(audioHandlerProvider);
    handler.attachSyncService(audio, isHost: widget.isHost);

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

      // 게스트: 호스트 연결 끊김 감지
      _disconnectSub = p2p.onDisconnected.listen((_) async {
        if (!mounted) return;
        // host-closed 수신 후 정식 종료 중이면 재연결 시도하지 않고 바로 정리
        if (_hostClosed) {
          _addLog('호스트가 방을 종료했습니다.');
          _leaveRoom();
          return;
        }
        // 호스트 자리비움 중 TCP 끊김: host-resumed는 이미 죽은 소켓이라 도달 불가.
        // TCP 재접속 성공 자체를 "호스트 복귀 신호"로 삼아 주기적으로 조용히 시도.
        if (_hostAway) {
          _addLog('호스트 자리비움 중 TCP 끊김 → 주기적 재접속 시도 시작');
          _startAwayReconnectLoop();
          return;
        }
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
      if (!result.contains(ConnectivityResult.wifi) &&
          !result.contains(ConnectivityResult.ethernet) &&
          !result.contains(ConnectivityResult.other)) {
        // 잠시 대기 후 실제 상태 재확인 (stale/일시적 이벤트 방지)
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final current = await Connectivity().checkConnectivity();
        final hasLocal = current.contains(ConnectivityResult.wifi) ||
            current.contains(ConnectivityResult.ethernet) ||
            current.contains(ConnectivityResult.other);
        if (!hasLocal && mounted) {
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

      // 게스트: 호스트 라이프사이클 메시지 처리
      if (!widget.isHost) {
        if (type == 'host-paused') {
          debugPrint('[LIFECYCLE-GUEST] received host-paused');
          setState(() => _hostAway = true);
          _addLog('호스트 일시 자리비움');
          return;
        }
        if (type == 'host-resumed') {
          debugPrint('[LIFECYCLE-GUEST] received host-resumed');
          _cancelAwayReconnectLoop();
          setState(() => _hostAway = false);
          _addLog('호스트 복귀');
          return;
        }
        if (type == 'host-closed') {
          debugPrint('[LIFECYCLE-GUEST] received host-closed');
          _hostClosed = true;
          _addLog('호스트가 방을 종료했습니다.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('호스트가 방을 종료했습니다')),
            );
          }
          _leaveRoom();
          return;
        }
      }

      // 게스트: 참가자 입퇴장 추적
      if (!widget.isHost) {
        if (type == 'welcome') {
          final peerCount = message['data']?['peerCount'] as int?;
          if (peerCount != null) {
            setState(() => _guestPeerCount = peerCount);
          }
        } else if (type == 'peer-joined') {
          final name = message['data']?['name'] as String? ?? '참가자';
          setState(() => _guestPeerCount++);
          _addLog('$name 입장');
        } else if (type == 'peer-left') {
          setState(() => _guestPeerCount = (_guestPeerCount - 1).clamp(0, 999));
          _addLog('참가자 퇴장');
        }
      }

      // 대량 메시지는 로그에서 제외
      const hiddenTypes = {'sync-ping', 'sync-pong', 'sync-position', 'audio-obs', 'audio-request', 'state-request', 'state-response', 'welcome', 'peer-joined', 'peer-left'};
      if (!hiddenTypes.contains(type)) {
        _addLog('메시지: $type');
      }
    });
  }

  /// 게스트: _hostAway=true 상태에서 TCP 끊김 감지 시 주기적 재접속.
  /// host-resumed 메시지는 이미 죽은 소켓이라 도달 불가 → 재접속 성공 자체가 복귀 신호.
  /// 5초 간격, 실패해도 계속 시도 (조용히). 방 나가기/호스트 종료/재접속 성공 시 취소.
  void _startAwayReconnectLoop() {
    _awayReconnectTimer?.cancel();
    _awayReconnectAttempts = 0;
    _awayReconnectTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      if (!mounted || !_hostAway || _leaving || _hostClosed) {
        t.cancel();
        return;
      }
      if (_awayReconnecting) return; // 이전 시도가 아직 진행 중
      _awayReconnecting = true;
      try {
        final p2p = ref.read(p2pServiceProvider);
        final reconnected = await p2p.reconnectToHost(retries: 1);
        if (!mounted) return;
        if (reconnected) {
          debugPrint('[AWAY-RECONNECT] success — treating as host resumed');
          t.cancel();
          _awayReconnectTimer = null;
          _awayReconnectAttempts = 0;
          setState(() => _hostAway = false);
          _addLog('호스트 복귀 감지 (TCP 재접속 성공) — 재동기화');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('호스트 복귀')),
            );
          }
          final sync = ref.read(syncServiceProvider);
          sync.reset();
          await _reconnectSync();
        } else {
          _awayReconnectAttempts++;
          debugPrint(
            '[AWAY-RECONNECT] attempt $_awayReconnectAttempts/$_awayReconnectMaxAttempts failed',
          );
          if (_awayReconnectAttempts >= _awayReconnectMaxAttempts) {
            t.cancel();
            _awayReconnectTimer = null;
            debugPrint(
              '[AWAY-RECONNECT] giving up after $_awayReconnectMaxAttempts attempts → leaveRoom',
            );
            _addLog('호스트 복귀 없음 (약 60초 경과). 방을 나갑니다.');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('호스트가 돌아오지 않습니다. 방을 나갑니다.')),
              );
            }
            _leaveRoom();
          }
        }
      } catch (e) {
        debugPrint('[AWAY-RECONNECT] attempt error: $e');
      } finally {
        _awayReconnecting = false;
      }
    });
  }

  void _cancelAwayReconnectLoop() {
    _awayReconnectTimer?.cancel();
    _awayReconnectTimer = null;
    _awayReconnecting = false;
    _awayReconnectAttempts = 0;
  }

  /// 호스트: 앱 라이프사이클에 따라 heartbeat pause/resume + 게스트에 알림.
  /// audio_service가 foreground service 승격 안 된 상태(재생 전)에서 paused되면
  /// OS가 프로세스를 background로 강등하여 Timer 억제 → 게스트가 dead 오판정하는 문제를
  /// 예방. 재생 중이어도 동일 신호로 게스트에게 자리비움 알림 UX 제공.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[LIFECYCLE] state=$state isHost=${widget.isHost} leaving=$_leaving closed=$_hostClosed');
    if (!widget.isHost) return;
    if (_leaving || _hostClosed) return;
    final p2p = ref.read(p2pServiceProvider);
    if (state == AppLifecycleState.paused) {
      debugPrint('[LIFECYCLE] HOST paused → pauseHeartbeat + broadcast host-paused');
      _addLog('[라이프사이클] paused — heartbeat 정지 + host-paused broadcast');
      p2p.pauseHeartbeat();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[LIFECYCLE] HOST resumed → broadcast host-resumed + resumeHeartbeat');
      _addLog('[라이프사이클] resumed — host-resumed broadcast + heartbeat 재개');
      p2p.resumeHeartbeat();
    }
  }

  Future<void> _loadHostIp() async {
    try {
      String? privateAddr;
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final name = iface.name.toLowerCase();
          if ((name.startsWith('wlan') || name.startsWith('en')) &&
              _isPrivateIP(addr.address)) {
            if (mounted) setState(() => _hostIp = addr.address);
            return;
          }
          if (privateAddr == null && _isPrivateIP(addr.address)) {
            privateAddr = addr.address;
          }
        }
      }
      if (privateAddr != null && mounted) {
        setState(() => _hostIp = privateAddr);
      }
    } catch (_) {}
  }

  /// 사설 IP 대역 확인 (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
  static bool _isPrivateIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
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

      // 동기화 완료 후 호스트에게 현재 오디오 요청
      ref.read(p2pServiceProvider).sendToHost({'type': 'audio-request', 'data': {}});
    } catch (e) {
      final msg = e is TimeoutException
          ? '호스트 응답 없음 (시간 초과)'
          : '동기화 실패: $e';
      _addLog(msg);
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
      final p2p = ref.read(p2pServiceProvider);
      p2p.sendToHost({'type': 'audio-request', 'data': {}});
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

  static const int _maxLogLines = 500;

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > _maxLogLines) {
        _logs.removeRange(0, _logs.length - _maxLogLines);
      }
    });
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
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
    if (_leaving) return; // #13: 중복 호출 방지
    _leaving = true;
    _cancelAwayReconnectLoop();
    // 구독 먼저 취소 (cleanup 중 콜백 방지)
    _joinSub?.cancel();
    _leaveSub?.cancel();
    _messageSub?.cancel();
    _disconnectSub?.cancel();
    _connectivitySub?.cancel();
    _audioErrorSub?.cancel();

    final p2p = ref.read(p2pServiceProvider);
    final discovery = ref.read(discoveryServiceProvider);
    final audio = ref.read(nativeAudioSyncServiceProvider);
    final sync = ref.read(syncServiceProvider);

    // 백그라운드 재생 핸들러 분리 + 알림 제거
    final handler = ref.read(audioHandlerProvider);
    handler.detachSyncService();
    await handler.stop();

    // 정리 완료 후 이동 (구독 취소했으므로 블로킹 없음)
    sync.reset();
    discovery.stop();
    // 호스트가 정식 나가기: host-closed broadcast 후 disconnect.
    // 이미 host-closed 수신(게스트측)이거나 비정상 경로면 일반 disconnect.
    if (widget.isHost && !_hostClosed) {
      await p2p.closeRoom();
    } else {
      await p2p.disconnect();
    }
    await audio.clearTempFiles();

    // Provider 무효화: 다음 방 입장 시 새 인스턴스 생성 보장
    // invalidate → onDispose 콜백 → service.dispose() 호출됨
    ref.invalidate(nativeAudioSyncServiceProvider);
    ref.invalidate(syncServiceProvider);
    ref.invalidate(p2pServiceProvider);
    ref.invalidate(discoveryServiceProvider);

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAwayReconnectLoop();
    _joinSub?.cancel();
    _leaveSub?.cancel();
    _messageSub?.cancel();
    _disconnectSub?.cancel();
    _connectivitySub?.cancel();
    _audioErrorSub?.cancel();

    _logScrollController.dispose();

    // _leaveRoom이 정상 경로로 이미 정리한 경우 중복 cleanup 방지 (#13)
    if (!_leaving) {
      final handler = ref.read(audioHandlerProvider);
      handler.detachSyncService();
      final audio = ref.read(nativeAudioSyncServiceProvider);
      audio.cleanupSync();

      // 비정상 종료 경로에서도 provider 무효화
      ref.invalidate(nativeAudioSyncServiceProvider);
      ref.invalidate(syncServiceProvider);
      ref.invalidate(p2pServiceProvider);
      ref.invalidate(discoveryServiceProvider);
    }

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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('방 코드: ${widget.roomCode}'),
                    if (widget.isHost && _hostIp != null)
                      Text('IP: $_hostIp',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
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

            // 게스트: 호스트 자리비움 안내 배너
            if (!widget.isHost && _hostAway)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  border: Border.all(color: Colors.orange[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '호스트가 일시 자리비움입니다. 복귀를 기다려 주세요.',
                        style: TextStyle(color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),

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
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      final pos = _logScrollController.position;
                      _autoScroll = pos.pixels >= pos.maxScrollExtent - 30;
                    }
                    return false;
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                    child: ListView.builder(
                      controller: _logScrollController,
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
            ),
          ],
        ),
      ),
    ),
    );
  }
}