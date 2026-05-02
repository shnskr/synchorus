import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'measurement/auto_measure_screen.dart';
import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'services/audio_handler.dart';

// 측정 자동화 모드 — `--dart-define=AUTO_MEASURE_MODE=host|guest` 빌드 시 활성화.
// default('') = 통상 앱 실행. 출시 빌드는 dart-define 없이 빌드되므로 영향 0.
const String _autoMeasureMode = String.fromEnvironment('AUTO_MEASURE_MODE');
const int _autoMeasureDurationSec =
    int.fromEnvironment('AUTO_MEASURE_DURATION_SEC', defaultValue: 720);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: _autoMeasureMode.isNotEmpty
          ? AutoMeasureScreen(
              mode: _autoMeasureMode,
              durationSec: _autoMeasureDurationSec,
            )
          : const HomeScreen(),
    );
  }
}
