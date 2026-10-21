import 'package:flutter/material.dart';

import '../game/world.dart';

const background = Color(0xFF070712);
const accent = Color(0xFF3DFFA2); // the player's snake
const hot = Color(0xFFFF3B6B); // danger
const gold = Color(0xFFFFD447);
const charge = Color(0xFF38E1FF); // boost food, charge orbs, portals
const poison = Color(0xFFB45CFF);
const enemyColor = Color(0xFFFF9F43);
const foodColor = Color(0xFFFF4FA3);

/// Boss colours by [BossKind] index.
const bossColors = <Color>[
  Color(0xFFFF6B2E), // wyrm
  Color(0xFFFF5D5D), // sentinel
  Color(0xFFFFB020), // brood queen
  Color(0xFFA77BFF), // pulsar
];

/// Particle colours by [Pc] index.
const particleColors = <Color>[
  accent, // Pc.player
  foodColor, // Pc.food
  gold, // Pc.golden
  poison, // Pc.poison
  enemyColor, // Pc.enemy
  Color(0xFFFF4FD8), // Pc.boss
  Color(0xFFFFF4D6), // Pc.white
  charge, // Pc.charge
];

/// Arena colours for a level: dark floor and glowing walls.
Color levelTint(double hue) => HSVColor.fromAHSV(1, hue, 0.7, 0.16).toColor();
Color wallColor(double hue) => HSVColor.fromAHSV(1, hue, 0.75, 1).toColor();

Color colorFor(FoodKind kind) => switch (kind) {
      FoodKind.normal => foodColor,
      FoodKind.golden => gold,
      FoodKind.boost => charge,
      FoodKind.poison => poison,
      FoodKind.orb => charge,
      FoodKind.bit => enemyColor,
    };

TextStyle neon(double size, {Color color = accent, FontWeight weight = FontWeight.w900, double spacing = 2}) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: size * 0.5)],
    );
