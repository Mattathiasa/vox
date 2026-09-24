#!/bin/bash
# Double-click me. Real-machine checks for Phases 1–2: tmux round trips, exit handling,
# voice phrasings, and actually starting freebuff, claude and kilo in ~/Projects.
# Log: .logs/selftest.log
cd "$(dirname "$0")/../Packages/VoxCore" || exit 1
mkdir -p ../../.logs
export PATH="$HOME/.homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
LOG=../../.logs/selftest.log
swift run -c debug VoxSelfTest 2>&1 | grep -v -E "^\[[0-9]+/[0-9]+\]|^Building|^Compiling|^Write|^Planning" | tee "$LOG"
echo "RESULT exit=${PIPESTATUS[0]}" | tee -a "$LOG"
echo "Done. You can close this window."
