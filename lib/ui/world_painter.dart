import 'dart:math';

import 'package:flutter/material.dart';

import '../game/levels.dart';
import '../game/world.dart';
import 'palette.dart';

/// Maps the arena grid into the widget: square cells, centred across and
/// pinned to the top, leaving any spare room below as a swipe area.
class GridTransform {
  GridTransform(Size size, int cols, int rows)
      : cell = min(size.width / cols, size.height / rows),
        origin = Offset((size.width - cols * min(size.width / cols, size.height / rows)) / 2, 0);

  final double cell;
  final Offset origin;
}

class WorldPainter extends CustomPainter {
  WorldPainter(this.world, {required Listenable repaint}) : super(repaint: repaint);

  final World world;

  static const _blur = MaskFilter.blur(BlurStyle.normal, 6);

  late double _c;

  Offset _center(int cell) => Offset((world.cx(cell) + 0.5) * _c, (world.cy(cell) + 0.5) * _c);

  @override
  void paint(Canvas canvas, Size size) {
    final w = world;
    final t = GridTransform(size, w.cols, w.rows);
    _c = t.cell;
    canvas.save();
    canvas.translate(t.origin.dx, t.origin.dy);
    if (w.shake > 0) {
      final r = Random(w.time.hashCode);
      canvas.translate((r.nextDouble() - 0.5) * w.shake * _c / 20, (r.nextDouble() - 0.5) * w.shake * _c / 20);
    }
    _floor(canvas);
    _walls(canvas);
    _portals(canvas);
    _sliders(canvas);
    _beams(canvas, warnOnly: true);
    _foods(canvas);
    if (w.boss != null) _boss(canvas, w.boss!);
    for (final e in w.enemies) {
      if (e.dead) continue;
      _snake(canvas, e, e.progress, e.hatchling ? const Color(0xFFFFC24D) : enemyColor, width: e.hatchling ? 0.55 : 0.68);
    }
    if (w.alive && (w.ready <= 0 || (w.time * 8).floor().isEven)) _player(canvas);
    _sparks(canvas);
    _beams(canvas, warnOnly: false);
    _particles(canvas);
    canvas.restore();
  }

  void _floor(Canvas canvas) {
    final w = world;
    final rect = Rect.fromLTWH(0, 0, w.cols * _c, w.rows * _c);
    final tint = levelTint(w.spec.hue);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [tint, background], radius: 0.9).createShader(rect),
    );
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var x = 1; x < w.cols; x++) {
      canvas.drawLine(Offset(x * _c, 0), Offset(x * _c, rect.height), grid);
    }
    for (var y = 1; y < w.rows; y++) {
      canvas.drawLine(Offset(0, y * _c), Offset(rect.width, y * _c), grid);
    }
    if (w.spec.wrap) {
      // Open edges: a dashed glowing frame.
      final dash = Paint()
        ..color = wallColor(w.spec.hue).withValues(alpha: 0.5)
        ..strokeWidth = 2;
      final phase = (w.time * 2) % 1;
      for (var i = -1.0; i < max(w.cols, w.rows); i += 1) {
        final a = (i + phase) * _c, b = a + _c * 0.45;
        if (a < rect.width) {
          canvas.drawLine(Offset(max(0, a), 1), Offset(min(rect.width, b), 1), dash);
          canvas.drawLine(Offset(max(0, a), rect.height - 1), Offset(min(rect.width, b), rect.height - 1), dash);
        }
        if (a < rect.height) {
          canvas.drawLine(Offset(1, max(0, a)), Offset(1, min(rect.height, b)), dash);
          canvas.drawLine(Offset(rect.width - 1, max(0, a)), Offset(rect.width - 1, min(rect.height, b)), dash);
        }
      }
    }
  }

  void _walls(Canvas canvas) {
    final w = world;
    final wall = wallColor(w.spec.hue);
    final path = Path(), closed = Path();
    for (var c = 0; c < w.cols * w.rows; c++) {
      if (!w.walls[c]) continue;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(w.cx(c) * _c + 1, w.cy(c) * _c + 1, _c - 2, _c - 2),
        Radius.circular(_c * 0.2),
      );
      (w.closedCells.contains(c) ? closed : path).addRRect(r);
    }
    canvas.drawPath(path, Paint()
      ..color = wall.withValues(alpha: 0.55)
      ..maskFilter = _blur);
    canvas.drawPath(path, Paint()..color = Color.lerp(wall, background, 0.55)!);
    canvas.drawPath(path, Paint()
      ..color = wall.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    if (w.closedCells.isNotEmpty) {
      canvas.drawPath(closed, Paint()..color = hot.withValues(alpha: 0.25));
      canvas.drawPath(closed, Paint()
        ..color = hot.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
    if (w.pendingCells.isNotEmpty) {
      final on = w.ringWarn <= 0 || (w.time * 6).floor().isEven;
      final p = Paint()
        ..color = hot.withValues(alpha: on ? 0.55 : 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final c in w.pendingCells) {
        canvas.drawRect(Rect.fromLTWH(w.cx(c) * _c + 2, w.cy(c) * _c + 2, _c - 4, _c - 4), p);
      }
    }
  }

  static const _portalColors = [charge, Color(0xFFFF4FD8), gold];

  void _portals(Canvas canvas) {
    final w = world;
    final seen = <int>{};
    var pair = 0;
    for (final MapEntry(key: a, value: b) in w.arena.portals.entries) {
      if (!seen.add(a) || !seen.add(b)) continue;
      final color = _portalColors[pair++ % _portalColors.length];
      for (final c in [a, b]) {
        final o = _center(c);
        canvas.drawCircle(o, _c * 0.6, Paint()
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = _blur);
        final arc = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _c * 0.12
          ..strokeCap = StrokeCap.round;
        for (var k = 0; k < 3; k++) {
          canvas.drawArc(Rect.fromCircle(center: o, radius: _c * 0.42), w.time * 3 + k * 2 * pi / 3, 1.2, false, arc);
        }
        canvas.drawCircle(o, _c * 0.16, Paint()..color = Colors.white);
      }
    }
  }

  void _sliders(Canvas canvas) {
    final w = world;
    for (final s in w.sliders) {
      final rect = Rect.fromLTWH(s.x * _c + 1, s.lane.row * _c + 2, s.lane.length * _c - 2, _c - 4);
      final r = RRect.fromRectAndRadius(rect, Radius.circular(_c * 0.3));
      canvas.drawRRect(r, Paint()
        ..color = hot.withValues(alpha: 0.6)
        ..maskFilter = _blur);
      canvas.drawRRect(r, Paint()..color = const Color(0xFF3A0B1A));
      canvas.drawRRect(r, Paint()
        ..color = hot
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      // Chevrons pointing the way it slides.
      final chev = Paint()
        ..color = hot.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var k = 0; k < s.lane.length; k++) {
        final cx = (s.x + k + 0.5) * _c, cy = (s.lane.row + 0.5) * _c;
        final d = s.dir * _c * 0.15;
        canvas.drawPath(
          Path()
            ..moveTo(cx - d, cy - _c * 0.2)
            ..lineTo(cx + d, cy)
            ..lineTo(cx - d, cy + _c * 0.2),
          chev,
        );
      }
    }
  }

  void _foods(Canvas canvas) {
    final w = world;
    for (final f in w.foods) {
      final o = _center(f.cell);
      final color = colorFor(f.kind);
      final pulse = 1 + sin(w.time * 6 + f.cell) * 0.08;
      // Pop in.
      final grow = min(1.0, f.age * 5);
      // Blink when about to vanish.
      if (f.ttl < 1.5 && (f.ttl * 8).floor().isEven) continue;
      final r = _c * 0.32 * pulse * grow;
      canvas.drawCircle(o, r * 2, Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = _blur);
      switch (f.kind) {
        case FoodKind.normal:
          canvas.drawCircle(o, r, Paint()..color = color);
          canvas.drawCircle(o.translate(-r * 0.3, -r * 0.3), r * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.8));
        case FoodKind.golden:
          _star(canvas, o, r * 1.35, color, w.time * 2);
          canvas.drawArc(
            Rect.fromCircle(center: o, radius: _c * 0.62),
            -pi / 2,
            2 * pi * (f.ttl / f.life).clamp(0, 1),
            false,
            Paint()
              ..color = gold.withValues(alpha: 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        case FoodKind.boost:
          final bolt = Path()
            ..moveTo(o.dx + r * 0.3, o.dy - r * 1.2)
            ..lineTo(o.dx - r * 0.6, o.dy + r * 0.15)
            ..lineTo(o.dx - r * 0.05, o.dy + r * 0.15)
            ..lineTo(o.dx - r * 0.3, o.dy + r * 1.2)
            ..lineTo(o.dx + r * 0.6, o.dy - r * 0.15)
            ..lineTo(o.dx + r * 0.05, o.dy - r * 0.15)
            ..close();
          canvas.drawPath(bolt, Paint()..color = color);
        case FoodKind.poison:
          canvas.drawCircle(o, r, Paint()..color = const Color(0xFF2A0F40));
          canvas.drawCircle(o, r, Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
          final x = Paint()
            ..color = color
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round;
          final k = r * 0.45;
          canvas.drawLine(o.translate(-k, -k), o.translate(k, k), x);
          canvas.drawLine(o.translate(k, -k), o.translate(-k, k), x);
        case FoodKind.orb:
          final big = r * 1.4;
          canvas.drawCircle(o, big, Paint()..color = color.withValues(alpha: 0.5));
          canvas.drawCircle(o, big * 0.55, Paint()..color = Colors.white);
          canvas.drawArc(
            Rect.fromCircle(center: o, radius: big * 1.5),
            w.time * 4,
            4,
            false,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        case FoodKind.bit:
          canvas.drawCircle(o, r * 0.6, Paint()..color = color);
      }
    }
  }

  void _star(Canvas canvas, Offset o, double r, Color color, double spin) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = spin + i * pi / 5 - pi / 2;
      final rr = i.isEven ? r : r * 0.45;
      final p = o + Offset(cos(a) * rr, sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  bool _adjacent(int a, int b) => (world.cx(a) - world.cx(b)).abs() + (world.cy(a) - world.cy(b)).abs() == 1;

  /// The snake's centre line: the head slid part-way into its new cell, every
  /// cell centre in between, and the tail slid part-way out of its old cell.
  List<Offset> _points(Snake s, double t) {
    final body = s.body, prev = s.prev;
    if (body.isEmpty) return const [];
    final pts = <Offset>[];
    final from = prev.isEmpty ? body.first : prev.first;
    pts.add(_adjacent(from, body.first) ? Offset.lerp(_center(from), _center(body.first), t)! : _center(body.first));
    for (var i = 1; i < body.length; i++) {
      pts.add(_center(body[i]));
    }
    if (prev.isNotEmpty && body.length > 1 && _adjacent(prev.last, body.last) && !body.contains(prev.last)) {
      pts.add(Offset.lerp(_center(prev.last), _center(body.last), t)!);
    }
    return pts;
  }

  void _snake(Canvas canvas, Snake s, double t, Color color, {double width = 0.7, Color? glow}) {
    if (s.body.isEmpty) return;
    final pts = _points(s, t);
    final n = pts.length;
    final glowPaint = Paint()
      ..color = (glow ?? color).withValues(alpha: 0.45)
      ..strokeWidth = _c * width * 1.6
      ..strokeCap = StrokeCap.round
      ..maskFilter = _blur;
    final body = Paint()
      ..strokeWidth = _c * width
      ..strokeCap = StrokeCap.round;
    bool joined(int i) => (pts[i] - pts[i + 1]).distance <= _c * 1.05;
    for (var i = 0; i + 1 < n; i++) {
      if (joined(i)) canvas.drawLine(pts[i], pts[i + 1], glowPaint);
    }
    for (var i = n - 2; i >= 0; i--) {
      body.color = Color.lerp(color, Color.lerp(color, background, 0.6), i / max(1, n - 1))!;
      if (joined(i)) {
        canvas.drawLine(pts[i], pts[i + 1], body);
      } else {
        canvas.drawCircle(pts[i + 1], _c * width / 2, body);
      }
    }
    final head = pts.first;
    canvas.drawCircle(head, _c * width * 0.62, Paint()..color = Color.lerp(color, Colors.white, 0.35)!);
    final d = s.dir;
    final fwd = Offset(d.dx.toDouble(), d.dy.toDouble()) * (_c * 0.14);
    final side = Offset(-d.dy.toDouble(), d.dx.toDouble()) * (_c * 0.17);
    for (final sgn in [-1.0, 1.0]) {
      final e = head + fwd + side * sgn;
      canvas.drawCircle(e, _c * 0.1, Paint()..color = background);
      canvas.drawCircle(e + fwd * 0.3, _c * 0.04, Paint()..color = Colors.white);
    }
  }

  void _player(Canvas canvas) {
    final w = world;
    final charged = w.charge > 0;
    final flicker = charged && w.charge < 2 && (w.time * 10).floor().isEven;
    final color = charged && !flicker ? Color.lerp(accent, charge, 0.6 + sin(w.time * 12) * 0.3)! : accent;
    if (charged) {
      for (final p in _points(w.player, w.progress).take(1)) {
        canvas.drawCircle(p, _c * (1.1 + sin(w.time * 10) * 0.15), Paint()
          ..color = charge.withValues(alpha: 0.35)
          ..maskFilter = _blur);
      }
    }
    _snake(canvas, w.player, w.progress, color, glow: charged ? charge : (w.boost > 0 ? gold : null), width: 0.74);
    if (w.ready > 0 || w.intro > 0) {
      // Direction hint while frozen.
      final h = _center(w.player.head);
      final d = Offset(w.player.dir.dx.toDouble(), w.player.dir.dy.toDouble());
      final a = Paint()
        ..color = accent.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var k = 1; k <= 2; k++) {
        final tip = h + d * (_c * (0.6 + k * 0.55));
        final s = Offset(-d.dy, d.dx) * (_c * 0.25);
        canvas.drawPath(Path()
          ..moveTo((tip - d * (_c * 0.25) + s).dx, (tip - d * (_c * 0.25) + s).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((tip - d * (_c * 0.25) - s).dx, (tip - d * (_c * 0.25) - s).dy), a);
      }
    }
  }

  void _boss(Canvas canvas, Boss b) {
    final w = world;
    if (!b.present) return;
    final color = b.flash > 0 && (b.flash * 20).floor().isEven ? Colors.white : bossColors[b.kind.index];
    if (b.wyrm != null) {
      _snake(canvas, b.wyrm!, b.wyrm!.progress, color, width: 0.92);
      // Horns.
      final pts = _points(b.wyrm!, b.wyrm!.progress);
      final d = b.wyrm!.dir;
      final side = Offset(-d.dy.toDouble(), d.dx.toDouble());
      final back = Offset(-d.dx.toDouble(), -d.dy.toDouble());
      final horn = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final s in [-1.0, 1.0]) {
        final base = pts.first + side * (s * _c * 0.35);
        canvas.drawLine(base, base + (back + side * s) * (_c * 0.45), horn);
      }
      return;
    }
    final rect = Rect.fromLTWH(b.x * _c + 2, b.y * _c + 2, Boss.size * _c - 4, Boss.size * _c - 4);
    final o = rect.center;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(_c * 0.6));
    final pulse = sin(w.time * 5) * 0.5 + 0.5;
    canvas.drawRRect(rr.inflate(4), Paint()
      ..color = color.withValues(alpha: 0.45 + pulse * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawRRect(rr, Paint()..color = Color.lerp(color, background, 0.75)!);
    canvas.drawRRect(rr, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    final R = rect.width / 2;
    switch (b.kind) {
      case BossKind.sentinel:
        // An eye that tracks you; the iris goes red while a beam charges.
        var look = Offset.zero;
        if (w.alive) {
          final v = _center(w.player.head) - o;
          if (v.distance > 0) look = v / v.distance * (R * 0.25);
        }
        canvas.drawOval(Rect.fromCenter(center: o, width: R * 1.5, height: R * 1.0), Paint()..color = const Color(0xFFFFE8E8));
        final firing = w.beams.isNotEmpty;
        canvas.drawCircle(o + look, R * 0.34, Paint()..color = firing ? hot : color);
        canvas.drawCircle(o + look, R * 0.14, Paint()..color = background);
      case BossKind.brood:
        // A clutch of eggs pulsing in a hex.
        for (var k = 0; k < 6; k++) {
          final a = k * pi / 3 + w.time * 0.6;
          final p = o + Offset(cos(a), sin(a)) * (R * 0.5);
          canvas.drawCircle(p, R * (0.2 + 0.04 * sin(w.time * 4 + k)), Paint()..color = color.withValues(alpha: 0.85));
        }
        canvas.drawCircle(o, R * 0.28, Paint()..color = Colors.white.withValues(alpha: 0.9));
        canvas.drawCircle(o, R * 0.14, Paint()..color = hot);
      case BossKind.pulsar:
        // Rings that wind up before each burst.
        final wind = (1 - (b.attackClock / 0.8).clamp(0.0, 1.0));
        for (var k = 0; k < 3; k++) {
          final ph = (w.time * 1.5 + k / 3) % 1;
          canvas.drawCircle(o, R * (0.2 + ph * 0.75), Paint()
            ..color = color.withValues(alpha: (1 - ph) * 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
        canvas.drawCircle(o, R * (0.25 + wind * 0.2), Paint()..color = Color.lerp(color, Colors.white, wind)!);
      case BossKind.wyrm:
        break;
    }
    if (w.charge > 0) {
      // Show it's vulnerable.
      final on = (w.time * 6).floor().isEven;
      canvas.drawRRect(rr.inflate(3), Paint()
        ..color = charge.withValues(alpha: on ? 0.9 : 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  void _beams(Canvas canvas, {required bool warnOnly}) {
    final w = world;
    for (final b in w.beams) {
      final live = b.live;
      if (warnOnly == live) continue;
      final rect = b.horizontal
          ? Rect.fromLTWH(0, b.line * _c, w.cols * _c, _c)
          : Rect.fromLTWH(b.line * _c, 0, _c, w.rows * _c);
      if (!live) {
        final on = (w.time * 10).floor().isEven;
        canvas.drawRect(rect, Paint()..color = hot.withValues(alpha: on ? 0.22 : 0.08));
        final mid = Paint()
          ..color = hot.withValues(alpha: 0.7)
          ..strokeWidth = 1;
        if (b.horizontal) {
          canvas.drawLine(Offset(0, rect.center.dy), Offset(rect.right, rect.center.dy), mid);
        } else {
          canvas.drawLine(Offset(rect.center.dx, 0), Offset(rect.center.dx, rect.bottom), mid);
        }
      } else {
        canvas.drawRect(rect.inflate(_c * 0.3), Paint()
          ..color = hot.withValues(alpha: 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawRect(rect.deflate(_c * 0.15), Paint()..color = const Color(0xFFFFE0E8));
      }
    }
  }

  void _sparks(Canvas canvas) {
    final w = world;
    for (final s in w.sparks) {
      final now = Offset((s.x + 0.5) * _c, (s.y + 0.5) * _c);
      final was = s.px < 0 ? now : Offset((s.px + 0.5) * _c, (s.py + 0.5) * _c);
      final p = Offset.lerp(was, now, (s.clock / w.sparkInterval).clamp(0.0, 1.0))!;
      canvas.drawLine(p - (now - was) * 0.8, p, Paint()
        ..color = bossColors[BossKind.pulsar.index].withValues(alpha: 0.6)
        ..strokeWidth = _c * 0.3
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(p, _c * 0.32, Paint()
        ..color = const Color(0xFFFF4FD8).withValues(alpha: 0.6)
        ..maskFilter = _blur);
      canvas.drawCircle(p, _c * 0.2, Paint()..color = Colors.white);
    }
  }

  void _particles(Canvas canvas) {
    final paint = Paint();
    for (final p in world.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      paint.color = particleColors[p.color].withValues(alpha: a);
      final s = _c * (0.12 + a * 0.12);
      canvas.drawRect(Rect.fromCenter(center: Offset(p.x * _c, p.y * _c), width: s, height: s), paint);
    }
  }

  @override
  bool shouldRepaint(WorldPainter old) => old.world != world;
}
