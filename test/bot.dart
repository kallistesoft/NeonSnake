import 'package:neon_snake/game/levels.dart';
import 'package:neon_snake/game/world.dart';

/// A BFS autopilot: heads for the nearest food (or charge orb, then the boss),
/// avoiding walls, bodies, beams and sparks, and never into a pocket smaller
/// than itself. Plays by the real rules; collisions still cost lives.
class Bot {
  Bot(this.world);

  final World world;

  Set<int> _blocked() {
    final w = world;
    final out = <int>{};
    for (var c = 0; c < w.cols * w.rows; c++) {
      if (w.blocked(c) || w.pendingCells.contains(c)) out.add(c);
    }
    for (final s in w.sliders) {
      out.add(w.at((s.x - 1).clamp(0, w.cols - 1), s.lane.row));
      out.add(w.at((s.x + s.lane.length).clamp(0, w.cols - 1), s.lane.row));
    }
    final p = w.player;
    out.addAll(p.grow > 0 ? p.body : p.body.sublist(0, p.body.length - 1));
    for (final e in w.enemies) {
      if (e.dead) continue;
      out.addAll(e.body);
      for (final d in Dir.values) {
        final n = w.step(e.head, d);
        if (n != null) out.add(n);
      }
    }
    final boss = w.boss;
    if (boss != null && w.charge <= 0) {
      out.addAll(w.bossCells());
      final wyrm = boss.present ? boss.wyrm : null;
      if (wyrm != null) {
        for (final d in Dir.values) {
          final n = w.step(wyrm.head, d);
          if (n != null) out.add(n);
        }
      }
    }
    for (final b in w.beams) {
      for (var i = 0; i < (b.horizontal ? w.cols : w.rows); i++) {
        out.add(b.horizontal ? w.at(i, b.line) : w.at(b.line, i));
      }
    }
    for (final s in w.sparks) {
      for (var k = 0; k <= 3; k++) {
        final x = s.x + s.dx * k, y = s.y + s.dy * k;
        if (x >= 0 && y >= 0 && x < w.cols && y < w.rows) out.add(w.at(x, y));
      }
    }
    for (final f in w.foods) {
      if (f.kind == FoodKind.poison) out.add(f.cell);
    }
    return out;
  }

  /// Where a move from [c] in [d] actually lands (through portals), or null.
  int? _land(int c, Dir d, Set<int> blocked) {
    var n = world.step(c, d);
    if (n == null || blocked.contains(n)) return null;
    final p = world.arena.portals[n];
    if (p != null) n = p;
    return blocked.contains(n) ? null : n;
  }

  int _space(int start, Set<int> blocked, int limit) {
    final seen = <int>{start};
    final queue = [start];
    for (var i = 0; i < queue.length && seen.length < limit; i++) {
      for (final d in Dir.values) {
        final n = _land(queue[i], d, blocked);
        if (n != null && seen.add(n)) queue.add(n);
      }
    }
    return seen.length;
  }

  Dir decide() {
    final w = world;
    final blocked = _blocked();
    final goals = <int>{};
    if (w.boss != null && w.charge > 0 && w.boss!.present) {
      goals.addAll(w.bossCells());
      for (final g in goals) {
        blocked.remove(g);
      }
    } else {
      final orbs = w.foods.where((f) => f.kind == FoodKind.orb);
      final food = orbs.isNotEmpty ? orbs : w.foods.where((f) => f.counts || f.kind == FoodKind.bit);
      goals.addAll(food.map((f) => f.cell));
    }
    final head = w.player.head;
    final need = w.player.body.length + 2;
    // BFS, remembering the first move of each path.
    final first = <int, Dir>{};
    final queue = <int>[];
    for (final d in Dir.values) {
      if (d == w.player.dir.opposite) continue;
      final n = _land(head, d, blocked);
      if (n == null || first.containsKey(n)) continue;
      first[n] = d;
      queue.add(n);
    }
    for (var i = 0; i < queue.length; i++) {
      final c = queue[i];
      if (goals.contains(c)) {
        final d = first[c]!;
        final n = _land(head, d, blocked)!;
        if (goals.contains(n) || _space(n, blocked, need) >= need) return d;
      }
      for (final d in Dir.values) {
        final n = _land(c, d, blocked);
        if (n == null || first.containsKey(n)) continue;
        first[n] = first[c]!;
        queue.add(n);
      }
    }
    // No safe path: take the roomiest move.
    var best = w.player.dir;
    var bestSpace = -1;
    for (final d in Dir.values) {
      if (d == w.player.dir.opposite) continue;
      final n = _land(head, d, blocked);
      if (n == null) continue;
      final s = _space(n, blocked, 400);
      if (s > bestSpace) {
        bestSpace = s;
        best = d;
      }
    }
    return best;
  }
}

class BotResult {
  BotResult(this.cleared, this.time, this.deaths, this.unreachable);

  final bool cleared;
  final double time;
  final int deaths;

  /// Food that appeared somewhere the player couldn't reach.
  final int unreachable;
}

/// Plays a level with the bot; lives are topped up so it always finishes,
/// and deaths are counted instead.
BotResult botPlay(World world, {double limit = 400}) {
  final bot = Bot(world);
  const dt = 1 / 60;
  int? lastHead;
  var deaths = 0, unreachable = 0;
  final seen = <Food>{};
  while (world.time < limit) {
    if (world.alive) {
      final head = world.player.head;
      if (head != lastHead && world.queuedTurns.isEmpty) {
        lastHead = head;
        world.turn(bot.decide());
      }
      for (final f in world.foods) {
        if (seen.add(f) && f.kind != FoodKind.bit && !world.reachable().contains(f.cell)) unreachable++;
      }
    } else {
      lastHead = null;
    }
    world.update(dt);
    if (world.events.contains(GameEvent.die)) {
      deaths++;
      world.run.lives = 3;
    }
    world.events.clear();
    if (world.cleared) return BotResult(true, world.time, deaths, unreachable);
  }
  return BotResult(false, world.time, deaths, unreachable);
}
