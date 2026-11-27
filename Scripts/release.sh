#!/bin/bash
# Builds, signs with Developer ID, notarizes and staples KeyFlag.app, then zips it for
# distribution: build/KeyFlag-<version>.zip
#
#   VERSION=0.2.0 Scripts/release.sh
#
# Needs a "Developer ID Application" certificate in the keychain and a notarytool
# keychain profile (default name "KeyFlag"):
#   xcrun notarytool store-credentials KeyFlag --apple-id <id> --team-id <team>
# Both can be set in Scripts/signing.local.env.
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f Scripts/signing.local.env ]] && NOTARY_PROFILE="${NOTARY_PROFILE:-$(sed -n 's/^NOTARY_PROFILE="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' Scripts/signing.local.env)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-KeyFlag}"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | awk 'index($0, "\"Developer ID Application:") { print $2; exit }')"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "error: no \"Developer ID Application\" identity in the keychain." >&2
        echo "Create one at developer.apple.com > Certificates (Apple Development and" >&2
        echo "Apple Distribution certificates can't be notarized for direct download)." >&2
        exit 1
    fi
fi
export SIGN_IDENTITY CONFIG=release

Scripts/build-app.sh

APP="build/KeyFlag.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="build/KeyFlag-$VERSION.zip"

# Capture first: with pipefail, grep -q closing the pipe early would fail the check.
SIGNATURE_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_INFO" \
    || { echo "error: $APP is not signed with a Developer ID Application identity" >&2; exit 1; }

# Zip without extended attributes. Plain `ditto -c -k` stores them as AppleDouble `._*`
# files; unzippers other than Archive Utility extract those into the bundle, which breaks
# the code signature and makes Gatekeeper reject the app.
make_zip() {
    rm -f "$ZIP"
    ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP" "$ZIP"
    if zipinfo -1 "$ZIP" | grep -q -e '/\._' -e '^__MACOSX/'; then
        echo "error: $ZIP contains AppleDouble files" >&2; exit 1
    fi
}

make_zip
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the download carries the stapled ticket.
make_zip
spctl --assess --type execute --verbose "$APP"

# Check the app as a downloader that doesn't use Archive Utility would get it.
CHECK_DIR="$(mktemp -d)"
unzip -q "$ZIP" -d "$CHECK_DIR"
codesign --verify --deep --strict "$CHECK_DIR/$(basename "$APP")"
xcrun stapler validate -q "$CHECK_DIR/$(basename "$APP")"
rm -rf "$CHECK_DIR"
echo "Notarized $ZIP"

# Sparkle: sign the zip with the EdDSA key from the keychain and print the appcast item.
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
if [[ -x "$SPARKLE_BIN/sign_update" ]]; then
    BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
    SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"
    DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/kurtcz/KeyFlag/releases/download/v$VERSION/$(basename "$ZIP")}"
    cat <<ITEM

Add this item to appcast.xml, upload $ZIP to the v$VERSION release, and push:

    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$DOWNLOAD_URL" $SIGNATURE type="application/octet-stream"/>
    </item>
ITEM
fi
