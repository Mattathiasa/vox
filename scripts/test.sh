#!/usr/bin/env bash
# The check every agent runs before marking a task done.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> VoxCore unit tests"
(cd Packages/VoxCore && swift test)

if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  echo "==> App build (unsigned, just to prove it compiles)"
  xcodegen generate >/dev/null
  xcodebuild -project Vox.xcodeproj -scheme Vox -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build -quiet
  echo "==> OK"
else
  echo "(skipping app build: xcodegen/xcodebuild not available)"
fi
