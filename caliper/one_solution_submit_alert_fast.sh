#!/usr/bin/env bash
set -euo pipefail

source ~/byz-fed-ids-5g/config/config.env

CHANNEL="dtchannel"
CC_NAME="governance"
CC_VERSION="1.1"
CC_SEQUENCE="3"
CC_LABEL="governance_1.1"

VM_ORG1="$VM9_IP"
VM_ORG2="$VM10_IP"

ORDERER_ADDR="orderer1.example.com:7050"
ORDERER_HOST="orderer1.example.com"

CAFILE="/opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

ORG1_MSP="/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
ORG2_MSP="/opt/fabric/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"

ORG1_TLS="/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS="/opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

REPO="$HOME/byz-fed-ids-5g"
CC_DIR="$REPO/fabric/chaincode/governance"

GOV_GO="$CC_DIR/governance.go"
test -f "$GOV_GO"

PKG="$(awk '/^package[[:space:]]+/{print $2; exit}' "$GOV_GO")"
test -n "$PKG"

RCV="GovernanceContract"
test -n "$RCV"

cat > "$CC_DIR/submit_alert_fast.go" <<GOEOF
package ${PKG}

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type AlertFast struct {
	AlertID    string \`json:"alertId"\`
	Round      string \`json:"round"\`
	ClientID   string \`json:"clientId"\`
	Timestamp  string \`json:"timestamp"\`
	Severity   string \`json:"severity"\`
	Signature  string \`json:"signature"\`
	Meta       string \`json:"meta"\`
	Nonce      string \`json:"nonce"\`
	TxID       string \`json:"txId"\`
}

func (s *${RCV}) SubmitAlert(ctx contractapi.TransactionContextInterface, alertId, round, clientId, timestamp, severity, signature, meta, nonce string) error {
	txid := ctx.GetStub().GetTxID()
	key := fmt.Sprintf("ALERTFAST_%s_%s_%s", clientId, round, txid)

	obj := AlertFast{
		AlertID:   alertId,
		Round:     round,
		ClientID:  clientId,
		Timestamp: timestamp,
		Severity:  severity,
		Signature: signature,
		Meta:      meta,
		Nonce:     nonce,
		TxID:      txid,
	}

	b, err := json.Marshal(obj)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, b)
}
GOEOF

mkdir -p "$REPO/caliper/tmp"
PKG_TGZ="$REPO/caliper/tmp/${CC_LABEL}.tgz"
rm -f "$PKG_TGZ"

docker run --rm --user $(id -u):$(id -g) -e GOPATH=/tmp/go -e GOCACHE=/tmp/go-cache \
  -v "$REPO:/ws" \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode package "/ws/caliper/tmp/${CC_LABEL}.tgz" \
    --path "/ws/fabric/chaincode/governance" \
    --lang golang \
    --label "${CC_LABEL}"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" "sudo mkdir -p /opt/fabric/chaincode && sudo chown -R ubuntu:ubuntu /opt/fabric/chaincode"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG2}" "sudo mkdir -p /opt/fabric/chaincode && sudo chown -R ubuntu:ubuntu /opt/fabric/chaincode"

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PKG_TGZ" "ubuntu@${VM_ORG1}:/opt/fabric/chaincode/${CC_LABEL}.tgz"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PKG_TGZ" "ubuntu@${VM_ORG2}:/opt/fabric/chaincode/${CC_LABEL}.tgz"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" bash -lc "
set -euo pipefail
docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG1_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG1_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode install '/opt/fabric/chaincode/${CC_LABEL}.tgz' >/dev/null

docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG1_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG1_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode queryinstalled --output json > /opt/fabric/chaincode/queryinstalled_org1.json
"

PKG_ID="$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" python3 - <<'PY'
import json
p="/opt/fabric/chaincode/queryinstalled_org1.json"
d=json.load(open(p))
label="'"${CC_LABEL}"'"
for it in d.get("installed_chaincodes",[]):
    if it.get("label")==label:
        print(it.get("package_id",""))
        raise SystemExit(0)
print("")
PY
)"
test -n "$PKG_ID"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG2}" bash -lc "
set -euo pipefail
docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG2_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG2_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode install '/opt/fabric/chaincode/${CC_LABEL}.tgz' >/dev/null
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" bash -lc "
set -euo pipefail
docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG1_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG1_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode approveformyorg \
    -C '${CHANNEL}' -n '${CC_NAME}' -v '${CC_VERSION}' \
    --package-id '${PKG_ID}' --sequence '${CC_SEQUENCE}' \
    --channel-config-policy Endorsement \
    --orderer '${ORDERER_ADDR}' --ordererTLSHostnameOverride '${ORDERER_HOST}' \
    --tls --cafile '${CAFILE}' >/dev/null
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG2}" bash -lc "
set -euo pipefail
docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG2_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG2_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode approveformyorg \
    -C '${CHANNEL}' -n '${CC_NAME}' -v '${CC_VERSION}' \
    --package-id '${PKG_ID}' --sequence '${CC_SEQUENCE}' \
    --channel-config-policy Endorsement \
    --orderer '${ORDERER_ADDR}' --ordererTLSHostnameOverride '${ORDERER_HOST}' \
    --tls --cafile '${CAFILE}' >/dev/null
"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM_ORG1}" bash -lc "
set -euo pipefail
docker run --rm --network host -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE='${ORG1_TLS}' \
  -e CORE_PEER_MSPCONFIGPATH='${ORG1_MSP}' \
  hyperledger/fabric-tools:2.5 \
  peer lifecycle chaincode commit \
    -C '${CHANNEL}' -n '${CC_NAME}' -v '${CC_VERSION}' \
    --sequence '${CC_SEQUENCE}' \
    --channel-config-policy Endorsement \
    --peerAddresses peer0.org1.example.com:7051 --tlsRootCertFiles '${ORG1_TLS}' \
    --peerAddresses peer0.org2.example.com:7051 --tlsRootCertFiles '${ORG2_TLS}' \
    --orderer '${ORDERER_ADDR}' --ordererTLSHostnameOverride '${ORDERER_HOST}' \
    --tls --cafile '${CAFILE}' >/dev/null
"

sed -i 's/SubmitAlert/SubmitAlert/g' benchmarks/workload/submit-alert.js

cat > benchmarks/benchmark.yaml <<'YAML'
test:
  name: governance-submitalert-fast
  description: 15 workers, 50k tx per TPS point, SubmitAlert
  workers:
    type: local
    number: 15

  rounds:
    - label: submit-fast-tps500
      txNumber: 50000
      rateControl:
        type: fixed-rate
        opts:
          tps: 500
      workload:
        module: benchmarks/workload/submit-alert.js
        arguments:
          contractId: governance

    - label: submit-fast-tps1000
      txNumber: 50000
      rateControl:
        type: fixed-rate
        opts:
          tps: 1000
      workload:
        module: benchmarks/workload/submit-alert.js
        arguments:
          contractId: governance

    - label: submit-fast-tps1500
      txNumber: 50000
      rateControl:
        type: fixed-rate
        opts:
          tps: 1500
      workload:
        module: benchmarks/workload/submit-alert.js
        arguments:
          contractId: governance

    - label: submit-fast-tps2000
      txNumber: 50000
      rateControl:
        type: fixed-rate
        opts:
          tps: 2000
      workload:
        module: benchmarks/workload/submit-alert.js
        arguments:
          contractId: governance
YAML

echo "OK package_id=${PKG_ID}"
echo "Run now:"
echo "cd ~/byz-fed-ids-5g/caliper && npx caliper launch manager --caliper-workspace . --caliper-networkconfig networks/fabric-network.yaml --caliper-benchconfig benchmarks/benchmark.yaml"
