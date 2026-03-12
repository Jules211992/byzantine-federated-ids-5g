#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

OUT="$RUN_DIR/reference_metrics_trace_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

cp -f "$BUNDLE"/baseline/baseline_all_rounds_clean.json "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE"/label_flip/label_flip_all_rounds_clean.json "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE"/backdoor/backdoor_all_rounds_clean.json "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE"/tables_input/paper_main_metrics.csv "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE"/figures_input/plot_round_metrics.csv "$OUT/" 2>/dev/null || true

grep -RIn \
  -E 'baseline_all_rounds_clean|label_flip_all_rounds_clean|backdoor_all_rounds_clean|paper_main_metrics|plot_round_metrics|f1_honest|f1_byz|fpr_honest|fpr_byz|f1_avg|baseline_f1_avg|label_flip_honest_f1_avg|backdoor_honest_f1_avg|p8_labelflip_all_rounds|p15_backdoor|p7_baseline|summary/p8_labelflip_round|summary/p15_backdoor_round|summary/p7_baseline' \
  rev phase7 phase8 phase9 phase10 "$RUN_DIR" \
  > "$OUT/grep_trace.txt" 2>/dev/null || true

python3 - <<'PY' "$BUNDLE" "$OUT"
import json
import csv
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
out = Path(sys.argv[2])

def load_json(p):
    return json.loads(Path(p).read_text())

baseline = load_json(bundle / "baseline" / "baseline_all_rounds_clean.json")
label = load_json(bundle / "label_flip" / "label_flip_all_rounds_clean.json")
backdoor = load_json(bundle / "backdoor" / "backdoor_all_rounds_clean.json")

paper = list(csv.DictReader(open(bundle / "tables_input" / "paper_main_metrics.csv")))
plot = list(csv.DictReader(open(bundle / "figures_input" / "plot_round_metrics.csv")))

report = {
    "bundle": str(bundle),
    "baseline_json_keys": list(baseline.keys()),
    "label_flip_json_keys": list(label.keys()),
    "backdoor_json_keys": list(backdoor.keys()),
    "baseline_json": baseline,
    "label_flip_json": label,
    "backdoor_json": backdoor,
    "paper_main_metrics_rows": paper,
    "plot_round_metrics_head": plot[:15],
}
(out / "REFERENCE_TRACE.json").write_text(json.dumps(report, indent=2))

notes = []
notes.append(f"BUNDLE={bundle}")
notes.append("")
notes.append("BASELINE JSON")
notes.append(json.dumps(baseline, indent=2))
notes.append("")
notes.append("LABEL FLIP JSON")
notes.append(json.dumps(label, indent=2))
notes.append("")
notes.append("BACKDOOR JSON")
notes.append(json.dumps(backdoor, indent=2))
notes.append("")
notes.append("PAPER MAIN METRICS")
for row in paper:
    notes.append(str(row))
notes.append("")
notes.append("PLOT ROUND METRICS HEAD")
for row in plot[:15]:
    notes.append(str(row))

(out / "REFERENCE_TRACE.txt").write_text("\n".join(notes))
print("TRACE_JSON=", out / "REFERENCE_TRACE.json")
print("TRACE_TXT=", out / "REFERENCE_TRACE.txt")
print("GREP_TRACE=", out / "grep_trace.txt")
PY

echo "OUT=$OUT"
echo "===== PAPER MAIN METRICS ====="
cat "$OUT/paper_main_metrics.csv"

echo
echo "===== BASELINE JSON ====="
cat "$OUT/baseline_all_rounds_clean.json"

echo
echo "===== LABEL FLIP JSON ====="
cat "$OUT/label_flip_all_rounds_clean.json"

echo
echo "===== BACKDOOR JSON ====="
cat "$OUT/backdoor_all_rounds_clean.json"

echo
echo "===== GREP TRACE HEAD ====="
sed -n '1,200p' "$OUT/grep_trace.txt"
