import 'package:flutter/widgets.dart';

import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';

/// App-wide services, available to every screen.
class Services extends InheritedWidget {
  const Services({super.key, required this.progress, required this.ads, required this.sound, required super.child});

  final ProgressStore progress;
  final AdService ads;
  final SoundService sound;

  static Services of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Services>()!;

  @override
  bool updateShouldNotify(Services old) => old.progress != progress || old.ads != ads || old.sound != sound;
}
