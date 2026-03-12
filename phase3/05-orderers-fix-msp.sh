set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

fix_one() {
  ip="$1"
  ord="$2"
  volkey="$3"
  yml="$4"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "set -euo pipefail
cd /opt/fabric

test -d crypto-config/ordererOrganizations/example.com/orderers/$ord/msp/signcerts
test -d crypto-config/ordererOrganizations/example.com/orderers/$ord/msp/keystore
test -f crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/server.crt
test -f crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/server.key
test -f crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/ca.crt

cat > $yml <<YAML
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
      - ORDERER_GENERAL_BOOTSTRAPMETHOD=none
      - ORDERER_CHANNELPARTICIPATION_ENABLED=true

      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]

      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]

      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:7053
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_TLS_CLIENTAUTHREQUIRED=true
      - ORDERER_ADMIN_TLS_CLIENTROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    volumes:
      - ./crypto-config/ordererOrganizations/example.com/orderers/$ord/msp:/var/hyperledger/orderer/msp
      - ./crypto-config/ordererOrganizations/example.com/orderers/$ord/tls:/var/hyperledger/orderer/tls
      - $volkey:/var/hyperledger/production/orderer
    command: orderer

volumes:
  $volkey:
YAML

if sudo docker compose version >/dev/null 2>&1; then DC='sudo docker compose'; else DC='sudo docker-compose'; fi

\$DC -f $yml down -v || true
sudo docker rm -f $ord || true
sudo docker volume rm -f fabric_$volkey $volkey || true

\$DC -f $yml up -d

sleep 2

sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}' | egrep '$ord|NAMES' || true
sudo ss -lntp | egrep ':7050|:7053' || true
sudo docker logs --tail 60 $ord | egrep 'Starting orderer|ChannelParticipation|Admin.ListenAddress|panic|PANI|error' || true
"
}

fix_one "$VM6_IP" "orderer1.example.com" "orderer1data" "orderer1.yml"
fix_one "$VM7_IP" "orderer2.example.com" "orderer2data" "orderer2.yml"
fix_one "$VM8_IP" "orderer3.example.com" "orderer3data" "orderer3.yml"
