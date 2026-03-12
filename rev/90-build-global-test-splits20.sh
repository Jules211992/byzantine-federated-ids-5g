#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SPLITS="$RUN_DIR/splits_20"
[ -d "$SPLITS" ] || { echo "ERROR: splits_20 introuvable: $SPLITS"; exit 1; }

OUT="$RUN_DIR/native_global_eval_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

python3 - "$SPLITS" "$OUT" <<'PY'
import json
import re
import sys
from pathlib import Path
import numpy as np

splits = Path(sys.argv[1])
out = Path(sys.argv[2])

def cid_num(p):
    m = re.search(r'edge-client-(\d+)', p.name)
    return int(m.group(1)) if m else 10**9

x_files = sorted(splits.glob("edge-client-*_test_X.npy"), key=cid_num)
y_files = sorted(splits.glob("edge-client-*_test_y.npy"), key=cid_num)

if len(x_files) != 20 or len(y_files) != 20:
    raise SystemExit(f"ERROR: expected 20 test X and 20 test y files, got {len(x_files)} and {len(y_files)}")

X = np.concatenate([np.load(f) for f in x_files], axis=0)
y = np.concatenate([np.load(f) for f in y_files], axis=0)

gx = splits / "global_test_X.npy"
gy = splits / "global_test_y.npy"

np.save(gx, X)
np.save(gy, y)

summary = {
    "run_dir": str(splits.parent),
    "splits_dir": str(splits),
    "global_test_X": str(gx),
    "global_test_y": str(gy),
    "n_clients": len(x_files),
    "n_samples": int(X.shape[0]),
    "n_features": int(X.shape[1]) if len(X.shape) > 1 else None,
    "x_sources": [str(f) for f in x_files],
    "y_sources": [str(f) for f in y_files]
}

(out / "GLOBAL_TEST_BUILD.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY

echo "RUN_DIR=$RUN_DIR"
echo "SPLITS=$SPLITS"
echo "GLOBAL_X=$SPLITS/global_test_X.npy"
echo "GLOBAL_Y=$SPLITS/global_test_y.npy"
echo "REPORT=$OUT/GLOBAL_TEST_BUILD.json"
