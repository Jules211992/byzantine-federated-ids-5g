#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
SPLITS="$RUN_DIR/splits_20"

[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }
[ -d "$SPLITS" ] || { echo "ERROR: splits_20 introuvable: $SPLITS"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/restore_splits20_$TS"
mkdir -p "$OUT"

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "SPLITS=$SPLITS"
echo "OUT=$OUT"

IPS=$(awk '{print $2}' "$MAP" | sort -u)

for ip in $IPS; do
  echo
  echo "================ PREP $ip ================"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -euo pipefail
    mkdir -p /opt/fl-client/splits /opt/fl-client/logs /opt/fl-client/models
    rm -f /opt/fl-client/splits/*
    rm -f /opt/fl-client/logs/*
    rm -f /opt/fl-client/models/*.npz
    ls -la /opt/fl-client/splits
  ' | tee "$OUT/prep_${ip}.txt"
done

while read -r cid ip; do
  [ -n "${cid:-}" ] || continue
  [ -n "${ip:-}" ] || continue

  echo
  echo "================ COPY $cid -> $ip ================"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$SPLITS/${cid}_train_X.npy" \
    "$SPLITS/${cid}_train_y.npy" \
    "$SPLITS/${cid}_test_X.npy" \
    "$SPLITS/${cid}_test_y.npy" \
    ubuntu@"$ip":/opt/fl-client/splits/
done < "$MAP"

for ip in $IPS; do
  echo
  echo "================ COPY SHARED -> $ip ================"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$SPLITS/feature_names.json" \
    "$SPLITS/feat_min.npy" \
    "$SPLITS/feat_max.npy" \
    "$SPLITS/split_stats.json" \
    ubuntu@"$ip":/opt/fl-client/splits/

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -euo pipefail
    python3 - <<'"'"'PY'"'"'
import glob, os, numpy as np, json

print("HOST=", os.uname().nodename)
train_files = sorted(glob.glob("/opt/fl-client/splits/*_train_X.npy"))
test_files = sorted(glob.glob("/opt/fl-client/splits/*_test_X.npy"))
print("N_TRAIN_FILES=", len(train_files))
print("N_TEST_FILES=", len(test_files))

for p in train_files:
    x = np.load(p, mmap_mode="r")
    print(os.path.basename(p), x.shape)

for p in test_files:
    x = np.load(p, mmap_mode="r")
    print(os.path.basename(p), x.shape)

with open("/opt/fl-client/splits/feature_names.json") as f:
    info = json.load(f)

if isinstance(info, dict) and "n_features" in info:
    print("N_FEATURES=", info["n_features"])
elif isinstance(info, list):
    print("N_FEATURES=", len(info))
else:
    print("N_FEATURES=UNKNOWN")
PY
  ' | tee "$OUT/verify_${ip}.txt"
done

python3 - <<'PY' "$MAP" "$OUT"
import sys, json, os, re
from pathlib import Path

map_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])

per_ip = {}
for line in map_path.read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    cid, ip = line.split()
    per_ip.setdefault(ip, []).append(cid)

summary = {
    "map": str(map_path),
    "out_dir": str(out_dir),
    "per_ip_clients": per_ip
}

(out_dir / "restore_summary.json").write_text(json.dumps(summary, indent=2))
print("SUMMARY_JSON=", out_dir / "restore_summary.json")
PY

echo
echo "DONE"
echo "$OUT"
