#!/usr/bin/env bash
# Builds the signed Play bundle with an automatic build number (versionCode): the number of commits on main, so every
# upload is higher than the last one. The version name stays in pubspec.yaml. Run from a clean, up-to-date main:
#   tools/build_release.sh
# Then, when emulator-5554 is connected, it runs the release smoke test (tools/smoke_release.sh). It only builds:
# uploading to Play is the owner's call.
# Not ready yet: the app has no Play upload key (android/app/build.gradle.kts signs release with the debug key), so
# the script stops until the upload signing config and android/key.properties exist (Block Daily shows the pattern).
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
gradle=android/app/build.gradle.kts

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || { echo "Switch to main first (on $branch)." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
git pull --ff-only --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main differs from origin/main: push or pull first." >&2; exit 1; }
grep -q 'key.properties' "$gradle" || { echo "$gradle has no upload signing config yet: the bundle would be signed with the debug key." >&2; exit 1; }
[ -f android/key.properties ] || { echo "android/key.properties is missing: the bundle would be signed with the debug key." >&2; exit 1; }
if grep -q 'com.google.gms.google-services' "$gradle"; then
  [ -f android/app/google-services.json ] || { echo "android/app/google-services.json is missing (copy it from ~/Keys/kallistesoft/)." >&2; exit 1; }
fi

build=$(git rev-list --count HEAD)
name=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)

flutter test
flutter build appbundle --release --build-number="$build"

out="build/app/outputs/bundle/release/neon-snake-$name-$build.aab"
cp build/app/outputs/bundle/release/app-release.aab "$out"
echo
echo "Built $out (version $name, build $build)."

# Release smoke test: the R8 build launched on the emulator (never a real device), only when emulator-5554 is connected.
if [ "$(adb -s emulator-5554 get-state 2>/dev/null)" = device ]; then
  flutter build apk --release --build-number="$build"
  ANDROID_SERIAL=emulator-5554 tools/smoke_release.sh build/app/outputs/flutter-apk/app-release.apk
else
  echo "WARNING: emulator-5554 is not connected, so the release smoke test was SKIPPED."
  echo "Start it and run tools/smoke_release.sh before this build goes to Play."
fi
echo "Upload it in Play Console › Neon Snake › Test and release › Internal testing › Create new release (owner)."
