import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neon_snake/main.dart';
import 'package:neon_snake/services/ad_service.dart';
import 'package:neon_snake/services/progress_store.dart';
import 'package:neon_snake/services/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('start a game from the home screen, steer, pause and quit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.open();
    final sound = NoSound();
    await tester.pumpWidget(NeonSnakeApp(progress: progress, ads: const NoAdService(), sound: sound));
    expect(find.text('SNAKE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('LEVEL 1'), findsOneWidget);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('LEVEL 1'), findsNothing); // intro banner has gone
    expect(find.byKey(const Key('score')), findsOneWidget);
    expect(find.text('FOOD'), findsOneWidget);

    // Keyboard and swipe turns are accepted.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(CustomPaint).last, const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('Quit to menu'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the home animation never settles
    expect(find.text('SNAKE'), findsOneWidget);
  });
}
