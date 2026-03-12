#!/usr/bin/env bash
set -euo pipefail

source ~/byz-fed-ids-5g/config/config.env

CHANNEL="dtchannel"
CC_NAME="governance"
CC_VERSION="1.1"
CC_SEQUENCE="3"
CC_LABEL="governance_1.1"
CC_POLICY="OR('Org1MSP.peer','Org2MSP.peer')"

ORDERER_ADDR="orderer1.example.com:7050"
ORDERER_HOST="orderer1.example.com"

REPO="$HOME/byz-fed-ids-5g"
PKG_DIR="$HOME/byz-fed-ids-5g/caliper/pkg"
PKG_TGZ="$PKG_DIR/governance_1.1.tgz"

VM_ORG1="$VM9_IP"
VM_ORG2="$VM10_IP"

mkdir -p "$PKG_DIR"
chmod 777 "$PKG_DIR"
rm -f "$PKG_TGZ"

OUT="$PKG_DIR/pkgid.out"
rm -f "$OUT"

docker run --rm --network host \
  -v "$REPO":/repo \
  -v "$PKG_DIR":/pkg \
  -w /repo \
  hyperledger/fabric-tools:2.2 sh -lc "
set -e
apk add --no-cache go >/dev/null
export HOME=/tmp
export GOPATH=/tmp/go
export GOCACHE=/tmp/go-build
export XDG_CACHE_HOME=/tmp
export GO111MODULE=on
mkdir -p /tmp/go /tmp/go-build
peer lifecycle chaincode package /pkg/governance_1.1.tgz --path ./fabric/chaincode/governance --lang golang --label governance_1.1
peer lifecycle chaincode calculatepackageid /pkg/governance_1.1.tgz
" | tr -d '\r' | tee "$OUT" >/dev/null

chmod 644 "$PKG_TGZ"

PKG_ID="$(grep -E '^governance_1\.1:[0-9a-f]+' "$OUT" | tail -n 1 || true)"
echo "PKG_ID=$PKG_ID"
test -n "$PKG_ID"

tar -xOf "$PKG_TGZ" metadata.json | python3 - <<'PY'
import sys, json
b = sys.stdin.buffer.read()
s = b.decode("utf-8")
j = json.loads(s)
assert j.get("label") == "governance_1.1"
assert j.get("type") == "golang"
print("OK: metadata.json UTF-8 + label OK")
PY

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PKG_TGZ" "ubuntu@${VM_ORG1}:/tmp/governance_1.1.tgz"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PKG_TGZ" "ubuntu@${VM_ORG2}:/tmp/governance_1.1.tgz"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" "
set -e
docker pull hyperledger/fabric-tools:2.2 >/dev/null
docker run --rm --network host \
  -v /opt/fabric:/opt/fabric \
  -v /tmp:/tmp \
  hyperledger/fabric-tools:2.2 sh -lc '
set -e
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org1.example.com
peer lifecycle chaincode install /tmp/governance_1.1.tgz
'
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG2}" "
set -e
docker pull hyperledger/fabric-tools:2.2 >/dev/null
docker run --rm --network host \
  -v /opt/fabric:/opt/fabric \
  -v /tmp:/tmp \
  hyperledger/fabric-tools:2.2 sh -lc '
set -e
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer0.org2.example.com:7051
export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org2.example.com
peer lifecycle chaincode install /tmp/governance_1.1.tgz
'
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" "
set -e
docker run --rm --network host \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.2 sh -lc '
set -e
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org1.example.com
peer lifecycle chaincode approveformyorg \
  -o ${ORDERER_ADDR} --ordererTLSHostnameOverride ${ORDERER_HOST} \
  --tls --cafile /opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -C ${CHANNEL} -n ${CC_NAME} -v ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --package-id ${PKG_ID} \
  --signature-policy \"${CC_POLICY}\"
'
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG2}" "
set -e
docker run --rm --network host \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.2 sh -lc '
set -e
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer0.org2.example.com:7051
export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org2.example.com
peer lifecycle chaincode approveformyorg \
  -o ${ORDERER_ADDR} --ordererTLSHostnameOverride ${ORDERER_HOST} \
  --tls --cafile /opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -C ${CHANNEL} -n ${CC_NAME} -v ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --package-id ${PKG_ID} \
  --signature-policy \"${CC_POLICY}\"
'
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" "
set -e
docker run --rm --network host \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.2 sh -lc '
set -e
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_TLS_SERVERHOSTOVERRIDE=peer0.org1.example.com
peer lifecycle chaincode commit \
  -o ${ORDERER_ADDR} --ordererTLSHostnameOverride ${ORDERER_HOST} \
  --tls --cafile /opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -C ${CHANNEL} -n ${CC_NAME} -v ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --signature-policy \"${CC_POLICY}\" \
  --peerAddresses peer0.org1.example.com:7051 --tlsRootCertFiles /opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses peer0.org2.example.com:7051 --tlsRootCertFiles /opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

peer lifecycle chaincode querycommitted -C ${CHANNEL} -n ${CC_NAME}
'
"
