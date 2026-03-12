'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class SubmitAlertWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.runId = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.txIndex = 0;
        this.runId = Date.now();
        this.baseTimestamp = String(Math.floor(this.runId / 1000));
    }

    async submitTransaction() {
        this.txIndex++;
        const clientID = `c${this.workerIndex}-${this.txIndex}`;
        const alertID  = `${this.runId}-${this.workerIndex}-${this.txIndex}`;
        const nonce    = `n-${this.workerIndex}-${this.txIndex}`;
        const identity = this.workerIndex % 2 === 0 ? 'admin.org1' : '_Org2MSP_admin.org2';

        await this.sutAdapter.sendRequests({
            contractId: this.roundArguments.contractId,
            contractFunction: 'SubmitAlert',
            invokerIdentity: identity,
            contractArguments: [
                alertID,
                '1',
                clientID,
                this.baseTimestamp,
                'HIGH',
                `sig-${this.workerIndex}-${this.txIndex}`,
                `{"model":"caliper","worker":${this.workerIndex},"tx":${this.txIndex}}`,
                nonce
            ],
            readOnly: false
        });
    }
}

function createWorkloadModule() { return new SubmitAlertWorkload(); }
module.exports.createWorkloadModule = createWorkloadModule;
