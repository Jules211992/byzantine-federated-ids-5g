#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

EDGE4_IP="$VM5_IP"

echo
echo "=== EDGE4 TLS local CA inventory (before) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" "
set -euo pipefail
echo HOST:\$(hostname)
echo IP:\$(hostname -I | awk '{print \$1}')
echo
ls -la /opt/fl-client/tls 2>/dev/null || true
echo
if [ -f /opt/fl-client/tls/ca.crt ]; then
  echo '--- /opt/fl-client/tls/ca.crt fingerprint ---'
  openssl x509 -in /opt/fl-client/tls/ca.crt -noout -subject -issuer -fingerprint -sha256 || true
fi
echo
echo '--- /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt fingerprint ---'
openssl x509 -in /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt -noout -subject -issuer -fingerprint -sha256 || true
"

echo
echo "=== Copy correct CA into /opt/fl-client/tls/ca.crt ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" "
set -euo pipefail
sudo mkdir -p /opt/fl-client/tls
sudo cp -f /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt /opt/fl-client/tls/ca.crt
sudo chown -R ubuntu:ubuntu /opt/fl-client/tls
echo
echo '--- /opt/fl-client/tls/ca.crt fingerprint (after) ---'
openssl x509 -in /opt/fl-client/tls/ca.crt -noout -subject -issuer -fingerprint -sha256
"

echo
echo "=== OpenSSL verify from EDGE4 using /opt/fl-client/tls/ca.crt ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" "
set -euo pipefail
PEER_HOST=$PEER1_HOST
echo | openssl s_client -connect \${PEER_HOST}:7051 -servername \${PEER_HOST} -CAfile /opt/fl-client/tls/ca.crt >/dev/null 2>&1
echo RC=\$?
"

echo
echo "=== Smoke tx from edge-client-4 (anti-rollback) ==="
ROUND=1
FABRIC_ROUND=9800

set +e
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" \
  "bash /opt/fl-client/run_fl_round.sh edge-client-4 $ROUND Org1MSP $PEER1_HOST $FABRIC_ROUND"
RC=$?
set -e
echo "EDGE4_RC=$RC"

echo
echo "=== peer0.org1 logs (last 2 minutes) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" "
set -euo pipefail
docker logs peer0.org1.example.com --since 2m 2>&1 | tail -n 220 || true
" || true
