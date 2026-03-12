package main

import (
	"crypto/x509"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
	"github.com/hyperledger/fabric-gateway/pkg/identity"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

type Config struct {
	ClientID  string
	OrgMSP    string
	PeerAddr  string
	PeerTLSCA string
	CertPath  string
	KeyPath   string
	Channel   string
	Chaincode string
}

func loadConfig() Config {
	return Config{
		ClientID:  getEnv("CLIENT_ID", "edge-client-1"),
		OrgMSP:    getEnv("ORG_MSP", "Org1MSP"),
		PeerAddr:  getEnv("PEER_ADDR", "peer0.org1.example.com:7051"),
		PeerTLSCA: getEnv("PEER_TLS_CA", "/opt/fl-client/tls/ca.crt"),
		CertPath:  getEnv("CERT_PATH", "/opt/fl-client/msp/signcerts/cert.pem"),
		KeyPath:   getEnv("KEY_PATH", "/opt/fl-client/msp/keystore/key.pem"),
		Channel:   getEnv("CHANNEL", "dtchannel"),
		Chaincode: getEnv("CHAINCODE", "governance"),
	}
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func newGrpcConnection(cfg Config) *grpc.ClientConn {
	caPEM, err := os.ReadFile(cfg.PeerTLSCA)
	if err != nil {
		panic(fmt.Sprintf("failed to read TLS CA: %v", err))
	}
	certPool := x509.NewCertPool()
	certPool.AppendCertsFromPEM(caPEM)
	tlsCreds := credentials.NewClientTLSFromCert(certPool, "")
	conn, err := grpc.Dial(
		cfg.PeerAddr,
		grpc.WithTransportCredentials(tlsCreds),
	)
	if err != nil {
		panic(fmt.Sprintf("grpc dial failed: %v", err))
	}
	return conn
}

func newIdentity(cfg Config) *identity.X509Identity {
	certPEM, err := os.ReadFile(cfg.CertPath)
	if err != nil {
		panic(err)
	}
	cert, err := identity.CertificateFromPEM(certPEM)
	if err != nil {
		panic(err)
	}
	id, err := identity.NewX509Identity(cfg.OrgMSP, cert)
	if err != nil {
		panic(err)
	}
	return id
}

func newSigner(cfg Config) identity.Sign {
	keyPEM, err := os.ReadFile(cfg.KeyPath)
	if err != nil {
		// Try as directory
		files, err2 := os.ReadDir(cfg.KeyPath)
		if err2 != nil {
			panic(fmt.Sprintf("failed to read key: %v", err))
		}
		for _, f := range files {
			if !f.IsDir() {
				keyPEM, err = os.ReadFile(cfg.KeyPath + "/" + f.Name())
				if err == nil {
					break
				}
			}
		}
		if keyPEM == nil {
			panic("no key found in " + cfg.KeyPath)
		}
	}
	pk, err := identity.PrivateKeyFromPEM(keyPEM)
	if err != nil {
		panic(err)
	}
	sign, err := identity.NewPrivateKeySign(pk)
	if err != nil {
		panic(err)
	}
	return sign
}

func submitAlert(contract *client.Contract, clientID string, roundID int, severity, payload string) error {
	alertID := fmt.Sprintf("%s-r%d-%d", clientID, roundID, time.Now().UnixNano())
	nonce := fmt.Sprintf("nonce-%d", time.Now().UnixNano())
	sig := fmt.Sprintf("sig-%s-%d", clientID, roundID)
	_, err := contract.SubmitTransaction(
		"SubmitAlert",
		alertID,
		strconv.Itoa(roundID),
		clientID,
		strconv.FormatInt(time.Now().Unix(), 10),
		severity,
		sig,
		payload,
		nonce,
	)
	if err != nil {
		return fmt.Errorf("SubmitAlert failed: %w", err)
	}
	fmt.Printf("[%s] round=%d alert=%s submitted\n", clientID, roundID, alertID)
	return nil
}

func getLastRound(contract *client.Contract, clientID string) string {
	result, err := contract.EvaluateTransaction("GetLastRound", clientID)
	if err != nil {
		return "?"
	}
	var r string
	json.Unmarshal(result, &r)
	return r
}

func main() {
	cfg := loadConfig()
	rounds := 5
	if v := os.Getenv("ROUNDS"); v != "" {
		r, _ := strconv.Atoi(v)
		if r > 0 {
			rounds = r
		}
	}

	conn := newGrpcConnection(cfg)
	defer conn.Close()

	gw, err := client.Connect(
		newIdentity(cfg),
		client.WithSign(newSigner(cfg)),
		client.WithClientConnection(conn),
		client.WithEvaluateTimeout(5*time.Second),
		client.WithEndorseTimeout(15*time.Second),
		client.WithSubmitTimeout(5*time.Second),
		client.WithCommitStatusTimeout(60*time.Second),
	)
	if err != nil {
		panic(fmt.Sprintf("gateway connect failed: %v", err))
	}
	defer gw.Close()

	network := gw.GetNetwork(cfg.Channel)
	contract := network.GetContract(cfg.Chaincode)

	fmt.Printf("FL Client %s connected — submitting %d rounds\n", cfg.ClientID, rounds)

	var totalLatency int64
	errors := 0
	for round := 1; round <= rounds; round++ {
		payload := fmt.Sprintf(`{"model_update":"round_%d","features":["port_scan","ddos"],"confidence":0.92}`, round)
		start := time.Now()
		if err := submitAlert(contract, cfg.ClientID, round, "HIGH", payload); err != nil {
			fmt.Printf("[ERROR] round %d: %v\n", round, err)
			errors++
		} else {
			lat := time.Since(start).Milliseconds()
			totalLatency += lat
			fmt.Printf("[OK] round %d latency=%dms\n", round, lat)
		}
		time.Sleep(200 * time.Millisecond)
	}

	success := rounds - errors
	if success > 0 {
		fmt.Printf("\n✓ %s done: %d/%d OK avg_latency=%dms lastRound=%s\n",
			cfg.ClientID, success, rounds, totalLatency/int64(success),
			getLastRound(contract, cfg.ClientID))
	}
}
