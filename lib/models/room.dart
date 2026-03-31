import 'peer.dart';

class Room {
  final String code;
  final bool isHost;
  final List<Peer> peers;

  Room({
    required this.code,
    required this.isHost,
    List<Peer>? peers,
  }) : peers = peers ?? [];
}
