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

echo "==> Building release (universal arm64 + x86_64)"
rm -rf .build
# Ship a universal binary so the app runs on both Apple Silicon and Intel Macs
# (issue #44). Scripts/build.sh honors PHOSPHOR_UNIVERSAL for the bundled binary.
export PHOSPHOR_UNIVERSAL=1
swift build -c release --arch arm64 --arch x86_64
bash Scripts/build.sh

echo "==> Verifying universal binary slices"
BINARY="$APP/Contents/MacOS/Phosphor"
if ! lipo -archs "$BINARY" | grep -q "x86_64" || ! lipo -archs "$BINARY" | grep -q "arm64"; then
    echo "ERROR: $BINARY is not universal (arch: $(lipo -archs "$BINARY")). Aborting release."
    exit 1
fi
echo "    slices: $(lipo -archs "$BINARY")"

echo "==> Signing app"
codesign --force --options runtime \
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

echo "==> Bumping in-repo Homebrew cask"
CASK="Homebrew/phosphor.rb"
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "$CASK"
/usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"

if ! git diff --quiet "$CASK"; then
    git add "$CASK"
    git commit -m "homebrew: bump cask to $TAG"
    git push origin main
fi

# Keep the external tap (`brew install --cask momenbasel/phosphor/phosphor`) in
# lockstep with the in-repo cask. Historically these drifted (issue #21: the tap
# still pointed at an old SHA after a release), so sync it from the SAME SHA here
# instead of by hand.
echo "==> Syncing external Homebrew tap"
TAP_REPO="${TAP_REPO:-momenbasel/homebrew-phosphor}"
TAP_CASK_PATH="Casks/phosphor.rb"
TAP_TMP="$(mktemp -d)"
if git clone --depth 1 "https://github.com/${TAP_REPO}.git" "$TAP_TMP" >/dev/null 2>&1; then
    TAP_CASK="$TAP_TMP/$TAP_CASK_PATH"
    if [ -f "$TAP_CASK" ]; then
        /usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "$TAP_CASK"
        /usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$TAP_CASK"
        if ! git -C "$TAP_TMP" diff --quiet; then
            git -C "$TAP_TMP" add "$TAP_CASK_PATH"
            git -C "$TAP_TMP" commit -m "phosphor: bump cask to $TAG (same DMG SHA as in-repo cask)"
            git -C "$TAP_TMP" push origin HEAD
            echo "    external tap synced to ${VERSION} / ${SHA}"
        else
            echo "    external tap already at ${VERSION} / ${SHA}"
        fi
    else
        echo "    WARNING: $TAP_CASK_PATH missing in $TAP_REPO - sync it manually"
    fi
else
    echo "    WARNING: could not clone $TAP_REPO - external tap NOT updated (fix manually to avoid SHA drift)"
fi
rm -rf "$TAP_TMP"

echo
echo "Released $TAG."
echo "  DMG: $DMG"
echo "  SHA: $SHA"
echo "  Release: https://github.com/$REPO/releases/tag/$TAG"
