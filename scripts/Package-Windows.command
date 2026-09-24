#!/bin/zsh
# Builds dist/Vox-Windows.zip to copy to the PC (AirDrop, USB, Google Drive…).
cd "$(dirname "$0")/.."
rm -rf dist/Vox-Windows && mkdir -p dist/Vox-Windows
cp -R windows/src windows/package.json windows/package-lock.json windows/*.cmd windows/README.md dist/Vox-Windows/
cp -R web/remote dist/Vox-Windows/public
(cd dist && rm -f Vox-Windows.zip && zip -qr Vox-Windows.zip Vox-Windows)
echo "Made $(pwd)/dist/Vox-Windows.zip — copy it to the PC, unzip, double-click Install-Vox.cmd."
