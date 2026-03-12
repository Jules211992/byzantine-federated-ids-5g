#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
TARGETS=("$VM2_IP" "$VM3_IP")

for ip in "${TARGETS[@]}"; do
  echo
  echo "===== FIX IDENTITY PATHS on $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail

mkdir -p /opt/fl-client/crypto/identity/cert /opt/fl-client/crypto/identity/key

rm -f /opt/fl-client/crypto/identity/cert.pem /opt/fl-client/crypto/identity/key.pem || true

rm -f /opt/fl-client/crypto/identity/cert/user1.pem || true

CERT=\$(ls -1 /opt/fl-client/crypto/identity/cert/*.pem 2>/dev/null | grep -m1 'User1@org1.example.com' || true)
KEY=\$(ls -1 /opt/fl-client/crypto/identity/key/* 2>/dev/null | head -n 1 || true)

echo CERT_FOUND=\$CERT
echo KEY_FOUND=\$KEY

[ -n \"\$CERT\" ] || { echo 'ERROR: missing User1 cert in /opt/fl-client/crypto/identity/cert'; exit 1; }
[ -n \"\$KEY\" ]  || { echo 'ERROR: missing key in /opt/fl-client/crypto/identity/key'; exit 1; }

ls -1 /opt/fl-client/crypto/identity/cert/*.pem | while read -r f; do
  if [ \"\$f\" != \"\$CERT\" ]; then rm -f \"\$f\"; fi
done

sed -i 's|^ID_CERT_PATH=.*|ID_CERT_PATH=/opt/fl-client/crypto/identity/cert|' /opt/fl-client/config.env
sed -i 's|^ID_KEY_PATH=.*|ID_KEY_PATH=/opt/fl-client/crypto/identity/key|' /opt/fl-client/config.env

echo '--- config.env ---'
grep -E 'CERT_PATH|ID_CERT_PATH|ID_KEY_PATH' /opt/fl-client/config.env || true

echo '--- cert dir ---'
ls -la /opt/fl-client/crypto/identity/cert

echo '--- key dir ---'
ls -la /opt/fl-client/crypto/identity/key
"
done

echo DONE
