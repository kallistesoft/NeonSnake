# Notes for Claude

- Neon Snake: neon snake arena: 6 arenas × 5 twists, rival snakes from level 7, a boss every 5th level (eat the charge orb, ram the boss), checkpoint after each boss. Flutter, package `ca.kallistesoft.neon_snake`. Not aimed at kids. Plays on the web at https://snake.kallistesoft.ca; no Android or iOS store build
  exists yet (no Play app, upload key, Firebase or AdMob).
- Ads: a break screen between levels with a 300×250 `AdSlot` placeholder and `AdService.showInterstitial()` on
  Continue, plus one rewarded revive/continue per run. All are no-ops until an ad SDK is wired in. AdMob work waits
  for the owner's go.
- Keep the `shared_preferences_android: 2.4.28` pin in pubspec.yaml (same stack as Block Daily).
- Checks: `tools/check.sh` (flutter analyze, flutter test). Run it before every push and quote the result in the PR.
  The repo is public: every push to main runs `flutter test` and deploys the web build to GoDaddy
  (`.github/workflows/deploy-godaddy.yml`), so main is live as soon as it's merged.
- Branches: feature branch → push → PR against main; the owner merges. Never `--admin`, never stacked PRs.
- Autonomy: normal. Show a rendered mock-up before building new screens; every screen readable in 2 seconds.
  Non-blocking choices go in [DECISIONS.md](DECISIONS.md) with the default taken; blocking ones are asked one at a time.

## Builds

- Tests include a bot that clears levels 1–25 (bosses included): it guards against unbeatable levels, keep it green.
- UI check without a device: web build + headless puppeteer.
- Release: `tools/build_release.sh` on a clean, up-to-date main (build number = commit count). It refuses to run until
  the app has a Play upload signing config and `android/key.properties` (follow Block Daily: key in `~/Keys/kallistesoft/`
  plus a Drive backup). It runs `tools/smoke_release.sh` (R8 release APK launched on emulator-5554, never a real
  device) when the emulator is connected; otherwise run it yourself before anything goes to Play. When Google Mobile
  Ads is added, add Block Daily's WorkManager keep rules to `android/app/proguard-rules.pro` or release builds crash at
  startup.
- Before the first device install, add a `.dev` applicationIdSuffix + "Neon Snake Dev" label for debug/profile builds and a
  `tools/install_dev.sh` (Block Daily pattern). Never uninstall a Play copy; say so before installing on the owner's
  devices.
- Play: the scripts only build. Never upload or start a Play release unless the owner asks.

## To-dos

- None recorded yet: store listing, real app icons, AdMob and app-ads.txt are still to do. Put new to-dos in a
  FOLLOW-UP.md at the repo root.
