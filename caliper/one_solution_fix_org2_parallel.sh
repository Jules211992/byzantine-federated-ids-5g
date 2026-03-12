#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/byz-fed-ids-5g/caliper"

TS="$(date +%Y%m%d-%H%M%S)"

CRYPTO="${CRYPTO_PATH:-$HOME/byz-fed-ids-5g/fabric/crypto-config}"
CHANNEL="${CHANNEL:-dtchannel}"
CC_ID="${CC_ID:-governance}"
CC_FCN="${CC_FCN:-SubmitAlert}"

ORG1_MSPID="${ORG1_MSPID:-Org1MSP}"
ORG2_MSPID="${ORG2_MSPID:-Org2MSP}"

mkdir -p networks benchmarks/workload results

if [ -f networks/fabric-network.yaml ]; then cp -a networks/fabric-network.yaml "networks/fabric-network.yaml.bak_${TS}"; fi
if [ -f networks/org2-connection.yaml ]; then cp -a networks/org2-connection.yaml "networks/org2-connection.yaml.bak_${TS}"; fi
if [ -f benchmarks/workload/submit-alert.js ]; then cp -a benchmarks/workload/submit-alert.js "benchmarks/workload/submit-alert.js.bak_${TS}"; fi

ORG1_KEY="$(ls -1 "$CRYPTO/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/"* | head -1)"
ORG2_KEY="$(ls -1 "$CRYPTO/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/keystore/"* | head -1)"
ORG1_CERT="$(ls -1 "$CRYPTO/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/"*.pem | head -1)"
ORG2_CERT="$(ls -1 "$CRYPTO/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/signcerts/"*.pem | head -1)"
ORD_TLS_CA="$(ls -1 "$CRYPTO/ordererOrganizations/example.com/msp/tlscacerts/"*.pem | head -1)"

ORG2_TLS_CA="$CRYPTO/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

cat > networks/org2-connection.yaml <<EON
name: org2-connection
version: "1.0"
client:
  organization: Org2MSP
  connection:
    timeout:
      peer:
        endorser: "300"
      orderer: "300"
organizations:
  Org2MSP:
    mspid: Org2MSP
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
EON

cat > networks/fabric-network.yaml <<EON
name: dtchannel-caliper
version: "2.0.0"

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
          admin: true
          clientPrivateKey:
            path: ${ORG1_KEY}
          clientSignedCert:
            path: ${ORG1_CERT}
    connectionProfile:
      path: networks/org1-connection.yaml
      discover: false

  - mspid: ${ORG2_MSPID}
    identities:
      certificates:
        - name: admin-org2
          admin: true
          clientPrivateKey:
            path: ${ORG2_KEY}
          clientSignedCert:
            path: ${ORG2_CERT}
    connectionProfile:
      path: networks/org2-connection.yaml
      discover: false
EON

cat > benchmarks/workload/submit-alert.js <<'EOJS'
'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class SubmitAlertWorkload extends WorkloadModuleBase {
  constructor() {
    super();
    this.txIndex = 0;
  }

  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    this.workerIndex = workerIndex;
    this.totalWorkers = totalWorkers;
    this.roundArgs = roundArguments || {};
    this.contractId = this.roundArgs.contractId || process.env.CC_ID || 'governance';
    this.contractFunction = this.roundArgs.contractFunction || process.env.CC_FCN || 'SubmitAlert';
    this.runId = this.roundArgs.runId || `${Math.floor(Date.now() / 1000)}`;
    this.baseClientId = this.roundArgs.baseClientId || `caliper-client-${this.workerIndex}`;
    this.clientId = `${this.baseClientId}-${this.runId}`;
    this.timeout = this.roundArgs.timeout || 30;
    this.org1Identity = this.roundArgs.org1Identity || 'admin-org1';
    this.org2Identity = this.roundArgs.org2Identity || 'admin-org2';
  }

  async submitTransaction() {
    this.txIndex += 1;

    const nowMs = Date.now();
    const ts = Math.floor(nowMs / 1000);
    const round = this.txIndex;

    const alertId = `cal-${this.workerIndex}-${round}-${nowMs}`;
    const severity = 'HIGH';
    const signature = `sig-${this.workerIndex}-${round}`;
    const meta = JSON.stringify({ model: 'caliper', runId: this.runId, worker: this.workerIndex, seq: round });
    const nonce = `n-${this.workerIndex}-${round}-${nowMs}`;

    const invokerIdentity = (this.workerIndex % 2 === 0) ? this.org1Identity : this.org2Identity;

    const request = {
      contractId: this.contractId,
      contractFunction: this.contractFunction,
      contractArguments: [
        String(alertId),
        String(round),
        String(this.clientId),
        String(ts),
        String(severity),
        String(signature),
        String(meta),
        String(nonce)
      ],
      timeout: this.timeout,
      invokerIdentity
    };

    await this.sutAdapter.sendRequests(request);
  }
}

function createWorkloadModule() {
  return new SubmitAlertWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
EOJS

REPORT="results/caliper-report-org1org2-${TS}.html"
LOG="results/caliper-run-org1org2-${TS}.log"

npx caliper launch manager \
  --caliper-bind-sut "${CALIPER_BIND_SUT:-fabric:2.5}" \
  --caliper-workspace . \
  --caliper-flow-only-test \
  --caliper-benchconfig benchmarks/benchmark.yaml \
  --caliper-networkconfig networks/fabric-network.yaml \
  --caliper-report-path "${REPORT}" \
  2>&1 | tee "${LOG}"

echo "${REPORT}"
