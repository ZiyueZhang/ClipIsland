#!/bin/bash
# Build a release .app, zip it, and publish a GitHub Release.
# Usage: ./scripts/release.sh 1.0.1 ["release notes title"]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: release.sh <version> e.g. 1.0.1}"
APP="build/ClipIsland.app"
ZIP="build/ClipIsland-${VERSION}.zip"

echo "==> building release"
./scripts/build-app.sh release

echo "==> packaging $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> running self-tests"
swift run SelfTest > /dev/null

if ! gh auth status > /dev/null 2>&1; then
    echo "gh not authenticated; release artifact ready at $ZIP (publish manually)"
    exit 0
fi

echo "==> creating GitHub release v$VERSION"
gh release create "v$VERSION" "$ZIP" \
    --title "ClipIsland v$VERSION" \
    --generate-notes

echo "==> done: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/v$VERSION"
