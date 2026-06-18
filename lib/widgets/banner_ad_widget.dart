import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 상단 anchored adaptive 배너. 무료 사용자에게만 노출(호출 측에서 `!isPro` 가드).
/// 로드 전/실패 시 빈 위젯(SizedBox.shrink)이라 레이아웃 흔들림 최소.
///
/// 광고 단위 ID: debug=테스트 / release=실 ID(Android). 무효 트래픽 방지로
/// debug는 항상 테스트 광고, release도 등록 기기(main.dart testDeviceIds)엔 테스트.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // debug = 테스트 단위(어떤 기기든 테스트 광고 → 무효 트래픽 방지).
  // release = 실 단위(Android만 실 ID, iOS는 iOS 라운드 때). 등록 기기는 testDeviceIds로 테스트.
  static String get _adUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9214589741' // Android 테스트
          : 'ca-app-pub-3940256099942544/2435281174'; // iOS 테스트
    }
    return Platform.isAndroid
        ? 'ca-app-pub-7354159087125839/9152452935' // Android 실 adaptive 배너
        : 'ca-app-pub-3940256099942544/2435281174'; // iOS 테스트(iOS 라운드 때 실 ID)
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 화면 폭(MediaQuery)이 필요해 여기서 1회 로드. adaptive size는 비동기.
    if (!_requested) {
      _requested = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    // 공식 문서(AdMob Flutter)는 "광고 로드 전 MobileAds 초기화 완료를 기다리는 게
    // 중요"라고 명시 — init 미완 상태로 요청하면 첫 요청에서 광고가 안 붙을 수 있음.
    // main.dart에서 unawaited로 먼저 시작해두므로 여기 await는 대개 즉시 반환하고,
    // initialize()는 완료/30초 타임아웃 후 반환하는 Future라 영구 hang도 없음.
    // (testDeviceIds 설정도 main에서 init 직후 동기 적용돼 이 시점엔 이미 반영됨.)
    await MobileAds.instance.initialize();
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: _adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _ad = loadedAd as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (failedAd, err) {
          debugPrint('[Ads] banner failed (try ${_retryCount + 1}): $err');
          failedAd.dispose();
          // 일시 오류(NO_FILL·네트워크·init 타이밍)는 지수 백오프로 제한 재시도.
          // 계정 미승인 같은 영구 사유면 재시도해도 안 뜨지만 무한 루프는 _maxRetries로 차단.
          if (_retryCount < _maxRetries && mounted) {
            _retryCount++;
            Future.delayed(Duration(seconds: 2 * _retryCount), () {
              if (mounted && !_loaded) _loadAd();
            });
          }
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
