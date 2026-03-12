#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -z "${RUN_DIR:-}" ] && { echo "ERROR: aucun RUN_DIR rev_*_5g"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ ! -f "$MAP" ] && { echo "ERROR: map introuvable: $MAP"; exit 1; }

ROUND=${ROUND:-1}

OUT="$RUN_DIR/manifest/debug_flclient_fail_round$(printf '%02d' "$ROUND")_$(date -u +%Y%m%d_%H%M%S).txt"
mkdir -p "$RUN_DIR/manifest"
exec > >(tee "$OUT") 2>&1

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "ROUND=$ROUND"
echo "UTC=$(date -u +%Y%m%d_%H%M%S)"
echo

python3 - "$MAP" > /tmp/plan_first.json <<'PY'
import json, sys
mp=sys.argv[1]
plan={}
with open(mp) as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        cid, ip = line.split()
        plan.setdefault(ip, []).append(cid)
for ip in plan:
    plan[ip]=sorted(plan[ip], key=lambda s: int(s.split("-")[-1]))
first={ip: plan[ip][0] for ip in plan if plan[ip]}
print(json.dumps(first, indent=2))
PY

echo "FIRST_CLIENT_PER_EDGE:"
cat /tmp/plan_first.json
echo

python3 - /tmp/plan_first.json > /tmp/first_pairs.txt <<'PY'
import json, sys
first=json.load(open(sys.argv[1]))
for ip,cid in sorted(first.items()):
    print(ip, cid)
PY

while read -r ip cid; do
  echo
  echo "========================================================"
  echo "EDGE=$ip FIRST_CLIENT=$cid"
  echo "--------------------------------------------------------"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
echo IP:\$(hostname -I | awk '{print \$1}')
echo PY:\$(python3 -V 2>&1 || true)
echo

echo '--- splits present? ---'
ls -lh /opt/fl-client/splits/${cid}_train_X.npy /opt/fl-client/splits/${cid}_train_y.npy /opt/fl-client/splits/${cid}_test_X.npy /opt/fl-client/splits/${cid}_test_y.npy 2>/dev/null || true
echo

echo '--- old model exists? ---'
ls -lh /opt/fl-client/models/${cid}_model.npz 2>/dev/null || true
echo

LOG=/opt/fl-client/logs/fl_client_${cid}_r${ROUND}.out
echo \"--- fl_client log: \$LOG ---\"
ls -lh \"\$LOG\" 2>/dev/null || true
echo

if [ -f \"\$LOG\" ]; then
  echo '--- tail 200 ---'
  tail -n 200 \"\$LOG\" || true
else
  echo 'NO fl_client log file found for this client/round.'
  echo 'Recent log files:'
  ls -lt /opt/fl-client/logs | head -n 25 || true
fi
"
done < /tmp/first_pairs.txt

echo
echo "SAVED=$OUT"
