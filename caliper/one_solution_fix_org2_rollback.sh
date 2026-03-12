#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/byz-fed-ids-5g/caliper"

TS="$(date +%Y%m%d-%H%M%S)"

CHANNEL="${CHANNEL:-dtchannel}"
CC_ID="${CC_ID:-governance}"
CC_FCN="${CC_FCN:-SubmitAlert}"

CRYPTO_HOME="${CRYPTO_HOME:-$HOME/byz-fed-ids-5g/fabric/crypto-config}"

mkdir -p networks benchmarks/workload results

cp -a networks/fabric-network.yaml "networks/fabric-network.yaml.bak_${TS}" 2>/dev/null || true
cp -a networks/org2-connection.yaml "networks/org2-connection.yaml.bak_${TS}" 2>/dev/null || true
cp -a benchmarks/workload/submit-alert.js "benchmarks/workload/submit-alert.js.bak_${TS}" 2>/dev/null || true

ORG1_KEY="$(ls -1 "$CRYPTO_HOME/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/"* | head -1)"
ORG2_KEY="$(ls -1 "$CRYPTO_HOME/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/keystore/"* | head -1)"
ORG1_CERT="$(ls -1 "$CRYPTO_HOME/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/"*.pem | head -1)"
ORG2_CERT="$(ls -1 "$CRYPTO_HOME/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/signcerts/"*.pem | head -1)"
ORG2_TLS_CA="$CRYPTO_HOME/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
ORD_TLS_CA="$(ls -1 "$CRYPTO_HOME/ordererOrganizations/example.com/msp/tlscacerts/"*.pem | head -1)"

test -f "$ORG1_KEY"
test -f "$ORG2_KEY"
test -f "$ORG1_CERT"
test -f "$ORG2_CERT"
test -f "$ORG2_TLS_CA"
test -f "$ORD_TLS_CA"

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
  - mspid: Org1MSP
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

  - mspid: Org2MSP
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
    this.seq = 0;
  }

  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);

    this.workerIndex = workerIndex;
    this.totalWorkers = totalWorkers;
    this.args = roundArguments || {};

    this.contractId = this.args.contractId || process.env.CC_ID || 'governance';
    this.contractFunction = this.args.contractFunction || process.env.CC_FCN || 'SubmitAlert';

    this.runId = this.args.runId || `${Math.floor(Date.now() / 1000)}`;
    this.baseClientId = this.args.baseClientId || `caliper-client-${this.workerIndex}`;
    this.clientId = `${this.baseClientId}-${this.runId}`;

    this.timeout = this.args.timeout || 30;

    this.org1Identity = this.args.org1Identity || 'admin-org1';
    this.org2Identity = this.args.org2Identity || 'admin-org2';
  }

  async submitTransaction() {
    this.seq += 1;

    const nowMs = Date.now();
    const ts = Math.floor(nowMs / 1000);

    const round = this.seq;

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

CC_ID="${CC_ID}" CC_FCN="${CC_FCN}" npx caliper launch manager \
  --caliper-bind-sut "${CALIPER_BIND_SUT:-fabric:2.5}" \
  --caliper-workspace . \
  --caliper-flow-only-test \
  --caliper-benchconfig benchmarks/benchmark.yaml \
  --caliper-networkconfig networks/fabric-network.yaml \
  --caliper-report-path "${REPORT}" \
  2>&1 | tee "${LOG}"

echo "${REPORT}"
