set -euo pipefail

cd "$HOME/byz-fed-ids-5g/caliper"

if [ -d /opt/fabric/crypto-config ]; then
  CRYPTO=/opt/fabric/crypto-config
elif [ -d "$HOME/byz-fed-ids-5g/fabric/crypto-config" ]; then
  CRYPTO="$HOME/byz-fed-ids-5g/fabric/crypto-config"
else
  echo "crypto-config introuvable (ni /opt/fabric/crypto-config ni ~/byz-fed-ids-5g/fabric/crypto-config)"; exit 1
fi

ORG1_SIGNCERT_DIR="$CRYPTO/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts"
ORG1_KEYSTORE_DIR="$CRYPTO/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
ORG2_SIGNCERT_DIR="$CRYPTO/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/signcerts"
ORG2_KEYSTORE_DIR="$CRYPTO/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/keystore"

ORG1_CERT_FILE="$(ls -1 "$ORG1_SIGNCERT_DIR" | head -1)"
ORG1_KEY_FILE="$(ls -1 "$ORG1_KEYSTORE_DIR" | head -1)"
ORG2_CERT_FILE="$(ls -1 "$ORG2_SIGNCERT_DIR" | head -1)"
ORG2_KEY_FILE="$(ls -1 "$ORG2_KEYSTORE_DIR" | head -1)"

ORG1_CERT="$ORG1_SIGNCERT_DIR/$ORG1_CERT_FILE"
ORG1_KEY="$ORG1_KEYSTORE_DIR/$ORG1_KEY_FILE"
ORG2_CERT="$ORG2_SIGNCERT_DIR/$ORG2_CERT_FILE"
ORG2_KEY="$ORG2_KEYSTORE_DIR/$ORG2_KEY_FILE"

mkdir -p networks
cat > networks/fabric-network.yaml <<YAML
name: Fabric
version: "2.0.0"
caliper:
  blockchain: fabric
  sutOptions:
    mutualTls: false

channels:
  - channelName: dtchannel
    contracts:
      - id: governance

organizations:
  - mspid: Org1MSP
    connectionProfile:
      path: networks/org1-connection.yaml
      discover: true
    identities:
      certificates:
        - name: admin.org1
          admin: true
          clientPrivateKey:
            path: "$ORG1_KEY"
          clientSignedCert:
            path: "$ORG1_CERT"

  - mspid: Org2MSP
    connectionProfile:
      path: networks/org2-connection.yaml
      discover: true
    identities:
      certificates:
        - name: admin.org2
          admin: true
          clientPrivateKey:
            path: "$ORG2_KEY"
          clientSignedCert:
            path: "$ORG2_CERT"
YAML

mkdir -p benchmarks/workload
cat > benchmarks/workload/submit-alert.js <<'JS'
'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class SubmitAlertWorkload extends WorkloadModuleBase {
  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    this.workerIndex = workerIndex;
    this.txIndex = 0;

    this.runBase = Math.floor(Date.now() / 1000).toString();
    this.fixedRound = this.runBase;

    this.contractId = (roundArguments && roundArguments.contractId) ? roundArguments.contractId : 'governance';
    this.contractFunction = (roundArguments && roundArguments.contractFunction) ? roundArguments.contractFunction : 'SubmitAlert';
  }

  async submitTransaction() {
    const seq = this.txIndex++;
    const nowMs = Date.now();

    const alertId = `cal-${this.workerIndex}-${seq}-${nowMs}`;
    const clientId = `caliper-client-${this.workerIndex}-${this.runBase}`;
    const tsSec = Math.floor(nowMs / 1000).toString();

    const severity = 'HIGH';
    const sig = `sig-${this.workerIndex}-${seq}`;
    const meta = JSON.stringify({ model: 'caliper', runId: this.runBase, worker: this.workerIndex, seq });
    const nonce = `n-${this.workerIndex}-${seq}-${nowMs}`;

    const invokerMspId = (this.workerIndex % 2 === 0) ? 'Org1MSP' : 'Org2MSP';

    await this.sutAdapter.sendRequests({
      contractId: this.contractId,
      contractFunction: this.contractFunction,
      invokerMspId,
      readOnly: false,
      contractArguments: [alertId, this.fixedRound, clientId, tsSec, severity, sig, meta, nonce]
    });
  }
}

function createWorkloadModule() {
  return new SubmitAlertWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
JS

echo "OK: fabric-network.yaml (version=2.0.0) + submit-alert.js (round constant, Org1/Org2 alternés)"
