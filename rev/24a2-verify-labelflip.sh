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

declare -A C2IP
while read -r c ip; do
  [ -n "${c:-}" ] || continue
  [ -n "${ip:-}" ] || continue
  C2IP["$c"]="$ip"
done < "$MAP"

for c in $BYZ_CLIENTS; do
  ip="${C2IP[$c]:-}"
  [ -n "${ip:-}" ] || { echo "ERROR: client not in map: $c"; exit 1; }

  echo
  echo "===== VERIFY $c @ $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
python3 - \"$c\" <<'PY'
import sys, os
import numpy as np

cid=sys.argv[1]
d='/opt/fl-client/splits'
y=f'{d}/{cid}_train_y.npy'
orig=f'{d}/{cid}_train_y.orig.npy'
if not os.path.exists(orig):
    raise SystemExit('MISSING_ORIG='+orig)

y0=np.load(orig)
y1=np.load(y)
diff=int((y0!=y1).sum())
print('LEN=', int(len(y1)), 'DIFF=', diff, 'DIFF_RATIO=', round(diff/max(len(y1),1),4))
print('UNIQUE_ORIG=', sorted(set(y0.tolist())), 'UNIQUE_NOW=', sorted(set(y1.tolist())))
PY
" </dev/null
done

echo
echo "OK"
