#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

ROUND=1
FABRIC_ROUND=1000

echo
echo "=== 1) Run one edge tx (expect success; if fail we collect logs) ==="
set +e
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" \
  "bash /opt/fl-client/run_fl_round.sh edge-client-1 $ROUND Org1MSP $PEER1_HOST $FABRIC_ROUND"
RC=$?
set -e
echo "EDGE_RC=$RC"
echo

echo "=== 2) peer0.org1 logs (last 5 min) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" "
set -euo pipefail
echo '--- peer0.org1.example.com (tail) ---'
docker logs peer0.org1.example.com --since 5m 2>&1 | tail -n 180 || true
echo
echo '--- chaincode container name ---'
CC=\$(docker ps --format '{{.Names}}' | grep -E '^dev-peer0\.org1\.example\.com-governance' | head -n 1 || true)
echo \"CC=\${CC:-NONE}\"
if [ -n \"\${CC:-}\" ]; then
  echo '--- chaincode logs (tail) ---'
  docker logs \"\$CC\" --since 5m 2>&1 | tail -n 180 || true
fi
echo
echo '--- inside peer0.org1: can it resolve/connect peer0.org2? ---'
docker exec peer0.org1.example.com sh -lc 'getent hosts peer0.org2.example.com || true'
docker exec peer0.org1.example.com sh -lc 'timeout 3 sh -lc \"</dev/tcp/peer0.org2.example.com/7051\" >/dev/null 2>&1; echo TCP_7051_RC=$?'
" || true

echo
echo "=== 3) peer0.org2 logs (last 5 min) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER2_IP" "
set -euo pipefail
echo '--- peer0.org2.example.com (tail) ---'
docker logs peer0.org2.example.com --since 5m 2>&1 | tail -n 180 || true
echo
echo '--- chaincode container name ---'
CC=\$(docker ps --format '{{.Names}}' | grep -E '^dev-peer0\.org2\.example\.com-governance' | head -n 1 || true)
echo \"CC=\${CC:-NONE}\"
if [ -n \"\${CC:-}\" ]; then
  echo '--- chaincode logs (tail) ---'
  docker logs \"\$CC\" --since 5m 2>&1 | tail -n 180 || true
fi
" || true
