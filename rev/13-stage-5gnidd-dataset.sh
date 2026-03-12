#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

mkdir -p "$RUN_DIR/dataset" "$RUN_DIR/manifest"

TS=$(date -u +%Y%m%d_%H%M%S)

SRC="${SRC:-}"
if [ -z "${SRC:-}" ]; then
  for d in "$HOME/Downloads" "$HOME/Téléchargements" "$HOME/Telechargements"; do
    if [ -d "$d" ]; then
      cand=$(ls -t "$d"/Combined*.zip "$d"/Combined*.csv 2>/dev/null | head -n 1 || true)
      if [ -n "${cand:-}" ]; then
        SRC="$cand"
        break
      fi
    fi
  done
fi

if [ -z "${SRC:-}" ] || [ ! -f "$SRC" ]; then
  echo "ERROR: fichier dataset introuvable. Fournis SRC=/chemin/vers/Combined.csv.zip (ou Combined.csv)"
  exit 1
fi

DST="$RUN_DIR/dataset/$(basename "$SRC")"
cp -f "$SRC" "$DST"

echo "RUN_DIR=$RUN_DIR"
echo "DST=$DST"
echo "SIZE_BYTES=$(stat -c %s "$DST" 2>/dev/null || stat -f %z "$DST")"

SHA=$(sha256sum "$DST" | awk '{print $1}')
echo "SHA256=$SHA" | tee "$RUN_DIR/manifest/5gnidd_sha256_${TS}.txt"

SAMPLE_ROWS="${SAMPLE_ROWS:-800000}"
OUT_JSON="$RUN_DIR/manifest/5gnidd_profile_${TS}.json"

python3 - "$DST" "$SAMPLE_ROWS" <<'PY' > "$OUT_JSON"
import sys, os, json, zipfile
import pandas as pd
import collections

path = sys.argv[1]
sample_rows = int(sys.argv[2])

def open_csv_any(p):
    if p.lower().endswith(".zip"):
        zf = zipfile.ZipFile(p)
        csvs = [n for n in zf.namelist() if n.lower().endswith(".csv")]
        if not csvs:
            raise RuntimeError("zip sans CSV")
        name = sorted(csvs)[0]
        return zf.open(name), {"zip": True, "inner": name, "members": zf.namelist()[:50]}
    return open(p, "rb"), {"zip": False}

f, meta = open_csv_any(path)

label = collections.Counter()
atype = collections.Counter()
tool  = collections.Counter()

cols = None
n = 0
first_chunk = None

for chunk in pd.read_csv(
    f,
    chunksize=200000,
    low_memory=False,
):
    if cols is None:
        cols = list(chunk.columns)
        first_chunk = chunk.head(2000).copy()
    if "Label" in chunk.columns:
        label.update(chunk["Label"].astype(str).fillna("NA"))
    if "Attack Type" in chunk.columns:
        atype.update(chunk["Attack Type"].astype(str).fillna("NA"))
    if "Attack Tool" in chunk.columns:
        tool.update(chunk["Attack Tool"].astype(str).fillna("NA"))
    n += len(chunk)
    if n >= sample_rows:
        break

dtypes = {}
obj_cols = []
if first_chunk is not None:
    for c in first_chunk.columns:
        dt = str(first_chunk[c].dtype)
        dtypes[c] = dt
    obj_cols = [c for c in first_chunk.columns if str(first_chunk[c].dtype) == "object"]

out = {
    "path": os.path.abspath(path),
    "meta": meta,
    "sample_rows_read": n,
    "n_cols": 0 if cols is None else len(cols),
    "columns_head": [] if cols is None else cols[:60],
    "object_cols": obj_cols,
    "dtypes_sample": dtypes,
    "label_counts": dict(label),
    "attack_type_top": atype.most_common(30),
    "attack_tool_top": tool.most_common(30),
}

print(json.dumps(out, indent=2))
PY

echo
echo "SAVED_PROFILE=$OUT_JSON"
python3 -c "import json; d=json.load(open('$OUT_JSON')); print('LABEL_COUNTS=',d.get('label_counts')); print('ATTACK_TYPES_TOP=',d.get('attack_type_top')[:10])"
