import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'providers/app_providers.dart';
import 'screens/player_screen.dart';
import 'services/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 세로 고정 — 가로 회전 시 시크바/카드 영역이 overflow되어 노란 경고 띄움.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // AdMob 초기화(배너 광고). 무료 사용자에게만 표시되지만 SDK는 앱 시작 시 1회 초기화.
  unawaited(MobileAds.instance.initialize());

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final audioHandler = await AudioService.init(
    builder: () => NativeAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.synchorus.audio',
      androidNotificationChannelName: 'Synchorus',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
      child: const SynchorusApp(),
    ),
  );
}

class SynchorusApp extends ConsumerStatefulWidget {
  const SynchorusApp({super.key});

  @override
  ConsumerState<SynchorusApp> createState() => _SynchorusAppState();
}

class _SynchorusAppState extends ConsumerState<SynchorusApp> {
  @override
  void initState() {
    super.initState();
    // 인앱결제 초기화(구독+상품조회+이전 구매 복원). 스토어 계정 기준 복원이라
    // 재설치/기기변경 후에도 같은 계정이면 프로가 자동 복원된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(purchaseServiceProvider).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 프로 상태가 바뀌면(구매/복원/로드) P2PService에 주입 → 방 도중 구매해도
    // 게스트 제한이 즉시 해제된다. 호스트 기준 정책.
    ref.listen<bool>(proProvider, (_, next) {
      ref.read(p2pServiceProvider).setProStatus(next);
    });
    return MaterialApp(
      title: 'Synchorus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PlayerScreen(),
    );
  }
}
