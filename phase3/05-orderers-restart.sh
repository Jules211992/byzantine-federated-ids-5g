set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

restart_one() {
  ip="$1"
  ord="$2"
  yml="$3"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" bash -s -- "$ord" "$yml" "$VM6_IP" "$VM7_IP" "$VM8_IP" <<'REMOTE'
set -euo pipefail

ord="$1"
yml="$2"
vm6="$3"
vm7="$4"
vm8="$5"

if command -v docker-compose >/dev/null 2>&1; then
  DC='sudo docker-compose'
else
  DC='sudo docker compose'
fi

cd /opt/fabric

test -d "crypto-config/ordererOrganizations/example.com/orderers/$ord/msp/signcerts"
test -d "crypto-config/ordererOrganizations/example.com/orderers/$ord/msp/keystore"
test -f "crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/server.crt"
test -f "crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/server.key"
test -f "crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/ca.crt"

sudo sed -i '/orderer1.example.com/d;/orderer2.example.com/d;/orderer3.example.com/d' /etc/hosts
printf '%s orderer1.example.com\n%s orderer2.example.com\n%s orderer3.example.com\n' "$vm6" "$vm7" "$vm8" | sudo tee -a /etc/hosts >/dev/null

vol="$(echo "$ord" | tr '.' '_')data"

cat > "$yml" <<YAML
services:
  $ord:
    image: hyperledger/fabric-orderer:2.5
    container_name: $ord
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
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=none
      - ORDERER_CHANNELPARTICIPATION_ENABLED=true
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:7053
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_TLS_CLIENTAUTHREQUIRED=true
      - ORDERER_ADMIN_TLS_CLIENTROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - /opt/fabric/crypto-config/ordererOrganizations/example.com/orderers/$ord/msp:/var/hyperledger/orderer/msp
      - /opt/fabric/crypto-config/ordererOrganizations/example.com/orderers/$ord/tls:/var/hyperledger/orderer/tls
      - $vol:/var/hyperledger/production/orderer
    command: orderer
volumes:
  $vol:
YAML

$DC -f "$yml" up -d --force-recreate

sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | egrep "$ord|NAMES" || true
sudo ss -lntp | egrep ':7050|:7053' || true
sudo docker logs --tail 60 "$ord" | egrep 'Starting orderer|Admin.ListenAddress|ChannelParticipation|panic' || true
REMOTE
}

restart_one "$VM6_IP" "orderer1.example.com" "orderer1.yml"
restart_one "$VM7_IP" "orderer2.example.com" "orderer2.yml"
restart_one "$VM8_IP" "orderer3.example.com" "orderer3.yml"
