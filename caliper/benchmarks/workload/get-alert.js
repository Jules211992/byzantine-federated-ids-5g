'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class GetAlertWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }
    async submitTransaction() {
        this.txIndex++;
        const request = {
            contractId: this.roundArguments.contractId,
            contractFunction: 'GetAlert',
            invokerIdentity: 'admin-org1',
            contractArguments: [`caliper-alert-0-1-${Date.now()}`],
            readOnly: true
        };
        await this.sutAdapter.sendRequests(request);
    }
}
function createWorkloadModule() { return new GetAlertWorkload(); }
module.exports.createWorkloadModule = createWorkloadModule;
