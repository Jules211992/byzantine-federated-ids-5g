#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
TARGETS=("$VM2_IP" "$VM3_IP")

CERT_SRC=$(ls -1 "$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/"*.pem | head -n 1)
KEY_SRC=$(ls -1 "$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore/"* | head -n 1)
TLSCA_SRC=$(ls -1 "$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/tlsca/"*pem | head -n 1)

for ip in "${TARGETS[@]}"; do
  echo
  echo "===== FIX TLS+IDENTITY on $ip ====="

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$CERT_SRC"  ubuntu@"$ip":/tmp/User1@org1.example.com-cert.pem >/dev/null
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$KEY_SRC"   ubuntu@"$ip":/tmp/priv_sk >/dev/null
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TLSCA_SRC" ubuntu@"$ip":/tmp/tlsca_org1.crt >/dev/null

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

mkdir -p /opt/fl-client/crypto/identity/cert /opt/fl-client/crypto/identity/key /opt/fl-client/tls

echo
echo '--- BEFORE /opt/fl-client/tls/ca.crt ---'
if [ -f /opt/fl-client/tls/ca.crt ]; then
  openssl x509 -in /opt/fl-client/tls/ca.crt -noout -subject -issuer -fingerprint -sha256 || true
else
  echo 'missing'
fi

cp -f /tmp/tlsca_org1.crt /opt/fl-client/tls/ca.crt

cp -f /tmp/User1@org1.example.com-cert.pem /opt/fl-client/crypto/identity/cert/User1@org1.example.com-cert.pem
cp -f /tmp/priv_sk /opt/fl-client/crypto/identity/key/priv_sk
chmod 600 /opt/fl-client/crypto/identity/key/priv_sk

touch /opt/fl-client/config.env
python3 - <<'PY'
from pathlib import Path
p=Path('/opt/fl-client/config.env')
lines=p.read_text().splitlines() if p.exists() else []
out=[]
for ln in lines:
    if ln.startswith('ID_CERT_PATH=') or ln.startswith('ID_KEY_PATH='):
        continue
    out.append(ln)
out.append('ID_CERT_PATH=/opt/fl-client/crypto/identity/cert')
out.append('ID_KEY_PATH=/opt/fl-client/crypto/identity/key')
p.write_text('\n'.join([x for x in out if x.strip()]) + '\n')
PY

echo
echo '--- AFTER /opt/fl-client/tls/ca.crt ---'
openssl x509 -in /opt/fl-client/tls/ca.crt -noout -subject -issuer -fingerprint -sha256 || true

echo
echo '--- IDENTITY CERT ---'
openssl x509 -in /opt/fl-client/crypto/identity/cert/User1@org1.example.com-cert.pem -noout -subject -issuer -fingerprint -sha256 || true

echo
echo '--- config.env identity lines ---'
grep -E '^ID_CERT_PATH=|^ID_KEY_PATH=|^CERT_PATH=' /opt/fl-client/config.env || true

echo
echo '--- openssl verify peer0 TLS using local CA ---'
echo | openssl s_client -connect peer0.org1.example.com:7051 -servername peer0.org1.example.com -CAfile /opt/fl-client/tls/ca.crt 2>/dev/null | tail -n 3 || true
"
done

echo
echo "DONE"
