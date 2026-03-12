#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

mkdir -p "$RUN_DIR/config" "$RUN_DIR/manifest"

OUT="$RUN_DIR/config/edges_map_20.txt"

: > "$OUT"
for i in 1 2 3 4 5; do echo "edge-client-$i $VM2_IP" >> "$OUT"; done
for i in 6 7 8 9 10; do echo "edge-client-$i $VM3_IP" >> "$OUT"; done
for i in 11 12 13 14 15; do echo "edge-client-$i $VM4_IP" >> "$OUT"; done
for i in 16 17 18 19 20; do echo "edge-client-$i $VM5_IP" >> "$OUT"; done

echo "RUN_DIR=$RUN_DIR"
echo
echo "=== edges_map_20.txt ==="
wc -l "$OUT" | awk '{print "LINES="$1}'
awk '{c[$1]++; ip[$2]++} END{print "UNIQUE_CLIENTS="length(c); print "UNIQUE_IPS="length(ip)}' "$OUT"
echo
echo "--- per IP counts ---"
awk '{k[$2]++} END{for (i in k) print i, k[i]}' "$OUT" | sort -V
echo
echo "--- first 25 lines ---"
sed -n '1,25p' "$OUT"
echo

echo "=== quick reachability (edge VMs only) ==="
for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  echo
  echo "----- $ip -----"
  set +e
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
test -d /opt/fl-client && echo FL_CLIENT=YES || echo FL_CLIENT=NO
"
  echo "RC=$?"
  set -e
done

echo
echo "SAVED=$OUT"
