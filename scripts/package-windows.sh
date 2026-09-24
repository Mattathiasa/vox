#!/usr/bin/env bash
# Builds dist/Vox-Windows.zip (Windows agent + phone web app). Used by scripts/Package-Windows.command and the release workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist/Vox-Windows dist/Vox-Windows.zip && mkdir -p dist/Vox-Windows
cp -R windows/src windows/package.json windows/package-lock.json windows/*.cmd windows/README.md LICENSE dist/Vox-Windows/
cp -R web/remote dist/Vox-Windows/public
(cd dist && zip -qr Vox-Windows.zip Vox-Windows)
echo "dist/Vox-Windows.zip"
