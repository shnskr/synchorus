import 'dart:io';

class Peer {
  final String id;
  final String name;
  final Socket socket;

  Peer({
    required this.id,
    required this.name,
    required this.socket,
  });
}
