import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  runApp(ProviderScope(
    overrides: [
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
    child: const SynchorusApp(),
  ));
}

class SynchorusApp extends StatelessWidget {
  const SynchorusApp({super.key});

  @override
  Widget build(BuildContext context) {
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
