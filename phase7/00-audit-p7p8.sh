#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

ts=$(date -u +%Y%m%d_%H%M%S)
out=~/byz-fed-ids-5g/phase7/logs/p7p8_audit_${ts}.txt
mkdir -p ~/byz-fed-ids-5g/phase7/logs
exec > >(tee "$out") 2>&1

echo "UTC: $(date -u)"
echo "HOST: $(hostname)"
echo "PWD: $(pwd)"
echo

echo "=== Local: config files ==="
ls -la config 2>/dev/null || true
for f in config/config.env config/edges_map.txt config/fabric_nodes.env config/nodes_ip.txt; do
  if [ -f "$f" ]; then
    echo
    echo "--- $f ---"
    sed -n '1,220p' "$f"
  fi
done
echo

echo "=== Local: phase7/phase8 listing ==="
ls -la phase7 2>/dev/null || true
echo
ls -la phase8 2>/dev/null || true
echo

echo "=== Local: scripts head (phase7/phase8) ==="
for f in phase7/*.sh phase8/*.sh; do
  if [ -f "$f" ]; then
    echo
    echo "--- $f (first 200 lines) ---"
    sed -n '1,200p' "$f"
  fi
done
echo

echo "=== Local: crypto tlsca/ca.crt paths (repo) ==="
find fabric/crypto-config -type f \( -name '*tlsca*.pem' -o -name 'ca.crt' -o -name '*tlsca*.crt' \) 2>/dev/null | sort | sed -n '1,240p'
echo

echo "=== Scan VMs for Fabric containers (peer/orderer/ca) ==="
IPS=()
for v in VM1_IP VM2_IP VM3_IP VM4_IP VM5_IP VM6_IP VM7_IP VM8_IP VM9_IP VM10_IP; do
  if [ -n "${!v:-}" ]; then
    IPS+=("${!v}")
  fi
done

for ip in "${IPS[@]}"; do
  echo
  echo "----- VM $ip -----"
  set +e
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "
if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer|orderer|ca|couch|kafka|zoo' || true
else
  echo 'NO_DOCKER'
fi
" || echo "SSH_FAIL"
  set -e
done
echo

echo "=== Edge nodes audit (focus run_fl_round + TLS roots) ==="
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")
for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "----- EDGE $ip -----"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo 'UTC:' \$(date -u)
echo 'HOST:' \$(hostname)
echo 'IP:' \$(hostname -I | awk '{print \$1}')
echo
echo '--- /opt/fl-client (top) ---'
ls -la /opt/fl-client 2>/dev/null | sed -n '1,220p' || true
echo
echo '--- run_fl_round.sh ---'
sed -n '1,220p' /opt/fl-client/run_fl_round.sh 2>/dev/null || true
echo
echo '--- config.env ---'
ls -la /opt/fl-client/config.env 2>/dev/null || true
sed -n '1,120p' /opt/fl-client/config.env 2>/dev/null || true
echo
echo '--- TLS CA dir ---'
ls -la /opt/fl-client/crypto/tls/ca 2>/dev/null || true
echo
echo '--- tls ca fingerprints ---'
for c in /opt/fl-client/crypto/tls/ca/*; do
  if [ -f \"\$c\" ]; then
    echo \"FILE=\$c\"
    openssl x509 -in \"\$c\" -noout -subject -issuer -fingerprint -sha256 2>/dev/null || true
  fi
done
echo
echo '--- resolve peer0.org1 ---'
getent hosts peer0.org1.example.com 2>/dev/null || true
"
done

echo
echo "SAVED: $out"
