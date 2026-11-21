#!/usr/bin/env bash
# Release smoke test: installs the minified (R8) release APK on an emulator, launches it, waits 15 s and fails if the
# app has died or logcat shows a fatal exception for it. Run it before any build goes to Play (green tests only prove
# that it builds). Never runs on a real device: the owner's phone and tablet hold real data.
#   tools/smoke_release.sh [APK]
# Without an APK it builds one with `flutter build apk --release` (with --flavor prod when the app has a prod flavor).
# ANDROID_SERIAL picks the emulator (default emulator-5554); serials that are not emulator-* are refused.
# It only uses `adb install -r`: it never uninstalls, so a copy signed with another key makes it stop with an error.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"

fail() { echo "SMOKE TEST FAIL: $*" >&2; exit 1; }

case "$ANDROID_SERIAL" in
  emulator-*) ;;
  *) fail "$ANDROID_SERIAL is not an emulator. This script only runs on emulators (ANDROID_SERIAL=emulator-5554)." ;;
esac
[ "$(adb -s "$ANDROID_SERIAL" get-state 2>/dev/null)" = device ] || fail "$ANDROID_SERIAL is not connected (adb devices)."

gradle=android/app/build.gradle.kts
[ -f "$gradle" ] || gradle=android/app/build.gradle
pkg=$(sed -n 's/^[[:space:]]*applicationId[[:space:]]*=\{0,1\}[[:space:]]*"\([^"]*\)".*/\1/p' "$gradle" | head -1)
[ -n "$pkg" ] || fail "could not read applicationId from $gradle."

apk="${1:-}"
if [ -z "$apk" ]; then
  if grep -qE 'create\("prod"\)|^[[:space:]]*prod[[:space:]]*\{' "$gradle"; then
    flutter build apk --release --flavor prod
    apk=build/app/outputs/flutter-apk/app-prod-release.apk
  else
    flutter build apk --release
    apk=build/app/outputs/flutter-apk/app-release.apk
  fi
fi
[ -f "$apk" ] || fail "APK not found: $apk"

echo "Smoke test: $apk ($pkg) on $ANDROID_SERIAL"
adb install -r "$apk" || fail "adb install -r failed (a copy signed with another key? It is never uninstalled here)."
adb logcat -c
adb shell am force-stop "$pkg"
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || fail "could not launch $pkg."
echo "Launched, waiting 15 s..."
sleep 15

log=$(mktemp -t smoke_logcat)
adb logcat -d >"$log"
pid=$(adb shell pidof "$pkg" | tr -d '\r' || true)
if grep -A6 -E 'FATAL EXCEPTION|AndroidRuntime: FATAL' "$log" | grep -qF "Process: $pkg,"; then
  grep -A20 -E 'FATAL EXCEPTION|AndroidRuntime: FATAL' "$log" | head -40 >&2 || true
  fail "fatal exception for $pkg in logcat (full log: $log)."
fi
if grep -q ">>> $pkg <<<" "$log"; then
  fail "native crash (tombstone) for $pkg in logcat (full log: $log)."
fi
[ -n "$pid" ] || fail "$pkg is not running 15 s after launch (full log: $log)."
echo "SMOKE TEST OK: $pkg is running on $ANDROID_SERIAL (pid $pid) 15 s after launch, no fatal exception."
