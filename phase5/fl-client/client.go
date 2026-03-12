package main

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
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
	Rounds     int
	StartRound int
	IPFSPath  string
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func loadConfig() Config {
	rounds, _ := strconv.Atoi(getEnv("ROUNDS", "3"))
	startRound, _ := strconv.Atoi(getEnv("START_ROUND", "1"))
	return Config{
		ClientID:  getEnv("CLIENT_ID", "edge-client-1"),
		OrgMSP:    getEnv("ORG_MSP", "Org1MSP"),
		PeerAddr:  getEnv("PEER_ADDR", "peer0.org1.example.com:7051"),
		PeerTLSCA: getEnv("PEER_TLS_CA", "/opt/fl-client/tls/ca.crt"),
		CertPath:  getEnv("CERT_PATH", "/opt/fl-client/msp/signcerts"),
		KeyPath:   getEnv("KEY_PATH", "/opt/fl-client/msp/keystore"),
		Channel:   getEnv("CHANNEL", "mychannel"),
		Chaincode: getEnv("CHAINCODE", "governance"),
		Rounds:     rounds,
		StartRound: startRound,
		IPFSPath:  getEnv("IPFS_PATH", "/home/ubuntu/.ipfs"),
	}
}

// Même pattern que phase4 — cherche le premier fichier dans le dossier
func firstFile(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) == 0 {
		panic(fmt.Sprintf("dossier vide ou inaccessible: %s — %v", dir, err))
	}
	return filepath.Join(dir, entries[0].Name())
}

func newGrpcConnection(tlsCA, peerAddr string) *grpc.ClientConn {
	caPEM, err := os.ReadFile(tlsCA)
	if err != nil {
		panic(fmt.Sprintf("TLS CA read error: %v", err))
	}
	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(caPEM) {
		panic("failed to append CA cert")
	}
	tlsCfg := &tls.Config{RootCAs: certPool}
	creds := credentials.NewTLS(tlsCfg)
	conn, err := grpc.Dial(peerAddr, grpc.WithTransportCredentials(creds))
	if err != nil {
		panic(fmt.Sprintf("grpc.Dial failed: %v", err))
	}
	return conn
}

func newIdentity(certDir, mspID string) *identity.X509Identity {
	certFile := firstFile(certDir)
	certPEM, err := os.ReadFile(certFile)
	if err != nil {
		panic(fmt.Sprintf("cert read error: %v", err))
	}
	cert, err := identity.CertificateFromPEM(certPEM)
	if err != nil {
		panic(fmt.Sprintf("CertificateFromPEM: %v", err))
	}
	id, err := identity.NewX509Identity(mspID, cert)
	if err != nil {
		panic(fmt.Sprintf("NewX509Identity: %v", err))
	}
	return id
}

func newSign(keyDir string) identity.Sign {
	keyFile := firstFile(keyDir)
	keyPEM, err := os.ReadFile(keyFile)
	if err != nil {
		panic(fmt.Sprintf("key read error: %v", err))
	}
	privateKey, err := identity.PrivateKeyFromPEM(keyPEM)
	if err != nil {
		panic(fmt.Sprintf("PrivateKeyFromPEM: %v", err))
	}
	sign, err := identity.NewPrivateKeySign(privateKey)
	if err != nil {
		panic(fmt.Sprintf("NewPrivateKeySign: %v", err))
	}
	return sign
}

func ipfsAdd(data []byte, ipfsPath string) (cid, hash string, ms int64, err error) {
	h := sha256.Sum256(data)
	hash = fmt.Sprintf("%x", h)

	tmp := fmt.Sprintf("/tmp/fl-update-%d.json", time.Now().UnixNano())
	if err = os.WriteFile(tmp, data, 0644); err != nil {
		return
	}
	defer os.Remove(tmp)

	t0 := time.Now()
	cmd := exec.Command("ipfs", "add", "-q", tmp)
	cmd.Env = append(os.Environ(), "IPFS_PATH="+ipfsPath)
	out, e := cmd.Output()
	ms = time.Since(t0).Milliseconds()
	if e != nil {
		err = fmt.Errorf("ipfs add: %v", e)
		return
	}
	cid = strings.TrimSpace(string(out))
	return
}

func ipfsPin(cid string) {
	exec.Command("ipfs-cluster-ctl", "pin", "add",
		"--replication-min", "3", "--replication-max", "5", cid).Run()
}

type RoundResult struct {
	Round      int    `json:"round"`
	OK         bool   `json:"ok"`
	AlertID    string `json:"alert_id,omitempty"`
	CID        string `json:"cid,omitempty"`
	Hash       string `json:"hash,omitempty"`
	IPFSAddMS  int64  `json:"ipfs_add_ms,omitempty"`
	TxCommitMS int64  `json:"tx_commit_ms,omitempty"`
	TotalMS    int64  `json:"total_ms,omitempty"`
	Error      string `json:"error,omitempty"`
}

func main() {
	cfg := loadConfig()

	conn := newGrpcConnection(cfg.PeerTLSCA, cfg.PeerAddr)
	defer conn.Close()

	id := newIdentity(cfg.CertPath, cfg.OrgMSP)
	sign := newSign(cfg.KeyPath)

	gw, err := client.Connect(id,
		client.WithSign(sign),
		client.WithClientConnection(conn),
	)
	if err != nil {
		panic(fmt.Sprintf("gateway connect: %v", err))
	}
	defer gw.Close()

	contract := gw.GetNetwork(cfg.Channel).GetContract(cfg.Chaincode)
	fmt.Printf("FL Client %s connecté — %d rounds\n", cfg.ClientID, cfg.Rounds)

	var results []RoundResult
	success := 0
	var totalMS int64

	for r := cfg.StartRound; r < cfg.StartRound+cfg.Rounds; r++ {
		t0 := time.Now()

		// Modèle FL simulé
		modelData, _ := json.Marshal(map[string]interface{}{
			"client_id": cfg.ClientID,
			"round":     r,
			"timestamp": time.Now().UnixNano(),
			"weights":   []float64{rand.Float64(), rand.Float64(), rand.Float64()},
			"loss":      0.5 - float64(r)*0.03,
			"accuracy":  0.7 + float64(r)*0.02,
			"samples":   1000 + rand.Intn(500),
		})

		// 1. IPFS add
		cid, hash, ipfsMS, err := ipfsAdd(modelData, cfg.IPFSPath)
		if err != nil {
			results = append(results, RoundResult{Round: r, Error: err.Error()})
			fmt.Printf("[ERROR] round %d ipfs: %v\n", r, err)
			continue
		}
		go ipfsPin(cid)

		// 2. Payload on-chain
		payload, _ := json.Marshal(map[string]interface{}{
			"cid": cid, "hash": hash,
			"loss": 0.5 - float64(r)*0.03,
			"accuracy": 0.7 + float64(r)*0.02,
		})

		nonce := fmt.Sprintf("%d", time.Now().UnixNano())
		alertID := fmt.Sprintf("fl-%s-r%d-%s", cfg.ClientID, r, nonce)
		ts := strconv.FormatInt(time.Now().UnixNano(), 10)

		// 3. SubmitAlert → Fabric
		t2 := time.Now()
		_, err = contract.SubmitTransaction("SubmitAlert",
			alertID, strconv.Itoa(r), cfg.ClientID,
			ts, "FL_UPDATE", cfg.OrgMSP,
			string(payload), nonce,
		)
		txMS := time.Since(t2).Milliseconds()
		totMS := time.Since(t0).Milliseconds()
		totalMS += totMS

		if err != nil {
			results = append(results, RoundResult{Round: r, Error: fmt.Sprintf("SubmitAlert: %v", err)})
			fmt.Printf("[ERROR] round %d tx: %v\n", r, err)
			continue
		}

		success++
		res := RoundResult{
			Round: r, OK: true,
			AlertID: alertID, CID: cid, Hash: hash[:16] + "...",
			IPFSAddMS: ipfsMS, TxCommitMS: txMS, TotalMS: totMS,
		}
		results = append(results, res)
		fmt.Printf("[%s] round=%d CID=%s... ipfs=%dms tx=%dms total=%dms\n",
			cfg.ClientID, r, cid[:12], ipfsMS, txMS, totMS)
	}

	avgMS := int64(0)
	if success > 0 {
		avgMS = totalMS / int64(success)
	}
	fmt.Printf("\n✓ %s done: %d/%d OK avg=%dms\n", cfg.ClientID, success, cfg.Rounds, avgMS)

	// Log JSON
	logData, _ := json.MarshalIndent(map[string]interface{}{
		"client_id": cfg.ClientID, "rounds": cfg.Rounds,
		"success": success, "avg_ms": avgMS, "results": results,
	}, "", "  ")
	os.WriteFile(fmt.Sprintf("/tmp/fl-p5-%s.json", cfg.ClientID), logData, 0644)
}
