#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/byz-fed-ids-5g"
source "$ROOT/config/config.env"

N="${1:-50}"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM9_IP}" bash -s -- "$N" <<'REMOTE'
set -euo pipefail
N="$1"

docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  -e CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
  hyperledger/fabric-tools:2.5 bash -lc "
set -euo pipefail
for i in \$(seq 1 \$N); do
  ID=\$(printf 'alert-%05d' \"\$i\")
  TS=\$(date +%s)
  peer chaincode invoke \
    -C dtchannel -n governance \
    --orderer orderer1.example.com:7050 \
    --ordererTLSHostnameOverride orderer1.example.com \
    --tls \
    --cafile /opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
    --peerAddresses peer0.org1.example.com:7051 \
    --tlsRootCertFiles /opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
    --peerAddresses peer0.org2.example.com:7051 \
    --tlsRootCertFiles /opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    --waitForEvent=false \
    -c '{\"function\":\"SubmitAlert\",\"Args\":[\"'\"\$ID\"'\",\"1\",\"client-edge1\",\"'\"\$TS\"'\",\"HIGH\",\"sig\",\"payload\",\"nonce\"]}' >/dev/null
done
LAST=\$(printf 'alert-%05d' \"\$N\")
peer chaincode query -C dtchannel -n governance -c '{\"function\":\"GetAlert\",\"Args\":[\"'\"\$LAST\"'\"]}'
"
REMOTE
