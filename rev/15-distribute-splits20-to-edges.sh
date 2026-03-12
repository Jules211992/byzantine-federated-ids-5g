#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -z "${RUN_DIR:-}" ] && { echo "ERROR: aucun RUN_DIR rev_*_5g"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
SPLITS="$RUN_DIR/splits_20"
MANIFEST="$RUN_DIR/manifest/splits20_manifest.json"
[ ! -f "$MAP" ] && { echo "ERROR: map introuvable: $MAP"; exit 1; }
[ ! -d "$SPLITS" ] && { echo "ERROR: splits introuvable: $SPLITS"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
WORK="/tmp/splits20_dist_${TS}"
mkdir -p "$WORK"

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "SPLITS=$SPLITS"
echo "UTC=$TS"
echo

python3 - <<'PY' "$MAP" > "$WORK/plan.json"
import json, sys
mp = sys.argv[1]
plan = {}
with open(mp) as f:
    for line in f:
        line=line.strip()
        if not line: 
            continue
        cid, ip = line.split()
        plan.setdefault(ip, []).append(cid)
for ip in plan:
    plan[ip] = sorted(plan[ip], key=lambda s: int(s.split("-")[-1]))
print(json.dumps(plan, indent=2))
PY

echo "PLAN:"
cat "$WORK/plan.json"
echo

for ip in "${EDGE_IPS[@]}"; do
  echo "=============================="
  echo "EDGE=$ip"
  echo "------------------------------"

  if ! grep -q "\"$ip\"" "$WORK/plan.json"; then
    echo "SKIP: no clients mapped to $ip"
    echo
    continue
  fi

  EDGE_DIR="$WORK/$ip"
  mkdir -p "$EDGE_DIR"

  cp -f "$SPLITS/feature_names.json" "$EDGE_DIR/"
  cp -f "$SPLITS/feat_min.npy" "$EDGE_DIR/"
  cp -f "$SPLITS/feat_max.npy" "$EDGE_DIR/"
  cp -f "$SPLITS/split_stats.json" "$EDGE_DIR/" || true
  [ -f "$MANIFEST" ] && cp -f "$MANIFEST" "$EDGE_DIR/" || true

  python3 - <<'PY' "$WORK/plan.json" "$ip" "$SPLITS" "$EDGE_DIR"
import json, sys, os, shutil
plan=json.load(open(sys.argv[1]))
ip=sys.argv[2]
splits=sys.argv[3]
dst=sys.argv[4]
cids=plan[ip]
need=[]
for cid in cids:
    need += [
        f"{cid}_train_X.npy",
        f"{cid}_train_y.npy",
        f"{cid}_test_X.npy",
        f"{cid}_test_y.npy",
    ]
missing=[p for p in need if not os.path.isfile(os.path.join(splits,p))]
if missing:
    raise SystemExit("MISSING_SPLITS: " + " ".join(missing))
for p in need:
    shutil.copy2(os.path.join(splits,p), os.path.join(dst,p))
print("CLIENTS=", " ".join(cids))
print("FILES_COPIED=", len(need))
PY

  TAR="$WORK/splits20_${ip}_${TS}.tgz"
  tar -czf "$TAR" -C "$EDGE_DIR" .
  echo "TAR=$(ls -lh "$TAR" | awk '{print $9, $5}')"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TAR" ubuntu@"$ip":/tmp/splits20.tgz >/dev/null

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mkdir -p /opt/fl-client
if [ -d /opt/fl-client/splits ]; then
  sudo mv /opt/fl-client/splits /opt/fl-client/splits_backup_${TS} || true
fi
sudo mkdir -p /opt/fl-client/splits
sudo tar -xzf /tmp/splits20.tgz -C /opt/fl-client/splits
sudo chown -R ubuntu:ubuntu /opt/fl-client/splits
rm -f /tmp/splits20.tgz

echo 'REMOTE_HOST='\"\$(hostname)\"
echo 'REMOTE_IP='\"\$(hostname -I | awk '{print \$1}')\"
echo 'FILES='\"\$(ls -1 /opt/fl-client/splits | wc -l)\"

python3 - <<'PY'
import os, glob, numpy as np
d='/opt/fl-client/splits'
ids=sorted({os.path.basename(p)[:-len('_train_X.npy')] for p in glob.glob(os.path.join(d,'*_train_X.npy'))})
print('CLIENT_IDS_FOUND=', ids)
for cid in ids:
    X=np.load(f'{d}/{cid}_train_X.npy', mmap_mode='r')
    y=np.load(f'{d}/{cid}_train_y.npy', mmap_mode='r')
    Xt=np.load(f'{d}/{cid}_test_X.npy', mmap_mode='r')
    yt=np.load(f'{d}/{cid}_test_y.npy', mmap_mode='r')
    print(f'  {cid}: train_X={X.shape} train_y={y.shape} test_X={Xt.shape} test_y={yt.shape}')
PY
"

  echo
done

echo "OK: distribution done"
