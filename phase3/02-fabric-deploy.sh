set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BASE="$HOME/byz-fed-ids-5g/fabric"
ROLE_ENV="$HOME/byz-fed-ids-5g/config/fabric_nodes.env"
if [ -f "$ROLE_ENV" ]; then source "$ROLE_ENV"; fi

need() { [ -n "${1:-}" ] || { echo "MISSING_ROLE_ENV"; exit 1; }; }
need "${ORDERER1_IP:-}"; need "${ORDERER2_IP:-}"; need "${ORDERER3_IP:-}"; need "${PEER1_IP:-}"; need "${PEER2_IP:-}"

if [ ! -f "$BASE/artifacts/dtchannel.block" ]; then echo "MISSING_BLOCK"; exit 1; fi
if [ ! -d "$BASE/crypto-config" ]; then echo "MISSING_CRYPTO"; exit 1; fi

remote_mkdir() {
  local ip="$1"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "mkdir -p ~/byz-fed-ids-5g/fabric"
}

remote_sync() {
  local ip="$1"
  rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15" \
    "$BASE/crypto-config" "$BASE/artifacts" "$BASE/config" \
    "$SSH_USER@$ip:~/byz-fed-ids-5g/fabric/"
}

remote_write_compose_orderer() {
  local ip="$1" name="$2" port="$3" adminport="$4"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "cat > ~/byz-fed-ids-5g/fabric/docker-compose.yaml << 'EOC'
services:
  ${name}:
    image: hyperledger/fabric-orderer:2.5
    container_name: ${name}
    restart: unless-stopped
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=${port}
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=file
      - ORDERER_GENERAL_BOOTSTRAPFILE=/var/hyperledger/orderer/genesis/dtchannel.block
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:${adminport}
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - ./crypto-config/ordererOrganizations/example.com/orderers/${name}.example.com/msp:/var/hyperledger/orderer/msp:ro
      - ./crypto-config/ordererOrganizations/example.com/orderers/${name}.example.com/tls:/var/hyperledger/orderer/tls:ro
      - ./artifacts/dtchannel.block:/var/hyperledger/orderer/genesis/dtchannel.block:ro
      - ordererdata:/var/hyperledger/production/orderer
    ports:
      - \"${port}:${port}\"
      - \"${adminport}:${adminport}\"
volumes:
  ordererdata:
EOC"
}

remote_write_compose_peer() {
  local ip="$1" org="$2" peername="$3" port="$4" ops="$5"
  local mspid=""
  local mspdir=""
  local tlsdir=""
  if [ "$org" = "org1" ]; then
    mspid="Org1MSP"
    mspdir="./crypto-config/peerOrganizations/org1.example.com/peers/${peername}.org1.example.com/msp"
    tlsdir="./crypto-config/peerOrganizations/org1.example.com/peers/${peername}.org1.example.com/tls"
  else
    mspid="Org2MSP"
    mspdir="./crypto-config/peerOrganizations/org2.example.com/peers/${peername}.org2.example.com/msp"
    tlsdir="./crypto-config/peerOrganizations/org2.example.com/peers/${peername}.org2.example.com/tls"
  fi

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "cat > ~/byz-fed-ids-5g/fabric/docker-compose.yaml << 'EOP'
services:
  ${peername}:
    image: hyperledger/fabric-peer:2.5
    container_name: ${peername}
    restart: unless-stopped
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=host
      - CORE_PEER_ID=${peername}
      - CORE_PEER_ADDRESS=0.0.0.0:${port}
      - CORE_PEER_LISTENADDRESS=0.0.0.0:${port}
      - CORE_PEER_CHAINCODEADDRESS=0.0.0.0:$((port+1))
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:$((port+1))
      - CORE_PEER_GOSSIP_BOOTSTRAP=
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=${peername}:${port}
      - CORE_PEER_LOCALMSPID=${mspid}
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_OPERATIONS_LISTENADDRESS=0.0.0.0:${ops}
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock
      - ${mspdir}:/etc/hyperledger/fabric/msp:ro
      - ${tlsdir}:/etc/hyperledger/fabric/tls:ro
      - peerdata:/var/hyperledger/production
    ports:
      - \"${port}:${port}\"
      - \"${ops}:${ops}\"
volumes:
  peerdata:
EOP"
}

remote_up() {
  local ip="$1"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "cd ~/byz-fed-ids-5g/fabric && sudo docker compose up -d"
}

echo "DEPLOY_ORDERERS"
remote_mkdir "$ORDERER1_IP"; remote_sync "$ORDERER1_IP"; remote_write_compose_orderer "$ORDERER1_IP" "orderer1" "7050" "7053"; remote_up "$ORDERER1_IP"
remote_mkdir "$ORDERER2_IP"; remote_sync "$ORDERER2_IP"; remote_write_compose_orderer "$ORDERER2_IP" "orderer2" "8050" "8053"; remote_up "$ORDERER2_IP"
remote_mkdir "$ORDERER3_IP"; remote_sync "$ORDERER3_IP"; remote_write_compose_orderer "$ORDERER3_IP" "orderer3" "9050" "9053"; remote_up "$ORDERER3_IP"

echo "DEPLOY_PEERS"
remote_mkdir "$PEER1_IP"; remote_sync "$PEER1_IP"; remote_write_compose_peer "$PEER1_IP" "org1" "peer0" "7051" "9443"; remote_up "$PEER1_IP"
remote_mkdir "$PEER2_IP"; remote_sync "$PEER2_IP"; remote_write_compose_peer "$PEER2_IP" "org2" "peer0" "9051" "9444"; remote_up "$PEER2_IP"

echo "OK_PHASE3_DEPLOY"
