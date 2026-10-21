import 'dart:math';

import 'levels.dart';

enum GameEvent { eat, golden, boost, poison, bit, charge, die, enemyDown, bossHit, warning, bossDown, levelClear, gameOver }

enum FoodKind { normal, golden, boost, poison, orb, bit }

/// What carries over from one level to the next.
class Run {
  Run({this.level = 1, this.score = 0, this.lives = 3});

  int level;
  int score;
  int lives;

  /// One rewarded revive per run.
  bool revived = false;
}

class Food {
  Food(this.cell, this.kind, {this.life = double.infinity}) : ttl = life;

  int cell;
  final FoodKind kind;

  /// Seconds it stays on the board, and seconds left.
  final double life;
  double ttl;
  double age = 0;

  /// Food that counts toward the level target.
  bool get counts => kind == FoodKind.normal || kind == FoodKind.golden || kind == FoodKind.boost;
}

/// A snake: the player's, an enemy, or the Wyrm boss. Body is head first.
class Snake {
  Snake(this.body, this.dir, {this.interval = 0.15, this.maxLength = 1 << 20}) : prev = List.of(body);

  List<int> body;

  /// Body before the last move, for smooth drawing between moves.
  List<int> prev;
  Dir dir;
  int grow = 0;
  final int maxLength;

  /// Seconds per move, and time since the last one.
  double interval;
  double clock = 0;

  bool dead = false;
  double respawn = 0;

  /// Spawned by the Brood Queen: hunts the player, never respawns.
  bool hatchling = false;

  int get head => body.first;
  double get progress => (clock / interval).clamp(0.0, 1.0);
}

class Boss {
  Boss(this.kind, this.maxHp) : hp = maxHp;

  final BossKind kind;
  final int maxHp;
  int hp;

  /// Top-left of the 3×3 body (Sentinel, Brood Queen, Pulsar).
  int x = 0, y = 0;

  /// The Wyrm's body.
  Snake? wyrm;

  /// Blinked out after a hit; reappears elsewhere when this runs out.
  double hidden = 0;
  double flash = 0;
  double moveClock = 0;
  double attackClock = 3;
  int bursts = 0;

  static const size = 3;

  bool get present => hidden <= 0 && hp > 0;
  bool get enraged => hp <= maxHp / 2;
}

/// A Sentinel laser across a whole row or column: harmless while [warn] counts down.
class Beam {
  Beam({required this.horizontal, required this.line, required this.warn});

  final bool horizontal;
  final int line;
  double warn;
  double active = 0.45;

  bool get live => warn <= 0 && active > 0;
}

/// A Pulsar spark: flies in a straight line, one cell per step.
class Spark {
  Spark(this.x, this.y, this.dx, this.dy);

  int x, y;
  final int dx, dy;
  int px = -1, py = -1;
  double clock = 0;
  bool dead = false;
}

class Slider {
  Slider(this.lane, this.x);

  final Lane lane;
  int x;
  int dir = 1;
  int prevX = -1;
  double clock = 0;
}

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color) : maxLife = life;

  /// In cell units.
  double x, y, vx, vy, life;
  final double maxLife;

  /// Index into the particle palette.
  final int color;
}

/// End-of-level numbers for the break screen.
class LevelSummary {
  const LevelSummary({
    required this.eaten,
    required this.longest,
    required this.deaths,
    required this.goldens,
    required this.enemiesDown,
    required this.flawlessBonus,
    required this.lengthBonus,
  });

  final int eaten, longest, deaths, goldens, enemiesDown;
  final int flawlessBonus, lengthBonus;
  int get bonus => flawlessBonus + lengthBonus;
}

/// Particle colour indices.
abstract final class Pc {
  static const player = 0, food = 1, golden = 2, poison = 3, enemy = 4, boss = 5, white = 6, charge = 7;
}

/// One level in play: a pure, deterministic-per-seed simulation on a grid.
/// The UI feeds turns, calls [update] every frame and draws the state.
class World {
  World(Run run, {Random? rng}) : this._(run, LevelSpec.forLevel(run.level), rng ?? Random());

  World._(this.run, this.spec, this.rng)
      : arena = Arena.generate(spec),
        cols = Arena.defaultCols,
        rows = Arena.defaultRows {
    walls = List.of(arena.walls);
    _setUp();
  }

  static const startLength = 4;
  static const respawnDelay = 1.3;
  static const readyDelay = 0.8;
  static const chargeTime = 8.0;
  static const introTime = 1.6;
  static const bossIntroTime = 2.6;

  final Run run;
  final LevelSpec spec;
  final Random rng;
  final Arena arena;
  final int cols, rows;

  /// Current walls: the arena's, plus rings closed by a shrinking arena.
  late final List<bool> walls;

  double time = 0;

  /// Everything holds still while the level banner is up.
  double intro = 0;

  late Snake player;
  bool alive = false;
  double respawnTimer = 0;

  /// Frozen after a respawn so you can get your bearings.
  double ready = 0;
  final _turns = <Dir>[];

  final foods = <Food>[];
  final enemies = <Snake>[];
  final sliders = <Slider>[];
  final sliderCells = <int>{};
  final beams = <Beam>[];
  final sparks = <Spark>[];
  final particles = <Particle>[];
  Boss? boss;

  // Shrinking arena.
  int closedRings = 0;
  int pendingRing = 0;
  double ringWarn = 0;
  final pendingCells = <int>{};
  final closedCells = <int>{};

  /// Seconds left on a speed boost (faster, double points) and a boss charge.
  double boost = 0;
  double charge = 0;

  final events = <GameEvent>[];

  int eaten = 0, deaths = 0, goldens = 0, enemiesDown = 0, longest = startLength;
  double shake = 0;

  double _goldenClock = 9, _boostClock = 6, _orbClock = 1;
  double? _clearTimer;
  bool cleared = false;
  bool get over => run.lives <= 0;

  int get target => spec.target;
  double get speed => spec.speed * (boost > 0 ? 1.3 : 1);
  int get tier => spec.tier;

  /// Points for a plain food at this level.
  int get basePoints => 10 + spec.number * 2;

  /// How far the player's head is between its last cell and the next (for drawing).
  double get progress => alive && ready <= 0 && intro <= 0 ? player.progress : 0;

  int cx(int c) => c % cols;
  int cy(int c) => c ~/ cols;
  int at(int x, int y) => y * cols + x;

  /// The cell one step from [c], wrapping if the arena wraps; null off the edge.
  int? step(int c, Dir d) {
    var x = cx(c) + d.dx, y = cy(c) + d.dy;
    if (spec.wrap) {
      x %= cols;
      y %= rows;
    } else if (x < 0 || y < 0 || x >= cols || y >= rows) {
      return null;
    }
    return at(x, y);
  }

  bool blocked(int c) => walls[c] || sliderCells.contains(c);

  /// Manhattan distance, the short way round on a wraparound arena.
  int dist(int a, int b) {
    var dx = (cx(a) - cx(b)).abs(), dy = (cy(a) - cy(b)).abs();
    if (spec.wrap) {
      dx = min(dx, cols - dx);
      dy = min(dy, rows - dy);
    }
    return dx + dy;
  }

  /// Ring index (0 = outer border) for shrinking arenas.
  int ringOf(int c) => min(min(cx(c), cy(c)), min(cols - 1 - cx(c), rows - 1 - cy(c)));

  // ---- set-up ----

  void _setUp() {
    intro = spec.isBoss ? bossIntroTime : introTime;
    for (final lane in arena.lanes) {
      final s = Slider(lane, lane.from + rng.nextInt(lane.to - lane.from - lane.length + 2));
      sliders.add(s);
    }
    _refreshSliders();
    final spawn = _findSpawn(initial: true)!;
    player = Snake(spawn.$1, spawn.$2);
    player.interval = 1 / speed;
    alive = true;
    if (spec.isBoss) {
      final b = boss = Boss(spec.boss!, 3 + tier);
      b.attackClock = 3.5;
      _placeBoss();
    }
    for (var i = 0; i < spec.enemies; i++) {
      final e = Snake([], Dir.up, maxLength: 8)
        ..dead = true
        ..respawn = i * 3.0;
      enemies.add(e);
      if (i == 0) _respawnEnemy(e);
    }
    _spawnFood(FoodKind.normal);
  }

  /// A head cell and direction with a free straight body behind it and room ahead.
  (List<int>, Dir)? _findSpawn({bool initial = false, int length = startLength, bool wyrm = false}) {
    (List<int>, Dir)? best;
    var bestScore = double.negativeInfinity;
    final dangers = <int>[
      for (final e in enemies)
        if (!e.dead) e.head,
      if (boss != null) ..._bossCells(boss!),
      if (wyrm && alive) ...player.body,
    ];
    final targetX = cols / 2, targetY = rows - 6.0;
    for (var c = 0; c < cols * rows; c++) {
      for (final d in Dir.values) {
        final body = <int>[c];
        var ok = _spawnable(c);
        for (var k = 1; ok && k < length; k++) {
          final x = cx(c) - d.dx * k, y = cy(c) - d.dy * k;
          if (x < 0 || y < 0 || x >= cols || y >= rows || !_spawnable(at(x, y))) {
            ok = false;
          } else {
            body.add(at(x, y));
          }
        }
        if (!ok) continue;
        var run = 0;
        for (var n = step(c, d); n != null && run < 12 && !blocked(n) && _spawnable(n); n = step(n, d)) {
          run++;
        }
        if (run < 4) continue;
        final danger = dangers.isEmpty ? 12 : dangers.map((x) => dist(x, c)).reduce(min);
        double score;
        if (initial) {
          score = run * 2 + (d == Dir.up ? 6 : 0) - ((cx(c) - targetX).abs() + (cy(c) - targetY).abs());
        } else {
          score = min(run, 10) * 3.0 + min(danger, 12) * 2 + rng.nextDouble();
        }
        if (score > bestScore) {
          bestScore = score;
          best = (body, d);
        }
      }
    }
    return best;
  }

  bool _spawnable(int c) {
    if (blocked(c) || pendingCells.contains(c) || arena.portals.containsKey(c)) return false;
    if (_snakeAt(c) != null) return false;
    if (boss != null && boss!.present && _bossOccupies(boss!, c, margin: 2)) return false;
    for (final s in sliders) {
      if ((cy(c) - s.lane.row).abs() <= 1) return false;
    }
    return true;
  }

  /// Any snake (player, enemy or Wyrm) on [c].
  Snake? _snakeAt(int c, {Snake? except}) {
    if (alive && player != except && player.body.contains(c)) return player;
    for (final e in enemies) {
      if (!e.dead && e != except && e.body.contains(c)) return e;
    }
    final w = boss?.wyrm;
    if (w != null && boss!.present && w != except && w.body.contains(c)) return w;
    return null;
  }

  // ---- input ----

  /// Queues a turn. Turns are buffered (up to three) so quick double-turns
  /// land on consecutive moves; reversing into yourself is ignored.
  void turn(Dir d) {
    final last = _turns.isEmpty ? player.dir : _turns.last;
    if (d == last || (d == last.opposite && player.body.length > 1)) return;
    if (_turns.length < 3) _turns.add(d);
  }

  List<Dir> get queuedTurns => List.unmodifiable(_turns);

  // ---- update ----

  void update(double dt) {
    if (cleared) return;
    time += dt;
    _updateParticles(dt);
    shake = max(0, shake - dt * 30);
    if (boss != null) boss!.flash = max(0, boss!.flash - dt);
    if (_clearTimer != null) {
      _clearTimer = _clearTimer! - dt;
      if (_clearTimer! <= 0) {
        cleared = true;
        events.add(GameEvent.levelClear);
      }
      return;
    }
    if (over) return;
    if (intro > 0) {
      intro -= dt;
      return;
    }
    boost = max(0, boost - dt);
    charge = max(0, charge - dt);
    _updateFoods(dt);
    _updateShrink(dt);
    _updateSliders(dt);
    _updateBoss(dt);
    _updateBeams(dt);
    _updateSparks(dt);
    _updateEnemies(dt);
    if (_clearTimer != null || over) return;

    if (!alive) {
      respawnTimer -= dt;
      if (respawnTimer <= 0) _respawn();
    } else if (ready > 0) {
      ready -= dt;
    } else {
      player.interval = 1 / speed;
      player.clock += dt;
      while (alive && player.clock >= player.interval && _clearTimer == null) {
        player.clock -= player.interval;
        _stepPlayer();
      }
    }
  }

  void _stepPlayer() {
    final s = player;
    if (_turns.isNotEmpty) s.dir = _turns.removeAt(0);
    var next = step(s.head, s.dir);
    if (next == null || blocked(next)) return _die();
    final portal = arena.portals[next];
    if (portal != null) {
      next = portal;
      _burst(next, Pc.charge, 8, speed: 3);
    }
    final growing = s.grow > 0;
    for (var i = 0; i < s.body.length - (growing ? 0 : 1); i++) {
      if (s.body[i] == next) return _die();
    }
    for (final e in enemies) {
      if (!e.dead && e.body.contains(next)) return _die();
    }
    final b = boss;
    if (b != null && b.present && _bossOccupies(b, next)) {
      if (charge > 0) {
        _hitBoss();
      } else {
        return _die();
      }
    }
    if (_deadlyAt(next)) return _die();
    s.prev = List.of(s.body);
    s.body.insert(0, next);
    if (growing) {
      s.grow--;
    } else {
      s.body.removeLast();
    }
    longest = max(longest, s.body.length);
    _eatAt(next);
  }

  bool _deadlyAt(int c) {
    for (final beam in beams) {
      if (beam.live && _onBeam(beam, c)) return true;
    }
    for (final sp in sparks) {
      if (!sp.dead && at(sp.x, sp.y) == c) return true;
    }
    return false;
  }

  bool _onBeam(Beam b, int c) => b.horizontal ? cy(c) == b.line : cx(c) == b.line;

  void _eatAt(int c) {
    final i = foods.indexWhere((f) => f.cell == c);
    if (i < 0) return;
    final f = foods.removeAt(i);
    final mult = boost > 0 ? 2 : 1;
    switch (f.kind) {
      case FoodKind.normal:
        eaten++;
        player.grow += 1;
        run.score += basePoints * mult;
        events.add(GameEvent.eat);
        _burst(c, Pc.food, 10);
      case FoodKind.boost:
        eaten++;
        player.grow += 1;
        run.score += basePoints * 2;
        boost = 5;
        events.add(GameEvent.boost);
        _burst(c, Pc.charge, 14);
      case FoodKind.golden:
        eaten++;
        goldens++;
        player.grow += 2;
        run.score += basePoints * 8 * mult;
        events.add(GameEvent.golden);
        _burst(c, Pc.golden, 22, speed: 6);
      case FoodKind.poison:
        final cut = min(3, player.body.length - 2);
        for (var k = 0; k < cut; k++) {
          _burst(player.body.removeLast(), Pc.poison, 3);
        }
        player.grow = 0;
        run.score = max(0, run.score - basePoints * 2);
        events.add(GameEvent.poison);
        shake = 6;
      case FoodKind.orb:
        charge = chargeTime;
        _orbClock = 1.2;
        events.add(GameEvent.charge);
        _burst(c, Pc.charge, 18, speed: 5);
      case FoodKind.bit:
        player.grow += 1;
        run.score += basePoints ~/ 2;
        events.add(GameEvent.bit);
        _burst(c, Pc.enemy, 4);
    }
    if (f.kind == FoodKind.normal) _spawnFood(FoodKind.normal);
    if (!spec.isBoss && eaten >= target) _clear();
  }

  void _die() {
    if (!alive) return;
    alive = false;
    deaths++;
    run.lives--;
    _turns.clear();
    charge = 0;
    boost = 0;
    shake = 10;
    for (final c in player.body) {
      _burst(c, Pc.player, 4, speed: 4);
    }
    events.add(GameEvent.die);
    if (over) {
      events.add(GameEvent.gameOver);
    } else {
      respawnTimer = respawnDelay;
    }
  }

  void _respawn() {
    final spawn = _findSpawn();
    if (spawn == null) {
      respawnTimer = 0.3; // nowhere safe this instant; try again shortly
      return;
    }
    player = Snake(spawn.$1, spawn.$2)..interval = 1 / speed;
    alive = true;
    ready = readyDelay;
    _turns.clear();
    foods.removeWhere((f) => player.body.contains(f.cell));
  }

  /// Cuts the player's body at [index], keeping the head end.
  void _cutPlayer(int index) {
    final keep = max(2, index);
    while (player.body.length > keep) {
      _burst(player.body.removeLast(), Pc.player, 2);
    }
    player.grow = 0;
    shake = max(shake, 5);
  }

  void _clear() {
    _clearTimer = spec.isBoss ? 1.8 : 0.9;
    if (alive) _burst(player.head, Pc.golden, 30, speed: 8);
  }

  // ---- food ----

  void _updateFoods(double dt) {
    foods.removeWhere((f) {
      f.age += dt;
      f.ttl -= dt;
      return f.ttl <= 0;
    });
    if (!foods.any((f) => f.kind == FoodKind.normal)) _spawnFood(FoodKind.normal);
    if (foods.where((f) => f.kind == FoodKind.poison).length < spec.poison) {
      _spawnFood(FoodKind.poison, life: 9 + rng.nextDouble() * 5, minDist: 5);
    }
    if (spec.golden && !spec.isBoss) {
      _goldenClock -= dt;
      if (_goldenClock <= 0) {
        _goldenClock = 14 + rng.nextDouble() * 6;
        _spawnFood(FoodKind.golden, life: max(4.5, 6.5 - spec.number * 0.05), minDist: 6);
      }
    }
    if (spec.boosts) {
      _boostClock -= dt;
      if (_boostClock <= 0) {
        _boostClock = 11 + rng.nextDouble() * 6;
        if (!foods.any((f) => f.kind == FoodKind.boost)) _spawnFood(FoodKind.boost, life: 8);
      }
    }
    if (spec.isBoss && charge <= 0 && boss!.hp > 0 && !foods.any((f) => f.kind == FoodKind.orb)) {
      _orbClock -= dt;
      if (_orbClock <= 0) _spawnFood(FoodKind.orb, minDist: 6);
    }
  }

  /// Every free cell reachable from the player (walls only: bodies move on).
  Set<int> reachable() {
    var start = alive ? player.head : -1;
    if (start < 0) {
      for (var c = 0; c < cols * rows; c++) {
        if (!walls[c] && !pendingCells.contains(c) && (spec.twist != Twist.shrink || ringOf(c) > closedRings + 1)) {
          start = c;
          break;
        }
      }
    }
    final seen = <int>{start};
    final queue = [start];
    for (var i = 0; i < queue.length; i++) {
      for (final d in Dir.values) {
        var n = step(queue[i], d);
        if (n == null || walls[n]) continue;
        final p = arena.portals[n];
        if (p != null && seen.add(n)) n = p;
        if (seen.add(n)) queue.add(n);
      }
    }
    return seen;
  }

  /// A cell food may appear on: reachable, not in a dead end, clear of everything.
  List<int> foodCells({int minDist = 4}) {
    final reach = reachable();
    final cells = <int>[];
    for (final c in reach) {
      if (blocked(c) || arena.portals.containsKey(c) || pendingCells.contains(c)) continue;
      if (spec.twist == Twist.shrink && ringOf(c) <= closedRings + 1) continue;
      if (sliders.any((s) => cy(c) == s.lane.row)) continue;
      if (_snakeAt(c) != null || foods.any((f) => f.cell == c)) continue;
      if (boss != null && boss!.present && _bossOccupies(boss!, c, margin: 1)) continue;
      var closed = 0;
      for (final d in Dir.values) {
        final n = step(c, d);
        if (n == null || walls[n]) closed++;
      }
      if (closed >= 3) continue;
      cells.add(c);
    }
    if (alive) {
      final far = [for (final c in cells) if (dist(c, player.head) >= minDist) c];
      if (far.isNotEmpty) return far;
    }
    return cells;
  }

  void _spawnFood(FoodKind kind, {double life = double.infinity, int minDist = 4}) {
    final cells = foodCells(minDist: minDist);
    if (cells.isEmpty) return;
    foods.add(Food(cells[rng.nextInt(cells.length)], kind, life: life));
  }

  // ---- shrinking arena ----

  void _updateShrink(double dt) {
    if (spec.twist != Twist.shrink) return;
    final rings = arena.innerRect.$1 - 1;
    if (pendingRing == 0 && closedRings < rings) {
      final threshold = (target * (closedRings + 1) / (rings + 1)).ceil();
      if (eaten >= threshold) {
        pendingRing = closedRings + 1;
        ringWarn = 2.5;
        for (var c = 0; c < cols * rows; c++) {
          if (ringOf(c) == pendingRing && !walls[c]) pendingCells.add(c);
        }
        events.add(GameEvent.warning);
        // Food in the closing ring (or the next one) moves inward now.
        final moved = foods.where((f) => ringOf(f.cell) <= pendingRing + 1 && f.kind != FoodKind.bit).toList();
        foods.removeWhere(moved.contains);
        for (final f in moved) {
          _spawnFood(f.kind, life: f.ttl);
        }
      }
    }
    if (pendingRing > 0) {
      ringWarn -= dt;
      if (ringWarn > 0) return;
      pendingCells.removeWhere((c) {
        if (_snakeAt(c) != null) return false; // closes once you've slid out
        walls[c] = true;
        closedCells.add(c);
        foods.removeWhere((f) => f.cell == c);
        return true;
      });
      if (pendingCells.isEmpty) {
        closedRings = pendingRing;
        pendingRing = 0;
      }
    }
  }

  // ---- moving walls ----

  void _refreshSliders() {
    sliderCells.clear();
    for (final s in sliders) {
      for (var k = 0; k < s.lane.length; k++) {
        sliderCells.add(at(s.x + k, s.lane.row));
      }
    }
  }

  double get sliderInterval => 1 / (spec.speed * 0.42);

  void _updateSliders(double dt) {
    var moved = false;
    for (final s in sliders) {
      s.clock += dt;
      if (s.clock < sliderInterval) continue;
      s.clock -= sliderInterval;
      if (s.x + s.dir < s.lane.from || s.x + s.dir + s.lane.length - 1 > s.lane.to) s.dir = -s.dir;
      final lead = at(s.dir > 0 ? s.x + s.lane.length : s.x - 1, s.lane.row);
      // Walls wait for whatever is in the way rather than crushing it.
      if (_snakeAt(lead) != null) continue;
      foods.removeWhere((f) => f.cell == lead);
      s.prevX = s.x;
      s.x += s.dir;
      moved = true;
    }
    if (moved) _refreshSliders();
  }

  // ---- enemies ----

  void _updateEnemies(double dt) {
    for (final e in enemies) {
      if (e.dead) {
        if (e.hatchling) continue;
        e.respawn -= dt;
        if (e.respawn <= 0) _respawnEnemy(e);
        continue;
      }
      e.clock += dt;
      while (!e.dead && e.clock >= e.interval) {
        e.clock -= e.interval;
        _stepEnemy(e);
      }
    }
    enemies.removeWhere((e) => e.dead && e.hatchling);
  }

  void _respawnEnemy(Snake e) {
    // Far from the player, entering from wherever there's room.
    final spawn = _findSpawn(length: 4);
    if (spawn == null || (alive && dist(spawn.$1.first, player.head) < 8)) {
      e.respawn = 1;
      return;
    }
    e
      ..body = spawn.$1
      ..prev = List.of(spawn.$1)
      ..dir = spawn.$2
      ..dead = false
      ..grow = 0
      ..clock = 0
      ..interval = 1 / (spec.speed * 0.68);
  }

  /// True if [c] is safe for a non-player snake to move into.
  bool _safeFor(Snake s, int c, {bool avoidPlayer = true}) {
    if (blocked(c) || arena.portals.containsKey(c) || pendingCells.contains(c)) return false;
    if (_deadlyAt(c)) return false;
    for (final beam in beams) {
      if (_onBeam(beam, c)) return false;
    }
    final b = boss;
    if (b != null && b.present && b.wyrm != s && _bossOccupies(b, c)) return false;
    if (foods.any((f) => f.cell == c && (f.kind == FoodKind.poison || f.kind == FoodKind.orb))) return false;
    final other = _snakeAt(c);
    if (other == null) return true;
    if (other == player) return !avoidPlayer; // a careless enemy crashes into you
    // Own tail moves out of the way.
    return other == s && c == s.body.last && s.grow == 0;
  }

  void _stepEnemy(Snake e) {
    int? goal;
    if (e.hatchling && alive) {
      goal = player.head;
    } else {
      var best = 1 << 30;
      for (final f in foods) {
        if (f.kind == FoodKind.poison || f.kind == FoodKind.orb) continue;
        final dd = dist(f.cell, e.head);
        if (dd < best) {
          best = dd;
          goal = f.cell;
        }
      }
    }
    final careless = rng.nextDouble() < 0.1;
    Dir? choice;
    var bestScore = double.negativeInfinity;
    for (final d in Dir.values) {
      if (d == e.dir.opposite) continue;
      final n = step(e.head, d);
      if (n == null || !_safeFor(e, n, avoidPlayer: !careless)) continue;
      var score = rng.nextDouble() * 2.5 + (d == e.dir ? 0.6 : 0);
      if (goal != null) score -= dist(n, goal);
      if (_space(n, e.body.length * 2 + 4, e) < e.body.length + 3) score -= 60;
      if (score > bestScore) {
        bestScore = score;
        choice = d;
      }
    }
    choice ??= careless ? e.dir : _anyDir(e);
    e.dir = choice;
    final n = step(e.head, choice);
    final hit = n == null ? null : _snakeAt(n, except: e);
    final ownHit = n != null && e.body.sublist(0, e.body.length - (e.grow > 0 ? 0 : 1)).contains(n);
    if (n == null || blocked(n) || arena.portals.containsKey(n) || ownHit || hit != null || _deadlyAt(n) ||
        (boss != null && boss!.present && _bossOccupies(boss!, n))) {
      _killEnemy(e, trapped: hit == player);
      return;
    }
    e.prev = List.of(e.body);
    e.body.insert(0, n);
    final fi = foods.indexWhere((f) => f.cell == n);
    if (fi >= 0) {
      final f = foods.removeAt(fi);
      if (e.body.length < e.maxLength) e.grow++;
      if (f.kind == FoodKind.normal) _spawnFood(FoodKind.normal);
    }
    if (e.grow > 0) {
      e.grow--;
    } else {
      e.body.removeLast();
    }
  }

  Dir _anyDir(Snake s) {
    for (final d in Dir.values) {
      final n = step(s.head, d);
      if (d != s.dir.opposite && n != null && _safeFor(s, n, avoidPlayer: false)) return d;
    }
    return s.dir;
  }

  /// Free cells reachable from [c], counting up to [limit].
  int _space(int c, int limit, Snake self) {
    final seen = <int>{c};
    final queue = [c];
    for (var i = 0; i < queue.length && seen.length < limit; i++) {
      for (final d in Dir.values) {
        final n = step(queue[i], d);
        if (n == null || seen.contains(n) || blocked(n)) continue;
        final s = _snakeAt(n);
        if (s != null && !(s == self && n == self.body.last)) continue;
        seen.add(n);
        queue.add(n);
      }
    }
    return seen.length;
  }

  void _killEnemy(Snake e, {bool trapped = false}) {
    e.dead = true;
    e.respawn = 6;
    enemiesDown++;
    events.add(GameEvent.enemyDown);
    if (trapped) run.score += 100;
    for (var i = 0; i < e.body.length; i++) {
      final c = e.body[i];
      _burst(c, Pc.enemy, 4, speed: 4);
      if (i.isOdd && !e.hatchling && !blocked(c) && !foods.any((f) => f.cell == c) && !arena.portals.containsKey(c)) {
        foods.add(Food(c, FoodKind.bit, life: 7));
      }
    }
  }

  // ---- bosses ----

  Iterable<int> _bossCells(Boss b) sync* {
    if (!b.present || (b.kind == BossKind.wyrm && b.wyrm == null)) return;
    if (b.wyrm != null) {
      yield* b.wyrm!.body;
      return;
    }
    for (var dy = 0; dy < Boss.size; dy++) {
      for (var dx = 0; dx < Boss.size; dx++) {
        yield at(b.x + dx, b.y + dy);
      }
    }
  }

  List<int> bossCells() => boss == null ? const [] : _bossCells(boss!).toList();

  bool _bossOccupies(Boss b, int c, {int margin = 0}) {
    if (!b.present || (b.kind == BossKind.wyrm && b.wyrm == null)) return false;
    if (b.wyrm != null) return margin == 0 ? b.wyrm!.body.contains(c) : b.wyrm!.body.any((w) => dist(w, c) <= margin);
    final x = cx(c), y = cy(c);
    return x >= b.x - margin && x < b.x + Boss.size + margin && y >= b.y - margin && y < b.y + Boss.size + margin;
  }

  bool _footprintFree(int x, int y) {
    if (x < 1 || y < 1 || x + Boss.size > cols - 1 || y + Boss.size > rows - 1) return false;
    for (var dy = 0; dy < Boss.size; dy++) {
      for (var dx = 0; dx < Boss.size; dx++) {
        final c = at(x + dx, y + dy);
        if (blocked(c) || arena.portals.containsKey(c) || _snakeAt(c, except: boss?.wyrm) != null) return false;
      }
    }
    return true;
  }

  void _placeBoss() {
    final b = boss!;
    final head = alive ? player.head : at(cols ~/ 2, rows - 6);
    if (b.kind == BossKind.wyrm) {
      b.wyrm = null;
      final length = min(10 + tier * 2, rows - 8);
      final spawn = _findSpawn(length: length, wyrm: true);
      if (spawn == null) {
        b.hidden = 0.5;
        return;
      }
      b.wyrm = Snake(spawn.$1, spawn.$2)..interval = 1 / (spec.speed * min(0.85, 0.58 + tier * 0.055));
      return;
    }
    var best = -1;
    var bestScore = double.negativeInfinity;
    for (var y = 1; y < rows - Boss.size; y++) {
      for (var x = 1; x < cols - Boss.size; x++) {
        if (!_footprintFree(x, y)) continue;
        final d = dist(at(x + 1, y + 1), head);
        if (d < 7) continue;
        // Prefer the middle band, away from the player.
        final score = min(d, 16) - (x + 1 - cols / 2).abs() * 0.4 + rng.nextDouble() * 4;
        if (score > bestScore) {
          bestScore = score;
          best = at(x, y);
        }
      }
    }
    if (best < 0) {
      b.hidden = 0.5;
      return;
    }
    b.x = cx(best);
    b.y = cy(best);
    foods.removeWhere((f) => _bossOccupies(b, f.cell));
    _burst(at(b.x + 1, b.y + 1), Pc.boss, 16, speed: 5);
  }

  void _hitBoss() {
    final b = boss!;
    b.hp--;
    b.flash = 0.35;
    charge = 0;
    shake = 12;
    run.score += 250 * tier;
    for (final c in _bossCells(b).toList()) {
      _burst(c, Pc.boss, 3, speed: 5);
    }
    beams.clear();
    if (b.hp <= 0) {
      events.add(GameEvent.bossDown);
      run.score += 1500 * tier;
      b.wyrm = null;
      for (final e in enemies) {
        if (e.hatchling && !e.dead) _killEnemy(e);
      }
      sparks.clear();
      _clear();
      return;
    }
    events.add(GameEvent.bossHit);
    b.hidden = 1.1;
    b.wyrm = null;
    b.attackClock = 2.5;
  }

  void _updateBoss(double dt) {
    final b = boss;
    if (b == null || b.hp <= 0) return;
    if (b.hidden > 0) {
      b.hidden -= dt;
      if (b.hidden <= 0) _placeBoss();
      return;
    }
    final t = tier;
    switch (b.kind) {
      case BossKind.wyrm:
        final w = b.wyrm;
        if (w == null) {
          b.hidden = 0.3;
          return;
        }
        w.clock += dt;
        while (b.present && b.wyrm != null && w.clock >= w.interval) {
          w.clock -= w.interval;
          _stepWyrm(b, w);
        }
      case BossKind.sentinel:
        if (beams.isNotEmpty) return; // holds still while firing
        b.moveClock += dt;
        final interval = max(0.32, 0.62 - t * 0.05);
        if (b.moveClock >= interval && alive) {
          b.moveClock = 0;
          final hx = cx(player.head), hy = cy(player.head);
          final mx = b.x + 1, my = b.y + 1;
          if ((hx - mx).abs() + (hy - my).abs() > 6) {
            final horizontal = (hx - mx).abs() > (hy - my).abs();
            final nx = b.x + (horizontal ? (hx - mx).sign : 0), ny = b.y + (horizontal ? 0 : (hy - my).sign);
            if (_footprintFree(nx, ny)) {
              b.x = nx;
              b.y = ny;
              foods.removeWhere((f) => _bossOccupies(b, f.cell));
            }
          }
        }
        b.attackClock -= dt;
        if (b.attackClock <= 0 && alive && ready <= 0) {
          b.attackClock = max(1.7, 3.6 - t * 0.35);
          final warn = max(0.85, 1.2 - t * 0.06);
          final both = t >= 3 || b.enraged;
          final horizontal = b.bursts.isEven;
          b.bursts++;
          if (both || horizontal) beams.add(Beam(horizontal: true, line: cy(player.head), warn: warn));
          if (both || !horizontal) beams.add(Beam(horizontal: false, line: cx(player.head), warn: warn));
          events.add(GameEvent.warning);
        }
      case BossKind.brood:
        b.moveClock += dt;
        if (b.moveClock >= 1.1) {
          b.moveClock = 0;
          final options = [
            for (final d in Dir.values)
              if (_footprintFree(b.x + d.dx, b.y + d.dy)) d,
          ];
          if (options.isNotEmpty) {
            final d = options[rng.nextInt(options.length)];
            b.x += d.dx;
            b.y += d.dy;
            foods.removeWhere((f) => _bossOccupies(b, f.cell));
          }
        }
        b.attackClock -= dt;
        final cap = min(1 + t, 5);
        if (b.attackClock <= 0) {
          b.attackClock = max(2.6, 6.5 - t * 0.7);
          if (enemies.where((e) => e.hatchling && !e.dead).length < cap) _hatch(b);
        }
      case BossKind.pulsar:
        b.attackClock -= dt;
        if (b.attackClock <= 0) {
          b.attackClock = max(1.3, 2.9 - t * 0.3) * (b.enraged ? 0.8 : 1);
          final diagonal = t >= 2 && b.bursts.isOdd;
          final both = t >= 4 || (t >= 2 && b.enraged);
          b.bursts++;
          final dirs = <(int, int)>[
            if (!diagonal || both) ...const [(1, 0), (-1, 0), (0, 1), (0, -1)],
            if (diagonal || both) ...const [(1, 1), (-1, 1), (1, -1), (-1, -1)],
          ];
          for (final (dx, dy) in dirs) {
            sparks.add(Spark(b.x + 1 + dx * 2, b.y + 1 + dy * 2, dx, dy));
          }
          _burst(at(b.x + 1, b.y + 1), Pc.boss, 10, speed: 6);
        }
    }
  }

  void _hatch(Boss b) {
    for (final d in Dir.values) {
      // Out of the middle of a side, three cells long.
      final ox = b.x + 1 + d.dx * 2, oy = b.y + 1 + d.dy * 2;
      final body = <int>[];
      for (var k = 0; k < 3; k++) {
        final x = ox + d.dx * (2 - k), y = oy + d.dy * (2 - k);
        if (x < 1 || y < 1 || x >= cols - 1 || y >= rows - 1) break;
        final c = at(x, y);
        if (blocked(c) || _snakeAt(c) != null || arena.portals.containsKey(c)) break;
        body.add(c);
      }
      if (body.length < 3) continue;
      enemies.add(Snake(body, d, maxLength: 5)
        ..hatchling = true
        ..interval = 1 / (spec.speed * min(0.85, 0.6 + tier * 0.05)));
      _burst(body.first, Pc.boss, 8);
      return;
    }
  }

  void _stepWyrm(Boss b, Snake w) {
    final goal = alive ? (step(player.head, player.dir) ?? player.head) : at(cols ~/ 2, rows ~/ 2);
    final careful = rng.nextDouble() < 0.75;
    Dir? choice;
    var bestScore = double.negativeInfinity;
    for (final d in Dir.values) {
      if (d == w.dir.opposite) continue;
      final n = step(w.head, d);
      if (n == null || blocked(n) || arena.portals.containsKey(n)) continue;
      if (foods.any((f) => f.cell == n && f.kind == FoodKind.orb)) continue; // it shies away from charge orbs
      final s = _snakeAt(n);
      if (s == w && n != w.body.last) continue;
      if (s != null && s != w && s != player) continue;
      if (s == player && careful && n != player.head) continue;
      var score = -dist(n, goal).toDouble() + rng.nextDouble() * 1.5 + (d == w.dir ? 0.5 : 0);
      if (_space(n, w.body.length + 6, w) < min(w.body.length, 14)) score -= 80;
      if (score > bestScore) {
        bestScore = score;
        choice = d;
      }
    }
    if (choice == null) {
      // Boxed in: turn round and lead with the tail.
      w.body = w.body.reversed.toList();
      w.prev = List.of(w.body);
      final a = w.body[0], c = w.body[1];
      w.dir = Dir.values.firstWhere((d) => step(c, d) == a, orElse: () => w.dir.opposite);
      return;
    }
    w.dir = choice;
    final n = step(w.head, choice)!;
    if (alive && player.body.contains(n)) {
      final idx = player.body.indexOf(n);
      if (idx == 0) {
        _die();
      } else {
        // It bit your tail: you lose it, but the neon burns the Wyrm.
        _cutPlayer(idx);
        _hitBoss();
        return;
      }
    }
    w.prev = List.of(w.body);
    w.body.insert(0, n);
    w.body.removeLast();
    foods.removeWhere((f) => f.cell == n && f.kind != FoodKind.orb);
    if (!foods.any((f) => f.kind == FoodKind.normal)) _spawnFood(FoodKind.normal);
  }

  void _updateBeams(double dt) {
    for (final beam in beams) {
      if (beam.warn > 0) {
        beam.warn -= dt;
        continue;
      }
      beam.active -= dt;
      if (alive && _onBeam(beam, player.head)) _die();
      for (final e in enemies) {
        if (!e.dead && _onBeam(beam, e.head)) _killEnemy(e);
      }
    }
    beams.removeWhere((b) => b.warn <= 0 && b.active <= 0);
  }

  double get sparkInterval => 1 / (5.0 + tier);

  void _updateSparks(double dt) {
    for (final s in sparks) {
      s.clock += dt;
      while (!s.dead && s.clock >= sparkInterval) {
        s.clock -= sparkInterval;
        s.px = s.x;
        s.py = s.y;
        s.x += s.dx;
        s.y += s.dy;
        _sparkHit(s);
      }
      if (!s.dead && s.px < 0) _sparkHit(s);
    }
    sparks.removeWhere((s) => s.dead);
  }

  void _sparkHit(Spark s) {
    if (s.x < 0 || s.y < 0 || s.x >= cols || s.y >= rows) {
      s.dead = true;
      return;
    }
    final c = at(s.x, s.y);
    if (blocked(c)) {
      s.dead = true;
      return;
    }
    if (alive) {
      final idx = player.body.indexOf(c);
      if (idx == 0) {
        s.dead = true;
        _die();
        return;
      }
      if (idx > 0) {
        s.dead = true;
        _cutPlayer(idx);
        return;
      }
    }
    for (final e in enemies) {
      if (!e.dead && e.body.contains(c)) {
        s.dead = true;
        _killEnemy(e);
        return;
      }
    }
  }

  // ---- effects ----

  void _burst(int c, int color, int count, {double speed = 3}) {
    final x = cx(c) + 0.5, y = cy(c) + 0.5;
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final v = speed * (0.3 + rng.nextDouble());
      particles.add(Particle(x, y, cos(a) * v, sin(a) * v, 0.35 + rng.nextDouble() * 0.4, color));
    }
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.94;
      p.vy *= 0.94;
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    if (particles.length > 400) particles.removeRange(0, particles.length - 400);
  }

  /// Ends the level: adds the bonuses to the score and returns the numbers.
  LevelSummary finish() {
    final summary = LevelSummary(
      eaten: eaten,
      longest: longest,
      deaths: deaths,
      goldens: goldens,
      enemiesDown: enemiesDown,
      flawlessBonus: deaths == 0 ? 250 * spec.number : 0,
      lengthBonus: longest * 10,
    );
    run.score += summary.bonus;
    return summary;
  }
}
