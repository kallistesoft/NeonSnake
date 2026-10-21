import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/levels.dart';
import '../game/world.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'ad_slot.dart';
import 'palette.dart';
import 'services.dart';
import 'world_painter.dart';

enum _Phase { playing, paused, cleared, over }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.startLevel, this.random});

  final int startLevel;

  /// Seeded in tests.
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Run _run = Run(level: widget.startLevel);
  late World _world = World(_run, rng: widget.random);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _frame = ValueNotifier(0);
  _Phase _phase = _Phase.playing;
  LevelSummary? _summary;
  bool _newBest = false;
  Offset _swipe = Offset.zero;

  late ProgressStore _progress;
  late AdService _ads;
  late SoundService _sound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = Services.of(context);
    _progress = services.progress;
    _ads = services.ads;
    _sound = services.sound;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) setState(() => _phase = _Phase.paused);
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    if (_phase != _Phase.playing) return;
    _world.update(dt);
    _handleEvents();
    _frame.value++;
  }

  void _handleEvents() {
    for (final e in _world.events) {
      switch (e) {
        case GameEvent.eat:
        case GameEvent.bit:
          _sound.play(Sfx.eat);
        case GameEvent.golden:
          _sound.play(Sfx.golden);
        case GameEvent.boost:
          _sound.play(Sfx.boost);
        case GameEvent.poison:
          _sound.play(Sfx.poison);
          HapticFeedback.lightImpact();
        case GameEvent.charge:
          _sound.play(Sfx.charge);
        case GameEvent.die:
          _sound.play(Sfx.die);
          HapticFeedback.heavyImpact();
        case GameEvent.enemyDown:
          _sound.play(Sfx.enemyDown);
        case GameEvent.bossHit:
          _sound.play(Sfx.bossHit);
          HapticFeedback.mediumImpact();
        case GameEvent.warning:
          _sound.play(Sfx.warning);
        case GameEvent.bossDown:
          _sound.play(Sfx.bossDown);
          HapticFeedback.heavyImpact();
        case GameEvent.levelClear:
          _onCleared();
        case GameEvent.gameOver:
          _onOver();
      }
    }
    _world.events.clear();
  }

  void _onCleared() {
    _sound.play(Sfx.levelClear);
    final next = _run.level + 1;
    _progress.reachLevel(next, LevelSpec.checkpointFor(next));
    if (_world.spec.isBoss) _progress.bossBeaten();
    setState(() {
      _summary = _world.finish();
      _phase = _Phase.cleared;
    });
  }

  Future<void> _onOver() async {
    _sound.play(Sfx.gameOver);
    setState(() => _phase = _Phase.over);
    await _progress.reachLevel(_run.level, LevelSpec.checkpointFor(_run.level));
    final best = await _progress.recordScore(_run.score);
    if (mounted) setState(() => _newBest = best);
  }

  bool _advancing = false;

  Future<void> _nextLevel() async {
    if (_phase != _Phase.cleared || _advancing) return;
    _advancing = true;
    await _ads.showInterstitial();
    _advancing = false;
    if (!mounted) return;
    setState(() {
      _run.level++;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
    });
  }

  Future<void> _revive() async {
    if (!await _ads.showRewarded() || !mounted) return;
    setState(() {
      _run
        ..revived = true
        ..lives = 2;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _retry() {
    setState(() {
      _run = Run(level: LevelSpec.checkpointFor(_run.level));
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _togglePause() {
    if (_phase == _Phase.playing) {
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.paused) {
      setState(() => _phase = _Phase.playing);
    }
  }

  static final _keyDirs = {
    LogicalKeyboardKey.arrowUp: Dir.up,
    LogicalKeyboardKey.keyW: Dir.up,
    LogicalKeyboardKey.arrowDown: Dir.down,
    LogicalKeyboardKey.keyS: Dir.down,
    LogicalKeyboardKey.arrowLeft: Dir.left,
    LogicalKeyboardKey.keyA: Dir.left,
    LogicalKeyboardKey.arrowRight: Dir.right,
    LogicalKeyboardKey.keyD: Dir.right,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) && _phase == _Phase.cleared) {
      _nextLevel();
      return KeyEventResult.handled;
    }
    final dir = _keyDirs[key];
    if (dir != null && _phase == _Phase.playing) {
      _world.turn(dir);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Swipes: every 18 px of drag along one axis is a turn, so an L-shaped
  /// swipe gives two quick turns without lifting your finger.
  void _onPan(DragUpdateDetails d) {
    if (_phase != _Phase.playing) return;
    _swipe += d.delta;
    if (_swipe.distance < 18) return;
    final dir = _swipe.dx.abs() > _swipe.dy.abs() ? (_swipe.dx > 0 ? Dir.right : Dir.left) : (_swipe.dy > 0 ? Dir.down : Dir.up);
    _world.turn(dir);
    _swipe = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _swipe = Offset.zero,
          onPanUpdate: _onPan,
          child: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListenableBuilder(
                      listenable: _frame,
                      builder: (context, _) => Column(
                        children: [
                          _hud(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                              child: Stack(
                                children: [
                                  Positioned.fill(child: CustomPaint(painter: WorldPainter(_world, repaint: _frame))),
                                  if (_phase == _Phase.playing) Positioned.fill(child: _banner()),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_phase != _Phase.playing) Positioned.fill(child: _overlay()),
            ],
          ),
        ),
      ),
    );
  }

  // ---- HUD ----

  Widget _hud() {
    final w = _world;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w800),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('pause'),
                    onPressed: _togglePause,
                    icon: const Icon(Icons.pause_rounded),
                    color: Colors.white70,
                    tooltip: 'Pause',
                  ),
                  Text('${_run.score}', key: const Key('score'), style: neon(20, color: Colors.white, spacing: 1)),
                  if (w.boost > 0) ...[
                    const SizedBox(width: 6),
                    Text('×2', style: neon(14, color: gold)),
                  ],
                  const Spacer(),
                  Text('LV ${_run.level}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  const SizedBox(width: 10),
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _run.lives ? accent : Colors.white12,
                        boxShadow: i < _run.lives ? [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 6)] : null,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: w.spec.isBoss ? _bossBar() : _foodMeter(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meter(String label, String value, double fraction, Color color, {Color? labelColor}) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(label, overflow: TextOverflow.ellipsis, style: neon(11, color: labelColor ?? color, spacing: 1.5)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), minHeight: 6, color: color, backgroundColor: Colors.white12),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _foodMeter() {
    final w = _world;
    return Column(
      children: [
        _meter('FOOD', '${min(w.eaten, w.target)}/${w.target}', w.eaten / w.target, foodColor, labelColor: Colors.white70),
        const SizedBox(height: 4),
        _effects(),
      ],
    );
  }

  Widget _bossBar() {
    final w = _world;
    final boss = w.boss!;
    final color = bossColors[boss.kind.index];
    return Column(
      children: [
        _meter(bossNames[boss.kind]!.toUpperCase(), '${boss.hp}/${boss.maxHp}', boss.hp / boss.maxHp, boss.enraged ? hot : color, labelColor: color),
        const SizedBox(height: 4),
        _effects(),
      ],
    );
  }

  /// Charge and boost timers, one line, always the same height.
  Widget _effects() {
    final w = _world;
    return SizedBox(
      height: 14,
      child: Row(
        children: [
          if (w.charge > 0) ...[
            Text('CHARGED · RAM IT', style: neon(10, color: charge, spacing: 1.5)),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(value: w.charge / World.chargeTime, minHeight: 3, color: charge, backgroundColor: Colors.white10),
            ),
          ] else if (w.boost > 0) ...[
            Text('BOOST ×2', style: neon(10, color: gold, spacing: 1.5)),
            const SizedBox(width: 8),
            Expanded(child: LinearProgressIndicator(value: w.boost / 5, minHeight: 3, color: gold, backgroundColor: Colors.white10)),
          ] else if (w.spec.isBoss && w.boss!.hp > 0)
            Text('EAT A CHARGE ORB', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: charge.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  static String _twistHint(LevelSpec s) => switch (s.twist) {
        Twist.none => '',
        Twist.wrap => 'Edges wrap around',
        Twist.portals => 'Portals link in pairs',
        Twist.sliders => 'Sliding walls · they wait for you',
        Twist.shrink => 'The arena closes in as you eat',
      };

  /// Level intro, boss warning, respawn and closing-wall notices.
  Widget _banner() {
    final w = _world;
    final spec = w.spec;
    if (w.intro > 0) {
      if (spec.isBoss) {
        final on = (w.time * 3).floor().isEven;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('WARNING', style: neon(34, color: on ? hot : hot.withValues(alpha: 0.3), spacing: 8)),
              const SizedBox(height: 8),
              Text(spec.name.toUpperCase(), style: neon(20, color: bossColors[spec.boss!.index], spacing: 4)),
              const SizedBox(height: 10),
              _hint(bossHints[spec.boss]!),
            ],
          ),
        );
      }
      final fade = (w.intro / 0.4).clamp(0.0, 1.0);
      return Center(
        child: Opacity(
          opacity: fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('LEVEL ${spec.number}', style: neon(34, spacing: 6)),
              const SizedBox(height: 6),
              Text(spec.name.toUpperCase(), textAlign: TextAlign.center, style: neon(14, color: Colors.white, spacing: 3)),
              const SizedBox(height: 8),
              _hint('Eat ${spec.target}'),
              if (_twistHint(spec).isNotEmpty) _hint(_twistHint(spec)),
              if (spec.enemies > 0) _hint('${spec.enemies == 1 ? 'A rival snake' : '${spec.enemies} rival snakes'} on the prowl', color: enemyColor),
              if (spec.number == 4) _hint('Purple pellets are poison', color: poison),
              if (spec.number == 2) _hint('Golden food is worth a fortune', color: gold),
              if (spec.number == 3) _hint('Lightning: speed boost, double points', color: charge),
            ],
          ),
        ),
      );
    }
    if (!w.alive && !w.over) {
      return Center(child: Text('${_run.lives} ${_run.lives == 1 ? 'LIFE' : 'LIVES'} LEFT', style: neon(22, color: hot, spacing: 4)));
    }
    if (w.alive && w.ready > 0) {
      return Center(child: Text('READY', style: neon(28, spacing: 8)));
    }
    if (w.pendingRing > 0 && w.ringWarn > 0) {
      return Align(
        alignment: const Alignment(0, -0.75),
        child: Text('WALLS CLOSING', style: neon(16, color: (w.time * 4).floor().isEven ? hot : hot.withValues(alpha: 0.4), spacing: 4)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _hint(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, letterSpacing: 0.5, color: color ?? Colors.white70, fontWeight: FontWeight.w700),
        ),
      );

  // ---- overlays ----

  Widget _overlay() {
    final panel = switch (_phase) {
      _Phase.paused => _pausePanel(),
      _Phase.cleared => _clearedPanel(),
      _Phase.over => _overPanel(),
      _Phase.playing => const SizedBox.shrink(),
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: panel),
          ),
        ),
      ),
    );
  }

  Widget _pausePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PAUSED', textAlign: TextAlign.center, style: neon(32, spacing: 6)),
        const SizedBox(height: 28),
        _button('Resume', _togglePause, primary: true),
        const SizedBox(height: 12),
        _button(_sound.muted ? 'Sound: off' : 'Sound: on', () async {
          await _sound.setMuted(!_sound.muted);
          setState(() {});
        }),
        const SizedBox(height: 12),
        _button('Quit to menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _clearedPanel() {
    final s = _summary!;
    final spec = _world.spec;
    final next = LevelSpec.forLevel(_run.level + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(spec.isBoss ? 'BOSS DEFEATED' : 'LEVEL ${spec.number} CLEAR',
            textAlign: TextAlign.center, style: neon(26, color: spec.isBoss ? gold : accent, spacing: 4)),
        if (spec.isBoss)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Checkpoint saved', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
        const SizedBox(height: 14),
        if (!spec.isBoss) _stat('Food eaten', '${s.eaten}'),
        _stat('Longest snake', '${s.longest}'),
        if (s.goldens > 0) _stat('Golden food', '${s.goldens}', color: gold),
        if (s.enemiesDown > 0) _stat('Rivals down', '${s.enemiesDown}'),
        _stat('Length bonus', '+${s.lengthBonus}'),
        if (s.flawlessBonus > 0) _stat('Flawless bonus', '+${s.flawlessBonus}', color: gold),
        const Divider(color: Colors.white24, height: 20),
        _stat('Score', '${_run.score}', big: true),
        const SizedBox(height: 16),
        const Center(child: AdSlot()),
        const SizedBox(height: 16),
        Text(
          next.isBoss ? 'BOSS AHEAD: ${next.name.toUpperCase()}' : 'NEXT · LEVEL ${next.number} · ${next.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: neon(12, color: next.isBoss ? hot : Colors.white70, spacing: 2),
        ),
        const SizedBox(height: 12),
        _button('Continue', _nextLevel, primary: true, key: const Key('continue')),
      ],
    );
  }

  Widget _overPanel() {
    final checkpoint = LevelSpec.checkpointFor(_run.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GAME OVER', textAlign: TextAlign.center, style: neon(34, color: hot, spacing: 6)),
        const SizedBox(height: 16),
        _stat('Level reached', '${_run.level}'),
        _stat('Score', '${_run.score}', big: true),
        if (_newBest) Text('NEW BEST', textAlign: TextAlign.center, style: neon(16, color: gold)),
        const SizedBox(height: 24),
        if (!_run.revived) ...[
          _button('Revive · watch an ad', _revive, primary: true, icon: Icons.play_circle_fill_rounded),
          const SizedBox(height: 12),
        ],
        _button('Retry from level $checkpoint', _retry, primary: _run.revived),
        const SizedBox(height: 12),
        _button('Menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _stat(String label, String value, {bool big = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.white60, fontSize: big ? 16 : 14)),
          const Spacer(),
          Text(value, style: big ? neon(22, color: color, spacing: 1) : TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = false, IconData? icon, Key? key}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 16);
    return primary
        ? FilledButton(
            key: key,
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: shape, padding: padding),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              shape: shape,
              padding: padding,
            ),
            child: child,
          );
  }
}
