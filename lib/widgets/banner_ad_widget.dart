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
          debugPrint('[Ads] banner failed: $err');
          failedAd.dispose();
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
