import 'dart:io';

class Peer {
  final String id;
  final String name;
  final String deviceId;
  final Socket socket;
  int lastSeen;

  Peer({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.socket,
  }) : lastSeen = DateTime.now().millisecondsSinceEpoch;
}
