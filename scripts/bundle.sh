#!/bin/bash
# Build release lalu bungkus menjadi build/Hardware Monitor.app (codesign ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product HardwareMonitor

APP="build/Hardware Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HardwareMonitor "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "Selesai: $APP"
