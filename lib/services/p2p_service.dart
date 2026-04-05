import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';

class P2PService {
  static const int defaultPort = 41235;
  static const int _heartbeatIntervalSec = 3;
  static const int _heartbeatTimeoutMs = 9000;

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

  /// 참가자: 호스트에 TCP 연결
  Future<void> connectToHost(String ip, int port, String myName) async {
    _hostSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
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

    for (int i = 0; i < retries; i++) {
      try {
        debugPrint('Reconnect attempt ${i + 1}/$retries to $ip:$port');
        await Future.delayed(Duration(seconds: i + 1)); // 1, 2, 3초 대기
        _hostSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
        _sendTo(_hostSocket!, {'type': 'join', 'data': {'name': name}});
        _listenToSocket(_hostSocket!, 'host');
        debugPrint('Reconnected successfully');
        return true;
      } catch (e) {
        debugPrint('Reconnect attempt ${i + 1} failed: $e');
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
    final byteBuffer = <int>[];
    final newLine = '\n'.codeUnitAt(0);

    socket.listen(
      (data) {
        byteBuffer.addAll(data);
        // 줄바꿈(\n)으로 메시지 구분 - 바이트 단위로 처리
        while (byteBuffer.contains(newLine)) {
          final index = byteBuffer.indexOf(newLine);
          final lineBytes = byteBuffer.sublist(0, index);
          byteBuffer.removeRange(0, index + 1);

          try {
            final line = utf8.decode(lineBytes);
            final message = jsonDecode(line) as Map<String, dynamic>;
            message['_from'] = sourceId;

            // 게스트: heartbeat 수신 → 자동 응답
            if (message['type'] == 'heartbeat' && sourceId == 'host') {
              _sendTo(socket, {'type': 'heartbeat-ack'});
              continue;
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
              continue;
            }
            // 호스트: heartbeat-ack 수신 → lastSeen 갱신
            if (message['type'] == 'heartbeat-ack') {
              final peer = _peers.cast<Peer?>().firstWhere(
                (p) => p!.id == sourceId, orElse: () => null);
              if (peer != null) {
                peer.lastSeen = DateTime.now().millisecondsSinceEpoch;
              }
              continue;
            }

            if (isFirst && onFirstMessage != null) {
              onFirstMessage(message);
              isFirst = false;
            } else {
              _messageController.add(message);
            }
          } catch (e) {
            debugPrint('Parse error: $e');
          }
        }
      },
      onError: (error) {
        debugPrint('Socket error from $sourceId: $error');
      },
      onDone: () {
        debugPrint('Connection closed: $sourceId');
        if (sourceId == 'host') {
          _disconnectedController.add(null);
        }
      },
    );
  }

  /// 호스트: 모든 참가자에게 메시지 전송
  void broadcastToAll(Map<String, dynamic> message, {String? exclude}) {
    for (final peer in _peers) {
      if (peer.id != exclude) {
        _sendTo(peer.socket, message);
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
      _sendTo(peer.socket, message);
    }
  }

  /// 참가자: 호스트에게 메시지 전송
  void sendToHost(Map<String, dynamic> message) {
    if (_hostSocket != null) {
      _sendTo(_hostSocket!, message);
    }
  }

  /// 소켓에 JSON 메시지 전송 (줄바꿈 구분)
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
