#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

for spec in "peer0.org1.example.com:$PEER1_IP" "peer0.org2.example.com:$PEER2_IP"; do
  peer_name="${spec%%:*}"
  ip="${spec##*:}"

  echo
  echo "===== $peer_name @ $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'peer0\.org1|peer0\.org2|dev-peer0' || true
echo
docker exec $peer_name peer lifecycle chaincode querycommitted -C $CHANNEL_NAME -n governance 2>&1 | sed -n '1,220p'
"
done
