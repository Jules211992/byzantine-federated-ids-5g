set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

join_one() {
  ip="$1"
  ord="$2"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" bash -s -- "$ord" <<'REMOTE'
set -euo pipefail
ord="$1"

IMG="hyperledger/fabric-tools:2.5"
cd /opt/fabric

test -f dtchannel.block
test -f "crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/ca.crt"
test -d "crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls"

BASE="crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls"

CERT=""
KEY=""

if [ -f "$BASE/client.crt" ]; then CERT="client.crt"; fi
if [ -z "$CERT" ] && [ -f "$BASE/server.crt" ]; then CERT="server.crt"; fi
if [ -z "$CERT" ]; then CERT="$(ls -1 "$BASE"/*.crt 2>/dev/null | xargs -n1 basename | egrep -v '^ca\.crt$' | head -n 1 || true)"; fi
test -n "$CERT"

if [ -f "$BASE/client.key" ]; then KEY="client.key"; fi
if [ -z "$KEY" ] && [ -f "$BASE/server.key" ]; then KEY="server.key"; fi
if [ -z "$KEY" ]; then KEY="$(ls -1 "$BASE"/*.key 2>/dev/null | xargs -n1 basename | head -n 1 || true)"; fi
if [ -z "$KEY" ]; then KEY="$(ls -1 "$BASE"/*_sk 2>/dev/null | xargs -n1 basename | head -n 1 || true)"; fi
if [ -z "$KEY" ] && [ -f "$BASE/priv_sk" ]; then KEY="priv_sk"; fi
test -n "$KEY"

sudo docker pull "$IMG" >/dev/null

sudo docker run --rm --network host \
  -v /opt/fabric:/work -w /work \
  "$IMG" osnadmin channel join \
    --channelID dtchannel \
    --config-block /work/dtchannel.block \
    -o localhost:7053 \
    --ca-file "/work/crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/ca.crt" \
    --client-cert "/work/crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls/$CERT" \
    --client-key  "/work/crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls/$KEY"

sudo docker run --rm --network host \
  -v /opt/fabric:/work -w /work \
  "$IMG" osnadmin channel list \
    -o localhost:7053 \
    --ca-file "/work/crypto-config/ordererOrganizations/example.com/orderers/$ord/tls/ca.crt" \
    --client-cert "/work/crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls/$CERT" \
    --client-key  "/work/crypto-config/ordererOrganizations/example.com/users/Admin@example.com/tls/$KEY"
REMOTE
}

join_one "$VM6_IP" "orderer1.example.com"
join_one "$VM7_IP" "orderer2.example.com"
join_one "$VM8_IP" "orderer3.example.com"
