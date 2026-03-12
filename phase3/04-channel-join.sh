set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

cd ~/byz-fed-ids-5g/fabric
IMG="hyperledger/fabric-tools:2.5"

docker run --rm --network host \
  -v "$PWD":/work -w /work \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_MSPCONFIGPATH=/work/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
  -e CORE_PEER_ADDRESS=${VM9_IP}:7051 \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/work/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org1.example.com \
  "$IMG" peer channel join -b artifacts/dtchannel.block

docker run --rm --network host \
  -v "$PWD":/work -w /work \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_MSPCONFIGPATH=/work/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
  -e CORE_PEER_ADDRESS=${VM10_IP}:9051 \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/work/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org2.example.com \
  "$IMG" peer channel join -b artifacts/dtchannel.block

docker run --rm --network host \
  -v "$PWD":/work -w /work \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_MSPCONFIGPATH=/work/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
  -e CORE_PEER_ADDRESS=${VM9_IP}:7051 \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/work/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org1.example.com \
  "$IMG" peer channel list

docker run --rm --network host \
  -v "$PWD":/work -w /work \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_MSPCONFIGPATH=/work/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
  -e CORE_PEER_ADDRESS=${VM10_IP}:9051 \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/work/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  -e CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org2.example.com \
  "$IMG" peer channel list
