#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env
source config/fabric_nodes.env 2>/dev/null || true

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "=============================="
  echo "EDGE=$ip"
  echo "------------------------------"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo

echo '--- getent hosts peer0.org1.example.com ---'
getent hosts peer0.org1.example.com || true
echo

echo '--- /etc/hosts lines (peer/orderer) ---'
grep -E 'peer0\.org1\.example\.com|peer0\.org2\.example\.com|orderer|ORDERER' /etc/hosts || true
echo

echo '--- TLS server cert seen on :7051 (peer0.org1) ---'
timeout 6 bash -lc '
  echo | openssl s_client -connect peer0.org1.example.com:7051 -servername peer0.org1.example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -fingerprint -sha256
' || echo 'OPENSSL_FAIL'
echo

echo '--- quick tcp check :7051 and :7050 ---'
timeout 3 bash -lc 'nc -vz peer0.org1.example.com 7051' 2>&1 | tail -n 1 || true
timeout 3 bash -lc 'nc -vz orderer.example.com 7050' 2>&1 | tail -n 1 || true
"
done

echo
echo "DONE"
