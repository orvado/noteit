#!/bin/zsh
# Rebuild the app icon: render the 1024px master (make-icon.swift), derive
# every macOS iconset size, and pack them into Resources/NoteIt.icns.
set -e
cd "$(dirname "$0")/.."

swift scripts/make-icon.swift

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz build/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz * 2)) $((sz * 2)) build/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/NoteIt.icns
echo "✓ wrote Resources/NoteIt.icns (picked up automatically by make-app.sh)"
