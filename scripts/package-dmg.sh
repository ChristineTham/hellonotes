#!/usr/bin/env bash
#
# package-dmg.sh — build, sign, notarize, and staple a distributable DMG
# from an already-notarized HelloNotes.app exported by Xcode
# (Organizer ▸ Distribute App ▸ Direct Distribution ▸ Export).
#
# Usage:  scripts/package-dmg.sh /path/to/exported/HelloNotes.app
#
# Prerequisites (one-time):
#   • A "Developer ID Application" cert in your keychain.
#   • A stored notarytool profile:
#       xcrun notarytool store-credentials "hellotham-notary" \
#         --apple-id info@hellotham.com --team-id RPL5R637DS
#
set -euo pipefail

# --- config ------------------------------------------------------------------
APP="${1:?Usage: scripts/package-dmg.sh /path/to/HelloNotes.app}"
# Confirm the exact string via: security find-identity -v -p codesigning
IDENTITY="Developer ID Application: Hello Tham Pty. Ltd. (RPL5R637DS)"
NOTARY_PROFILE="hellotham-notary"
VOLNAME="HelloNotes"
OUT="dist/HelloNotes.dmg"
# -----------------------------------------------------------------------------

[ -d "$APP" ] || { echo "✗ Not found: $APP"; exit 1; }

echo "▸ Verifying the input app is signed & stapled…"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"   # fails loudly if the .app wasn't notarized in Xcode

echo "▸ Staging a drag-to-Applications layout…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▸ Building the DMG…"
mkdir -p dist
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
  -ov -format UDZO "$OUT"
rm -rf "$STAGING"

echo "▸ Signing the DMG with Developer ID…"
codesign --sign "$IDENTITY" --timestamp "$OUT"

echo "▸ Notarizing (uploads to Apple, waits for the ticket)…"
xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling the ticket…"
xcrun stapler staple "$OUT"

echo "▸ Verifying…"
xcrun stapler validate "$OUT"
spctl --assess -t open --context context:primary-signature --verbose "$OUT"

echo "✓ $OUT is signed, notarized, and stapled — ready to ship."
