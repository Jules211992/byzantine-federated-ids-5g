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

IPS="10.10.0.112 10.10.0.11 10.10.0.121 10.10.0.10"

for ip in $IPS; do
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    mkdir -p /opt/fl-client/models /opt/fl-client/logs
    rm -f /opt/fl-client/models/*.npz
    rm -f /opt/fl-client/logs/fl-ids-*.json
    rm -f /opt/fl-client/logs/fl-byz-*.json
    rm -f /opt/fl-client/logs/fl_client_*.out
    rm -f /opt/fl-client/logs/fl_fabric_*.out
  '
done

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/clean_agg_r1_weighted_$TS"

mkdir -p \
  "$OUT"/raw/baseline/round01 \
  "$OUT"/client_logs/baseline/round01 \
  "$OUT"/fedavg/raw \
  "$OUT"/multikrum/raw \
  "$OUT"/trimmedmean/raw \
  "$OUT"/tables_input \
  "$OUT"/figures_input \
  "$OUT"/manifest \
  "$OUT"/logs

run_one_client() {
  local cid="$1"
  local ip="$2"
  local fab="$3"

  local round_raw="$OUT/raw/baseline/round01"
  local round_logs="$OUT/client_logs/baseline/round01"

  local out_runfl="$round_logs/${cid}.runfl.out"
  local out_client="$round_logs/fl_client_${cid}_r1.out"
  local out_fabric="$round_logs/fl_fabric_${cid}_r1.out"

  local remote_cmd=""
  remote_cmd="rm -f /opt/fl-client/logs/fl-ids-${cid}-r1.json /opt/fl-client/logs/fl-byz-${cid}-r1.json /opt/fl-client/logs/fl_client_${cid}_r1.out /opt/fl-client/logs/fl_fabric_${cid}_r1.out ; unset ATTACK_MODE ; unset BYZ_CLIENTS ; timeout 300 /opt/fl-client/run_fl_round.sh $cid 1 Org1MSP peer0.org1.example.com $fab"

  set +e
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@"$ip" "$remote_cmd" >"$out_runfl" 2>&1 </dev/null
  local rc=$?
  set -e

  echo "RC=$rc"

  if [ "$rc" -ne 0 ]; then
    echo "baseline round=1 client=$cid ip=$ip fab=$fab rc=$rc" >> "$OUT/logs/failures.txt"
    tail -n 120 "$out_runfl" || true
    return 1
  fi

  local remote_json=""
  remote_json=$(ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
    if [ -f /opt/fl-client/logs/fl-ids-${cid}-r1.json ]; then
      printf '/opt/fl-client/logs/fl-ids-${cid}-r1.json'
    else
      exit 1
    fi
  " </dev/null)

  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"$remote_json" "$round_raw/" </dev/null
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_client_${cid}_r1.out" "$out_client" </dev/null || true
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_fabric_${cid}_r1.out" "$out_fabric" </dev/null || true

  return 0
}

: > "$OUT/logs/failures.txt"

echo "=============================="
echo "SCENARIO=baseline ROUND=1"
echo "=============================="

ok=0
fail=0
i=0

while read -r cid ip; do
  [ -n "${cid:-}" ] || continue
  [ -n "${ip:-}" ] || continue

  fab=$((9800000 + i))

  echo
  echo "===== $cid @ $ip FABRIC_ROUND=$fab ====="

  if run_one_client "$cid" "$ip" "$fab"; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
  fi

  i=$((i+1))
done < <(sort -V "$MAP")

echo
echo "SUMMARY scenario=baseline round=1 ok=$ok fail=$fail"

[ "$fail" -eq 0 ] || { echo "ERROR: failures in $OUT/logs/failures.txt"; exit 1; }

python3 - <<'PY' "$OUT" "$SPLITS"
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

mk_spec = importlib.util.spec_from_file_location("mk", str(Path("/home/ubuntu/byz-fed-ids-5g/phase7/multi_krum_aggregator.py")))
mk = importlib.util.module_from_spec(mk_spec)
mk_spec.loader.exec_module(mk)

tm_spec = importlib.util.spec_from_file_location("tm", str(Path("/home/ubuntu/byz-fed-ids-5g/phase8/trimmed_mean_aggregator.py")))
tm = importlib.util.module_from_spec(tm_spec)
tm_spec.loader.exec_module(tm)

X = np.load(splits / "global_test_X.npy")
y = np.load(splits / "global_test_y.npy").astype(int)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def client_num_from_name(name):
    m = re.search(r'edge-client-(\d+)', name)
    return int(m.group(1)) if m else 10**9

def load_updates(files):
    updates = []
    for fp in sorted(files, key=lambda p: client_num_from_name(p.name)):
        j = json.loads(fp.read_text())
        cid = j.get("client_id")
        updates.append({
            "client_id": cid,
            "weights": j["weights"],
            "bias": j["bias"],
            "byzantine": False,
            "test_metrics": j.get("test_metrics", {})
        })
    return updates

def weighted_f1_binary(y_true, y_pred):
    n = len(y_true)
    total = 0.0
    for c in (0, 1):
        tp = int(np.sum((y_pred == c) & (y_true == c)))
        fp = int(np.sum((y_pred == c) & (y_true != c)))
        fn = int(np.sum((y_pred != c) & (y_true == c)))
        support = int(np.sum(y_true == c))
        denom = 2 * tp + fp + fn
        f1 = (2 * tp / denom) if denom > 0 else 0.0
        total += (support / n) * f1
    return float(total)

def roc_auc_binary(y_true, scores):
    y_true = np.asarray(y_true).astype(int)
    scores = np.asarray(scores, dtype=float)
    pos = int(np.sum(y_true == 1))
    neg = int(np.sum(y_true == 0))
    if pos == 0 or neg == 0:
        return float("nan")
    order = np.argsort(scores, kind="mergesort")
    sorted_scores = scores[order]
    ranks = np.empty(len(scores), dtype=float)
    i = 0
    rank = 1
    n = len(scores)
    while i < n:
        j = i
        while j + 1 < n and sorted_scores[j + 1] == sorted_scores[i]:
            j += 1
        avg_rank = (rank + (rank + (j - i))) / 2.0
        ranks[order[i:j+1]] = avg_rank
        rank += (j - i + 1)
        i = j + 1
    sum_pos = float(np.sum(ranks[y_true == 1]))
    auc = (sum_pos - pos * (pos + 1) / 2.0) / (pos * neg)
    return float(auc)

def eval_global_full(w, b):
    scores = sigmoid(X @ w + b)
    pred = (scores >= 0.5).astype(int)

    tp = int(np.sum((pred == 1) & (y == 1)))
    fp = int(np.sum((pred == 1) & (y == 0)))
    fn = int(np.sum((pred == 0) & (y == 1)))
    tn = int(np.sum((pred == 0) & (y == 0)))

    acc = (tp + tn) / len(y)
    prec = tp / max(tp + fp, 1)
    rec = tp / max(tp + fn, 1)
    f1 = 2 * prec * rec / max(prec + rec, 1e-12)
    fpr = fp / max(fp + tn, 1)
    wf1 = weighted_f1_binary(y, pred)
    auc = roc_auc_binary(y, scores)

    return {
        "accuracy": round(acc, 6),
        "precision": round(prec, 6),
        "recall": round(rec, 6),
        "f1": round(f1, 6),
        "weighted_f1": round(wf1, 6),
        "fpr": round(fpr, 6),
        "roc_auc": round(auc, 6),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
        "n_samples": int(len(y))
    }

def fedavg_native(updates):
    w = np.mean(np.array([np.array(u["weights"], dtype=np.float32) for u in updates], dtype=np.float32), axis=0)
    b = float(np.mean([float(u["bias"]) for u in updates]))
    return w, b

def run_fedavg(updates):
    t0 = time.perf_counter()
    w, b = fedavg_native(updates)
    m = eval_global_full(w, b)
    agg_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": m,
        "weights": w.tolist(),
        "bias": float(b)
    }

def run_multikrum(updates):
    t0 = time.perf_counter()
    selected_idx, rejected_idx, scores = mk.multi_krum(updates, 0)
    w, b = mk.fedavg(updates, selected_idx)
    m = eval_global_full(w, b)
    agg_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [updates[i]["client_id"] for i in selected_idx],
        "rejected": [updates[i]["client_id"] for i in rejected_idx],
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": m,
        "weights": np.array(w, dtype=np.float32).tolist(),
        "bias": float(b)
    }

def run_trimmedmean(updates):
    t0 = time.perf_counter()
    w = tm.trimmed_mean_weights(updates, 0)
    b = tm.trimmed_mean_bias(updates, 0)
    m = eval_global_full(np.array(w, dtype=np.float32), float(b))
    agg_ms = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": agg_ms,
        "global_metrics": m,
        "weights": np.array(w, dtype=np.float32).tolist(),
        "bias": float(b)
    }

files = list((out / "raw" / "baseline" / "round01").glob("*.json"))
if len(files) != 20:
    raise SystemExit(f"ERROR: baseline round01 expected 20 json, got {len(files)}")

updates = load_updates(files)

runs = [
    ("fedavg", run_fedavg(updates)),
    ("multikrum", run_multikrum(updates)),
    ("trimmedmean", run_trimmedmean(updates)),
]

rows = []
for agg_name, result in runs:
    out_json = out / agg_name / "raw" / f"baseline_{agg_name}_r01.json"
    payload = {
        "scenario": "baseline_clean",
        "round": 1,
        "aggregator": agg_name,
        "selected": result["selected"],
        "rejected": result["rejected"],
        "rejected_byz": result["rejected_byz"],
        "detect_round": result["detect_round"],
        "aggregation_time_ms": round(float(result["aggregation_time_ms"]), 6),
        "global_metrics": result["global_metrics"],
        "bias": result["bias"],
        "weights": result["weights"]
    }
    out_json.write_text(json.dumps(payload, indent=2))

    gm = result["global_metrics"]
    rows.append({
        "scenario": "baseline_clean_r1",
        "round": 1,
        "aggregator": agg_name,
        "weighted_f1": gm["weighted_f1"],
        "f1": gm["f1"],
        "accuracy": gm["accuracy"],
        "precision": gm["precision"],
        "recall": gm["recall"],
        "fpr": gm["fpr"],
        "roc_auc": gm["roc_auc"],
        "selected_count": len(result["selected"]),
        "rejected_count": len(result["rejected"]),
        "rejected_byz": result["rejected_byz"],
        "detect_round": result["detect_round"],
        "aggregation_time_ms": round(float(result["aggregation_time_ms"]), 6),
        "tp": gm["tp"],
        "fp": gm["fp"],
        "fn": gm["fn"],
        "tn": gm["tn"],
        "n_samples": gm["n_samples"],
        "source_json": str(out_json)
    })

summary_csv = out / "tables_input" / "clean_r1_weighted_summary.csv"
with open(summary_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "scenario","round","aggregator","weighted_f1","f1","accuracy","precision","recall","fpr","roc_auc",
        "selected_count","rejected_count","rejected_byz","detect_round","aggregation_time_ms",
        "tp","fp","fn","tn","n_samples","source_json"
    ])
    w.writeheader()
    for r in rows:
        w.writerow(r)

paper_csv = out / "tables_input" / "clean_r1_weighted_paper.csv"
with open(paper_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "aggregator","weighted_f1","accuracy","roc_auc","f1","fpr","aggregation_time_ms"
    ])
    w.writeheader()
    for r in rows:
        w.writerow({
            "aggregator": r["aggregator"],
            "weighted_f1": r["weighted_f1"],
            "accuracy": r["accuracy"],
            "roc_auc": r["roc_auc"],
            "f1": r["f1"],
            "fpr": r["fpr"],
            "aggregation_time_ms": r["aggregation_time_ms"]
        })

round_csv = out / "figures_input" / "clean_r1_weighted_round_metrics.csv"
with open(round_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "scenario","round","aggregator","weighted_f1","f1","accuracy","precision","recall","fpr","roc_auc",
        "selected_count","rejected_count","rejected_byz","detect_round","aggregation_time_ms","source_json"
    ])
    w.writeheader()
    for r in rows:
        w.writerow({
            "scenario": "baseline_clean",
            "round": 1,
            "aggregator": r["aggregator"],
            "weighted_f1": r["weighted_f1"],
            "f1": r["f1"],
            "accuracy": r["accuracy"],
            "precision": r["precision"],
            "recall": r["recall"],
            "fpr": r["fpr"],
            "roc_auc": r["roc_auc"],
            "selected_count": r["selected_count"],
            "rejected_count": r["rejected_count"],
            "rejected_byz": r["rejected_byz"],
            "detect_round": r["detect_round"],
            "aggregation_time_ms": r["aggregation_time_ms"],
            "source_json": r["source_json"]
        })

manifest = {
    "out": str(out),
    "splits": str(splits),
    "global_test_X": str(splits / "global_test_X.npy"),
    "global_test_y": str(splits / "global_test_y.npy"),
    "summary_csv": str(summary_csv),
    "paper_csv": str(paper_csv),
    "round_csv": str(round_csv),
    "n_samples": int(len(y)),
    "n_features": int(X.shape[1]),
    "rows": rows
}
(out / "manifest" / "CLEAN_R1_WEIGHTED_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = []
readme.append("CLEAN R1 AGGREGATOR BENCHMARK")
readme.append(f"out={out}")
readme.append(f"splits={splits}")
readme.append(f"summary_csv={summary_csv}")
readme.append(f"paper_csv={paper_csv}")
readme.append(f"round_csv={round_csv}")
readme.append(f"n_samples={len(y)}")
readme.append(f"n_features={X.shape[1]}")
(out / "README.txt").write_text("\n".join(readme) + "\n")

print(f"OUT={out}")
print(f"SUMMARY_CSV={summary_csv}")
print(f"PAPER_CSV={paper_csv}")
print(f"ROUND_CSV={round_csv}")
print(f"MANIFEST={out / 'manifest' / 'CLEAN_R1_WEIGHTED_MANIFEST.json'}")
PY

echo
echo "===== README ====="
cat "$OUT/README.txt"

echo
echo "===== SUMMARY CSV ====="
cat "$OUT/tables_input/clean_r1_weighted_summary.csv"

echo
echo "===== PAPER CSV ====="
cat "$OUT/tables_input/clean_r1_weighted_paper.csv"

echo
echo "===== ROUND CSV ====="
cat "$OUT/figures_input/clean_r1_weighted_round_metrics.csv"

echo
echo "CLEAN_DIR=$OUT"
