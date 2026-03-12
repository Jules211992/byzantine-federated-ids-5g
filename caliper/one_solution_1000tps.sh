#!/usr/bin/env bash
set -euo pipefail

source ~/byz-fed-ids-5g/config/config.env

if [ -d "$HOME/byz-fed-ids-5g/fabric/crypto-config" ]; then
  CRYPTO="$HOME/byz-fed-ids-5g/fabric/crypto-config"
elif [ -d "/opt/fabric/crypto-config" ]; then
  CRYPTO="/opt/fabric/crypto-config"
else
  echo "ERROR: crypto-config introuvable sur VM1"
  exit 1
fi

CHANNEL="dtchannel"
CC_ID="governance"

ORG1_MSPID="Org1MSP"
ORG2_MSPID="Org2MSP"

ORG1_TLS_CA="${CRYPTO}/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS_CA="${CRYPTO}/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
ORD_TLS_CA="$(ls -1 ${CRYPTO}/ordererOrganizations/example.com/msp/tlscacerts/*.pem | head -1)"

ORG1_CERT="$(ls -1 ${CRYPTO}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/*.pem | head -1)"
ORG2_CERT="$(ls -1 ${CRYPTO}/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/signcerts/*.pem | head -1)"
ORG1_KEY="$(ls -1 ${CRYPTO}/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/* | head -1)"
ORG2_KEY="$(ls -1 ${CRYPTO}/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/keystore/* | head -1)"

test -f "$ORG1_TLS_CA"
test -f "$ORG2_TLS_CA"
test -f "$ORD_TLS_CA"
test -f "$ORG1_CERT"
test -f "$ORG2_CERT"
test -f "$ORG1_KEY"
test -f "$ORG2_KEY"

mkdir -p networks benchmarks/workload results

ORG1_TLS_CA="$(readlink -f "$ORG1_TLS_CA")"
ORG2_TLS_CA="$(readlink -f "$ORG2_TLS_CA")"
ORD_TLS_CA="$(readlink -f "$ORD_TLS_CA")"
ORG1_CERT="$(readlink -f "$ORG1_CERT")"
ORG2_CERT="$(readlink -f "$ORG2_CERT")"
ORG1_KEY="$(readlink -f "$ORG1_KEY")"
ORG2_KEY="$(readlink -f "$ORG2_KEY")"

cat > networks/org1-connection.yaml <<CONNEOF
name: org1-connection
version: "1.0"
client:
  organization: ${ORG1_MSPID}
  connection:
    timeout:
      peer:
        endorser: "300"
      orderer: "300"
organizations:
  ${ORG1_MSPID}:
    mspid: ${ORG1_MSPID}
    peers:
      - peer0.org1.example.com
peers:
  peer0.org1.example.com:
    url: grpcs://peer0.org1.example.com:7051
    tlsCACerts:
      path: ${ORG1_TLS_CA}
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
orderers:
  orderer1.example.com:
    url: grpcs://orderer1.example.com:7050
    tlsCACerts:
      path: ${ORD_TLS_CA}
    grpcOptions:
      ssl-target-name-override: orderer1.example.com
      hostnameOverride: orderer1.example.com
CONNEOF

cat > networks/org2-connection.yaml <<CONNEOF
name: org2-connection
version: "1.0"
client:
  organization: ${ORG2_MSPID}
  connection:
    timeout:
      peer:
        endorser: "300"
      orderer: "300"
organizations:
  ${ORG2_MSPID}:
    mspid: ${ORG2_MSPID}
    peers:
      - peer0.org2.example.com
peers:
  peer0.org2.example.com:
    url: grpcs://peer0.org2.example.com:7051
    tlsCACerts:
      path: ${ORG2_TLS_CA}
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
orderers:
  orderer1.example.com:
    url: grpcs://orderer1.example.com:7050
    tlsCACerts:
      path: ${ORD_TLS_CA}
    grpcOptions:
      ssl-target-name-override: orderer1.example.com
      hostnameOverride: orderer1.example.com
CONNEOF

cat > networks/fabric-network.yaml <<NETEOF
name: fabric-network-2orgs
version: "2.0"
caliper:
  blockchain: fabric

channels:
  - channelName: ${CHANNEL}
    contracts:
      - id: ${CC_ID}

organizations:
  - mspid: ${ORG1_MSPID}
    identities:
      certificates:
        - name: admin-org1
          clientPrivateKey:
            path: ${ORG1_KEY}
          clientSignedCert:
            path: ${ORG1_CERT}
    connectionProfile:
      path: networks/org1-connection.yaml
      discover: true

  - mspid: ${ORG2_MSPID}
    identities:
      certificates:
        - name: admin-org2
          clientPrivateKey:
            path: ${ORG2_KEY}
          clientSignedCert:
            path: ${ORG2_CERT}
    connectionProfile:
      path: networks/org2-connection.yaml
      discover: true
NETEOF

cat > benchmarks/workload/submit-alert.js <<'JSEOF'
'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class SubmitAlertWorkload extends WorkloadModuleBase {
  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    this.contractId = 'governance';
    this.contractFunction = 'SubmitAlert';
    this.runId = process.env.CALIPER_RUN_ID || String(Date.now());
    this.clientId = `caliper-client-${workerIndex}-r${roundIndex}-${this.runId}`;
    this.meta = JSON.stringify({ model: 'caliper', run: this.runId, worker: workerIndex, round: roundIndex });
    this.i = 0;

    if (workerIndex % 2 === 0) {
      this.invokerMspId = 'Org1MSP';
      this.invokerIdentity = 'admin-org1';
    } else {
      this.invokerMspId = 'Org2MSP';
      this.invokerIdentity = 'admin-org2';
    }
  }

  async submitTransaction() {
    this.i++;
    const round = String(this.i);
    const now = String(Math.floor(Date.now() / 1000));
    const alertId = `cal-${this.workerIndex}-${round}-${this.runId}`;
    const severity = 'HIGH';
    const sig = `sig-${this.workerIndex}-${round}-${this.runId}`;
    const nonce = `n-${this.workerIndex}-${round}-${this.runId}`;

    const req = {
      contractId: this.contractId,
      contractFunction: this.contractFunction,
      invokerMspId: this.invokerMspId,
      invokerIdentity: this.invokerIdentity,
      contractArguments: [alertId, round, this.clientId, now, severity, sig, this.meta, nonce],
      readOnly: false
    };

    await this.sutAdapter.sendRequests(req);
  }
}

function createWorkloadModule() { return new SubmitAlertWorkload(); }
module.exports.createWorkloadModule = createWorkloadModule;
JSEOF

export CALIPER_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig networks/fabric-network.yaml \
  --caliper-benchconfig benchmarks/benchmark.yaml \
  --caliper-flow-only-test
