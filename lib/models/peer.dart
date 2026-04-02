import 'dart:io';

class Peer {
  final String id;
  final String name;
  final Socket socket;
  int lastSeen;

  Peer({
    required this.id,
    required this.name,
    required this.socket,
  }) : lastSeen = DateTime.now().millisecondsSinceEpoch;
}
