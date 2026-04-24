import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';

class P2PService {
  static const int defaultPort = 41235;
  static const int _heartbeatIntervalSec = 3;
  // 대용량 다운로드 중 게스트 이벤트 루프가 바쁘면 heartbeat-ack 처리가 지연되어
  // 9초(3회 miss) 안에 못 돌아오는 경우가 잦아 연결이 끊겼음. 5회 miss(15초)로 완화.
  static const int _heartbeatTimeoutMs = 15000;

  ServerSocket? _serverSocket;
  Socket? _hostSocket;
  String? _connectedHostIp;
  String? _roomCode;
  Timer? _heartbeatTimer;
  final List<Peer> _peers = [];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _peerJoinController = StreamController<Peer>.broadcast();
  final _peerLeaveController = StreamController<String>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();

  /// 메시지 수신 스트림
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// 참가자 입장 스트림
  Stream<Peer> get onPeerJoin => _peerJoinController.stream;

  /// 참가자 퇴장 스트림
  Stream<String> get onPeerLeave => _peerLeaveController.stream;

  /// 호스트 연결 끊김 스트림 (게스트용)
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// 연결된 참가자 목록
  List<Peer> get peers => List.unmodifiable(_peers);

  /// 호스트인지 여부
  bool get isHost => _serverSocket != null;
  String? get connectedHostIp => _connectedHostIp;

  /// 4자리 방 코드 생성
  String generateRoomCode() {
    final random = Random();
    _roomCode = (1000 + random.nextInt(9000)).toString();
    return _roomCode!;
  }

  /// 호스트: TCP 서버 시작
  Future<int> startHost() async {
    await disconnect();
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, defaultPort, shared: true);

    _serverSocket!.listen(
      (socket) {
        _handleNewPeer(socket);
      },
      onError: (error) {
        debugPrint('Server error: $error');
      },
    );

    _startHeartbeat();
    return _serverSocket!.port;
  }

  /// 호스트: heartbeat 시작 (죽은 피어 감지)
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatIntervalSec),
      (_) {
        _removeDeadPeers();
        broadcastToAll({'type': 'heartbeat'});
      },
    );
  }

  /// 호스트: paused 진입 시 heartbeat 정지 + host-paused 알림.
  /// background로 가면 Timer가 억제돼서 어차피 안 돌지만,
  /// 복귀(resumed) 직후 stale lastSeen으로 dead 판정되는 걸 막기 위해 명시적으로 cancel.
  void pauseHeartbeat() {
    debugPrint('[P2P] pauseHeartbeat peers=${_peers.length}');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    broadcastToAll({'type': 'host-paused'});
    // paused 진입 전 OS 소켓 버퍼로 강제 flush (짧은 시간 여유 내)
    for (final peer in _peers) {
      try {
        peer.socket.flush();
      } catch (_) {}
    }
  }

  /// 호스트: resumed 시 모든 peer의 lastSeen을 지금 시각으로 리셋한 뒤 heartbeat 재개.
  /// 리셋 안 하면 paused 기간이 lastSeen에 누적돼 바로 dead 판정될 수 있음.
  void resumeHeartbeat() {
    debugPrint('[P2P] resumeHeartbeat peers=${_peers.length}');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final peer in _peers) {
      peer.lastSeen = now;
    }
    broadcastToAll({'type': 'host-resumed'});
    _startHeartbeat();
  }

  /// 호스트: 정식으로 방 종료. 게스트들에게 먼저 알린 뒤 disconnect.
  Future<void> closeRoom() async {
    debugPrint('[P2P] closeRoom peers=${_peers.length}');
    broadcastToAll({'type': 'host-closed'});
    // 메시지가 소켓 버퍼로 flush될 시간 확보
    for (final peer in _peers) {
      try {
        await peer.socket.flush();
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 100));
    await disconnect();
  }

  /// 호스트: detached(앱 종료 직전) 콜백에서 호출. await 없이 best-effort로
  /// host-closed를 브로드캐스트 + flush 트리거만 한다. Dart isolate가 곧
  /// 사라질 수 있어서 await을 기대할 수 없음. 메시지가 OS 소켓 버퍼까지
  /// 내려가면 커널이 프로세스 종료 시 마저 보낸다(best-effort).
  void broadcastHostClosedBestEffort() {
    debugPrint('[P2P] broadcastHostClosedBestEffort peers=${_peers.length}');
    broadcastToAll({'type': 'host-closed'});
    for (final peer in _peers) {
      try {
        // flush()는 Future지만 await 안 함 — 호출로 "send" 유도만
        // ignore: discarded_futures
        peer.socket.flush();
      } catch (_) {}
    }
  }

  /// 호스트: 응답 없는 피어 제거
  void _removeDeadPeers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deadPeers = _peers.where((p) => now - p.lastSeen > _heartbeatTimeoutMs).toList();
    for (final peer in deadPeers) {
      debugPrint('Heartbeat timeout: ${peer.id}');
      peer.socket.destroy();
      _peers.remove(peer);
      _peerLeaveController.add(peer.id);
      broadcastToAll({
        'type': 'peer-left',
        'data': {'peerId': peer.id},
      });
    }
  }

  int? _lastHostPort;
  String? _lastMyName;

  /// 마지막 reconnect 시도에서 잡힌 SocketException의 errno (없으면 null).
  /// 호출부가 errno=111(refused) 같은 값으로 빠른 포기 판정에 사용.
  int? _lastReconnectErrno;
  int? get lastReconnectErrno => _lastReconnectErrno;

  /// 참가자: 호스트에 TCP 연결
  Future<void> connectToHost(String ip, int port, String myName) async {
    _hostSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
    _connectedHostIp = ip;
    _lastHostPort = port;
    _lastMyName = myName;

    // 입장 메시지 전송
    _sendTo(_hostSocket!, {'type': 'join', 'data': {'name': myName}});

    // 호스트로부터 메시지 수신
    _listenToSocket(_hostSocket!, 'host');
  }

  /// 참가자: 호스트에 재연결 시도 (최대 retries회)
  Future<bool> reconnectToHost({int retries = 3}) async {
    final ip = _connectedHostIp;
    final port = _lastHostPort;
    final name = _lastMyName;
    if (ip == null || port == null || name == null) return false;

    _hostSocket?.destroy();
    _hostSocket = null;
    _lastReconnectErrno = null;

    for (int i = 0; i < retries; i++) {
      try {
        debugPrint('Reconnect attempt ${i + 1}/$retries to $ip:$port');
        await Future.delayed(Duration(seconds: i + 1)); // 1, 2, 3초 대기
        _hostSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
        _sendTo(_hostSocket!, {'type': 'join', 'data': {'name': name}});
        _listenToSocket(_hostSocket!, 'host');
        debugPrint('Reconnected successfully');
        _lastReconnectErrno = null;
        return true;
      } catch (e) {
        debugPrint('Reconnect attempt ${i + 1} failed: $e');
        if (e is SocketException) {
          _lastReconnectErrno = e.osError?.errorCode;
        } else {
          _lastReconnectErrno = null;
        }
        _hostSocket?.destroy();
        _hostSocket = null;
      }
    }
    return false;
  }

  /// 호스트: 새 참가자 처리
  void _handleNewPeer(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';
    String peerName = 'Unknown';

    _listenToSocket(socket, peerId, onFirstMessage: (message) {
      if (message['type'] != 'join') {
        debugPrint('Invalid first message from $peerId: ${message['type']}');
        socket.destroy();
        return;
      }

      peerName = message['data']['name'] ?? 'Unknown';
      final peer = Peer(id: peerId, name: peerName, socket: socket);
      _peers.add(peer);
      _peerJoinController.add(peer);

      // 입장 승인
      _sendTo(socket, {
        'type': 'welcome',
        'data': {
          'peerId': peerId,
          'peerCount': _peers.length,
          'roomCode': _roomCode,
        },
      });

      // 다른 참가자들에게 알림
      broadcastToAll({
        'type': 'peer-joined',
        'data': {'peerId': peerId, 'name': peerName},
      }, exclude: peerId);
    });

    socket.done.then((_) {
      // heartbeat에서 이미 제거된 경우 중복 처리 방지
      if (!_peers.any((p) => p.id == peerId)) return;
      _peers.removeWhere((p) => p.id == peerId);
      _peerLeaveController.add(peerId);
      broadcastToAll({
        'type': 'peer-left',
        'data': {'peerId': peerId},
      });
    }).catchError((e) {
      if (!_peers.any((p) => p.id == peerId)) return;
      _peers.removeWhere((p) => p.id == peerId);
      _peerLeaveController.add(peerId);
    });
  }

  /// 소켓에서 메시지 수신 리스너
  void _listenToSocket(Socket socket, String sourceId, {Function(Map<String, dynamic>)? onFirstMessage}) {
    bool isFirst = true;
    // 누적 버퍼 + 라인 시작 오프셋: O(n²) 회피 (#9)
    // List.removeRange 대신 lineStart만 전진시키고, 임계치를 넘으면 한 번에 잘라냄
    var buffer = <int>[];
    int lineStart = 0;
    const newLine = 0x0A; // '\n'

    void processMessage(Map<String, dynamic> message) {
      // 게스트: heartbeat 수신 → 자동 응답
      if (message['type'] == 'heartbeat' && sourceId == 'host') {
        _sendTo(socket, {'type': 'heartbeat-ack'});
        return;
      }
      // 호스트: 게스트 leave 수신 → 즉시 퇴장 처리
      if (message['type'] == 'leave' && sourceId != 'host') {
        final peer = _peers.cast<Peer?>().firstWhere(
            (p) => p!.id == sourceId, orElse: () => null);
        if (peer != null) {
          peer.socket.destroy();
          _peers.remove(peer);
          _peerLeaveController.add(peer.id);
          broadcastToAll({
            'type': 'peer-left',
            'data': {'peerId': peer.id},
          });
        }
        return;
      }
      // 호스트: heartbeat-ack 수신 → lastSeen 갱신
      if (message['type'] == 'heartbeat-ack') {
        final peer = _peers.cast<Peer?>().firstWhere(
            (p) => p!.id == sourceId, orElse: () => null);
        if (peer != null) {
          peer.lastSeen = DateTime.now().millisecondsSinceEpoch;
        }
        return;
      }

      if (isFirst && onFirstMessage != null) {
        onFirstMessage(message);
        isFirst = false;
      } else {
        _messageController.add(message);
      }
    }

    socket.listen(
      (data) {
        buffer.addAll(data);
        for (int i = lineStart; i < buffer.length; i++) {
          if (buffer[i] == newLine) {
            final lineBytes = buffer.sublist(lineStart, i);
            lineStart = i + 1;
            try {
              final line = utf8.decode(lineBytes);
              final message = jsonDecode(line) as Map<String, dynamic>;
              message['_from'] = sourceId;
              processMessage(message);
            } catch (e) {
              debugPrint('Parse error: $e');
            }
          }
        }
        // 처리된 부분 잘라내기 (lineStart가 일정 크기 이상 누적됐을 때만)
        if (lineStart > 4096) {
          buffer = buffer.sublist(lineStart);
          lineStart = 0;
        }
      },
      onError: (error) {
        debugPrint('Socket error from $sourceId: $error');
      },
      onDone: () {
        debugPrint('Connection closed: $sourceId');
        if (sourceId == 'host') {
          // #1: stale 소켓 참조 정리 (이후 sendToHost가 죽은 소켓에 쓰지 않도록)
          _hostSocket?.destroy();
          _hostSocket = null;
          // dispose() 후 지연 도착하는 Socket.onDone 가드 (closed controller에 add하면 예외)
          if (!_disconnectedController.isClosed) {
            _disconnectedController.add(null);
          }
        }
      },
    );
  }

  /// 호스트: 모든 참가자에게 메시지 전송
  void broadcastToAll(Map<String, dynamic> message, {String? exclude}) {
    // 전송 중 peer 리스트가 변경될 수 있으므로 스냅샷 순회
    final snapshot = List<Peer>.from(_peers);
    for (final peer in snapshot) {
      if (peer.id != exclude) {
        _sendToPeerSafe(peer, message);
      }
    }
  }

  /// 호스트: 특정 참가자에게 메시지 전송
  void sendToPeer(String peerId, Map<String, dynamic> message) {
    final peer = _peers.cast<Peer?>().firstWhere(
      (p) => p!.id == peerId,
      orElse: () => null,
    );
    if (peer != null) {
      _sendToPeerSafe(peer, message);
    }
  }

  /// 참가자: 호스트에게 메시지 전송
  void sendToHost(Map<String, dynamic> message) {
    final socket = _hostSocket;
    if (socket == null) return;
    try {
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send to host error: $e');
      // 호스트 소켓이 깨진 상태 → 정리 + 재연결 트리거
      _hostSocket?.destroy();
      _hostSocket = null;
      if (!_disconnectedController.isClosed) {
        _disconnectedController.add(null);
      }
    }
  }

  /// 호스트: peer 객체로 안전 전송. 실패 시 즉시 peer 제거 (#15)
  void _sendToPeerSafe(Peer peer, Map<String, dynamic> message) {
    try {
      peer.socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send error to ${peer.id}: $e');
      try {
        peer.socket.destroy();
      } catch (_) {}
      if (_peers.remove(peer)) {
        _peerLeaveController.add(peer.id);
        // 다른 피어들에게도 알림 (재귀 호출이지만 해당 peer는 이미 _peers에서 빠졌으므로 안전)
        broadcastToAll({
          'type': 'peer-left',
          'data': {'peerId': peer.id},
        });
      }
    }
  }

  /// 소켓에 JSON 메시지 전송 (줄바꿈 구분) - 일반 socket용
  void _sendTo(Socket socket, Map<String, dynamic> message) {
    try {
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } catch (e) {
      debugPrint('Send error: $e');
    }
  }

  /// 연결 종료
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // 게스트: 호스트에게 leave 메시지 전송 후 소켓 종료
    if (_hostSocket != null) {
      _sendTo(_hostSocket!, {'type': 'leave'});
    }

    for (final peer in _peers) {
      peer.socket.destroy();
    }
    _peers.clear();
    _hostSocket?.destroy();
    _hostSocket = null;
    _connectedHostIp = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    _messageController.close();
    _peerJoinController.close();
    _peerLeaveController.close();
    _disconnectedController.close();
  }
}
