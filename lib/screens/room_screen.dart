import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
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
  bool _syncing = false;
  bool _syncDone = false;

  @override
  void initState() {
    super.initState();
    final p2p = ref.read(p2pServiceProvider);
    final sync = ref.read(syncServiceProvider);

    if (widget.isHost) {
      _addLog('방 생성 완료 (코드: ${widget.roomCode})');
      _addLog('참가자를 기다리는 중...');

      // 호스트: sync-ping 응답 핸들러 시작
      sync.startHostHandler();
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
      _startSync();
    }

    _messageSub = p2p.onMessage.listen((message) {
      final type = message['type'] as String;
      // 대량 메시지는 로그에서 제외
      const hiddenTypes = {'sync-ping', 'sync-pong', 'audio-data', 'audio-meta'};
      if (!hiddenTypes.contains(type)) {
        _addLog('메시지: $type');
      }
    });
  }

  /// 참가자: 시간 동기화 수행
  Future<void> _startSync() async {
    setState(() => _syncing = true);
    _addLog('시간 동기화 중...');

    try {
      final sync = ref.read(syncServiceProvider);
      final result = await sync.syncWithHost();
      _addLog('동기화 완료! offset: ${result.offsetMs}ms, RTT: ${result.rttMs}ms');
      setState(() {
        _syncing = false;
        _syncDone = true;
      });
    } catch (e) {
      _addLog('동기화 실패: $e');
      setState(() => _syncing = false);
    }
  }

  void _addLog(String message) {
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

  Future<void> _leaveRoom() async {
    final p2p = ref.read(p2pServiceProvider);
    final discovery = ref.read(discoveryServiceProvider);

    await p2p.disconnect();
    discovery.stop();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _joinSub?.cancel();
    _leaveSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('방 ${widget.roomCode}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leaveRoom,
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
    );
  }
}