set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

IPS=$(cat ~/byz-fed-ids-5g/config/nodes_ip.txt)

TMP_MAP=$(mktemp)
for ip in $IPS; do
  hn=$(timeout 25s ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "hostname -s" || true)
  fq=$(timeout 25s ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$ip" "hostname -f" || true)
  if [ -n "${hn}" ] && [ -n "${fq}" ]; then
    echo "$ip $fq $hn" >> "$TMP_MAP"
  fi
done

sort -u "$TMP_MAP" > "$TMP_MAP.sorted"

BLOCK=$(mktemp)
{
  echo "# FL_IDS_CLUSTER_BEGIN"
  cat "$TMP_MAP.sorted"
  if grep -q "^10\.10\.0\.52 " "$TMP_MAP.sorted"; then echo "10.10.0.52 orderer1.example.com orderer1"; fi
  if grep -q "^10\.10\.0\.106 " "$TMP_MAP.sorted"; then echo "10.10.0.106 orderer2.example.com orderer2"; fi
  if grep -q "^10\.10\.0\.57 " "$TMP_MAP.sorted"; then echo "10.10.0.57 orderer3.example.com orderer3"; fi
  if grep -q "^10\.10\.0\.126 " "$TMP_MAP.sorted"; then echo "10.10.0.126 peer0.org1.example.com peer0.org1"; fi
  if grep -q "^10\.10\.0\.82 " "$TMP_MAP.sorted"; then echo "10.10.0.82 peer0.org2.example.com peer0.org2"; fi
  echo "# FL_IDS_CLUSTER_END"
} > "$BLOCK"

B64=$(base64 -w0 "$BLOCK")

for ip in $IPS; do
  echo "PIN-HOSTS $ip"
  timeout 45s ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$ip" "sudo bash -lc '
set -e
TS=\$(date +%s)
cp -a /etc/hosts /etc/hosts.bak.\$TS || true

echo \"$B64\" | base64 -d > /tmp/flids_hosts_block.\$TS

awk \"BEGIN{skip=0}
  /^# FL_IDS_CLUSTER_BEGIN/{skip=1;next}
  /^# FL_IDS_CLUSTER_END/{skip=0;next}
  skip==0{print}
\" /etc/hosts > /tmp/hosts.new.\$TS

cat /tmp/flids_hosts_block.\$TS >> /tmp/hosts.new.\$TS
mv /tmp/hosts.new.\$TS /etc/hosts

getent hosts orderer1.example.com orderer2.example.com orderer3.example.com || true
getent hosts peer0.org1.example.com peer0.org2.example.com || true
'"
done

rm -f "$TMP_MAP" "$TMP_MAP.sorted" "$BLOCK"
