package main

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type AlertFast struct {
	AlertID    string `json:"alertId"`
	Round      string `json:"round"`
	ClientID   string `json:"clientId"`
	Timestamp  string `json:"timestamp"`
	Severity   string `json:"severity"`
	Signature  string `json:"signature"`
	Meta       string `json:"meta"`
	Nonce      string `json:"nonce"`
	TxID       string `json:"txId"`
}

func (s *GovernanceContract) SubmitAlertFast(ctx contractapi.TransactionContextInterface, alertId, round, clientId, timestamp, severity, signature, meta, nonce string) error {
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
