#!/bin/zsh
# Build NoteIt.app without full Xcode (uses SwiftPM + CommandLineTools)
set -e
cd "$(dirname "$0")/.."

APP_NAME="NoteIt"
BUNDLE="dist/$APP_NAME.app"
BIN=".build/release/$APP_NAME"

echo "→ building release binary…"
swift build -c release

echo "→ creating bundle at $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
# Optional icon: drop NoteIt.icns into Resources/ to include it
if [[ -f "Resources/NoteIt.icns" ]]; then
  cp "Resources/NoteIt.icns" "$BUNDLE/Contents/Resources/"
fi
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✓ done: $BUNDLE"
echo "  open with: open \"$BUNDLE\""
