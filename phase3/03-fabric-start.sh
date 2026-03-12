set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/orderer1.yml" <<'EOC'
services:
  orderer1.example.com:
    container_name: orderer1.example.com
    image: hyperledger/fabric-orderer:2.5
    network_mode: host
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=7050
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=file
      - ORDERER_GENERAL_BOOTSTRAPFILE=/var/hyperledger/orderer/genesis/dtchannel.block
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:7053
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - ./example.com/orderers/orderer1.example.com/msp:/var/hyperledger/orderer/msp:ro
      - ./example.com/orderers/orderer1.example.com/tls:/var/hyperledger/orderer/tls:ro
      - ./dtchannel.block:/var/hyperledger/orderer/genesis/dtchannel.block:ro
      - orderer1data:/var/hyperledger/production/orderer
volumes:
  orderer1data:
EOC

cat > "$TMP/orderer2.yml" <<'EOC'
services:
  orderer2.example.com:
    container_name: orderer2.example.com
    image: hyperledger/fabric-orderer:2.5
    network_mode: host
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=8050
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=file
      - ORDERER_GENERAL_BOOTSTRAPFILE=/var/hyperledger/orderer/genesis/dtchannel.block
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:8053
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - ./example.com/orderers/orderer2.example.com/msp:/var/hyperledger/orderer/msp:ro
      - ./example.com/orderers/orderer2.example.com/tls:/var/hyperledger/orderer/tls:ro
      - ./dtchannel.block:/var/hyperledger/orderer/genesis/dtchannel.block:ro
      - orderer2data:/var/hyperledger/production/orderer
volumes:
  orderer2data:
EOC

cat > "$TMP/orderer3.yml" <<'EOC'
services:
  orderer3.example.com:
    container_name: orderer3.example.com
    image: hyperledger/fabric-orderer:2.5
    network_mode: host
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=9050
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=file
      - ORDERER_GENERAL_BOOTSTRAPFILE=/var/hyperledger/orderer/genesis/dtchannel.block
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:9053
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - ./example.com/orderers/orderer3.example.com/msp:/var/hyperledger/orderer/msp:ro
      - ./example.com/orderers/orderer3.example.com/tls:/var/hyperledger/orderer/tls:ro
      - ./dtchannel.block:/var/hyperledger/orderer/genesis/dtchannel.block:ro
      - orderer3data:/var/hyperledger/production/orderer
volumes:
  orderer3data:
EOC

cat > "$TMP/peer1.yml" <<EOC
services:
  peer0.org1.example.com:
    container_name: peer0.org1.example.com
    image: hyperledger/fabric-peer:2.5
    network_mode: host
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0.org1.example.com
      - CORE_PEER_LOCALMSPID=Org1MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_LISTENADDRESS=0.0.0.0:7051
      - CORE_PEER_ADDRESS=0.0.0.0:7051
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
      - CORE_PEER_CHAINCODEADDRESS=0.0.0.0:7052
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=${VM9_IP}:7051
      - CORE_PEER_GOSSIP_USELEADERELECTION=true
      - CORE_PEER_GOSSIP_ORGLEADER=false
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_OPERATIONS_LISTENADDRESS=0.0.0.0:9443
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=host
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock
      - ./peers/peer0.org1.example.com/msp:/etc/hyperledger/fabric/msp:ro
      - ./peers/peer0.org1.example.com/tls:/etc/hyperledger/fabric/tls:ro
      - peer0org1data:/var/hyperledger/production
volumes:
  peer0org1data:
EOC

cat > "$TMP/peer2.yml" <<EOC
services:
  peer0.org2.example.com:
    container_name: peer0.org2.example.com
    image: hyperledger/fabric-peer:2.5
    network_mode: host
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0.org2.example.com
      - CORE_PEER_LOCALMSPID=Org2MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_LISTENADDRESS=0.0.0.0:9051
      - CORE_PEER_ADDRESS=0.0.0.0:9051
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:9052
      - CORE_PEER_CHAINCODEADDRESS=0.0.0.0:9052
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=${VM10_IP}:9051
      - CORE_PEER_GOSSIP_USELEADERELECTION=true
      - CORE_PEER_GOSSIP_ORGLEADER=false
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_OPERATIONS_LISTENADDRESS=0.0.0.0:9444
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=host
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock
      - ./peers/peer0.org2.example.com/msp:/etc/hyperledger/fabric/msp:ro
      - ./peers/peer0.org2.example.com/tls:/etc/hyperledger/fabric/tls:ro
      - peer0org2data:/var/hyperledger/production
volumes:
  peer0org2data:
EOC

push_and_up() {
  local ip="$1"
  local file="$2"

  rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    "$file" ubuntu@"$ip":/opt/fabric/docker-compose.yml

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "set -euo pipefail
cd /opt/fabric
if sudo docker compose version >/dev/null 2>&1; then DC='sudo docker compose'; else DC='sudo docker-compose'; fi
\$DC down --remove-orphans || true
\$DC up -d
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
"
}

push_and_up "$VM6_IP" "$TMP/orderer1.yml"
push_and_up "$VM7_IP" "$TMP/orderer2.yml"
push_and_up "$VM8_IP" "$TMP/orderer3.yml"
push_and_up "$VM9_IP" "$TMP/peer1.yml"
push_and_up "$VM10_IP" "$TMP/peer2.yml"

echo "✓ Fabric démarré sur VM6–VM10"
