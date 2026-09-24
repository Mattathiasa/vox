#!/bin/bash
# Double-click me. Installs the Vox Bridge extension into every VS Code–based IDE
# found in /Applications or ~/Applications (Antigravity, Kiro, VS Code, Cursor…).
# Log: .logs/ide-install.log
cd "$(dirname "$0")/.." || exit 1
mkdir -p .logs
LOG=".logs/ide-install.log"
VSIX="$(pwd)/extensions/vox-bridge/vox-bridge-0.1.0.vsix"

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
  if [ ! -f "$VSIX" ]; then
    echo "MISSING: $VSIX"
    exit 1
  fi

  found=0
  for app in /Applications/*.app "$HOME"/Applications/*.app; do
    [ -f "$app/Contents/Resources/app/product.json" ] || continue
    bin="$app/Contents/Resources/app/bin"
    [ -d "$bin" ] || continue
    cli=""
    for candidate in "$bin"/*; do
      name="$(basename "$candidate")"
      case "$name" in *tunnel*|*.cmd|*.ps1) continue ;; esac
      if [ -x "$candidate" ] && [ -f "$candidate" ]; then cli="$candidate"; break; fi
    done
    [ -n "$cli" ] || { echo "SKIP $(basename "$app"): no command-line tool in $bin"; continue; }
    found=1
    echo "--> $(basename "$app")  ($cli)"
    if "$cli" --install-extension "$VSIX" --force 2>&1; then
      echo "RESULT $(basename "$app" .app)=installed"
    else
      echo "RESULT $(basename "$app" .app)=FAILED"
    fi
  done
  [ "$found" = 1 ] || echo "No VS Code–based IDEs found in /Applications or ~/Applications."
} 2>&1 | tee "$LOG"

cat <<'EOF'

Next: in each IDE that's already open, press Cmd+Shift+P and run
"Developer: Reload Window" (or quit and reopen the IDE).
Then say: "Balcha, open antigravity and open 3 terminals and run claude on one of the terminals".
You can close this window.
EOF
