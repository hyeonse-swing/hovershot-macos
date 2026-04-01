#!/bin/zsh

set -euo pipefail

IDENTITY_NAME="${1:-HoverShot Local Development}"
TMP_DIR="$(mktemp -d /tmp/hovershot-codesign.XXXXXX)"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
PASS_PHRASE="hovershot"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Codesigning identity already exists:"
  echo "$IDENTITY_NAME"
  exit 0
fi

cat > "$TMP_DIR/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[dn]
CN = ${IDENTITY_NAME}
O = HoverShot
OU = Local Development
C = KR

[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

/opt/homebrew/bin/openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -config "$TMP_DIR/openssl.cnf" \
  -keyout "$TMP_DIR/key.pem" \
  -out "$TMP_DIR/cert.pem" \
  >/dev/null 2>&1

/opt/homebrew/bin/openssl pkcs12 \
  -export \
  -inkey "$TMP_DIR/key.pem" \
  -in "$TMP_DIR/cert.pem" \
  -out "$TMP_DIR/codesign.p12" \
  -passout "pass:$PASS_PHRASE" \
  >/dev/null 2>&1

security import "$TMP_DIR/codesign.p12" \
  -k "$KEYCHAIN" \
  -f pkcs12 \
  -P "$PASS_PHRASE" \
  -A \
  >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k "$KEYCHAIN" \
  "$TMP_DIR/cert.pem" \
  >/dev/null 2>&1 || true

echo "Created local codesigning identity:"
security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY_NAME\""
