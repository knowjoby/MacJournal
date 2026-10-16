#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION" --arch arm64 --product MacJournal
BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"
APP="$PWD/dist/MacJournal.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MacJournal" "$APP/Contents/MacOS/MacJournal"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/MacJournal.icns "$APP/Contents/Resources/MacJournal.icns"
for bundle in "$BIN_DIR"/*.bundle; do
    [ ! -d "$bundle" ] || cp -R "$bundle" "$APP/Contents/Resources/"
done
if [ -d "$BIN_DIR/SQLCipher.framework" ]; then
    cp -R "$BIN_DIR/SQLCipher.framework" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/MacJournal"
fi
# Use your stable Developer ID for persistent TCC permissions, if available.
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$APP"
printf 'Built %s\n' "$APP"
