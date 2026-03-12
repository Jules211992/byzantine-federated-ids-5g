#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
SPLITS="$RUN_DIR/splits_20"

[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }
[ -d "$SPLITS" ] || { echo "ERROR: splits_20 introuvable: $SPLITS"; exit 1; }
[ -f "$SPLITS/global_test_X.npy" ] || { echo "ERROR: global_test_X.npy introuvable"; exit 1; }
[ -f "$SPLITS/global_test_y.npy" ] || { echo "ERROR: global_test_y.npy introuvable"; exit 1; }

START_ROUND="${START_ROUND:-1}"
END_ROUND="${END_ROUND:-5}"

BASELINE_BASE_FABRIC="${BASELINE_BASE_FABRIC:-9100000}"
LABEL_FLIP_BASE_FABRIC="${LABEL_FLIP_BASE_FABRIC:-9200000}"
BACKDOOR_BASE_FABRIC="${BACKDOOR_BASE_FABRIC:-9300000}"

PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"
BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
SCENARIOS="${SCENARIOS:-baseline label_flip backdoor}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/agg_compare_n20_live_$TS"

mkdir -p \
  "$OUT"/raw/baseline \
  "$OUT"/raw/label_flip \
  "$OUT"/raw/backdoor \
  "$OUT"/client_logs/baseline \
  "$OUT"/client_logs/label_flip \
  "$OUT"/client_logs/backdoor \
  "$OUT"/fedavg/raw \
  "$OUT"/multikrum/raw \
  "$OUT"/trimmedmean/raw \
  "$OUT"/figures_input \
  "$OUT"/tables_input \
  "$OUT"/manifest \
  "$OUT"/logs

printf "%s\n" "$OUT" > rev/.last_n20_live_agg_dir
: > "$OUT/logs/failures.txt"

run_one_client() {
  local scenario="$1"
  local attack_mode="$2"
  local cid="$3"
  local ip="$4"
  local round="$5"
  local fab="$6"
  local round_raw="$7"
  local round_logs="$8"

  local out_runfl="$round_logs/${cid}.runfl.out"
  local out_client="$round_logs/fl_client_${cid}_r${round}.out"
  local out_fabric="$round_logs/fl_fabric_${cid}_r${round}.out"

  local remote_cmd=""
  if [ -n "$attack_mode" ]; then
    remote_cmd="rm -f /opt/fl-client/logs/fl-ids-${cid}-r${round}.json /opt/fl-client/logs/fl-byz-${cid}-r${round}.json /opt/fl-client/logs/fl_client_${cid}_r${round}.out /opt/fl-client/logs/fl_fabric_${cid}_r${round}.out ; export ATTACK_MODE='$attack_mode' ; export BYZ_CLIENTS='$BYZ_CLIENTS' ; timeout 300 /opt/fl-client/run_fl_round.sh $cid $round $MSP $PEER_HOST $fab"
  else
    remote_cmd="rm -f /opt/fl-client/logs/fl-ids-${cid}-r${round}.json /opt/fl-client/logs/fl-byz-${cid}-r${round}.json /opt/fl-client/logs/fl_client_${cid}_r${round}.out /opt/fl-client/logs/fl_fabric_${cid}_r${round}.out ; unset ATTACK_MODE ; unset BYZ_CLIENTS ; timeout 300 /opt/fl-client/run_fl_round.sh $cid $round $MSP $PEER_HOST $fab"
  fi

  set +e
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@"$ip" "$remote_cmd" >"$out_runfl" 2>&1 </dev/null
  local rc=$?
  set -e

  echo "RC=$rc"

  if [ "$rc" -ne 0 ]; then
    echo "$scenario round=$round client=$cid ip=$ip fab=$fab rc=$rc" >> "$OUT/logs/failures.txt"
    tail -n 80 "$out_runfl" || true
    return 1
  fi

  local remote_json=""
  remote_json=$(ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
    if [ -f /opt/fl-client/logs/fl-byz-${cid}-r${round}.json ]; then
      printf '/opt/fl-client/logs/fl-byz-${cid}-r${round}.json'
    elif [ -f /opt/fl-client/logs/fl-ids-${cid}-r${round}.json ]; then
      printf '/opt/fl-client/logs/fl-ids-${cid}-r${round}.json'
    else
      exit 1
    fi
  " </dev/null)

  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"$remote_json" "$round_raw/" </dev/null
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_client_${cid}_r${round}.out" "$out_client" </dev/null || true
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_fabric_${cid}_r${round}.out" "$out_fabric" </dev/null || true

  return 0
}

run_scenario() {
  local scenario="$1"
  local attack_mode="$2"
  local base_fabric="$3"

  local scenario_raw="$OUT/raw/$scenario"
  local scenario_logs="$OUT/client_logs/$scenario"
  mkdir -p "$scenario_raw" "$scenario_logs"

  local r="$START_ROUND"
  while [ "$r" -le "$END_ROUND" ]; do
    local r2
    r2=$(printf '%02d' "$r")
    local round_raw="$scenario_raw/round$r2"
    local round_logs="$scenario_logs/round$r2"
    mkdir -p "$round_raw" "$round_logs"

    local ok=0
    local fail=0
    local i=0

    echo
    echo "=============================="
    echo "SCENARIO=$scenario ROUND=$r"
    echo "=============================="

    while read -r cid ip; do
      [ -n "${cid:-}" ] || continue
      [ -n "${ip:-}" ] || continue

      local fab=$(( base_fabric + (r - START_ROUND) * 1000 + i ))

      echo
      echo "===== $cid @ $ip FABRIC_ROUND=$fab ====="

      if run_one_client "$scenario" "$attack_mode" "$cid" "$ip" "$r" "$fab" "$round_raw" "$round_logs"; then
        ok=$((ok+1))
      else
        fail=$((fail+1))
      fi

      i=$((i+1))
    done < <(sort -V "$MAP")

    echo
    echo "SUMMARY scenario=$scenario round=$r ok=$ok fail=$fail"

    if [ "$fail" -ne 0 ]; then
      echo "ERROR: failures saved to $OUT/logs/failures.txt"
      exit 1
    fi

    r=$((r+1))
  done
}

for scenario in $SCENARIOS; do
  case "$scenario" in
    baseline)
      run_scenario baseline "" "$BASELINE_BASE_FABRIC"
      ;;
    label_flip)
      run_scenario label_flip "label_flip" "$LABEL_FLIP_BASE_FABRIC"
      ;;
    backdoor)
      run_scenario backdoor "backdoor" "$BACKDOOR_BASE_FABRIC"
      ;;
    *)
      echo "ERROR: scenario inconnu: $scenario"
      exit 1
      ;;
  esac
done

python3 - <<'PY' "$OUT" "$SPLITS" "$START_ROUND" "$END_ROUND" "$BYZ_CLIENTS"
import csv
import importlib.util
import json
import re
import sys
import time
from pathlib import Path
import numpy as np

out = Path(sys.argv[1])
splits = Path(sys.argv[2])
start_round = int(sys.argv[3])
end_round = int(sys.argv[4])
byz_set = set(sys.argv[5].split())

mk_spec = importlib.util.spec_from_file_location("mk", str(Path("/home/ubuntu/byz-fed-ids-5g/phase7/multi_krum_aggregator.py")))
mk = importlib.util.module_from_spec(mk_spec)
mk_spec.loader.exec_module(mk)

tm_spec = importlib.util.spec_from_file_location("tm", str(Path("/home/ubuntu/byz-fed-ids-5g/phase8/trimmed_mean_aggregator.py")))
tm = importlib.util.module_from_spec(tm_spec)
tm_spec.loader.exec_module(tm)

def client_num_from_name(name):
    m = re.search(r'edge-client-(\d+)', name)
    return int(m.group(1)) if m else 10**9

def load_updates(files, scenario):
    updates = []
    for fp in sorted(files, key=lambda p: client_num_from_name(p.name)):
        j = json.loads(fp.read_text())
        cid = j.get("client_id")
        if not cid:
            m = re.search(r'edge-client-\d+', fp.name)
            cid = m.group(0) if m else fp.stem
        byz = False
        if scenario != "baseline":
            if j.get("byzantine") is True:
                byz = True
            elif "fl-byz-" in fp.name:
                byz = True
            elif cid in byz_set:
                byz = True
        updates.append({
            "client_id": cid,
            "weights": j["weights"],
            "bias": j["bias"],
            "byzantine": byz,
            "test_metrics": j.get("test_metrics", {})
        })
    return updates

def fedavg_native(updates):
    w = np.mean(np.array([np.array(u["weights"], dtype=np.float32) for u in updates], dtype=np.float32), axis=0)
    b = float(np.mean([float(u["bias"]) for u in updates]))
    return w, b

def eval_global(w, b):
    return mk.evaluate_global(w, float(b), str(splits))

def run_fedavg(updates):
    t0 = time.perf_counter()
    w, b = fedavg_native(updates)
    metrics = eval_global(w, b)
    agg_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": metrics,
        "weights": w.tolist(),
        "bias": float(b)
    }

def run_multikrum(updates, f_assumed):
    t0 = time.perf_counter()
    selected_idx, rejected_idx, scores = mk.multi_krum(updates, f_assumed)
    w, b = mk.fedavg(updates, selected_idx)
    metrics = eval_global(w, b)
    agg_ms = (time.perf_counter() - t0) * 1000.0
    selected = [updates[i]["client_id"] for i in selected_idx]
    rejected = [updates[i]["client_id"] for i in rejected_idx]
    rejected_byz = sum(1 for i in rejected_idx if updates[i].get("byzantine"))
    return {
        "selected": selected,
        "rejected": rejected,
        "scores": scores,
        "rejected_byz": rejected_byz,
        "detect_round": 1 if rejected_byz > 0 else 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": metrics,
        "weights": np.array(w, dtype=np.float32).tolist(),
        "bias": float(b)
    }

def run_trimmedmean(updates, f_assumed):
    t0 = time.perf_counter()
    w = tm.trimmed_mean_weights(updates, f_assumed)
    b = tm.trimmed_mean_bias(updates, f_assumed)
    metrics = eval_global(w, b)
    agg_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": metrics,
        "weights": np.array(w, dtype=np.float32).tolist(),
        "bias": float(b)
    }

scenario_f = {
    "baseline": 0,
    "label_flip": 4,
    "backdoor": 4
}

per_round_rows = []

for scenario in ["baseline", "label_flip", "backdoor"]:
    for r in range(start_round, end_round + 1):
        r2 = f"round{r:02d}"
        round_dir = out / "raw" / scenario / r2
        files = list(round_dir.glob("*.json"))
        if len(files) != 20:
            raise SystemExit(f"ERROR: {scenario} {r2} expected 20 json, got {len(files)}")
        updates = load_updates(files, scenario)
        f_assumed = scenario_f[scenario]

        fed = run_fedavg(updates)
        mkm = run_multikrum(updates, f_assumed)
        tmm = run_trimmedmean(updates, f_assumed)

        runs = [
            ("fedavg", fed),
            ("multikrum", mkm),
            ("trimmedmean", tmm),
        ]

        for agg_name, result in runs:
            raw_out = out / agg_name / "raw" / f"{scenario}_{agg_name}_r{r:02d}.json"
            raw_out.write_text(json.dumps({
                "scenario": scenario,
                "round": r,
                "aggregator": agg_name,
                "selected": result["selected"],
                "rejected": result["rejected"],
                "rejected_byz": result["rejected_byz"],
                "detect_round": result["detect_round"],
                "aggregation_time_ms": result["aggregation_time_ms"],
                "global_metrics": result["global_metrics"],
                "bias": result["bias"],
                "weights": result["weights"]
            }, indent=2))

            gm = result["global_metrics"]
            per_round_rows.append({
                "scenario": scenario,
                "aggregator": agg_name,
                "round": r,
                "global_f1": gm["f1"],
                "global_fpr": gm["fpr"],
                "global_accuracy": gm["accuracy"],
                "global_precision": gm["precision"],
                "global_recall": gm["recall"],
                "selected_count": len(result["selected"]),
                "rejected_count": len(result["rejected"]),
                "rejected_byz": result["rejected_byz"],
                "detect_round": result["detect_round"],
                "aggregation_time_ms": result["aggregation_time_ms"],
                "source_json": str(raw_out)
            })

per_round_csv = out / "figures_input" / "agg_compare_round_metrics_live.csv"
with per_round_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=list(per_round_rows[0].keys()))
    w.writeheader()
    w.writerows(per_round_rows)

summary_rows = []
for scenario in ["baseline", "label_flip", "backdoor"]:
    for agg_name in ["fedavg", "multikrum", "trimmedmean"]:
        rows = [r for r in per_round_rows if r["scenario"] == scenario and r["aggregator"] == agg_name]
        summary_rows.append({
            "scenario": scenario,
            "aggregator": agg_name,
            "rounds": len(rows),
            "avg_f1": sum(r["global_f1"] for r in rows) / len(rows),
            "min_f1": min(r["global_f1"] for r in rows),
            "max_f1": max(r["global_f1"] for r in rows),
            "avg_fpr": sum(r["global_fpr"] for r in rows) / len(rows),
            "avg_accuracy": sum(r["global_accuracy"] for r in rows) / len(rows),
            "avg_recall": sum(r["global_recall"] for r in rows) / len(rows),
            "avg_selected": sum(r["selected_count"] for r in rows) / len(rows),
            "avg_rejected": sum(r["rejected_count"] for r in rows) / len(rows),
            "avg_rejected_byz": sum(r["rejected_byz"] for r in rows) / len(rows),
            "detect_rounds": sum(r["detect_round"] for r in rows),
            "avg_aggregation_time_ms": sum(r["aggregation_time_ms"] for r in rows) / len(rows)
        })

summary_csv = out / "tables_input" / "agg_compare_summary_live.csv"
with summary_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=list(summary_rows[0].keys()))
    w.writeheader()
    w.writerows(summary_rows)

paper_rows = [r for r in summary_rows if r["scenario"] in ("label_flip", "backdoor")]
paper_csv = out / "tables_input" / "agg_compare_paper_table_live.csv"
with paper_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=[
        "scenario","aggregator","avg_f1","avg_fpr","avg_rejected","avg_rejected_byz","detect_rounds","avg_aggregation_time_ms"
    ])
    w.writeheader()
    for r in paper_rows:
        w.writerow({
            "scenario": r["scenario"],
            "aggregator": r["aggregator"],
            "avg_f1": r["avg_f1"],
            "avg_fpr": r["avg_fpr"],
            "avg_rejected": r["avg_rejected"],
            "avg_rejected_byz": r["avg_rejected_byz"],
            "detect_rounds": r["detect_rounds"],
            "avg_aggregation_time_ms": r["avg_aggregation_time_ms"]
        })

manifest = {
    "live_benchmark_dir": str(out),
    "splits_dir": str(splits),
    "per_round_csv": str(per_round_csv),
    "summary_csv": str(summary_csv),
    "paper_csv": str(paper_csv),
    "scenarios": ["baseline", "label_flip", "backdoor"],
    "rounds": list(range(start_round, end_round + 1)),
    "f_assumed": scenario_f,
    "note": "live N20 benchmark with native aggregation on freshly collected raw updates"
}
(out / "manifest" / "LIVE_BENCHMARK_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = "\n".join([
    "LIVE N20 AGGREGATOR BENCHMARK",
    f"out={out}",
    f"splits={splits}",
    f"per_round_csv={per_round_csv}",
    f"summary_csv={summary_csv}",
    f"paper_csv={paper_csv}",
    "source=real live benchmark then native aggregation"
]) + "\n"
(out / "README.txt").write_text(readme)

print(f"LIVE_OUT={out}")
print(f"PER_ROUND_CSV={per_round_csv}")
print(f"SUMMARY_CSV={summary_csv}")
print(f"PAPER_CSV={paper_csv}")
print(f"MANIFEST={out / 'manifest' / 'LIVE_BENCHMARK_MANIFEST.json'}")
PY

echo "DONE"
echo "$OUT"
