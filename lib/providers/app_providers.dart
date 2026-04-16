import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/p2p_service.dart';
import '../services/discovery_service.dart';
import '../services/sync_service.dart';
import '../services/native_audio_sync_service.dart';

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

final syncServiceProvider = Provider<SyncService>((ref) {
  final p2p = ref.read(p2pServiceProvider);
  final service = SyncService(p2p);
  ref.onDispose(() => service.dispose());
  return service;
});

final nativeAudioSyncServiceProvider = Provider<NativeAudioSyncService>((ref) {
  final p2p = ref.read(p2pServiceProvider);
  final sync = ref.read(syncServiceProvider);
  final service = NativeAudioSyncService(p2p, sync);
  ref.onDispose(() => service.dispose());
  return service;
});
