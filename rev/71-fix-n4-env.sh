#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

cat <<'PY' > /tmp/patch_fl_ids_client.py
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old_ipfs = "IPFS_PATH  = os.environ.get('IPFS_PATH',  '/data/ipfs')"
new_ipfs = "IPFS_PATH  = os.environ.get('IPFS_PATH',  '/home/ubuntu/.ipfs')"
if old_ipfs not in s:
    raise SystemExit("IPFS_PATH pattern not found in fl_ids_client.py")
s = s.replace(old_ipfs, new_ipfs, 1)

old_load_model = """def load_model():
    path = f"{MODEL_DIR}/{CLIENT_ID}_model.npz"
    if os.path.exists(path):
        m = np.load(path)
        return m["w"].copy(), float(m["b"])
    with open(f"{SPLITS_DIR}/feature_names.json") as f:
        info = json.load(f)
    n = None
    try:
        if isinstance(info, dict) and "n_features" in info:
            n = int(info["n_features"])
        elif isinstance(info, list):
            n = len(info)
    except Exception:
        n = None
    if n is None:
        try:
            n = int(np.load(f"{SPLITS_DIR}/feat_min.npy").shape[0])
        except Exception:
            n = 0
    return np.zeros(n, dtype=np.float32), 0.0
"""

new_load_model = """def feature_count():
    with open(f"{SPLITS_DIR}/feature_names.json") as f:
        info = json.load(f)
    n = None
    try:
        if isinstance(info, dict) and "n_features" in info:
            n = int(info["n_features"])
        elif isinstance(info, list):
            n = len(info)
    except Exception:
        n = None
    if n is None:
        try:
            n = int(np.load(f"{SPLITS_DIR}/feat_min.npy").shape[0])
        except Exception:
            n = 0
    return n

def load_model():
    path = f"{MODEL_DIR}/{CLIENT_ID}_model.npz"
    n = feature_count()
    if os.path.exists(path):
        try:
            m = np.load(path)
            w = m["w"].copy()
            b = float(m["b"])
            if int(w.shape[0]) == int(n):
                return w, b
        except Exception:
            pass
    return np.zeros(n, dtype=np.float32), 0.0
"""

if old_load_model not in s:
    raise SystemExit("load_model block not found in fl_ids_client.py")

s = s.replace(old_load_model, new_load_model, 1)
p.write_text(s)
print("OK client patch:", p)
PY

cat <<'PY' > /tmp/patch_fl_ids_byz.py
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old_attack_block = """    if BYZ_TYPE == "label_flip":
        y_train = 1 - y
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y_train, w, b)

    elif BYZ_TYPE == "noise":
        w = np.random.randn(n_feat).astype(np.float32) * BYZ_SCALE
        b = float(np.random.randn() * BYZ_SCALE)
        t_train = 0.0

    elif BYZ_TYPE == "model_poison":
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y, w, b)
        w = -w * BYZ_SCALE
        b = -b * BYZ_SCALE

    else:
        raise ValueError(f"Unknown BYZ_TYPE: {BYZ_TYPE}")
"""

new_attack_block = """    attack = (BYZ_TYPE or "").strip().lower().replace("-", "_")

    if attack in ("label_flip", "labelflip"):
        y_train = 1 - y
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y_train, w, b)

    elif attack in ("noise", "gaussian"):
        w = np.random.randn(n_feat).astype(np.float32) * BYZ_SCALE
        b = float(np.random.randn() * BYZ_SCALE)
        t_train = 0.0

    elif attack in ("model_poison", "signflip", "sign_flip", "flip"):
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y, w, b)
        w = -w * BYZ_SCALE
        b = -b * BYZ_SCALE

    elif attack == "backdoor":
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y, w, b)
        if w.size:
            w[-1] = w[-1] + BYZ_SCALE

    else:
        raise ValueError(f"Unknown BYZ_TYPE: {BYZ_TYPE}")
"""

if old_attack_block not in s:
    raise SystemExit("attack block not found in fl_ids_byzantine.py")

s = s.replace(old_attack_block, new_attack_block, 1)

old_attack_type = '"attack_type":   BYZ_TYPE,'
new_attack_type = '"attack_type":   attack,'
if old_attack_type not in s:
    raise SystemExit("attack_type field not found in fl_ids_byzantine.py")
s = s.replace(old_attack_type, new_attack_type, 1)

p.write_text(s)
print("OK byz patch:", p)
PY

for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  echo
  echo "================ FIX $ip ================"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/patch_fl_ids_client.py ubuntu@"$ip":/tmp/patch_fl_ids_client.py >/dev/null
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/patch_fl_ids_byz.py ubuntu@"$ip":/tmp/patch_fl_ids_byz.py >/dev/null

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    python3 /tmp/patch_fl_ids_client.py /opt/fl-client/fl_ids_client.py
    if [ -f /opt/fl-client/fl_ids_byzantine.py ]; then
      python3 /tmp/patch_fl_ids_byz.py /opt/fl-client/fl_ids_byzantine.py
    fi
    mkdir -p /opt/fl-client/models /opt/fl-client/logs
    rm -f /opt/fl-client/models/*.npz
    rm -f /opt/fl-client/logs/*.json
    rm -f /opt/fl-client/logs/*.out
    test -d /home/ubuntu/.ipfs
    ipfs version >/dev/null
    python3 - <<'"'"'PY'"'"'
import glob, json, os, numpy as np

with open("/opt/fl-client/splits/feature_names.json") as f:
    info = json.load(f)

if isinstance(info, dict) and "n_features" in info:
    n = int(info["n_features"])
elif isinstance(info, list):
    n = len(info)
else:
    n = int(np.load("/opt/fl-client/splits/feat_min.npy").shape[0])

print("N_FEATURES=", n)

for p in sorted(glob.glob("/opt/fl-client/splits/*_train_X.npy")):
    x = np.load(p, mmap_mode="r")
    print(os.path.basename(p), x.shape)
PY
  '
done

echo
echo "DONE_FIX"
