#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

CRYPTO="$HOME/byz-fed-ids-5g/fabric/crypto-config"
CH="$CHANNEL_NAME"

echo
echo "=== peer0.org1 (Org1MSP) ==="
docker run --rm --network host \
  --add-host "peer0.org1.example.com:${PEER1_IP}" \
  -v "${CRYPTO}:/crypto:ro" \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_MSPCONFIGPATH=/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode querycommitted -C "$CH" -n governance 2>&1 | sed -n '1,220p'

echo
echo "=== peer0.org2 (Org2MSP) ==="
docker run --rm --network host \
  --add-host "peer0.org2.example.com:${PEER2_IP}" \
  -v "${CRYPTO}:/crypto:ro" \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_MSPCONFIGPATH=/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode querycommitted -C "$CH" -n governance 2>&1 | sed -n '1,220p'
