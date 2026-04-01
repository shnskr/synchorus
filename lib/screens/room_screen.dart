import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/audio_service.dart';
import 'player_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomCode;
  final bool isHost;

  const RoomScreen({
    super.key,
    required this.roomCode,
    required this.isHost,
  });

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final List<String> _peerNames = [];
  final List<String> _logs = [];
  StreamSubscription? _joinSub;
  StreamSubscription? _leaveSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _disconnectSub;
  bool _syncing = false;
  bool _syncDone = false;

  @override
  void initState() {
    super.initState();
    final p2p = ref.read(p2pServiceProvider);
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
          _peerNames.add(peer.name);
        });
        _addLog('${peer.name} 입장');
      });

      _leaveSub = p2p.onPeerLeave.listen((peerId) {
        _addLog('참가자 퇴장');
      });
    } else {
      _addLog('방 참가 완료 (코드: ${widget.roomCode})');
      audio.startListening(isHost: false);
      _startSync();

      // 게스트: 호스트 연결 끊김 감지
      _disconnectSub = p2p.onDisconnected.listen((_) {
        _addLog('호스트와 연결이 끊어졌습니다');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('호스트가 방을 나갔습니다')),
          );
          _leaveRoom();
        }
      });
    }

    _messageSub = p2p.onMessage.listen((message) {
      final type = message['type'] as String;
      // 대량 메시지는 로그에서 제외
      const hiddenTypes = {'sync-ping', 'sync-pong', 'audio-data', 'audio-meta', 'audio-request'};
      if (!hiddenTypes.contains(type)) {
        _addLog('메시지: $type');
      }
    });
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
      // 동기화 완료 후 호스트에게 현재 오디오 요청
      final audio = ref.read(audioSyncServiceProvider);
      audio.requestCurrentAudio();
    } catch (e) {
      _addLog('동기화 실패: $e');
      if (!mounted) return;
      setState(() => _syncing = false);
    }
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

    final p2p = ref.read(p2pServiceProvider);
    final discovery = ref.read(discoveryServiceProvider);
    final audio = ref.read(audioSyncServiceProvider);

    // 정리 완료 후 이동 (구독 취소했으므로 블로킹 없음)
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
                subtitle: Text('방 코드: ${widget.roomCode}'),
              ),
            ),

            const SizedBox(height: 16),

            // 접속자 수
            Text(
              '접속자: ${_peerNames.length + 1}명',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            // 플레이어 이동 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncDone ? _goToPlayer : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_syncing
                    ? '동기화 중...'
                    : _syncDone
                        ? '플레이어 열기'
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
          ],
        ),
      ),
    ),
    );
  }
}