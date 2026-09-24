#!/bin/zsh
# Double-click: builds dist/Vox-Windows.zip to copy to the PC (AirDrop, USB, Google Drive…).
cd "$(dirname "$0")/.."
scripts/package-windows.sh && echo "Copy it to the PC, unzip, double-click Install-Vox.cmd."
read -k 1 "?Press any key to close."
