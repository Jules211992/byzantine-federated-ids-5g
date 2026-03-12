#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

PY_LOCAL=/tmp/inv_splits.py
cat <<'PY' > "$PY_LOCAL"
import os, glob
import numpy as np

d="/opt/fl-client/splits"
if not os.path.isdir(d):
    print("NO_SPLITS_DIR")
    raise SystemExit(0)

ids=sorted({os.path.basename(p)[:-len("_train_X.npy")] for p in glob.glob(os.path.join(d,"*_train_X.npy"))})
print("CLIENT_IDS_FOUND:")
for cid in ids:
    print(cid)
print()
print("SUMMARY:")

for cid in ids:
    paths = {
        "train_X": os.path.join(d, f"{cid}_train_X.npy"),
        "train_y": os.path.join(d, f"{cid}_train_y.npy"),
        "test_X":  os.path.join(d, f"{cid}_test_X.npy"),
        "test_y":  os.path.join(d, f"{cid}_test_y.npy"),
    }
    missing=[k for k,p in paths.items() if not os.path.exists(p)]
    if missing:
        print(f"  {cid}: MISSING {','.join(missing)}")
        continue

    X=np.load(paths["train_X"], mmap_mode="r")
    y=np.load(paths["train_y"], mmap_mode="r")
    Xt=np.load(paths["test_X"], mmap_mode="r")
    yt=np.load(paths["test_y"], mmap_mode="r")
    print(f"  {cid}: train_X={X.shape} train_y={y.shape} test_X={Xt.shape} test_y={yt.shape}")
PY

chmod 644 "$PY_LOCAL"

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "=============================="
  echo "EDGE=$ip"
  echo "------------------------------"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "mkdir -p /tmp"
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$PY_LOCAL" ubuntu@"$ip":/tmp/inv_splits.py >/dev/null

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
echo IP:\$(hostname -I | awk '{print \$1}')
echo
python3 /tmp/inv_splits.py | sed -n '1,160p'
"
done
