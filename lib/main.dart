import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';

import 'providers/app_providers.dart';
import 'screens/player_screen.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';

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

  // 알림 카드 컬러 아트: 번들 logo.png를 파일로 1회 복사해 artUri로 사용
  // (Android 알림 large art는 file/content URI 필요 — asset 직접 참조 불가).
  // 상태바 작은 아이콘은 drawable 흰 실루엣(androidNotificationIcon)이 따로 담당.
  try {
    final dir = await getApplicationSupportDirectory();
    final artFile = File('${dir.path}/notif_art.png');
    if (!await artFile.exists()) {
      final bytes = await rootBundle.load('assets/branding/logo.png');
      await artFile.writeAsBytes(bytes.buffer.asUint8List());
    }
    NativeAudioHandler.notifArtUri = Uri.file(artFile.path);
  } catch (_) {
    // 복사 실패 시 artUri=null → 카드 아트만 생략(크래시 없음).
  }

  final audioHandler = await AudioService.init(
    builder: () => NativeAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.synchorus.audio',
      androidNotificationChannelName: 'Synchorus',
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_synchorus', // 상태바 흰 실루엣
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
      theme: AppTheme.dark, // 디자인 시스템 다크 테마 (lib/theme/)
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // 다크 전용
      home: const PlayerScreen(),
    );
  }
}
