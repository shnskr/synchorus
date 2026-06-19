import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'providers/app_providers.dart';
import 'screens/player_screen.dart';
import 'services/audio_handler.dart';
import 'theme/app_theme.dart';

/// 테스트 기기 — 여기 등록된 기기는 **release 빌드에서도 테스트 광고만** 노출
/// (개발자 본인 기기 무효 클릭으로 AdMob 계정 정지되는 것 방지). 새 기기는 ID 추가.
/// ID 얻는 법: 앱 실행 시 logcat에 `setTestDeviceIds(["XXXX..."])` 줄이 뜸 → 그 값 추가.
/// (debug 빌드는 어차피 테스트 광고단위라 이 목록과 무관하게 안전.)
const List<String> _kTestDeviceIds = <String>[
  '0F9E5626455023F56EA6AA7FD9C02ED1', // SM S947N (R3KL207HBBF)
  '0BFACB8F367F18AD86CF1E3BFD6B7B78', // SM S901N / S22 (R3CT60D20XE)
];

/// 네이티브 스플래시 최소 표시 시간(ms). 스플래시는 첫 Flutter 프레임에 자동으로
/// 사라지는데, 콜드/웜 스타트 편차로 거의 0초에 휙 지나가 깜빡임처럼 보였음(HISTORY 163).
/// preserve로 붙잡아 두고 main 진입 기준 이 시간을 채운 뒤 remove → 표시 시간 평탄화.
/// main 진입 기준이라 엔진 로드 구간(프로세스 시작~Dart 진입)은 미포함 — 그 변동까지
/// 잡으려면 네이티브 채널 필요(docs A안). 현재 B안: Dart만, 출시 단계 리스크 최소.
const int _kMinSplashMs = 1000;

Future<void> main() async {
  // 스플래시를 첫 프레임 이후에도 붙잡아 둠(아래 remove까지 유지) — 최소 표시 시간 보장.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  // main 진입 시점부터 경과 측정 — _kMinSplashMs 채우는 기준.
  final splashWatch = Stopwatch()..start();

  // release 빌드에선 모든 debugPrint를 no-op으로 — production logcat에 진단 로그
  // 안 나가게(+I/O 절감). debug/profile 빌드는 그대로 출력 → 디버깅·측정 가시성 유지.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // 세로 고정 — 가로 회전 시 시크바/카드 영역이 overflow되어 노란 경고 띄움.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // AdMob 초기화(배너 광고). 무료 사용자에게만 표시되지만 SDK는 앱 시작 시 1회 초기화.
  unawaited(MobileAds.instance.initialize());
  // 등록된 테스트 기기는 release에서도 테스트 광고만 (무효 트래픽 방지).
  if (_kTestDeviceIds.isNotEmpty) {
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: _kTestDeviceIds),
    );
  }

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

  // 스플래시 최소 표시(B안): runApp으로 첫 프레임을 그리게 한 뒤, main 진입~지금 경과가
  // _kMinSplashMs 미만이면 남은 만큼 채우고 remove(이미 넘었으면 즉시). 준비된 화면을
  // 스플래시 뒤에 미리 그려둔 상태로 자연스럽게 전환 → 콜드/웜별 0초 깜빡임 제거.
  final remaining = _kMinSplashMs - splashWatch.elapsedMilliseconds;
  if (remaining > 0) {
    await Future.delayed(Duration(milliseconds: remaining));
  }
  FlutterNativeSplash.remove();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 인앱결제 초기화(구독+상품조회+이전 구매 복원). 스토어 계정 기준 복원이라
      // 재설치/기기변경 후에도 같은 계정이면 프로가 자동 복원된다.
      ref.read(purchaseServiceProvider).init();
      // 미디어 알림(미니플레이어/잠금화면 컨트롤) 표시 권한. Android 13+만 런타임 권한이고
      // 거절해도 재생·동기화는 정상(알림 UI만 숨김). 영구 거절(2회 거절) 뒤엔 OS가 다이얼로그를
      // 더 안 띄워 설정 화면의 "알림 켜기"(openAppSettings)로만 재승인 가능 → cold-start에선
      // 설정 강제 이동 없이 요청만 한다. permission_handler 공식 패턴.
      unawaited(_requestNotificationPermissionIfNeeded());
    });
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    if (!Platform.isAndroid) return; // iOS 알림은 추후 라운드(audio_service 경유)
    // Android <13은 permission_handler가 자동 granted 반환 → isDenied=false라 통과.
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
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
