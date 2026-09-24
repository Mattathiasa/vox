#!/bin/bash
# Double-click me in Finder. Installs tmux + xcodegen if missing, runs the core
# tests, builds the app (unsigned), and saves everything to .logs/verify.log so an
# AI agent can read the results and fix errors without terminal access.
cd "$(dirname "$0")/.." || exit 1
mkdir -p .logs
LOG=".logs/verify.log"
export PATH="$HOME/.homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

step() { echo; echo "===== $1 ====="; }

{
  step "environment $(date '+%Y-%m-%d %H:%M:%S')"
  sw_vers
  uname -m
  xcodebuild -version 2>&1 | head -2
  swift --version 2>&1 | head -1
  echo "brew: $(command -v brew || echo MISSING)"

  step "install tools"
  for tool in tmux xcodegen; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "$tool: $(command -v "$tool")"
    elif command -v brew >/dev/null 2>&1; then
      brew install "$tool" || echo "FAILED to install $tool"
    else
      echo "FAILED: $tool missing and Homebrew not found"
    fi
  done

  step "VoxCore tests"
  (cd Packages/VoxCore && swift test 2>&1)
  echo "RESULT core_tests=$?"

  step "generate Xcode project"
  xcodegen generate 2>&1
  echo "RESULT xcodegen=$?"

  step "app build (unsigned)"
  xcodebuild -project Vox.xcodeproj -scheme Vox -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build/xcode \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*(Sendable|isolated)|BUILD (SUCCEEDED|FAILED)" | sort -u | head -150
  echo "RESULT app_build=${PIPESTATUS[0]}"

  step "done $(date '+%H:%M:%S')"
} 2>&1 | tee "$LOG"

echo
echo "Saved to $(pwd)/$LOG. Tell Claude it's done. You can close this window."
