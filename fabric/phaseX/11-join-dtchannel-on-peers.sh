set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BLOCK_LOCAL=~/byz-fed-ids-5g/fabric/artifacts/dtchannel.block
BLOCK_HOST=/opt/fabric/dtchannel.block
BLOCK_IN_CONTAINER=/opt/fabric/dtchannel.block

run_one() {
  local ip="$1"
  local peer="$2"
  local org_domain="$3"
  local mspid="$4"
  local port="$5"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BLOCK_LOCAL" "ubuntu@${ip}:/tmp/dtchannel.block"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${ip}" bash -s -- \
    "$peer" "$org_domain" "$mspid" "$port" "$BLOCK_HOST" "$BLOCK_IN_CONTAINER" <<'REMOTE'
set -euo pipefail
peer="$1"
org_domain="$2"
mspid="$3"
port="$4"
block_host="$5"
block_in_container="$6"

sudo mkdir -p /opt/fabric
sudo mv /tmp/dtchannel.block "$block_host"
sudo test -f "$block_host"

sudo docker inspect "$peer" >/dev/null
if [ "$(sudo docker inspect -f '{{.State.Running}}' "$peer")" != "true" ]; then
  sudo docker start "$peer" >/dev/null
fi

sudo docker cp "$block_host" "${peer}:${block_in_container}"

admin_msp="$(sudo docker exec "$peer" bash -lc "
for p in \
  /opt/fabric/organizations/peerOrganizations/${org_domain}/users/Admin@${org_domain}/msp \
  /opt/fabric/organizations/peerOrganizations/${org_domain}/users/admin@${org_domain}/msp \
  /etc/hyperledger/fabric/organizations/peerOrganizations/${org_domain}/users/Admin@${org_domain}/msp \
  /etc/hyperledger/fabric/organizations/peerOrganizations/${org_domain}/users/admin@${org_domain}/msp
do
  [ -d \"\$p\" ] && echo \"\$p\" && exit 0
done
exit 1
")"

tls_root="$(sudo docker exec "$peer" bash -lc "
for p in \
  /etc/hyperledger/fabric/tls/ca.crt \
  /etc/hyperledger/fabric/tls/ca.pem \
  /opt/fabric/organizations/peerOrganizations/${org_domain}/peers/${peer}/tls/ca.crt \
  /etc/hyperledger/fabric/organizations/peerOrganizations/${org_domain}/peers/${peer}/tls/ca.crt
do
  [ -f \"\$p\" ] && echo \"\$p\" && exit 0
done
exit 1
")"

echo "peer=${peer} admin_msp=${admin_msp}"
echo "peer=${peer} tls_root=${tls_root}"

if sudo docker exec \
  -e CORE_PEER_ADDRESS="127.0.0.1:${port}" \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE="${peer}" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="${tls_root}" \
  "$peer" peer channel list 2>/dev/null | grep -q '^dtchannel$'
then
  sudo docker exec \
    -e CORE_PEER_ADDRESS="127.0.0.1:${port}" \
    -e CORE_PEER_TLS_SERVERHOSTOVERRIDE="${peer}" \
    -e CORE_PEER_TLS_ROOTCERT_FILE="${tls_root}" \
    "$peer" peer channel list
  exit 0
fi

sudo docker exec \
  -e CORE_PEER_ADDRESS="127.0.0.1:${port}" \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE="${peer}" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="${tls_root}" \
  -e CORE_PEER_LOCALMSPID="${mspid}" \
  -e CORE_PEER_MSPCONFIGPATH="${admin_msp}" \
  "$peer" peer channel join -b "${block_in_container}"

sudo docker exec \
  -e CORE_PEER_ADDRESS="127.0.0.1:${port}" \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE="${peer}" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="${tls_root}" \
  "$peer" peer channel list
REMOTE
}

run_one "$VM9_IP"  "peer0.org1.example.com" "org1.example.com" "Org1MSP" "7051"
run_one "$VM10_IP" "peer0.org2.example.com" "org2.example.com" "Org2MSP" "9051"
