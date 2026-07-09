#!/bin/bash
# Cuts a release: bumps the version, commits, tags and pushes.
# GitHub Actions (.github/workflows/release.yml) then builds, signs and
# publishes the zip + DMG on the GitHub release.
#
# Usage: ./scripts/release.sh 0.2.0
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version, e.g. 0.2.0 or 0.2.0-rc.1>}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "❌ Version invalide « $VERSION » (attendu: X.Y.Z ou X.Y.Z-rc.N)" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Working tree non propre — commit ou stash d'abord." >&2
    exit 1
fi

echo "▸ Bump version → $VERSION"
sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" scripts/build-app.sh

git add scripts/build-app.sh
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push origin main "v$VERSION"

if [[ "$VERSION" == *-* ]]; then
    echo "✅ Tag v$VERSION (pré-release/RC) poussé — la CI construit et publie la release :"
else
    echo "✅ Tag v$VERSION poussé — la CI construit et publie la release :"
fi
echo "   https://github.com/jklakosz/clockapp/actions"
