# Neon Snake

Neon arcade snake by Kallistesoft. Play it at https://snake.kallistesoft.ca.

- Swipe to turn (arrow keys or WASD on desktop). Turns are buffered, so a quick
  double swipe lands on consecutive moves. Eat food to grow and fill the level
  meter; walls, obstacles, rival snakes and your own body cost a life (3 lives,
  short respawn).
- Every level is a new arena: 6 layouts (Open Grid, Pillars, Crossroads, Rings,
  Labyrinth, Chambers) × 5 twists (none, wraparound edges, portals, moving walls,
  closing-in arena). The pair never repeats for 30 regular levels.
- Food: plain, golden (on a timer, big points), lightning (speed boost, double
  points), poison (shrinks you). Rival snakes from level 7 steal food and die if
  they run into you, leaving bits behind.
- Speed, food target, obstacle density, rivals and poison rise every level.
- Every 5th level is a boss: The Wyrm, Sentinel (row/column lasers), Brood Queen
  (spawns hatchlings), Pulsar (spark bursts that cut your tail). Eat a charge
  orb, then ram the boss; the Wyrm is also hurt when it bites your tail. Bosses
  cycle back with more HP and faster attacks.
- Game over sends you back to the level after the last boss beaten; one rewarded
  revive per run.
- Between levels, a break screen with an `AdSlot` (300×250) placeholder and
  `AdService.showInterstitial()` on Continue. Both are no-ops until an ad network
  is wired in (`lib/services/ad_service.dart`, `lib/ui/ad_slot.dart`).

## Code

- `lib/game/levels.dart`: level specs built from the level number; arena generation (always fully connected).
- `lib/game/world.dart`: the whole simulation on a 21×37 grid (pure Dart, tested).
- `lib/ui/`: screens and the canvas renderer. No image assets: everything is drawn.
- `tools/make_sfx.py`: synthesizes the sound effects into `assets/sfx`.
- `test/bot.dart`: a BFS autopilot; `test/world_test.dart` uses it to clear levels 1–25
  (bosses included) and checks food never spawns out of reach.

## Run

```
flutter test
flutter run -d chrome
```

Every push to `main` builds and deploys the web version to the GoDaddy hosting
(`.github/workflows/deploy-godaddy.yml`).
