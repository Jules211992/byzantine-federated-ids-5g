#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
TS=$(date -u +%Y%m%d_%H%M%S)

OUT="$RUN_DIR/manifest/attack_label_flip_setup_${TS}.txt"
mkdir -p "$RUN_DIR/manifest"
exec > >(tee "$OUT") 2>&1

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "BYZ_CLIENTS=$BYZ_CLIENTS"
echo "UTC=$TS"
echo

declare -A C2IP
while read -r c ip; do
  [ -n "${c:-}" ] || continue
  [ -n "${ip:-}" ] || continue
  C2IP["$c"]="$ip"
done < "$MAP"

EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

echo "RESET: remove ALL models on edges"
for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "EDGE=$ip"
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
rm -f /opt/fl-client/models/*.npz 2>/dev/null || true
ls -la /opt/fl-client/models || true
" </dev/null
done

echo
echo "POISON: label flip (train_y) for BYZ clients only"
for c in $BYZ_CLIENTS; do
  ip="${C2IP[$c]:-}"
  [ -n "${ip:-}" ] || { echo "ERROR: client not in map: $c"; exit 1; }

  echo
  echo "BYZ=$c IP=$ip"
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
python3 - \"$c\" <<'PY'
import sys, os
import numpy as np

cid=sys.argv[1]
d='/opt/fl-client/splits'
y_path=f'{d}/{cid}_train_y.npy'
orig=f'{d}/{cid}_train_y.orig.npy'

y=np.load(y_path)

if not os.path.exists(orig):
    np.save(orig, y)
    y0=y
else:
    y0=np.load(orig)
    np.save(y_path, y0)
    y=y0

u=sorted(set(y0.tolist()))
yflip=(1-y0).astype(y0.dtype)
np.save(y_path, yflip)

diff=int((y0!=yflip).sum())
print('ORIG_UNIQUE=', u)
print('LEN=', int(len(y0)), 'DIFF=', diff, 'DIFF_RATIO=', round(diff/max(len(y0),1),4))
PY
" </dev/null
done

echo
echo "SAVED=$OUT"
