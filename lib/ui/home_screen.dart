import 'dart:math';

import 'package:flutter/material.dart';

import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'game_screen.dart';
import 'palette.dart';
import 'services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<void> _play(int level) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(startLevel: level)));
    if (mounted) setState(() {}); // refresh best score and checkpoint
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final ProgressStore progress = services.progress;
    final SoundService sound = services.sound;
    final checkpoint = progress.checkpoint;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _DemoPainter(_clock))),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('NEON', textAlign: TextAlign.center, style: neon(64, color: foodColor, spacing: 14)),
                      Text('SNAKE', textAlign: TextAlign.center, style: neon(64, spacing: 12)),
                      const SizedBox(height: 8),
                      Text('Grow fast. Turn faster.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), letterSpacing: 1)),
                      const SizedBox(height: 36),
                      Row(
                        children: [
                          _Stat(label: 'BEST SCORE', value: '${progress.bestScore}'),
                          _Stat(label: 'BEST LEVEL', value: '${progress.bestLevel}'),
                          _Stat(label: 'BOSSES', value: '${progress.bossesBeaten}'),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (checkpoint > 1) ...[
                        FilledButton(
                          key: const Key('continue-run'),
                          onPressed: () => _play(checkpoint),
                          style: _primary,
                          child: Text('CONTINUE · LEVEL $checkpoint', style: _label),
                        ),
                        const SizedBox(height: 12),
                      ],
                      (checkpoint > 1 ? OutlinedButton.new : FilledButton.new)(
                        key: const Key('play'),
                        onPressed: () => _play(1),
                        style: checkpoint > 1 ? _secondary : _primary,
                        child: Text(checkpoint > 1 ? 'NEW GAME' : 'PLAY', style: _label),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Swipe to turn · arrow keys or WASD on desktop\n'
                        'Eat to fill the meter · dodge walls, rivals, yourself\n'
                        'A boss every 5 levels: eat a charge orb, then ram it\n'
                        'Esc or P to pause',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), height: 1.6, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: IconButton(
                          tooltip: sound.muted ? 'Sound off' : 'Sound on',
                          onPressed: () async {
                            await sound.setMuted(!sound.muted);
                            setState(() {});
                          },
                          icon: Icon(sound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white54),
                        ),
                      ),
                      Text('Kallistesoft', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _label = TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2);
  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  static final _primary = FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
  static final _secondary = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white30),
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: neon(22, color: Colors.white, spacing: 1)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

/// A faint grid with two neon snakes chasing round a loop behind the menu.
class _DemoPainter extends CustomPainter {
  _DemoPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(colors: [levelTint(160), background], radius: 1.1).createShader(Offset.zero & size),
    );
    const cell = 22.0;
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.04);
    for (var x = 0.0; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Snakes walk a rectangular loop, cell by cell.
    final cols = (size.width / cell).floor(), rows = (size.height / cell).floor();
    final loop = <Offset>[];
    const inset = 1;
    for (var x = inset; x < cols - inset; x++) {
      loop.add(Offset(x.toDouble(), inset.toDouble()));
    }
    for (var y = inset; y < rows - inset; y++) {
      loop.add(Offset((cols - inset).toDouble(), y.toDouble()));
    }
    for (var x = cols - inset; x > inset; x--) {
      loop.add(Offset(x.toDouble(), (rows - inset).toDouble()));
    }
    for (var y = rows - inset; y > inset; y--) {
      loop.add(Offset(inset.toDouble(), y.toDouble()));
    }
    if (loop.isEmpty) return;
    final t = anim.value * 60 * 7; // cells travelled
    for (final (offset, color, length) in [(0.0, accent, 14), (loop.length / 2, enemyColor, 9)]) {
      final head = t + offset;
      final pts = <Offset>[
        for (var i = 0; i <= length; i++)
          (Offset.lerp(loop[(head - i).floor() % loop.length], loop[((head - i).floor() + 1) % loop.length], (head - i) - (head - i).floor())! +
                  const Offset(0.5, 0.5)) *
              cell,
      ];
      for (var i = pts.length - 2; i >= 0; i--) {
        final fade = 1 - i / (length + 1);
        canvas.drawLine(pts[i], pts[i + 1], Paint()
          ..color = color.withValues(alpha: 0.2 * fade)
          ..strokeWidth = cell
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.drawLine(pts[i], pts[i + 1], Paint()
          ..color = color.withValues(alpha: 0.45 * fade)
          ..strokeWidth = cell * 0.6
          ..strokeCap = StrokeCap.round);
      }
      canvas.drawCircle(pts.first, cell * 0.38, Paint()..color = color.withValues(alpha: 0.6));
    }
    final food = (const Offset(0.5, 0.5) + Offset(cols / 2, inset.toDouble())) * cell;
    canvas.drawCircle(food, cell * 0.25 * (1 + sin(anim.value * 400) * 0.1), Paint()..color = foodColor.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_DemoPainter old) => false;
}
