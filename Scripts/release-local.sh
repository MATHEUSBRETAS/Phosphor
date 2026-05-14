#!/bin/bash
# Local release: build, sign, notarize, staple, tag, publish, bump cask.
# Reads ASC API key from ~/.appstoreconnect/private_keys/.
# Usage: bash Scripts/release-local.sh v1.0.6

set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 vX.Y.Z"
    exit 1
fi
VERSION="${TAG#v}"

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Moamen Basel (H3WXHVTP97)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
REPO="${REPO:-momenbasel/Phosphor}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP=".build/Phosphor.app"
DMG=".build/Phosphor.dmg"
ENTITLEMENTS="Resources/Phosphor.entitlements"

echo "==> Building release"
rm -rf .build
swift build -c release
bash Scripts/build.sh

echo "==> Signing app"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Creating DMG"
bash Scripts/create-dmg.sh

echo "==> Signing DMG"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "==> Submitting to Apple notary (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

echo "==> Verifying"
spctl -a -vv -t install "$DMG"
xcrun stapler validate "$DMG"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "==> SHA256: $SHA"

if ! git tag -l "$TAG" | grep -q "^$TAG$"; then
    echo "==> Creating + pushing tag $TAG"
    git tag -a "$TAG" -m "$TAG"
    git push origin "$TAG"
fi

echo "==> Creating GitHub release"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || \
    gh release create "$TAG" --repo "$REPO" "$DMG" --title "$TAG" --generate-notes
gh release upload "$TAG" --repo "$REPO" "$DMG" --clobber

echo "==> Bumping Homebrew cask"
CASK="Homebrew/phosphor.rb"
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "$CASK"
/usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"

if ! git diff --quiet "$CASK"; then
    git add "$CASK"
    git commit -m "homebrew: bump cask to $TAG"
    git push origin main
fi

echo
echo "Released $TAG."
echo "  DMG: $DMG"
echo "  SHA: $SHA"
echo "  Release: https://github.com/$REPO/releases/tag/$TAG"
