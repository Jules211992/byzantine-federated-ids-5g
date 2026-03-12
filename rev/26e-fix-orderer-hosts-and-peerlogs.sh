#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

PEER_IP="${VM9_IP:-10.10.0.126}"
ORDERER1_IP="${VM6_IP:-10.10.0.52}"

echo "PEER_IP=$PEER_IP"
echo "ORDERER1_IP=$ORDERER1_IP"
echo

echo "=== 1) Fix /etc/hosts on all edges: add orderer.example.com alias ==="
for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "----- EDGE $ip -----"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
if ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+orderer\.example\.com([[:space:]]|\$)' /etc/hosts; then
  echo '$ORDERER1_IP orderer.example.com' | sudo tee -a /etc/hosts >/dev/null
fi
getent hosts orderer.example.com || true
"
done

echo
echo "=== 2) Collect peer0.org1 docker logs (last 15 minutes) for endorsement reason ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$PEER_IP" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo

C=\$(sudo docker ps --format '{{.Names}}' | grep -E '^peer0\.org1(\.|$)' | head -n 1 || true)
if [ -z \"\$C\" ]; then
  C=\$(sudo docker ps --format '{{.Names}}' | grep -i 'peer0' | head -n 1 || true)
fi
echo PEER_CONTAINER=\"\$C\"
[ -n \"\$C\" ] || { echo 'ERROR: peer container not found'; exit 1; }

echo
echo '--- grep suspicious lines (endorse/VSCC/ACL/MSP/creator/signature/MVCC) ---'
sudo docker logs --since 15m \"\$C\" 2>/dev/null | grep -E 'endorse|VSCC|ACL|creator|MSP|signature|access|policy|MVCC|validation|error|failed' | tail -n 260 || true

echo
echo '--- raw tail (last 200 lines) ---'
sudo docker logs --tail 200 \"\$C\" 2>/dev/null || true
"

echo
echo "DONE"
