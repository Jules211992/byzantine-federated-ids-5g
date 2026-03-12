#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/agg_compare_n4_${TS}"
RAW="$OUT/raw"
mkdir -p "$RAW"

LOGROOT="$HOME/byz-fed-ids-5g/phase8/logs"

run_one () {
  local attack="$1"
  local agg="$2"

  echo
  echo "========================================"
  echo "RUN attack=$attack agg=$agg"
  echo "========================================"

  mkdir -p "$RAW/$attack/$agg"

  if [ "$agg" = "fedavg" ]; then
    rm -f "$LOGROOT"/fedavg_r*.json
  elif [ "$agg" = "trimmedmean" ]; then
    rm -f "$LOGROOT"/trimmedmean_r*.json
    rm -f "$LOGROOT"/"${attack}_${agg}"_r*.json
  else
    rm -f "$LOGROOT"/"${attack}_${agg}"_r*.json
  fi

  bash ~/byz-fed-ids-5g/phase8/run_experiment.sh "$attack" "$agg" | tee "$RAW/$attack/$agg/console.txt"

  if [ "$agg" = "fedavg" ]; then
    cp -f "$LOGROOT"/fedavg_r*.json "$RAW/$attack/$agg/" 2>/dev/null || true
  else
    cp -f "$LOGROOT"/"${attack}_${agg}"_r*.json "$RAW/$attack/$agg/" 2>/dev/null || true
  fi
}

run_one signflip multikrum
run_one signflip fedavg
run_one signflip trimmedmean
run_one backdoor multikrum
run_one backdoor fedavg
run_one backdoor trimmedmean

python3 - "$RAW" "$OUT/agg_compare_n4_per_round.csv" "$OUT/agg_compare_n4_summary.csv" <<'PY'
import sys, json, csv, statistics
from pathlib import Path

raw = Path(sys.argv[1])
out_per = Path(sys.argv[2])
out_sum = Path(sys.argv[3])

rows = []

def load_json_maybe_mixed(path):
    txt = path.read_text(errors="ignore").strip()
    if not txt:
        return None
    if txt.startswith("{"):
        return json.loads(txt)
    i = txt.find("{")
    if i >= 0:
        return json.loads(txt[i:])
    return None

for attack_dir in sorted([p for p in raw.iterdir() if p.is_dir()]):
    attack = attack_dir.name
    for agg_dir in sorted([p for p in attack_dir.iterdir() if p.is_dir()]):
        agg = agg_dir.name
        for p in sorted(agg_dir.glob("*.json")):
            data = load_json_maybe_mixed(p)
            if not data:
                continue

            gm = data.get("global_metrics", {})
            round_num = data.get("round")

            if agg == "multikrum":
                n_clients = len(data.get("selected", [])) + len(data.get("rejected", []))
                rejected_count = len(data.get("rejected", []))
                byz_detected = data.get("byzantine_detected")
                agg_time_ms = data.get("krum_time_ms")
            elif agg == "trimmedmean":
                n_clients = data.get("n_clients")
                rejected_count = 0
                byz_detected = data.get("byzantine_detected", False)
                agg_time_ms = data.get("aggregation_time_ms")
            else:
                n_clients = data.get("n_clients")
                rejected_count = 0
                byz_detected = data.get("byzantine_detected", False)
                agg_time_ms = None

            rows.append({
                "attack": attack,
                "aggregator": agg,
                "round": round_num,
                "n_clients": n_clients,
                "global_f1": gm.get("f1"),
                "global_fpr": gm.get("fpr"),
                "global_accuracy": gm.get("accuracy"),
                "global_recall": gm.get("recall"),
                "byzantine_detected": byz_detected,
                "rejected_count": rejected_count,
                "aggregation_time_ms": agg_time_ms,
                "source_file": str(p)
            })

rows = [r for r in rows if r["round"] is not None]
rows.sort(key=lambda r: (r["attack"], r["aggregator"], r["round"]))

with out_per.open("w", newline="") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "attack","aggregator","round","n_clients",
            "global_f1","global_fpr","global_accuracy","global_recall",
            "byzantine_detected","rejected_count","aggregation_time_ms","source_file"
        ]
    )
    w.writeheader()
    for r in rows:
        w.writerow(r)

groups = {}
for r in rows:
    k = (r["attack"], r["aggregator"])
    groups.setdefault(k, []).append(r)

summary_rows = []
for (attack, agg), vals in sorted(groups.items()):
    f1s = [v["global_f1"] for v in vals if v["global_f1"] is not None]
    fprs = [v["global_fpr"] for v in vals if v["global_fpr"] is not None]
    accs = [v["global_accuracy"] for v in vals if v["global_accuracy"] is not None]
    recs = [v["global_recall"] for v in vals if v["global_recall"] is not None]
    rejects = [v["rejected_count"] for v in vals if v["rejected_count"] is not None]
    aggs = [v["aggregation_time_ms"] for v in vals if v["aggregation_time_ms"] is not None]

    summary_rows.append({
        "attack": attack,
        "aggregator": agg,
        "rounds": len(vals),
        "avg_f1": round(statistics.mean(f1s), 6) if f1s else None,
        "min_f1": round(min(f1s), 6) if f1s else None,
        "max_f1": round(max(f1s), 6) if f1s else None,
        "avg_fpr": round(statistics.mean(fprs), 6) if fprs else None,
        "avg_accuracy": round(statistics.mean(accs), 6) if accs else None,
        "avg_recall": round(statistics.mean(recs), 6) if recs else None,
        "avg_rejected": round(statistics.mean(rejects), 6) if rejects else None,
        "avg_aggregation_time_ms": round(statistics.mean(aggs), 6) if aggs else None
    })

with out_sum.open("w", newline="") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "attack","aggregator","rounds",
            "avg_f1","min_f1","max_f1",
            "avg_fpr","avg_accuracy","avg_recall",
            "avg_rejected","avg_aggregation_time_ms"
        ]
    )
    w.writeheader()
    for r in summary_rows:
        w.writerow(r)

print("OK")
print("PER_ROUND=", out_per)
print("SUMMARY=", out_sum)
PY

echo
echo "DONE: $OUT"
ls -R "$OUT"
