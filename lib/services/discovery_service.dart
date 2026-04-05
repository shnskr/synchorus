import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredHost {
  final String name;
  final String ip;
  final int port;
  final String roomCode;

  DiscoveredHost({
    required this.name,
    required this.ip,
    required this.port,
    required this.roomCode,
  });
}

class DiscoveryService {
  static const int udpPort = 41234;
  static const String prefix = 'SYNCHORUS';

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;

  /// 호스트: UDP 브로드캐스트로 자신의 존재를 알림
  Future<void> startBroadcast({
    required String hostName,
    required int tcpPort,
    required String roomCode,
  }) async {
    stop(); // 기존 소켓/타이머 정리
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;

    final message = '$prefix:$hostName:$tcpPort:$roomCode';
    final data = utf8.encode(message);

    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _socket?.send(data, InternetAddress('255.255.255.255'), udpPort);
    });
  }

  /// 참가자: UDP 브로드캐스트를 수신하여 호스트 발견
  Stream<DiscoveredHost> discoverHosts() async* {
    stop(); // 기존 소켓/타이머 정리
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
    _socket = socket;

    await for (final event in socket) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram == null) continue;

        final message = utf8.decode(datagram.data);
        final parts = message.split(':');

        if (parts.length == 4 && parts[0] == prefix) {
          final port = int.tryParse(parts[2]);
          if (port == null) continue;
          yield DiscoveredHost(
            name: parts[1],
            ip: datagram.address.address,
            port: port,
            roomCode: parts[3],
          );
        }
      }
    }
  }

  void stop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
  }
}
