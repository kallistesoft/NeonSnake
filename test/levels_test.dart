import 'package:flutter_test/flutter_test.dart';
import 'package:neon_snake/game/levels.dart';

/// Free cells reachable from the first free cell.
int _connected(Arena a, {required bool wrap}) {
  final start = a.walls.indexOf(false);
  final seen = <int>{start};
  final queue = [start];
  for (var i = 0; i < queue.length; i++) {
    for (final n in Arena.neighbours(queue[i], a.cols, a.rows, wrap: wrap)) {
      if (!a.walls[n] && seen.add(n)) queue.add(n);
    }
  }
  return seen.length;
}

void main() {
  test('a boss every fifth level, cycling through all four', () {
    for (var n = 1; n <= 60; n++) {
      expect(LevelSpec.forLevel(n).isBoss, n % 5 == 0, reason: 'level $n');
    }
    expect({for (var n = 5; n <= 20; n += 5) LevelSpec.forLevel(n).boss}, BossKind.values.toSet());
    expect(LevelSpec.forLevel(25).boss, BossKind.wyrm);
    expect(LevelSpec.forLevel(25).tier, greaterThan(LevelSpec.forLevel(5).tier));
  });

  test('every regular level differs from the last, and none repeat for 30 regular levels', () {
    final seen = <(Layout, Twist)>{};
    LevelSpec? prev;
    for (var n = 1; n <= 37; n++) {
      final s = LevelSpec.forLevel(n);
      if (s.isBoss) continue;
      expect(seen.add((s.layout, s.twist)), isTrue, reason: 'level $n repeats a layout');
      if (prev != null) {
        expect(s.layout, isNot(prev.layout), reason: 'level $n');
        expect(s.twist, isNot(prev.twist), reason: 'level $n');
      }
      prev = s;
    }
    // Every layout and every twist shows up within the first 10 levels.
    final early = [for (var n = 1; n <= 10; n++) LevelSpec.forLevel(n)];
    expect(early.where((s) => !s.isBoss).map((s) => s.layout).toSet(), hasLength(Layout.values.length));
    expect(early.map((s) => s.twist).toSet(), Twist.values.toSet());
  });

  test('every level has its own arena', () {
    final arenas = <String>{};
    for (var n = 1; n <= 30; n++) {
      final s = LevelSpec.forLevel(n);
      if (s.isBoss) continue;
      final a = Arena.generate(s);
      expect(arenas.add(a.walls.map((w) => w ? '#' : '.').join()), isTrue, reason: 'level $n');
    }
  });

  test('difficulty never goes down', () {
    LevelSpec? prevRegular;
    for (var n = 2; n <= 80; n++) {
      final a = LevelSpec.forLevel(n - 1), b = LevelSpec.forLevel(n);
      expect(b.speed, greaterThanOrEqualTo(a.speed), reason: 'speed at $n');
      expect(b.density, greaterThanOrEqualTo(a.density), reason: 'density at $n');
      expect(b.poison, greaterThanOrEqualTo(a.poison), reason: 'poison at $n');
      if (!b.isBoss) {
        if (prevRegular != null) {
          expect(b.target, greaterThanOrEqualTo(prevRegular.target), reason: 'target at $n');
          expect(b.enemies, greaterThanOrEqualTo(prevRegular.enemies), reason: 'enemies at $n');
        }
        prevRegular = b;
      }
    }
    // Bosses are fought one on one; rival snakes roam the regular levels.
    expect([for (var n = 5; n <= 80; n += 5) LevelSpec.forLevel(n).enemies].every((e) => e == 0), isTrue);
    expect(LevelSpec.forLevel(25).speed, greaterThan(LevelSpec.forLevel(1).speed + 3));
    expect(LevelSpec.forLevel(24).target, greaterThan(LevelSpec.forLevel(1).target * 3));
  });

  test('checkpoints are the level after each boss', () {
    expect([1, 4, 5, 6, 10, 11, 14].map(LevelSpec.checkpointFor), [1, 1, 1, 6, 6, 11, 11]);
  });

  test('every arena is fully connected, walled unless it wraps, with sound portals and lanes', () {
    for (var n = 1; n <= 60; n++) {
      final s = LevelSpec.forLevel(n);
      final a = Arena.generate(s);
      final free = a.walls.where((w) => !w).length;
      expect(_connected(a, wrap: s.wrap), free, reason: 'level $n has a cut-off pocket');
      expect(free, greaterThan(a.cols * a.rows * 0.55), reason: 'level $n is too cramped');
      final border = [
        for (var x = 0; x < a.cols; x++) ...[x, (a.rows - 1) * a.cols + x],
        for (var y = 0; y < a.rows; y++) ...[y * a.cols, y * a.cols + a.cols - 1],
      ];
      expect(border.every((c) => a.walls[c]), !s.wrap, reason: 'level $n border');
      if (s.twist == Twist.portals) {
        expect(a.portals.length, greaterThanOrEqualTo(4), reason: 'level $n');
        a.portals.forEach((p, q) {
          expect(a.portals[q], p);
          expect(a.walls[p], isFalse);
        });
      } else {
        expect(a.portals, isEmpty);
      }
      if (s.twist == Twist.sliders) {
        expect(a.lanes, isNotEmpty);
        for (final lane in a.lanes) {
          for (var y = lane.row - 1; y <= lane.row + 1; y++) {
            for (var x = 1; x < a.cols - 1; x++) {
              expect(a.walls[y * a.cols + x], isFalse, reason: 'level $n lane $y');
            }
          }
        }
      }
      if (s.twist == Twist.shrink) {
        // Nothing but open floor where the walls will close in.
        final (l, t, r, b) = a.innerRect;
        for (var y = 1; y < a.rows - 1; y++) {
          for (var x = 1; x < a.cols - 1; x++) {
            if (x <= l || y <= t || x >= r || y >= b) expect(a.walls[y * a.cols + x], isFalse, reason: 'level $n ($x,$y)');
          }
        }
      }
    }
  });
}
