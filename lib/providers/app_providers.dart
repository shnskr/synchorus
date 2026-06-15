import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_handler.dart';
import '../services/p2p_service.dart';
import '../services/discovery_service.dart';
import '../services/sync_service.dart';
import '../services/native_audio_sync_service.dart';
import '../services/purchase_service.dart';

/// 일회성 "프로" 구매 여부 전역 상태. 호스트가 프로면 그 방 게스트 무제한 +
/// 배너 광고 제거 (수익화, 호스트 기준). 진실의 출처는 스토어 계정이고
/// (in_app_purchase restorePurchases), 로컬엔 `isPro_v1`로 캐싱한다.
/// 구매/복원 완료 시 PurchaseService가 setPro(true) 호출 → 런타임 즉시 반영.
class ProController extends Notifier<bool> {
  static const String _prefsKey = 'isPro_v1';

  @override
  bool build() {
    // 동기 기본값 false 반환 후 SharedPreferences에서 비동기 로드해 갱신.
    // (hasSeenGuide_v1 / device_uuid 와 동일 패턴)
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefsKey) ?? false;
  }

  /// 구매/복원 완료(또는 테스트) 시 호출. 전역 state 갱신 + 영속화.
  Future<void> setPro(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

final proProvider = NotifierProvider<ProController, bool>(ProController.new);

/// 일회성 프로 인앱결제 서비스. main에서 init() 호출(구독+상품조회+복원).
/// 구매/복원 완료 시 proProvider를 갱신한다.
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

final audioHandlerProvider = Provider<NativeAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden in main.dart',
  );
});

final p2pServiceProvider = Provider<P2PService>((ref) {
  final service = P2PService();
  ref.onDispose(() => service.dispose());
  return service;
});

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.dispose());
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
