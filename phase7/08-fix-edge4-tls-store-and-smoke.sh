#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

EDGE4_IP="$VM5_IP"
TLSCA_ORG1="$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"

echo
echo "=== 1) Install org1 TLSca into system trust store on $EDGE4_IP ==="
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TLSCA_ORG1" ubuntu@"$EDGE4_IP":/tmp/tlsca_org1.crt

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" "
set -euo pipefail
sudo cp -f /tmp/tlsca_org1.crt /usr/local/share/ca-certificates/tlsca_org1.crt
sudo update-ca-certificates >/dev/null 2>&1 || true
ls -la /etc/ssl/certs | grep -i tlsca_org1 || true
"

echo
echo "=== 2) Smoke tx from edge-client-4 (no pipe, keep real exit code) ==="
ROUND=1
FABRIC_ROUND=9500

set +e
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$EDGE4_IP" \
  "bash /opt/fl-client/run_fl_round.sh edge-client-4 $ROUND Org1MSP $PEER1_HOST $FABRIC_ROUND"
RC=$?
set -e
echo "EDGE4_RC=$RC"

echo
echo "=== 3) peer0.org1 logs (last 2 minutes) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" "
set -euo pipefail
docker logs peer0.org1.example.com --since 2m 2>&1 | tail -n 240 || true
" || true
