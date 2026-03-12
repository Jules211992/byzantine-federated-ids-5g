#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
TARGETS=("$VM2_IP" "$VM3_IP")

for ip in "${TARGETS[@]}"; do
  echo
  echo "===== FIX ID PATHS on $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

sudo mkdir -p /opt/fl-client/crypto/identity/cert /opt/fl-client/crypto/identity/key

sed -i 's|^ID_CERT_PATH=.*|ID_CERT_PATH=/opt/fl-client/crypto/identity/cert|' /opt/fl-client/config.env || true
sed -i 's|^ID_KEY_PATH=.*|ID_KEY_PATH=/opt/fl-client/crypto/identity/key|' /opt/fl-client/config.env || true

echo '--- config.env (identity paths) ---'
grep -E '^ID_CERT_PATH=|^ID_KEY_PATH=|^CERT_PATH=' /opt/fl-client/config.env || true

echo
echo '--- identity dir listing ---'
ls -la /opt/fl-client/crypto/identity/cert || true
ls -la /opt/fl-client/crypto/identity/key || true

echo
echo '--- clean local .pem shortcuts that broke readdir (optional) ---'
rm -f /opt/fl-client/crypto/identity/cert.pem /opt/fl-client/crypto/identity/key.pem || true
ls -la /opt/fl-client/crypto/identity | sed -n '1,60p' || true
"
done

echo
echo "OK"
