#!/bin/bash
# Builds KeyFlag.app into build/ and signs it.
#
#   Scripts/build-app.sh                 release build, signed with the best identity found
#   CONFIG=debug Scripts/build-app.sh
#   SIGN_IDENTITY=- Scripts/build-app.sh  force ad hoc signing
#
# Settings can also live in Scripts/signing.local.env (gitignored; see
# Scripts/signing.example.env). Environment variables win over that file.
#
# Without SIGN_IDENTITY the script picks, in order: "Developer ID Application" (for
# distribution outside the App Store), "Apple Development" (local builds), ad hoc.
# macOS ties the Accessibility permission to the signature. Ad hoc signatures change on
# every build, so you'd have to re-grant the permission each time; a certificate-based
# identity keeps it between builds.
set -euo pipefail

cd "$(dirname "$0")/.."

# Keep values already set in the environment; fill the rest from the local file.
if [[ -f Scripts/signing.local.env ]]; then
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        value="${value%\"}"; value="${value#\"}"
        [[ -z "${!key:-}" ]] && export "$key=$value"
    done < Scripts/signing.local.env
fi

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-com.tnemec.keyflag}"
# Sparkle: the appcast and the EdDSA public key matching the private key in the maintainer's
# keychain (from Sparkle's generate_keys). Set SPARKLE_PUBLIC_KEY= (empty) to build an app
# that never checks for updates.
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/kurtcz/KeyFlag/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY-wmf4u/ZQsqPTVbiRk4MjnlbNf+Li2L38rJVV47I2tjU=}"
ENTITLEMENTS="Resources/KeyFlag.entitlements"

# Prints the SHA-1 of the first valid identity whose name starts with $1. Using the hash
# avoids codesign's "ambiguous identity" error when a certificate is installed twice.
find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -v prefix="\"$1" 'index($0, prefix) { print $2; exit }'
}

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(find_identity "Developer ID Application:")"
    [[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY="$(find_identity "Apple Development:")"
    [[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY="-"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    IDENTITY_NAME="ad hoc"
else
    IDENTITY_NAME="$(security find-identity -v -p codesigning \
        | awk -v id="$SIGN_IDENTITY" '$2 == id || index($0, "\"" id) { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }')"
    [[ -z "$IDENTITY_NAME" ]] && { echo "error: signing identity '$SIGN_IDENTITY' not found in the keychain" >&2; exit 1; }
fi

# Notarization needs a secure timestamp; local builds skip it so they work offline.
TIMESTAMP="--timestamp=none"
[[ "$IDENTITY_NAME" == "Developer ID Application:"* ]] && TIMESTAMP="--timestamp"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/KeyFlag.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/KeyFlag" "$APP/Contents/MacOS/KeyFlag"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
sed -e "s|\$(BUNDLE_ID)|$BUNDLE_ID|" \
    -e "s|\$(VERSION)|$VERSION|" \
    -e "s|\$(BUILD)|$BUILD|" \
    -e "s|\$(FEED_URL)|$FEED_URL|" \
    -e "s|\$(SPARKLE_PUBLIC_KEY)|$SPARKLE_PUBLIC_KEY|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
# App icon and the flags-only menu icon (regenerate with: swift Scripts/make-icon.swift).
install -m 644 Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
install -m 644 Resources/MenuIcon*.png "$APP/Contents/Resources/"
# Bundled resources (e.g. the Keyboard Viewer shortcut), when present.
find Resources -maxdepth 1 -name '*.shortcut' -exec install -m 644 {} "$APP/Contents/Resources/" \;
# Flags and coats of arms from Wikimedia Commons, with their credits.
ditto Resources/Flags "$APP/Contents/Resources/Flags"
ditto Resources/CoatsOfArms "$APP/Contents/Resources/CoatsOfArms"
install -m 644 Resources/Wikimedia-Credits.md "$APP/Contents/Resources/"

# Sign Sparkle's nested helpers inside out, then the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
    [[ -e "$nested" ]] && codesign --force --options runtime $TIMESTAMP --sign "$SIGN_IDENTITY" "$nested"
done
codesign --force --options runtime $TIMESTAMP --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime $TIMESTAMP \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP ($VERSION, build $BUILD, signed: $IDENTITY_NAME)"
