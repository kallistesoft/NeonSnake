import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neon_snake/game/levels.dart';
import 'package:neon_snake/game/world.dart';

import 'bot.dart';

/// A level with the intro skipped, the snake placed by hand and no food.
World _world(int level, List<(int, int)> body, Dir dir) {
  final w = World(Run(level: level), rng: Random(1))..intro = 0;
  w.player = Snake([for (final (x, y) in body) w.at(x, y)], dir)..interval = 1 / w.speed;
  w.foods.clear();
  w.enemies.clear();
  return w;
}

/// Advances exactly one snake move.
void _move(World w, [int times = 1]) {
  for (var i = 0; i < times; i++) {
    w.update(1 / w.speed * 1.0001);
  }
}

void main() {
  test('a BFS autopilot clears levels 1–25, bosses included, and food is always reachable', () {
    for (var level = 1; level <= 25; level++) {
      final r = botPlay(World(Run(level: level), rng: Random(level)));
      expect(r.cleared, isTrue, reason: 'level $level never cleared');
      expect(r.unreachable, 0, reason: 'level $level spawned unreachable food');
      expect(r.deaths, lessThanOrEqualTo(10), reason: 'level $level cost the bot ${r.deaths} lives');
    }
  });

  test('quick double turns are buffered and play out on consecutive moves', () {
    final w = _world(1, [(10, 16), (10, 17), (10, 18), (10, 19)], Dir.up);
    w.turn(Dir.left);
    w.turn(Dir.down);
    _move(w);
    expect((w.cx(w.player.head), w.cy(w.player.head)), (9, 16));
    _move(w);
    expect((w.cx(w.player.head), w.cy(w.player.head)), (9, 17));
    expect(w.alive, isTrue);
  });

  test('reversing straight into yourself is ignored', () {
    final w = _world(1, [(10, 16), (10, 17), (10, 18), (10, 19)], Dir.up);
    w.turn(Dir.down);
    expect(w.queuedTurns, isEmpty);
    _move(w);
    expect((w.cx(w.player.head), w.cy(w.player.head)), (10, 15));
  });

  test('hitting a wall costs a life, then you respawn somewhere safe', () {
    final w = _world(1, [(10, 1), (10, 2), (10, 3), (10, 4)], Dir.up);
    _move(w);
    expect(w.alive, isFalse);
    expect(w.run.lives, 2);
    expect(w.events, contains(GameEvent.die));
    for (var i = 0; i < 120 && !w.alive; i++) {
      w.update(1 / 60);
    }
    expect(w.alive, isTrue);
    expect(w.player.body, hasLength(World.startLength));
    for (final c in w.player.body) {
      expect(w.blocked(c), isFalse);
    }
  });

  test('running into your own body costs a life', () {
    final w = _world(1, [(5, 10), (5, 9), (6, 9), (6, 10), (6, 11), (5, 11), (4, 11)], Dir.down);
    _move(w);
    expect(w.alive, isFalse);
  });

  test('losing the last life ends the game', () {
    final w = _world(1, [(10, 1), (10, 2), (10, 3), (10, 4)], Dir.up);
    w.run.lives = 1;
    _move(w);
    expect(w.over, isTrue);
    expect(w.events, contains(GameEvent.gameOver));
  });

  test('food grows you; poison shrinks you; reaching the target clears the level', () {
    final w = _world(1, [(10, 16), (10, 17), (10, 18), (10, 19)], Dir.up);
    w.foods.add(Food(w.at(10, 15), FoodKind.normal));
    _move(w, 2);
    expect(w.eaten, 1);
    expect(w.player.body, hasLength(5));
    w.foods
      ..clear()
      ..add(Food(w.at(10, 13), FoodKind.poison));
    _move(w);
    expect(w.player.body, hasLength(2));
    expect(w.events, contains(GameEvent.poison));

    w.eaten = w.target - 1;
    w.foods
      ..clear()
      ..add(Food(w.at(10, 12), FoodKind.normal));
    _move(w);
    for (var i = 0; i < 90; i++) {
      w.update(1 / 60);
    }
    expect(w.cleared, isTrue);
    expect(w.events, contains(GameEvent.levelClear));
    final before = w.run.score;
    final s = w.finish();
    expect(s.flawlessBonus, greaterThan(0));
    expect(w.run.score, before + s.bonus);
  });

  test('a charged ram hurts the boss; an uncharged one costs a life', () {
    final w = _world(10, [(10, 20), (10, 21), (10, 22), (10, 23)], Dir.up);
    final boss = w.boss!
      ..x = 9
      ..y = 16
      ..attackClock = 99;
    w.charge = World.chargeTime;
    _move(w, 2);
    expect(boss.hp, boss.maxHp - 1);
    expect(w.alive, isTrue);
    expect(w.charge, 0);
    expect(w.events, contains(GameEvent.bossHit));

    final w2 = _world(10, [(10, 20), (10, 21), (10, 22), (10, 23)], Dir.up);
    w2.boss!
      ..x = 9
      ..y = 16
      ..attackClock = 99;
    _move(w2, 2);
    expect(w2.alive, isFalse);
    expect(w2.boss!.hp, w2.boss!.maxHp);
  });

  test('portals carry you to their partner', () {
    final w = World(Run(level: 3), rng: Random(1))..intro = 0;
    expect(w.spec.twist, Twist.portals);
    final (a, b) = w.arena.portals.entries.map((e) => (e.key, e.value)).first;
    final body = [for (var k = 1; k <= 4; k++) w.at(w.cx(a), w.cy(a) + k)];
    w.player = Snake(body, Dir.up)..interval = 1 / w.speed;
    w.foods.clear();
    _move(w);
    expect(w.player.head, b);
    expect(w.alive, isTrue);
  });

  test('wraparound edges carry you across', () {
    final w = World(Run(level: 2), rng: Random(1))..intro = 0;
    expect(w.spec.wrap, isTrue);
    w.player = Snake([w.at(0, 0), w.at(1, 0), w.at(2, 0), w.at(3, 0)], Dir.left)..interval = 1 / w.speed;
    w.foods.clear();
    _move(w);
    expect(w.alive, isTrue);
    expect((w.cx(w.player.head), w.cy(w.player.head)), (w.cols - 1, 0));
  });

  test('a shrinking arena closes its outer ring after a warning', () {
    final w = World(Run(level: 6), rng: Random(1))..intro = 0;
    expect(w.spec.twist, Twist.shrink);
    w.ready = 1000; // hold the snake still
    w.eaten = (w.target / 5).ceil();
    w.update(1 / 60);
    expect(w.pendingRing, 1);
    expect(w.events, contains(GameEvent.warning));
    for (var i = 0; i < 200; i++) {
      w.update(1 / 60);
    }
    expect(w.closedRings, 1);
    expect(w.walls[w.at(1, 1)], isTrue);
    // Food never sits in a closed or closing ring.
    for (final f in w.foods) {
      expect(w.ringOf(f.cell), greaterThan(2));
    }
  });

  test('moving walls wait instead of crushing you', () {
    final w = World(Run(level: 4), rng: Random(1))..intro = 0;
    expect(w.spec.twist, Twist.sliders);
    final s = w.sliders.first;
    s.dir = 1;
    s.x = 3;
    w.sliderCells.clear();
    final ahead = s.x + s.lane.length; // the cell the wall moves into next
    w.player = Snake([w.at(ahead, s.lane.row), w.at(ahead, s.lane.row + 1), w.at(ahead, s.lane.row + 2)], Dir.up)
      ..interval = 1 / w.speed;
    w.ready = 1000;
    for (var i = 0; i < 120; i++) {
      w.update(1 / 60);
    }
    expect(s.x, 3);
    expect(w.alive, isTrue);
  });
}
