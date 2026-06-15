import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../providers/app_providers.dart';

/// 일회성 "프로" 비소비성(non-consumable) 상품 ID. Play Console / App Store
/// Connect에 동일 ID로 등록해야 한다. 등록 전이면 queryProductDetails가 빈 결과를
/// 주고 buy()가 false 반환 — 흐름/UI는 그대로 테스트 가능.
const String kProProductId = 'synchorus_pro';

/// in_app_purchase 래퍼 (서버리스). 복원 기준은 스토어 계정(Google/Apple)이라
/// 재설치·기기변경해도 같은 계정이면 restorePurchases로 프로 유지. 구매/복원
/// 완료 시 [proProvider]를 true로 갱신 → 배너 제거 + 게스트 제한 해제가 즉시 반영.
class PurchaseService {
  PurchaseService(this._ref);

  final Ref _ref;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _available = false;

  bool get available => _available;

  /// 스토어가 현지화한 가격 문자열(예: "₩6,900", "$4.99"). 미로드 시 null.
  String? get priceLabel => _product?.price;

  /// 앱 시작 시 1회. 스토어 가용성 확인 → purchaseStream 구독 → 상품 조회 →
  /// 이전 구매 복원. 구독을 먼저 걸어야 restorePurchases 결과를 받는다.
  Future<void> init() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('[IAP] store unavailable');
      return;
    }
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) => debugPrint('[IAP] purchaseStream error: $e'),
    );
    await _queryProduct();
    await _iap.restorePurchases();
  }

  Future<void> _queryProduct() async {
    final resp = await _iap.queryProductDetails({kProProductId});
    if (resp.error != null) {
      debugPrint('[IAP] queryProductDetails error: ${resp.error}');
    }
    if (resp.productDetails.isNotEmpty) {
      _product = resp.productDetails.first;
    } else {
      debugPrint('[IAP] product not found: $kProProductId (스토어 등록 전이면 정상)');
    }
  }

  /// 프로 구매 시작. 상품 미로드(스토어 미등록/오프라인)면 false 반환.
  /// 실제 프로 잠금해제는 purchaseStream 콜백에서 이뤄진다.
  Future<bool> buy() async {
    final product = _product;
    if (product == null) return false;
    final param = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// 구매 복원(재설치·기기변경). 결과는 purchaseStream으로 들어온다.
  Future<void> restore() => _iap.restorePurchases();

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.productID == kProProductId &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        // 클라이언트 신뢰(서버리스 결정). 더 강한 검증이 필요하면 후속에서 서버 추가.
        _ref.read(proProvider.notifier).setPro(true);
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint('[IAP] purchase error: ${purchase.error}');
      }
      // 어떤 상태든 pending 완료 처리 누락 시 스토어가 재전송하므로 꼭 호출.
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
