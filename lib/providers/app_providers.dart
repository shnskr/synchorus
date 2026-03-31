import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/p2p_service.dart';
import '../services/discovery_service.dart';

final p2pServiceProvider = Provider<P2PService>((ref) {
  final service = P2PService();
  ref.onDispose(() => service.dispose());
  return service;
});

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.stop());
  return service;
});
