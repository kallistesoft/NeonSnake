#!/usr/bin/env bash
# Local checks for this repo: tools/check.sh
# Run before every push and PR. The global pre-push hook (~/.config/git/hooks/pre-push) runs it too and blocks the
# push when it fails (emergency bypass: git push --no-verify).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter analyze
flutter test
