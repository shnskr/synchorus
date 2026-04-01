import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/peer.dart';

class P2PService {
  static const int defaultPort = 41235;

  ServerSocket? _serverSocket;
  Socket? _hostSocket;
  final List<Peer> _peers = [];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _peerJoinController = StreamController<Peer>.broadcast();
  final _peerLeaveController = StreamController<String>.broadcast();

  /// 메시지 수신 스트림
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// 참가자 입장 스트림
  Stream<Peer> get onPeerJoin => _peerJoinController.stream;

  /// 참가자 퇴장 스트림
  Stream<String> get onPeerLeave => _peerLeaveController.stream;

  /// 연결된 참가자 목록
  List<Peer> get peers => List.unmodifiable(_peers);

  /// 호스트인지 여부
  bool get isHost => _serverSocket != null;

  /// 4자리 방 코드 생성
  String generateRoomCode() {
    final random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  /// 호스트: TCP 서버 시작
  Future<int> startHost() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, defaultPort);

    _serverSocket!.listen(
      (socket) {
        _handleNewPeer(socket);
      },
      onError: (error) {
        print('Server error: $error');
      },
    );

    return _serverSocket!.port;
  }

  /// 참가자: 호스트에 TCP 연결
  Future<void> connectToHost(String ip, int port, String myName) async {
    _hostSocket = await Socket.connect(ip, port);

    // 입장 메시지 전송
    _sendTo(_hostSocket!, {'type': 'join', 'data': {'name': myName}});

    // 호스트로부터 메시지 수신
    _listenToSocket(_hostSocket!, 'host');
  }

  /// 호스트: 새 참가자 처리
  void _handleNewPeer(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';
    String peerName = 'Unknown';

    _listenToSocket(socket, peerId, onFirstMessage: (message) {
      if (message['type'] == 'join') {
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
          },
        });

        // 다른 참가자들에게 알림
        broadcastToAll({
          'type': 'peer-joined',
          'data': {'peerId': peerId, 'name': peerName},
        }, exclude: peerId);
      }
    });

    socket.done.then((_) {
      _peers.removeWhere((p) => p.id == peerId);
      _peerLeaveController.add(peerId);
      broadcastToAll({
        'type': 'peer-left',
        'data': {'peerId': peerId},
      });
    });
  }

  /// 소켓에서 메시지 수신 리스너
  void _listenToSocket(Socket socket, String sourceId, {Function(Map<String, dynamic>)? onFirstMessage}) {
    bool isFirst = true;
    String buffer = '';

    socket.listen(
      (data) {
        buffer += utf8.decode(data);
        // 줄바꿈으로 메시지 구분
        while (buffer.contains('\n')) {
          final index = buffer.indexOf('\n');
          final line = buffer.substring(0, index);
          buffer = buffer.substring(index + 1);

          try {
            final message = jsonDecode(line) as Map<String, dynamic>;
            message['_from'] = sourceId;
            if (isFirst && onFirstMessage != null) {
              onFirstMessage(message);
              isFirst = false;
            } else {
              _messageController.add(message);
            }
          } catch (e) {
            print('Parse error: $e');
          }
        }
      },
      onError: (error) {
        print('Socket error from $sourceId: $error');
      },
      onDone: () {
        print('Connection closed: $sourceId');
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
    socket.write('${jsonEncode(message)}\n');
  }

  /// 연결 종료
  Future<void> disconnect() async {
    for (final peer in _peers) {
      await peer.socket.close();
    }
    _peers.clear();
    await _hostSocket?.close();
    _hostSocket = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    _messageController.close();
    _peerJoinController.close();
    _peerLeaveController.close();
  }
}
