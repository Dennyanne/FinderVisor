#!/bin/zsh
# Creates a self-signed code-signing identity "FinderVisor Local Signing" in your login keychain
# and trusts it for code signing, so rebuilt FinderVisor builds keep their privacy permissions.
# macOS asks for your login password (or Touch ID) when the trust setting is added.
set -euo pipefail

NAME="FinderVisor Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # system LibreSSL: produces a PKCS#12 file that `security import` accepts

if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
  echo "'$NAME' already exists and is trusted. Nothing to do."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
P12_PASS=$("$OPENSSL" rand -hex 16)

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASS"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
echo "Adding code-signing trust (macOS will ask for your password)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
  echo "Done: '$NAME' is a valid code-signing identity."
else
  echo "The certificate was imported but is not yet a valid code-signing identity." >&2
  exit 1
fi
