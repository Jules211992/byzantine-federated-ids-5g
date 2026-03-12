#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

LIVE=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* 2>/dev/null | head -n 1 || true)
[ -n "${LIVE:-}" ] || { echo "ERROR: agg_compare_n20_live introuvable"; exit 1; }

OUT="$RUN_DIR/live_pipeline_audit_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

cp -f rev/92-run-live-agg-benchmark-n20.sh "$OUT/" 2>/dev/null || true
cp -f phase7/multi_krum_aggregator.py "$OUT/" 2>/dev/null || true
cp -f phase8/fedavg_aggregator.py "$OUT/" 2>/dev/null || true
cp -f phase8/trimmed_mean_aggregator.py "$OUT/" 2>/dev/null || true

python3 - <<'PY' "$LIVE" "$OUT"
import csv
import json
import hashlib
import sys
from pathlib import Path

live = Path(sys.argv[1])
out = Path(sys.argv[2])

per_round = live / "figures_input" / "agg_compare_round_metrics_live.csv"
rows = list(csv.DictReader(per_round.open()))

interesting = []
for r in rows:
    if (r["scenario"], r["aggregator"], r["round"]) in {
        ("label_flip", "fedavg", "5"),
        ("backdoor", "multikrum", "4"),
        ("backdoor", "multikrum", "5"),
        ("backdoor", "fedavg", "5"),
        ("backdoor", "trimmedmean", "5"),
        ("baseline", "fedavg", "5"),
    }:
        interesting.append(r)

def digest_weights(j):
    w = j.get("weights", [])
    s = json.dumps(w, separators=(",", ":"))
    return hashlib.sha256(s.encode()).hexdigest()

report = {
    "live_dir": str(live),
    "interesting_rows": [],
}

for r in interesting:
    p = Path(r["source_json"])
    j = json.loads(p.read_text())
    report["interesting_rows"].append({
        "scenario": r["scenario"],
        "aggregator": r["aggregator"],
        "round": int(r["round"]),
        "source_json": str(p),
        "global_metrics": j.get("global_metrics", {}),
        "selected": j.get("selected", []),
        "rejected": j.get("rejected", []),
        "rejected_byz": j.get("rejected_byz"),
        "detect_round": j.get("detect_round"),
        "aggregation_time_ms": j.get("aggregation_time_ms"),
        "bias": j.get("bias"),
        "weights_sha256": digest_weights(j),
        "weights_len": len(j.get("weights", [])),
    })

(out / "LIVE_PIPELINE_AUDIT.json").write_text(json.dumps(report, indent=2))

print("===== INTERESTING SOURCE JSONS =====")
for item in report["interesting_rows"]:
    print(item["scenario"], item["aggregator"], item["round"], item["weights_sha256"], item["source_json"])
PY

echo
echo "===== SCRIPT rev/92-run-live-agg-benchmark-n20.sh ====="
sed -n '1,320p' rev/92-run-live-agg-benchmark-n20.sh > "$OUT/rev92.txt"
cat "$OUT/rev92.txt"

echo
echo "===== PIPELINE AUDIT JSON ====="
cat "$OUT/LIVE_PIPELINE_AUDIT.json"

echo
echo "===== RAW FILE TREE ====="
find "$LIVE" -maxdepth 3 -type f | sort > "$OUT/live_tree.txt"
sed -n '1,260p' "$OUT/live_tree.txt"

echo
echo "OUT=$OUT"
