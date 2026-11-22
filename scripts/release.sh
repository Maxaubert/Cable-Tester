#!/bin/bash
# Build, sign, notarize and publish a Cable Tester release from this Mac.
#
#   scripts/release.sh [--notes notes.md] [--dry-run]
#
# Version comes from project.yml (MARKETING_VERSION, build number CURRENT_PROJECT_VERSION).
# Publishes the DMG to github.com/loftspace/cable-tester-releases and adds it to the Sparkle feed
# (appcast.xml in that repo). --dry-run stops after the notarized DMG is built.
#
# Needs: Xcode, xcodegen, gh (logged in), the Developer ID certificate and the notarytool keychain
# profile "notary", and the Sparkle EdDSA key in the Keychain (account "cable-tester").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
IDENTITY="Developer ID Application: MAX AUBERT (WV7BY8CUM8)"
NOTARY_PROFILE="notary"
RELEASES_REPO="loftspace/cable-tester-releases"
SPARKLE_ACCOUNT="cable-tester"
MIN_MACOS="15.0"

NOTES_FILE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
TAG="v$VERSION"
DMG_NAME="Cable-Tester-$VERSION.dmg"
OUT="$ROOT/build/release/$VERSION"
DD="$ROOT/build/release-dd"
APP="$DD/Build/Products/Release/Cable Tester.app"
step() { printf '\n==> %s\n' "$*"; }

[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "Could not read the version from project.yml" >&2; exit 1; }
if gh release view "$TAG" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
  echo "$TAG is already released. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml." >&2
  exit 1
fi
if [ "$DRY_RUN" = 0 ] && [ -n "$(git status --porcelain)" ]; then
  echo "The working tree has uncommitted changes. Release from a clean master." >&2
  exit 1
fi
security find-identity -v -p codesigning | grep -q "$IDENTITY" || { echo "Missing signing identity: $IDENTITY" >&2; exit 1; }

step "Building Cable Tester $VERSION ($BUILD)"
xcodegen generate -q
xcodebuild -project CableTester.xcodeproj -scheme CableTester -configuration Release \
  -derivedDataPath "$DD" clean build -quiet
SPARKLE_BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
mkdir -p "$OUT"

step "Signing (inside out, hardened runtime, secure timestamp)"
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
FW="$APP/Contents/Frameworks/Sparkle.framework"
for xpc in "$FW"/Versions/B/XPCServices/*.xpc; do
  [ -e "$xpc" ] && sign --preserve-metadata=entitlements "$xpc"
done
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"
codesign --verify --deep --strict "$APP"

notarize() {
  local file="$1"
  local log="$OUT/notary-$(basename "$file").json"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$log"
  if ! grep -q '"status" *: *"Accepted"' "$log"; then
    cat "$log" >&2
    local id; id=$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' "$log" | head -1)
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    echo "Notarization failed for $file" >&2
    exit 1
  fi
}

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
notarize "$OUT/app.zip"
xcrun stapler staple "$APP"
rm -f "$OUT/app.zip"

step "Making $DMG_NAME"
STAGE="$OUT/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Cable Tester.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT/$DMG_NAME"
hdiutil create -volname "Cable Tester $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/$DMG_NAME" -quiet
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$OUT/$DMG_NAME"

step "Notarizing the DMG"
notarize "$OUT/$DMG_NAME"
xcrun stapler staple "$OUT/$DMG_NAME"
spctl -a -t open --context context:primary-signature -v "$OUT/$DMG_NAME"

step "Signing the update for Sparkle"
SIG=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$OUT/$DMG_NAME")
echo "$SIG"

if [ "$DRY_RUN" = 1 ]; then
  step "Dry run: notarized DMG at $OUT/$DMG_NAME (not published)"
  exit 0
fi

NOTES="Cable Tester $VERSION"
[ -n "$NOTES_FILE" ] && NOTES=$(cat "$NOTES_FILE")

step "Publishing $TAG to $RELEASES_REPO"
printf '%s\n' "$NOTES" > "$OUT/notes.md"
gh release create "$TAG" "$OUT/$DMG_NAME" --repo "$RELEASES_REPO" --title "Cable Tester $VERSION" --notes-file "$OUT/notes.md"

step "Adding $VERSION to the update feed"
URL="https://github.com/$RELEASES_REPO/releases/download/$TAG/$DMG_NAME"
NOTES_HTML=$(printf '%s\n' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's#^- \(.*\)#<li>\1</li>#' -e 's#^\([^<].*\)$#<p>\1</p>#')
ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url=\"$URL\" type=\"application/octet-stream\" $SIG />
    </item>"
FEED_JSON=$(gh api "repos/$RELEASES_REPO/contents/appcast.xml")
FEED_SHA=$(printf '%s' "$FEED_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
printf '%s' "$FEED_JSON" | python3 -c 'import json,sys,base64; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["content"]).decode())' > "$OUT/appcast-old.xml"
ITEM="$ITEM" python3 - "$OUT/appcast-old.xml" "$OUT/appcast.xml" <<'PY'
import os, sys
old = open(sys.argv[1]).read()
marker = "</language>\n"
i = old.index(marker) + len(marker)
open(sys.argv[2], "w").write(old[:i] + os.environ["ITEM"] + "\n" + old[i:])
PY
gh api -X PUT "repos/$RELEASES_REPO/contents/appcast.xml" -f message="Cable Tester $VERSION" \
  -f content="$(base64 -i "$OUT/appcast.xml")" -f sha="$FEED_SHA" --jq .commit.sha

COPY="$HOME/Documents/Claude/zz-Misc/cable-tester/release"
mkdir -p "$COPY" && cp "$OUT/$DMG_NAME" "$COPY/"
step "Released Cable Tester $VERSION: https://github.com/$RELEASES_REPO/releases/tag/$TAG"
