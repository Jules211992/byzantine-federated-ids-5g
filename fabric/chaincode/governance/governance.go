package main

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type GovernanceContract struct {
	contractapi.Contract
}

type IDSAlert struct {
	AlertID    string `json:"alert_id"`
	RoundID    string `json:"round_id"`
	ClientID   string `json:"client_id"`
	Timestamp  int64  `json:"timestamp"`
	Severity   string `json:"severity"`
	Signature  string `json:"signature"`
	Payload    string `json:"payload"`
	TxNonce    string `json:"tx_nonce"`
}

// SubmitAlert soumet une alerte IDS avec anti-replay et anti-rollback
func (g *GovernanceContract) SubmitAlert(ctx contractapi.TransactionContextInterface,
	alertID, roundID, clientID string, timestamp int64,
	severity, signature, payload, txNonce string) error {

	// Limite taille payload
	if len(payload) > 65536 {
		return fmt.Errorf("payload exceeds 64KB limit")
	}
	if len(signature) > 1024 {
		return fmt.Errorf("signature exceeds 1KB limit")
	}

	// Anti-replay: vérifier si alertID déjà soumis
	existing, err := ctx.GetStub().GetState("ALERT_" + alertID)
	if err != nil {
		return fmt.Errorf("failed to read state: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("replay detected: alert %s already exists", alertID)
	}

	// Anti-rollback: vérifier roundID >= lastRound de ce client
	lastRoundKey := "LASTROUND_" + clientID
	lastRoundBytes, err := ctx.GetStub().GetState(lastRoundKey)
	if err != nil {
		return fmt.Errorf("failed to read last round: %v", err)
	}
	if lastRoundBytes != nil {
		lastRound, _ := strconv.ParseInt(string(lastRoundBytes), 10, 64)
		currentRound, _ := strconv.ParseInt(roundID, 10, 64)
		if currentRound < lastRound {
			return fmt.Errorf("rollback detected: round %s < last round %d", roundID, lastRound)
		}
	}

	alert := IDSAlert{
		AlertID:   alertID,
		RoundID:   roundID,
		ClientID:  clientID,
		Timestamp: timestamp,
		Severity:  severity,
		Signature: signature,
		Payload:   payload,
		TxNonce:   txNonce,
	}

	alertBytes, err := json.Marshal(alert)
	if err != nil {
		return fmt.Errorf("failed to marshal alert: %v", err)
	}

	if err := ctx.GetStub().PutState("ALERT_"+alertID, alertBytes); err != nil {
		return fmt.Errorf("failed to put state: %v", err)
	}

	// Mettre à jour lastRound
	if err := ctx.GetStub().PutState(lastRoundKey, []byte(roundID)); err != nil {
		return fmt.Errorf("failed to update last round: %v", err)
	}

	return ctx.GetStub().SetEvent("AlertSubmitted", alertBytes)
}

// GetAlert récupère une alerte par ID
func (g *GovernanceContract) GetAlert(ctx contractapi.TransactionContextInterface, alertID string) (*IDSAlert, error) {
	alertBytes, err := ctx.GetStub().GetState("ALERT_" + alertID)
	if err != nil {
		return nil, fmt.Errorf("failed to read alert: %v", err)
	}
	if alertBytes == nil {
		return nil, fmt.Errorf("alert %s not found", alertID)
	}
	var alert IDSAlert
	if err := json.Unmarshal(alertBytes, &alert); err != nil {
		return nil, err
	}
	return &alert, nil
}

// GetLastRound retourne le dernier round d'un client
func (g *GovernanceContract) GetLastRound(ctx contractapi.TransactionContextInterface, clientID string) (string, error) {
	val, err := ctx.GetStub().GetState("LASTROUND_" + clientID)
	if err != nil {
		return "", err
	}
	if val == nil {
		return "0", nil
	}
	return string(val), nil
}

func main() {
	cc, err := contractapi.NewChaincode(&GovernanceContract{})
	if err != nil {
		panic(fmt.Sprintf("Error creating governance chaincode: %v", err))
	}
	if err := cc.Start(); err != nil {
		panic(fmt.Sprintf("Error starting governance chaincode: %v", err))
	}
}
