#!/bin/bash
# Packages dist/Clockapp.app into a distributable DMG (drag & drop to /Applications).
#
# The app is self-signed (no paid Developer ID), so Gatekeeper will quarantine the
# download on colleagues' Macs — a README in the DMG explains the two workarounds.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Clockapp"
# Keep the version in sync with build-app.sh
VERSION="$(grep '^VERSION=' scripts/build-app.sh | cut -d'"' -f2)"
DMG="dist/${APP_NAME}-${VERSION}.dmg"

echo "▸ Building the app…"
./scripts/build-app.sh release >/dev/null

echo "▸ Staging DMG contents…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "dist/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/README.txt" <<'EOF'
Clockapp — installation
=======================

1. Glisse Clockapp.app sur le dossier « Applications » ci-contre.

2. L'app n'est pas notarisée par Apple (pas de compte développeur payant),
   donc macOS va bloquer le premier lancement. Deux options :

   Option A (terminal, recommandé) :
       xattr -cr /Applications/Clockapp.app
     puis lance l'app normalement.

   Option B (interface) :
     Lance l'app (refusée) → Réglages Système → Confidentialité et
     sécurité → bouton « Ouvrir quand même » en bas → relance.

3. Au premier lancement : icône ⏱️ dans la barre de menu →
   ⚙️ Réglages → onglet Clockify → colle ta clé API Clockify
   (clockify.me → Profile → Preferences → Advanced → API).

---

English: the app is not notarized. After copying to /Applications, either run
`xattr -cr /Applications/Clockapp.app` or approve it in System Settings →
Privacy & Security → "Open Anyway" after the first blocked launch.
EOF

echo "▸ Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

echo "✅ $(du -h "$DMG" | cut -f1 | tr -d ' ')  $DMG"
