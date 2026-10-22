#!/bin/bash
# Build, instal ke /Applications (menggantikan versi lama), lalu jalankan.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

DEST="/Applications/Hardware Monitor.app"

# Tutup versi yang sedang berjalan dan tunggu sampai benar-benar keluar.
if pkill -x HardwareMonitor; then
    for _ in {1..50}; do
        pgrep -x HardwareMonitor > /dev/null || break
        sleep 0.1
    done
fi

rm -rf "$DEST"
cp -R "build/Hardware Monitor.app" "$DEST"
open "$DEST"

echo "Terinstal: $DEST"
