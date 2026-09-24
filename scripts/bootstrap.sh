#!/usr/bin/env bash
# One-time setup on a Mac: installs tools, runs core tests, generates the Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

for tool in tmux xcodegen; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "==> Installing $tool"
    brew install "$tool"
  fi
done

echo "==> Running VoxCore tests"
(cd Packages/VoxCore && swift test)

echo "==> Generating Vox.xcodeproj"
xcodegen generate

cat <<'EOF'

Done. Next:
  1. open Vox.xcodeproj
  2. Target Vox > Signing & Capabilities > pick your Team (not "Sign to Run Locally")
  3. Run (Cmd-R). Look for the waveform icon in the menu bar.
  4. Press Option-Space, type:  run freebuff in vox
EOF
