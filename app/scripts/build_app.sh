#!/bin/bash
# Builds Stashbar.app (universal) and, with --dmg, a drag-to-Applications disk image.
#
# Environment (all optional):
#   VERSION             e.g. 2.0.1 (defaults to the Info.plist value)
#   BUILD_NUMBER        e.g. 42
#   SUPABASE_URL        https://<project>.supabase.co   — enables sign-in + sync
#   SUPABASE_ANON_KEY   the project's anon (public) key
#   WEBSITE_URL         where the landing page lives (help/feedback/privacy links)
#   CODESIGN_IDENTITY   "Developer ID Application: …" — omit for ad-hoc signing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build"
APP="$OUT/Stashbar.app"
PLIST="$APP/Contents/Info.plist"

ARCHS=(--arch arm64 --arch x86_64)
if [[ "${SINGLE_ARCH:-}" == "1" ]]; then ARCHS=(); fi

echo "→ Building release binary"
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

echo "→ Assembling Stashbar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/Logos"
cp "$BIN_DIR/StashBar" "$APP/Contents/MacOS/StashBar"
cp "$ROOT/Resources/Info.plist" "$PLIST"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Fonts/"*.ttf "$ROOT/Resources/Fonts/OFL.txt" "$APP/Contents/Resources/Fonts/"
cp "$ROOT/Resources/Logos/"*.png "$APP/Contents/Resources/Logos/"

set_plist() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST"; }
[[ -n "${VERSION:-}" ]] && set_plist CFBundleShortVersionString "$VERSION"
[[ -n "${BUILD_NUMBER:-}" ]] && set_plist CFBundleVersion "$BUILD_NUMBER"
[[ -n "${SUPABASE_URL:-}" ]] && set_plist StashbarSupabaseURL "$SUPABASE_URL"
[[ -n "${SUPABASE_ANON_KEY:-}" ]] && set_plist StashbarSupabaseAnonKey "$SUPABASE_ANON_KEY"
[[ -n "${WEBSITE_URL:-}" ]] && set_plist StashbarWebsiteURL "$WEBSITE_URL"

echo "→ Signing (${CODESIGN_IDENTITY:-ad-hoc})"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
echo "✓ $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  DMG="$OUT/Stashbar.dmg"
  STAGE="$OUT/dmg"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Stashbar" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
  rm -rf "$STAGE"
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then codesign --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"; fi
  echo "✓ $DMG"
fi
