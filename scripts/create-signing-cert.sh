#!/bin/bash
# Creates (once) a stable self-signed code-signing identity named "Clockapp Dev"
# in your login keychain. Signing the app with a stable identity gives it a stable
# "designated requirement", so a single Keychain "Always Allow" survives every rebuild.
#
# Safe to run multiple times: it does nothing if the identity already exists.
set -euo pipefail

IDENTITY="Clockapp Dev"
BUNDLE_ID="com.jules.clockapp"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ L'identité « $IDENTITY » existe déjà — rien à faire."
    exit 0
fi

# Prefer an OpenSSL 3 (Homebrew) that supports -legacy; fall back to system openssl.
OPENSSL="$(command -v openssl)"
[ -x /opt/homebrew/bin/openssl ] && OPENSSL=/opt/homebrew/bin/openssl
P12LEGACY=""
"$OPENSSL" version | grep -q "OpenSSL 3" && P12LEGACY="-legacy"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3_code
prompt = no
[ dn ]
CN = Clockapp Dev
[ v3_code ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "▸ Génération du certificat auto-signé…"
"$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/openssl.cnf" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export $P12LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:clockapp -name "$IDENTITY" >/dev/null 2>&1

LOGIN_KC="$(security default-keychain -d user | tr -d ' "')"
[ -z "$LOGIN_KC" ] && LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

echo "▸ Import dans le trousseau : $LOGIN_KC"
# -A: allow any tool (incl. codesign) to use the key without prompting — avoids
#     needing your login password and avoids per-build codesign dialogs.
security import "$TMP/cert.p12" -k "$LOGIN_KC" -P clockapp -A

echo "✅ Identité « $IDENTITY » créée."
echo "   Reconstruis avec ./scripts/build-app.sh, puis au 1er lancement clique"
echo "   « Toujours autoriser » sur la demande du Trousseau — et c'est fini."
