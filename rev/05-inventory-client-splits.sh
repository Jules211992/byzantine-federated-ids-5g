#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "=============================="
  echo "EDGE=$ip"
  echo "------------------------------"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
echo IP:\$(hostname -I | awk '{print \$1}')
echo

if [ ! -d /opt/fl-client/splits ]; then
  echo NO_SPLITS_DIR
  exit 0
fi

echo CLIENT_IDS_FOUND:
ls -1 /opt/fl-client/splits | awk -F'_' '/_train_X.npy$/{print \$1}' | sort -u | sed -n '1,120p'
echo

python3 - <<'PY'
import os, glob
try:
  import numpy as np
except Exception as e:
  print("SUMMARY: numpy_import_error", e)
  raise SystemExit(0)

d="/opt/fl-client/splits"
ids=sorted({os.path.basename(p).split("_train_X.npy")[0] for p in glob.glob(d+"/*_train_X.npy")})
print("SUMMARY:")
for cid in ids:
  tx=os.path.join(d,f"{cid}_train_X.npy")
  ty=os.path.join(d,f"{cid}_train_y.npy")
  vx=os.path.join(d,f"{cid}_test_X.npy")
  vy=os.path.join(d,f"{cid}_test_y.npy")
  ok=all(os.path.exists(p) for p in (tx,ty,vx,vy))
  if not ok:
    print(f"  {cid}: MISSING_FILES")
    continue
  X=np.load(tx, mmap_mode='r')
  y=np.load(ty, mmap_mode='r')
  Xt=np.load(vx, mmap_mode='r')
  yt=np.load(vy, mmap_mode='r')
  print(f"  {cid}: train_X={X.shape} train_y={y.shape} test_X={Xt.shape} test_y={yt.shape}")
PY
"
done
