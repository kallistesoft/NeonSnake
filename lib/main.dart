import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/ad_service.dart';
import 'services/progress_store.dart';
import 'services/sound_service.dart';
import 'ui/home_screen.dart';
import 'ui/palette.dart';
import 'ui/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final progress = await ProgressStore.open();
  runApp(NeonSnakeApp(
    progress: progress,
    ads: const NoAdService(),
    sound: AudioSoundService(muted: progress.muted, persist: progress.setMuted),
  ));
}

class NeonSnakeApp extends StatelessWidget {
  const NeonSnakeApp({super.key, required this.progress, required this.ads, required this.sound});

  final ProgressStore progress;
  final AdService ads;
  final SoundService sound;

  @override
  Widget build(BuildContext context) {
    return Services(
      progress: progress,
      ads: ads,
      sound: sound,
      child: MaterialApp(
        title: 'Neon Snake',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: accent,
          scaffoldBackgroundColor: background,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
