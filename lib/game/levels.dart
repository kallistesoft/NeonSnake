import 'dart:math';

/// Obstacle layout inside the arena.
enum Layout { box, pillars, cross, rings, maze, chambers }

/// The twist a level adds on top of its layout.
enum Twist { none, wrap, portals, sliders, shrink }

enum BossKind { wyrm, sentinel, brood, pulsar }

const layoutNames = {
  Layout.box: 'Open Grid',
  Layout.pillars: 'Pillars',
  Layout.cross: 'Crossroads',
  Layout.rings: 'Rings',
  Layout.maze: 'Labyrinth',
  Layout.chambers: 'Chambers',
};

const twistNames = {
  Twist.none: '',
  Twist.wrap: 'Wraparound',
  Twist.portals: 'Portals',
  Twist.sliders: 'Moving Walls',
  Twist.shrink: 'Closing In',
};

const bossNames = {
  BossKind.wyrm: 'The Wyrm',
  BossKind.sentinel: 'Sentinel',
  BossKind.brood: 'Brood Queen',
  BossKind.pulsar: 'Pulsar',
};

const bossHints = {
  BossKind.wyrm: 'Eat a charge orb, then ram it · or make it bite your tail',
  BossKind.sentinel: 'Dodge the beams · eat a charge orb, then ram it',
  BossKind.brood: 'Its hatchlings hunt you · eat a charge orb, then ram it',
  BossKind.pulsar: 'Sparks cut your tail · eat a charge orb, then ram it',
};

/// Everything that makes one level what it is. Built from the level number
/// alone, so a level plays the same every time.
class LevelSpec {
  const LevelSpec({
    required this.number,
    required this.layout,
    required this.twist,
    required this.target,
    required this.speed,
    required this.density,
    required this.enemies,
    required this.poison,
    required this.boosts,
    required this.golden,
    required this.boss,
    required this.hue,
  });

  final int number;
  final Layout layout;
  final Twist twist;

  /// Food to eat to clear the level (0 on boss levels: beat the boss instead).
  final int target;

  /// Snake moves per second.
  final double speed;

  /// 0..1: how crowded the layout is.
  final double density;

  /// Wandering enemy snakes.
  final int enemies;

  /// Poison pellets on the board at once.
  final int poison;

  /// Speed-boost food can appear.
  final bool boosts;

  /// Golden bonus food appears on a timer.
  final bool golden;
  final BossKind? boss;

  /// Arena tint, in degrees.
  final double hue;

  bool get isBoss => boss != null;

  /// Boss tier: 1 for level 5, 2 for level 10...
  int get tier => (number + 4) ~/ 5;

  bool get wrap => twist == Twist.wrap;

  String get name {
    if (isBoss) return bossNames[boss]!;
    final t = twistNames[twist]!;
    return t.isEmpty ? layoutNames[layout]! : '${layoutNames[layout]} · $t';
  }

  /// Level a game over sends you back to: the one after the last boss beaten.
  static int checkpointFor(int level) => ((level - 1) ~/ 5) * 5 + 1;

  // Layouts and twists cycle with coprime lengths (6 and 5), so the pair only
  // repeats every 30 regular levels and neighbours always differ in both.
  static const _layoutOrder = [Layout.box, Layout.pillars, Layout.cross, Layout.rings, Layout.maze, Layout.chambers];
  // Arena hues, steering clear of the player's green.
  static const _hues = [205.0, 280.0, 25.0, 190.0, 300.0, 45.0, 230.0, 10.0, 260.0, 35.0, 215.0];
  static const _bossHues = [262.0, 195.0, 285.0, 218.0];
  static const _twistOrder = [Twist.none, Twist.wrap, Twist.portals, Twist.sliders, Twist.shrink];

  factory LevelSpec.forLevel(int n) {
    final d = (n - 1).toDouble();
    final boss = n % 5 == 0 ? BossKind.values[(n ~/ 5 - 1) % BossKind.values.length] : null;
    // Count regular levels only, so bosses don't skip layouts.
    final regular = n - n ~/ 5 - 1;
    return LevelSpec(
      number: n,
      layout: boss != null ? Layout.box : _layoutOrder[regular % _layoutOrder.length],
      twist: boss != null ? Twist.none : _twistOrder[regular % _twistOrder.length],
      target: boss != null ? 0 : min(8 + (d * 1.15).round(), 40),
      speed: min(6.5 + d * 0.2, 13),
      density: min(0.15 + d * 0.035, 1),
      enemies: n < 7 || boss != null ? 0 : min(1 + (n - 7) ~/ 6, 4),
      poison: n < 4 ? 0 : min(1 + (n - 4) ~/ 7, 4),
      boosts: n >= 3,
      golden: n >= 2,
      boss: boss,
      hue: boss != null ? _bossHues[boss.index] : _hues[n % _hues.length],
    );
  }
}

/// The static arena: walls (including the border unless edges wrap),
/// portal pairs and moving-wall lanes. Generated from the spec alone and
/// always fully connected.
class Arena {
  Arena._(this.cols, this.rows, this.walls, this.portals, this.lanes, this.innerRect);

  static const defaultCols = 21, defaultRows = 37;

  final int cols, rows;

  /// 1 where there is a wall, by cell index (y * cols + x).
  final List<bool> walls;

  /// Portal cell → partner cell.
  final Map<int, int> portals;

  /// Moving-wall lanes: (row, from x, to x inclusive, bar length).
  final List<Lane> lanes;

  /// Smallest rectangle a shrinking arena closes down to (left, top, right, bottom inclusive).
  final (int, int, int, int) innerRect;

  factory Arena.generate(LevelSpec spec, {int cols = defaultCols, int rows = defaultRows}) {
    final rng = Random(spec.number * 7919 + 13);
    final walls = List<bool>.filled(cols * rows, false);
    void set(int x, int y, [bool v = true]) {
      if (x >= 0 && y >= 0 && x < cols && y < rows) walls[y * cols + x] = v;
    }

    if (!spec.wrap) {
      for (var x = 0; x < cols; x++) {
        set(x, 0);
        set(x, rows - 1);
      }
      for (var y = 0; y < rows; y++) {
        set(0, y);
        set(cols - 1, y);
      }
    }
    // Shrinking arenas keep the layout inside the final rectangle, so closing
    // rings never cut anything off.
    const shrinkMargin = 5;
    final inner = (shrinkMargin, shrinkMargin, cols - 1 - shrinkMargin, rows - 1 - shrinkMargin);
    final (l, t, r, b) = spec.twist == Twist.shrink ? (inner.$1 + 1, inner.$2 + 1, inner.$3 - 1, inner.$4 - 1) : (2, 2, cols - 3, rows - 3);
    _layout(spec, rng, set, l, t, r, b);

    // Keep the spawn strip (bottom centre column) clear.
    final lanes = <Lane>[];
    if (spec.twist == Twist.sliders) {
      final count = spec.density > 0.55 ? 3 : 2;
      for (var i = 0; i < count; i++) {
        final row = (rows * (i + 1) / (count + 1)).round() - (count == 2 ? 2 : 1);
        for (var y = row - 1; y <= row + 1; y++) {
          for (var x = 1; x < cols - 1; x++) {
            set(x, y, false);
          }
        }
        lanes.add(Lane(row, 1, cols - 2, 4 + (spec.density * 3).round()));
      }
    }

    _connect(walls, cols, rows, wrap: spec.wrap);

    final portals = <int, int>{};
    if (spec.twist == Twist.portals) {
      final pairs = spec.density > 0.6 ? 3 : 2;
      bool open(int x, int y) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx <= 0 || yy <= 0 || xx >= cols - 1 || yy >= rows - 1 || walls[yy * cols + xx]) return false;
          }
        }
        return true;
      }

      // Pairs link opposite corners/sides of the arena.
      final anchors = [
        ((cols * 0.25).round(), (rows * 0.2).round(), (cols * 0.75).round(), (rows * 0.8).round()),
        ((cols * 0.75).round(), (rows * 0.2).round(), (cols * 0.25).round(), (rows * 0.8).round()),
        ((cols * 0.15).round(), (rows * 0.5).round(), (cols * 0.85).round(), (rows * 0.5).round()),
      ];
      final used = <int>{};
      for (var p = 0; p < pairs; p++) {
        final (ax, ay, bx, by) = anchors[p];
        final a = _nearest(ax, ay, cols, rows, (x, y) => open(x, y) && !_near(used, x, y, cols, 3));
        if (a == null) continue;
        used.add(a);
        final c = _nearest(bx, by, cols, rows, (x, y) => open(x, y) && !_near(used, x, y, cols, 3));
        if (c == null) {
          used.remove(a);
          continue;
        }
        used.add(c);
        portals[a] = c;
        portals[c] = a;
      }
    }
    return Arena._(cols, rows, walls, portals, lanes, inner);
  }

  static bool _near(Set<int> cells, int x, int y, int cols, int dist) =>
      cells.any((c) => (c % cols - x).abs() + (c ~/ cols - y).abs() <= dist);

  static int? _nearest(int x0, int y0, int cols, int rows, bool Function(int x, int y) ok) {
    for (var radius = 0; radius < cols + rows; radius++) {
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx.abs() + dy.abs() != radius) continue;
          final x = x0 + dx, y = y0 + dy;
          if (x < 0 || y < 0 || x >= cols || y >= rows) continue;
          if (ok(x, y)) return y * cols + x;
        }
      }
    }
    return null;
  }

  /// Draws the layout inside the rectangle (l, t)–(r, b), inclusive.
  static void _layout(LevelSpec spec, Random rng, void Function(int x, int y, [bool v]) setCell, int l, int t, int r, int b) {
    // Everything stays inside the rectangle.
    void set(int x, int y, [bool v = true]) {
      if (x >= l && x <= r && y >= t && y <= b) setCell(x, y, v);
    }

    final w = r - l + 1, h = b - t + 1;
    final cx = (l + r) ~/ 2, cy = (t + b) ~/ 2;
    final d = spec.density;
    switch (spec.layout) {
      case Layout.box:
        if (spec.isBoss) {
          // Boss arena: four pillars to dodge round.
          for (final (px, py) in [(l + w ~/ 4 - 1, t + h ~/ 4 - 1), (r - w ~/ 4, t + h ~/ 4 - 1), (l + w ~/ 4 - 1, b - h ~/ 4), (r - w ~/ 4, b - h ~/ 4)]) {
            set(px, py);
            set(px + 1, py);
            set(px, py + 1);
            set(px + 1, py + 1);
          }
          return;
        }
        // Scattered single blocks, more as the game goes on.
        final count = (d * 10).round();
        for (var i = 0; i < count; i++) {
          set(l + 1 + rng.nextInt(w - 2), t + 1 + rng.nextInt(h - 2));
        }
      case Layout.pillars:
        // 2×2 pillars on a lattice; the lattice tightens with density.
        final step = d > 0.6 ? 4 : 5;
        for (var y = t + 1; y + 1 <= b - 1; y += step + 1) {
          for (var x = l + 1; x + 1 <= r - 1; x += step) {
            if (rng.nextDouble() > 0.45 + d * 0.5) continue;
            set(x, y);
            set(x + 1, y);
            set(x, y + 1);
            set(x + 1, y + 1);
          }
        }
      case Layout.cross:
        // A plus through the middle with a gap at the centre and arm tips open.
        final gap = 2;
        final armX = ((w ~/ 2) * (0.5 + d * 0.4)).round(), armY = ((h ~/ 2) * (0.5 + d * 0.4)).round();
        for (var x = cx - armX; x <= cx + armX; x++) {
          if ((x - cx).abs() > gap) set(x, cy);
        }
        for (var y = cy - armY; y <= cy + armY; y++) {
          if ((y - cy).abs() > gap) set(cx, y);
        }
        if (d > 0.4) {
          // Corner brackets.
          for (final (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
            final x0 = cx + sx * (w ~/ 4 + 1), y0 = cy + sy * (h ~/ 4 + 1);
            for (var k = 0; k < 3; k++) {
              set(x0 + sx * k, y0);
              set(x0, y0 + sy * k);
            }
          }
        }
      case Layout.rings:
        // Concentric rectangles with doorways; fewer doorways when denser.
        var inset = 0;
        var ring = 0;
        while (w - 2 * inset >= 7 && h - 2 * inset >= 7) {
          final x0 = l + inset, y0 = t + inset, x1 = r - inset, y1 = b - inset;
          final doors = <(int, int)>[];
          final rw = x1 - x0, rh = y1 - y0;
          // Door positions alternate between rings so you have to wind round.
          final offset = ring.isEven ? 0.5 : 0.25;
          doors.add((x0 + (rw * offset).round(), y0));
          doors.add((x1 - (rw * offset).round(), y1));
          if (d < 0.7 || ring == 0) {
            doors.add((x0, y0 + (rh * (1 - offset)).round()));
            doors.add((x1, y1 - (rh * (1 - offset)).round()));
          }
          bool isDoor(int x, int y) => doors.any((p) => (p.$1 - x).abs() + (p.$2 - y).abs() <= 1);
          for (var x = x0; x <= x1; x++) {
            if (!isDoor(x, y0)) set(x, y0);
            if (!isDoor(x, y1)) set(x, y1);
          }
          for (var y = y0; y <= y1; y++) {
            if (!isDoor(x0, y)) set(x0, y);
            if (!isDoor(x1, y)) set(x1, y);
          }
          inset += 4;
          ring++;
          if (ring >= 3) break;
        }
      case Layout.maze:
        // A maze of 2-wide corridors, with loops knocked through it (fewer at higher density).
        final kx = (w + 1) ~/ 3, ky = (h + 1) ~/ 3;
        final ox = l + (w - (kx * 3 - 1)) ~/ 2, oy = t + (h - (ky * 3 - 1)) ~/ 2;
        // Wall lines on every third row/column, then carve.
        for (var i = 1; i < kx; i++) {
          for (var y = oy; y < oy + ky * 3 - 1; y++) {
            set(ox + i * 3 - 1, y);
          }
        }
        for (var j = 1; j < ky; j++) {
          for (var x = ox; x < ox + kx * 3 - 1; x++) {
            set(x, oy + j * 3 - 1);
          }
        }
        void openBetween(int ax, int ay, int bx, int by) {
          if (ax != bx) {
            final wx = ox + max(ax, bx) * 3 - 1;
            set(wx, oy + ay * 3, false);
            set(wx, oy + ay * 3 + 1, false);
          } else {
            final wy = oy + max(ay, by) * 3 - 1;
            set(ox + ax * 3, wy, false);
            set(ox + ax * 3 + 1, wy, false);
          }
        }
        final seen = List<bool>.filled(kx * ky, false);
        final stack = <(int, int)>[(kx ~/ 2, ky ~/ 2)];
        seen[(ky ~/ 2) * kx + kx ~/ 2] = true;
        while (stack.isNotEmpty) {
          final (x, y) = stack.last;
          final next = [
            for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
              if (x + dx >= 0 && y + dy >= 0 && x + dx < kx && y + dy < ky && !seen[(y + dy) * kx + x + dx]) (x + dx, y + dy),
          ];
          if (next.isEmpty) {
            stack.removeLast();
            continue;
          }
          final (nx, ny) = next[rng.nextInt(next.length)];
          seen[ny * kx + nx] = true;
          openBetween(x, y, nx, ny);
          stack.add((nx, ny));
        }
        // Loops: knock out extra walls so it's an arena, not a dead-end trap.
        final loops = ((1 - d) * kx * ky * 0.3).round() + 2;
        for (var i = 0; i < loops; i++) {
          final x = rng.nextInt(kx), y = rng.nextInt(ky);
          if (rng.nextBool() && x + 1 < kx) {
            openBetween(x, y, x + 1, y);
          } else if (y + 1 < ky) {
            openBetween(x, y, x, y + 1);
          }
        }
      case Layout.chambers:
        // Rooms split by wall lines with doorways that narrow as density grows.
        final door = d > 0.5 ? 2 : 3;
        final splitsX = [l + w ~/ 2];
        final splitsY = [t + h ~/ 3, t + 2 * h ~/ 3];
        for (final sx in splitsX) {
          for (var y = t; y <= b; y++) {
            set(sx, y);
          }
        }
        for (final sy in splitsY) {
          for (var x = l; x <= r; x++) {
            set(x, sy);
          }
        }
        // A door in every wall segment between neighbouring rooms.
        final ys = [t - 1, ...splitsY, b + 1];
        final xs = [l - 1, ...splitsX, r + 1];
        for (var i = 0; i + 1 < ys.length; i++) {
          final mid = (ys[i] + ys[i + 1]) ~/ 2;
          for (final sx in splitsX) {
            for (var k = 0; k < door; k++) {
              set(sx, mid - door ~/ 2 + k, false);
            }
          }
        }
        for (var i = 0; i + 1 < xs.length; i++) {
          final mid = (xs[i] + xs[i + 1]) ~/ 2;
          for (final sy in splitsY) {
            for (var k = 0; k < door; k++) {
              set(mid - door ~/ 2 + k, sy, false);
            }
          }
        }
    }
  }

  /// Opens walls until every free cell is reachable from every other.
  static void _connect(List<bool> walls, int cols, int rows, {required bool wrap}) {
    while (true) {
      final comp = List<int>.filled(cols * rows, -1);
      final sizes = <int>[];
      for (var i = 0; i < walls.length; i++) {
        if (walls[i] || comp[i] >= 0) continue;
        final id = sizes.length;
        var size = 0;
        final queue = [i];
        comp[i] = id;
        while (queue.isNotEmpty) {
          final c = queue.removeLast();
          size++;
          for (final n in neighbours(c, cols, rows, wrap: wrap)) {
            if (!walls[n] && comp[n] < 0) {
              comp[n] = id;
              queue.add(n);
            }
          }
        }
        sizes.add(size);
      }
      if (sizes.length <= 1) return;
      // Tunnel from the smallest piece to any other piece through the fewest walls.
      var small = 0;
      for (var i = 1; i < sizes.length; i++) {
        if (sizes[i] < sizes[small]) small = i;
      }
      final from = <int>[for (var i = 0; i < comp.length; i++) if (comp[i] == small) i];
      final prev = List<int>.filled(cols * rows, -2);
      final queue = <int>[...from];
      for (final f in from) {
        prev[f] = -1;
      }
      var hit = -1;
      for (var qi = 0; qi < queue.length && hit < 0; qi++) {
        final c = queue[qi];
        for (final n in neighbours(c, cols, rows, wrap: wrap)) {
          if (prev[n] != -2) continue;
          // Never tunnel through the outer border.
          final x = n % cols, y = n ~/ cols;
          if (!wrap && (x == 0 || y == 0 || x == cols - 1 || y == rows - 1)) continue;
          prev[n] = c;
          if (!walls[n] && comp[n] != small) {
            hit = n;
            break;
          }
          queue.add(n);
        }
      }
      if (hit < 0) {
        // Unreachable pocket (can't happen with an open interior): wall it in.
        for (final f in from) {
          walls[f] = true;
        }
        continue;
      }
      for (var c = prev[hit]; c >= 0 && prev[c] != -1; c = prev[c]) {
        walls[c] = false;
      }
    }
  }

  /// Orthogonal neighbours of a cell, wrapping round the edges if [wrap].
  static Iterable<int> neighbours(int c, int cols, int rows, {required bool wrap}) sync* {
    final x = c % cols, y = c ~/ cols;
    for (final dir in Dir.values) {
      var nx = x + dir.dx, ny = y + dir.dy;
      if (wrap) {
        nx %= cols;
        ny %= rows;
      } else if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) {
        continue;
      }
      yield ny * cols + nx;
    }
  }
}

class Lane {
  const Lane(this.row, this.from, this.to, this.length);

  final int row, from, to, length;
}

enum Dir {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  const Dir(this.dx, this.dy);

  final int dx, dy;

  Dir get opposite => Dir.values[(index + 2) % 4];
}
