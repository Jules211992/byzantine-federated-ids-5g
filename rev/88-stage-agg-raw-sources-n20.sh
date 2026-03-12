#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

AGG=$(cat rev/.last_n20_agg_compare_dir 2>/dev/null || true)
[ -n "${AGG:-}" ] || { echo "ERROR: rev/.last_n20_agg_compare_dir introuvable"; exit 1; }
[ -d "${AGG:-}" ] || { echo "ERROR: dossier AGG introuvable: $AGG"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

COMPARE=$(cat rev/.last_n20_compare_dir 2>/dev/null || true)
[ -n "${COMPARE:-}" ] || { echo "ERROR: rev/.last_n20_compare_dir introuvable"; exit 1; }
[ -d "${COMPARE:-}" ] || { echo "ERROR: dossier COMPARE introuvable: $COMPARE"; exit 1; }

mkdir -p \
  "$AGG"/raw/baseline \
  "$AGG"/raw/label_flip \
  "$AGG"/raw/backdoor \
  "$AGG"/manifest \
  "$AGG"/logs

rm -rf "$AGG"/raw/baseline/*
rm -rf "$AGG"/raw/label_flip/*
rm -rf "$AGG"/raw/backdoor/*

for r in 1 2 3 4 5; do
  r2=$(printf '%02d' "$r")

  mkdir -p "$AGG/raw/baseline/round$r2"
  mkdir -p "$AGG/raw/label_flip/round$r2"
  mkdir -p "$AGG/raw/backdoor/round$r2"

  find "$RUN_DIR/p7_baseline/round$r2/client_logs" -maxdepth 1 -type f -name '*.json' -exec cp -f {} "$AGG/raw/baseline/round$r2/" \; 2>/dev/null || true

  find "$COMPARE/label_flip_raw/round$r2" -maxdepth 1 -type f -name '*.json' -exec cp -f {} "$AGG/raw/label_flip/round$r2/" \; 2>/dev/null || true

  if [ -d "$BUNDLE/raw/backdoor/round$r2" ]; then
    find "$BUNDLE/raw/backdoor/round$r2" -maxdepth 1 -type f -name '*.json' -exec cp -f {} "$AGG/raw/backdoor/round$r2/" \; 2>/dev/null || true
  fi
done

python3 - <<'PY' "$AGG" "$RUN_DIR" "$BUNDLE" "$COMPARE"
import json
import re
import sys
from pathlib import Path

agg = Path(sys.argv[1])
run_dir = Path(sys.argv[2])
bundle = Path(sys.argv[3])
compare = Path(sys.argv[4])

def natural_key(s):
    return [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', s)]

summary = {
    "agg_dir": str(agg),
    "run_dir": str(run_dir),
    "bundle": str(bundle),
    "compare_dir": str(compare),
    "sources": {}
}

for scenario in ["baseline", "label_flip", "backdoor"]:
    sc = {"rounds": {}, "total_json": 0}
    for r in range(1, 6):
        r2 = f"round{r:02d}"
        d = agg / "raw" / scenario / r2
        files = sorted([p.name for p in d.glob("*.json")], key=natural_key)
        sc["rounds"][r2] = {
            "dir": str(d),
            "count": len(files),
            "sample": files[:10]
        }
        sc["total_json"] += len(files)
    summary["sources"][scenario] = sc

(agg / "manifest" / "RAW_SOURCE_MANIFEST.json").write_text(json.dumps(summary, indent=2))

lines = [
    "RAW SOURCES STAGED FOR N20 AGGREGATOR COMPARISON",
    f"agg_dir={agg}",
    f"baseline_total={summary['sources']['baseline']['total_json']}",
    f"label_flip_total={summary['sources']['label_flip']['total_json']}",
    f"backdoor_total={summary['sources']['backdoor']['total_json']}",
]
(agg / "README_RAW_SOURCES.txt").write_text("\n".join(lines) + "\n")

print("AGG_DIR=", agg)
print("RAW_MANIFEST=", agg / "manifest" / "RAW_SOURCE_MANIFEST.json")
print("README=", agg / "README_RAW_SOURCES.txt")
PY
