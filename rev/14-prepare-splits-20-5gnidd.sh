#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

ZIP="$RUN_DIR/dataset/Combined.csv.zip"
if [ ! -f "$ZIP" ]; then
  echo "ERROR: zip introuvable: $ZIP"
  exit 1
fi

OUT_DIR="$RUN_DIR/splits_20"
MAN_DIR="$RUN_DIR/manifest"
mkdir -p "$OUT_DIR" "$MAN_DIR"

TS=$(date -u +%Y%m%d_%H%M%S)
LOG="$MAN_DIR/prepare_splits20_${TS}.txt"

exec > >(tee "$LOG") 2>&1

echo "RUN_DIR=$RUN_DIR"
echo "ZIP=$ZIP"
echo "OUT_DIR=$OUT_DIR"
echo "UTC=$TS"
echo

python3 - <<'PY'
import os, json, zipfile, re
import numpy as np
import pandas as pd
from collections import Counter, defaultdict

run_dir = os.environ.get("RUN_DIR")
zip_path = os.environ.get("ZIP")
out_dir = os.environ.get("OUT_DIR")
man_dir = os.environ.get("MAN_DIR")

def die(msg):
    raise SystemExit(msg)

os.makedirs(out_dir, exist_ok=True)
os.makedirs(man_dir, exist_ok=True)

with zipfile.ZipFile(zip_path, "r") as z:
    names = z.namelist()
    csvs = [n for n in names if n.lower().endswith(".csv")]
    if not csvs:
        die("ERROR: aucun .csv trouvé dans le zip")
    csv_in_zip = csvs[0]
    csv_path = os.path.join(run_dir, "dataset", "Combined.csv")
    if not os.path.isfile(csv_path) or os.path.getsize(csv_path) < 1024:
        with z.open(csv_in_zip) as f_in, open(csv_path, "wb") as f_out:
            while True:
                b = f_in.read(1024*1024)
                if not b:
                    break
                f_out.write(b)
    print("CSV_IN_ZIP=", csv_in_zip)
    print("CSV_PATH=", csv_path)
    print("CSV_SIZE_BYTES=", os.path.getsize(csv_path))
    print()

df = pd.read_csv(csv_path, low_memory=False)

cols = list(df.columns)
lc = {c.lower(): c for c in cols}

label_candidates = ["label", "class", "y", "target", "is_attack"]
attack_candidates = ["attack", "attacktype", "attack_type", "type", "category", "traffic", "subtype"]

label_col = None
for k in label_candidates:
    for c in cols:
        if c.lower() == k or c.lower().endswith(k):
            label_col = c
            break
    if label_col:
        break

attack_col = None
for k in attack_candidates:
    for c in cols:
        if c.lower() == k or c.lower().endswith(k) or k in c.lower():
            if c != label_col:
                attack_col = c
                break
    if attack_col:
        break

if label_col is None:
    die("ERROR: impossible de détecter la colonne label (Label/Class/Target).")

print("DETECTED_LABEL_COL=", label_col)
print("DETECTED_ATTACK_COL=", attack_col if attack_col else "NONE")
print("N_ROWS=", len(df))
print("N_COLS=", len(cols))
print()

label_vals = df[label_col].astype(str).str.strip()
label_vals_low = label_vals.str.lower()

def map_label(v):
    v = str(v).strip().lower()
    if v in ["benign", "normal", "0", "false", "legit"]:
        return 0
    if v in ["malicious", "attack", "1", "true"]:
        return 1
    if "benign" in v or "normal" in v:
        return 0
    return 1

y = label_vals_low.map(map_label).astype(np.int8).to_numpy()

if attack_col:
    attack_vals = df[attack_col].astype(str).str.strip()
else:
    attack_vals = pd.Series(["Unknown"] * len(df))

def family(att):
    a = str(att).strip().lower()
    if a == "" or a == "nan":
        return "Unknown"
    if "http" in a:
        return "AppLayer"
    if "slow" in a:
        return "LowRateDoS"
    if "scan" in a or "connect" in a:
        return "Scanning"
    if "flood" in a or "icmp" in a or "udp" in a or "syn" in a:
        return "Flooding"
    if a in ["benign", "normal"]:
        return "Benign"
    return "Other"

fam = attack_vals.map(family)

print("LABEL_COUNTS=", dict(Counter(y)))
top_att = Counter(attack_vals).most_common(15)
print("ATTACK_TYPES_TOP15=", top_att)
top_fam = Counter(fam).most_common()
print("FAMILY_COUNTS=", top_fam)
print()

feature_df = df.drop(columns=[label_col], errors="ignore")
if attack_col:
    feature_df = feature_df.drop(columns=[attack_col], errors="ignore")

for c in list(feature_df.columns):
    if feature_df[c].dtype == object:
        feature_df[c] = pd.to_numeric(feature_df[c], errors="coerce")

feature_df = feature_df.replace([np.inf, -np.inf], np.nan).fillna(0.0)

num_cols = [c for c in feature_df.columns]
X_raw = feature_df.to_numpy(dtype=np.float32)

feat_min = np.min(X_raw, axis=0).astype(np.float32)
feat_max = np.max(X_raw, axis=0).astype(np.float32)
den = (feat_max - feat_min)
den[den == 0] = 1.0
X = (X_raw - feat_min) / den

with open(os.path.join(out_dir, "feature_names.json"), "w") as f:
    json.dump(num_cols, f, indent=2)

np.save(os.path.join(out_dir, "feat_min.npy"), feat_min)
np.save(os.path.join(out_dir, "feat_max.npy"), feat_max)

print("N_FEATURES=", X.shape[1])
print("FEATURE_SAMPLE=", num_cols[:15])
print()

idx_all = np.arange(len(X))
idx_ben = idx_all[y == 0]
idx_mal = idx_all[y == 1]

rng = np.random.default_rng(42)
rng.shuffle(idx_ben)
rng.shuffle(idx_mal)

clients = [f"edge-client-{i}" for i in range(1, 21)]

primary = {}
for i, cid in enumerate(clients, start=1):
    if 1 <= i <= 5:
        primary[cid] = "Flooding"
    elif 6 <= i <= 10:
        primary[cid] = "AppLayer"
    elif 11 <= i <= 15:
        primary[cid] = "Scanning"
    else:
        primary[cid] = "LowRateDoS"

fam_idx = defaultdict(list)
for i in idx_mal:
    fam_idx[fam.iloc[i]].append(int(i))
for k in list(fam_idx.keys()):
    rng.shuffle(fam_idx[k])

B = max(5000, len(idx_ben) // 20)
M = max(4000, len(idx_mal) // 20)
p_primary = 0.7

ben_chunks = np.array_split(idx_ben, 20)

used_mal = set()
split_stats = {}

def take_from_list(lst, n, used_set):
    out = []
    j = 0
    while j < len(lst) and len(out) < n:
        v = lst[j]
        j += 1
        if v in used_set:
            continue
        used_set.add(v)
        out.append(v)
    return out

mal_pool = [int(i) for i in idx_mal]
rng.shuffle(mal_pool)

pool_ptr = 0

for k, cid in enumerate(clients):
    ben_sel = ben_chunks[k]
    if len(ben_sel) > B:
        ben_sel = rng.choice(ben_sel, size=B, replace=False)
    ben_sel = np.array(ben_sel, dtype=int)

    need_m = M
    need_primary = int(p_primary * need_m)
    need_rest = need_m - need_primary

    fam_name = primary[cid]
    fam_list = fam_idx.get(fam_name, [])
    primary_sel = take_from_list(fam_list, need_primary, used_mal)

    rest_sel = []
    while len(rest_sel) < need_rest and pool_ptr < len(mal_pool):
        v = mal_pool[pool_ptr]
        pool_ptr += 1
        if v in used_mal:
            continue
        used_mal.add(v)
        rest_sel.append(v)

    if len(primary_sel) + len(rest_sel) < need_m:
        remaining = need_m - (len(primary_sel) + len(rest_sel))
        cand = [v for v in mal_pool if v not in used_mal]
        if len(cand) >= remaining:
            extra = rng.choice(cand, size=remaining, replace=False).tolist()
        else:
            extra = rng.choice(mal_pool, size=remaining, replace=True).tolist()
        for v in extra:
            if v not in used_mal:
                used_mal.add(v)
            rest_sel.append(int(v))

    mal_sel = np.array(primary_sel + rest_sel, dtype=int)

    sel = np.concatenate([ben_sel, mal_sel])
    rng.shuffle(sel)

    y_sel = y[sel]
    idx0 = sel[y_sel == 0]
    idx1 = sel[y_sel == 1]
    rng.shuffle(idx0); rng.shuffle(idx1)

    n0 = len(idx0); n1 = len(idx1)
    te0 = max(1, int(0.2 * n0))
    te1 = max(1, int(0.2 * n1))

    test_idx = np.concatenate([idx0[:te0], idx1[:te1]])
    train_idx = np.concatenate([idx0[te0:], idx1[te1:]])

    rng.shuffle(train_idx)
    rng.shuffle(test_idx)

    Xtr = X[train_idx]
    ytr = y[train_idx]
    Xte = X[test_idx]
    yte = y[test_idx]

    np.save(os.path.join(out_dir, f"{cid}_train_X.npy"), Xtr.astype(np.float32))
    np.save(os.path.join(out_dir, f"{cid}_train_y.npy"), ytr.astype(np.int8))
    np.save(os.path.join(out_dir, f"{cid}_test_X.npy"), Xte.astype(np.float32))
    np.save(os.path.join(out_dir, f"{cid}_test_y.npy"), yte.astype(np.int8))

    fam_counts = Counter([family(attack_vals.iloc[int(i)]) for i in sel[y[sel]==1]])
    atk_counts = Counter([str(attack_vals.iloc[int(i)]) for i in sel[y[sel]==1]]).most_common(8)

    split_stats[cid] = {
        "primary_family": fam_name,
        "n_features": int(X.shape[1]),
        "train_samples": int(len(train_idx)),
        "test_samples": int(len(test_idx)),
        "train_benign": int(np.sum(ytr == 0)),
        "train_malicious": int(np.sum(ytr == 1)),
        "test_benign": int(np.sum(yte == 0)),
        "test_malicious": int(np.sum(yte == 1)),
        "malicious_family_dist": dict(fam_counts),
        "malicious_attack_top": atk_counts,
    }

with open(os.path.join(out_dir, "split_stats.json"), "w") as f:
    json.dump(split_stats, f, indent=2)

manifest = {
    "dataset": "5G-NIDD Combined.csv",
    "label_col": label_col,
    "attack_col": attack_col,
    "n_rows": int(len(df)),
    "n_features": int(X.shape[1]),
    "clients": clients,
    "primary_family_map": primary,
    "B_per_client_target": int(B),
    "M_per_client_target": int(M),
}
with open(os.path.join(man_dir, "splits20_manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)

print("OK: splits_20 generated")
print("OUT_DIR=", out_dir)
print("MANIFEST=", os.path.join(man_dir, "splits20_manifest.json"))
print("SPLIT_STATS=", os.path.join(out_dir, "split_stats.json"))
PY
