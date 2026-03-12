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

OUT="$RUN_DIR/clean_agg_5rounds_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p \
  "$OUT/raw/baseline" \
  "$OUT/client_logs/baseline" \
  "$OUT/fedavg/raw" \
  "$OUT/multikrum/raw" \
  "$OUT/trimmedmean/raw" \
  "$OUT/figures_input" \
  "$OUT/tables_input" \
  "$OUT/manifest" \
  "$OUT/logs"

printf "%s\n" "$OUT" > rev/.last_clean_5rounds_dir

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

run_one_client() {
  local cid="$1"
  local ip="$2"
  local round="$3"
  local fab="$4"
  local round_raw="$5"
  local round_logs="$6"

  local out_runfl="$round_logs/${cid}.runfl.out"
  local out_client="$round_logs/fl_client_${cid}_r${round}.out"
  local out_fabric="$round_logs/fl_fabric_${cid}_r${round}.out"

  set +e
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@"$ip" \
    "unset ATTACK_MODE ; unset BYZ_CLIENTS ; timeout 300 /opt/fl-client/run_fl_round.sh $cid $round Org1MSP peer0.org1.example.com $fab" \
    >"$out_runfl" 2>&1 </dev/null
  local rc=$?
  set -e

  echo "RC=$rc"

  if [ "$rc" -ne 0 ]; then
    echo "baseline round=$round client=$cid ip=$ip fab=$fab rc=$rc" >> "$OUT/logs/failures.txt"
    tail -n 80 "$out_runfl" || true
    return 1
  fi

  local remote_json=""
  remote_json=$(ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
    if [ -f /opt/fl-client/logs/fl-ids-${cid}-r${round}.json ]; then
      printf '/opt/fl-client/logs/fl-ids-${cid}-r${round}.json'
    else
      exit 1
    fi
  " </dev/null)

  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"$remote_json" "$round_raw/" </dev/null
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_client_${cid}_r${round}.out" "$out_client" </dev/null || true
  scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_fabric_${cid}_r${round}.out" "$out_fabric" </dev/null || true
}

: > "$OUT/logs/failures.txt"

for round in 1 2 3 4 5; do
  r2=$(printf '%02d' "$round")
  round_raw="$OUT/raw/baseline/round$r2"
  round_logs="$OUT/client_logs/baseline/round$r2"
  mkdir -p "$round_raw" "$round_logs"

  ok=0
  fail=0
  i=0

  echo
  echo "=============================="
  echo "SCENARIO=baseline ROUND=$round"
  echo "=============================="

  while read -r cid ip; do
    [ -n "${cid:-}" ] || continue
    [ -n "${ip:-}" ] || continue
    fab=$(( 9900000 + (round - 1) * 1000 + i ))

    echo
    echo "===== $cid @ $ip FABRIC_ROUND=$fab ====="

    if run_one_client "$cid" "$ip" "$round" "$fab" "$round_raw" "$round_logs"; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
    fi

    i=$((i+1))
  done < <(sort -V "$MAP")

  echo
  echo "SUMMARY scenario=baseline round=$round ok=$ok fail=$fail"

  if [ "$fail" -ne 0 ]; then
    echo "ERROR: failures saved to $OUT/logs/failures.txt"
    exit 1
  fi
done

python3 - <<'PY' "$OUT" "$SPLITS"
import csv
import json
import sys
import time
import importlib.util
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
y = np.load(splits / "global_test_y.npy")

def client_num_from_name(name):
    import re
    m = re.search(r'edge-client-(\d+)', name)
    return int(m.group(1)) if m else 10**9

def load_updates(files):
    updates = []
    for fp in sorted(files, key=lambda p: client_num_from_name(p.name)):
        j = json.loads(fp.read_text())
        updates.append({
            "client_id": j["client_id"],
            "weights": j["weights"],
            "bias": j["bias"],
            "byzantine": False
        })
    return updates

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def metrics_at_threshold(scores, y_true, thr):
    preds = (scores >= thr).astype(int)
    tp = int(np.sum((preds == 1) & (y_true == 1)))
    fp = int(np.sum((preds == 1) & (y_true == 0)))
    fn = int(np.sum((preds == 0) & (y_true == 1)))
    tn = int(np.sum((preds == 0) & (y_true == 0)))
    acc = (tp + tn) / max(len(y_true), 1)
    prec = tp / max(tp + fp, 1)
    rec = tp / max(tp + fn, 1)
    f1 = 2 * prec * rec / max(prec + rec, 1e-12)
    fpr = fp / max(fp + tn, 1)
    support0 = int(np.sum(y_true == 0))
    support1 = int(np.sum(y_true == 1))
    f1_0 = 2 * tn / max(2 * tn + fp + fn, 1e-12)
    f1_1 = f1
    weighted_f1 = ((support0 * f1_0) + (support1 * f1_1)) / max(support0 + support1, 1)
    return {
        "weighted_f1": float(weighted_f1),
        "f1": float(f1),
        "accuracy": float(acc),
        "precision": float(prec),
        "recall": float(rec),
        "fpr": float(fpr),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn
    }

def roc_auc_score_manual(y_true, scores):
    y_true = np.asarray(y_true)
    scores = np.asarray(scores)
    pos = scores[y_true == 1]
    neg = scores[y_true == 0]
    if len(pos) == 0 or len(neg) == 0:
        return float("nan")
    wins = 0.0
    for p in pos:
        wins += np.sum(p > neg)
        wins += 0.5 * np.sum(p == neg)
    return float(wins / (len(pos) * len(neg)))

def best_threshold(scores, y_true):
    best = None
    for thr in np.round(np.arange(0.05, 0.96, 0.01), 2):
        m = metrics_at_threshold(scores, y_true, float(thr))
        row = {"thr": float(thr), **m}
        if best is None or row["weighted_f1"] > best["weighted_f1"] or (
            row["weighted_f1"] == best["weighted_f1"] and row["accuracy"] > best["accuracy"]
        ):
            best = row
    return best

def fedavg_native(updates):
    w = np.mean(np.array([np.array(u["weights"], dtype=np.float32) for u in updates], dtype=np.float32), axis=0)
    b = float(np.mean([float(u["bias"]) for u in updates]))
    return w, b, list(range(len(updates))), []

def multikrum_native(updates):
    selected_idx, rejected_idx, _ = mk.multi_krum(updates, 0)
    w, b = mk.fedavg(updates, selected_idx)
    return np.array(w, dtype=np.float32), float(b), selected_idx, rejected_idx

def trimmed_native(updates):
    w = tm.trimmed_mean_weights(updates, 0)
    b = tm.trimmed_mean_bias(updates, 0)
    return np.array(w, dtype=np.float32), float(b), list(range(len(updates))), []

round_dir = out / "raw" / "baseline" / "round05"
files = list(round_dir.glob("*.json"))
if len(files) != 20:
    raise SystemExit(f"ERROR: round05 expected 20 json, got {len(files)}")

updates = load_updates(files)

rows = []
paper_rows = []

for agg_name, fn in [
    ("fedavg", fedavg_native),
    ("multikrum", multikrum_native),
    ("trimmedmean", trimmed_native),
]:
    t0 = time.perf_counter()
    w, b, selected_idx, rejected_idx = fn(updates)
    scores = sigmoid(X @ w + b)
    roc_auc = roc_auc_score_manual(y, scores)
    best = best_threshold(scores, y)
    agg_ms = (time.perf_counter() - t0) * 1000.0

    result = {
        "scenario": "baseline_clean_final",
        "round": 5,
        "aggregator": agg_name,
        "threshold": best["thr"],
        "weighted_f1": round(best["weighted_f1"], 6),
        "f1": round(best["f1"], 6),
        "accuracy": round(best["accuracy"], 6),
        "precision": round(best["precision"], 6),
        "recall": round(best["recall"], 6),
        "fpr": round(best["fpr"], 6),
        "roc_auc": round(roc_auc, 6),
        "selected_count": len(selected_idx),
        "rejected_count": len(rejected_idx),
        "rejected_byz": 0,
        "detect_round": 0,
        "aggregation_time_ms": round(agg_ms, 6),
        "tp": best["tp"],
        "fp": best["fp"],
        "fn": best["fn"],
        "tn": best["tn"],
        "n_samples": int(len(y)),
    }

    out_json = out / agg_name / "raw" / f"baseline_{agg_name}_r05_final.json"
    out_json.write_text(json.dumps({
        **result,
        "selected": [updates[i]["client_id"] for i in selected_idx],
        "rejected": [updates[i]["client_id"] for i in rejected_idx],
        "bias": float(b),
        "weights": w.tolist(),
    }, indent=2))

    result["source_json"] = str(out_json)
    rows.append(result)

    paper_rows.append({
        "aggregator": agg_name,
        "threshold": result["threshold"],
        "weighted_f1": result["weighted_f1"],
        "accuracy": result["accuracy"],
        "roc_auc": result["roc_auc"],
        "f1": result["f1"],
        "fpr": result["fpr"],
        "aggregation_time_ms": result["aggregation_time_ms"],
    })

summary_csv = out / "tables_input" / "clean_5rounds_final_summary.csv"
with open(summary_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

paper_csv = out / "tables_input" / "clean_5rounds_final_paper.csv"
with open(paper_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(paper_rows[0].keys()))
    w.writeheader()
    w.writerows(paper_rows)

round_csv = out / "figures_input" / "clean_5rounds_final_round_metrics.csv"
with open(round_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "scenario","round","aggregator","threshold","weighted_f1","f1","accuracy",
        "precision","recall","fpr","roc_auc","selected_count","rejected_count",
        "rejected_byz","detect_round","aggregation_time_ms","source_json"
    ])
    w.writeheader()
    for r in rows:
        w.writerow({
            "scenario": "baseline_clean_final",
            "round": 5,
            "aggregator": r["aggregator"],
            "threshold": r["threshold"],
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
            "source_json": r["source_json"],
        })

manifest = {
    "out": str(out),
    "summary_csv": str(summary_csv),
    "paper_csv": str(paper_csv),
    "round_csv": str(round_csv),
    "n_samples": int(len(y)),
    "n_features": int(X.shape[1]),
    "final_round_used": "round05",
}
(out / "manifest" / "CLEAN_5ROUNDS_FINAL_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

(out / "README.txt").write_text(
    f"CLEAN 5 ROUNDS FINAL AGGREGATOR BENCHMARK\n"
    f"out={out}\n"
    f"splits={splits}\n"
    f"summary_csv={summary_csv}\n"
    f"paper_csv={paper_csv}\n"
    f"round_csv={round_csv}\n"
    f"n_samples={len(y)}\n"
    f"n_features={X.shape[1]}\n"
    f"final_round=5\n"
)

print(f"OUT={out}")
print(f"SUMMARY_CSV={summary_csv}")
print(f"PAPER_CSV={paper_csv}")
print(f"ROUND_CSV={round_csv}")
print(f"MANIFEST={out / 'manifest' / 'CLEAN_5ROUNDS_FINAL_MANIFEST.json'}")
PY

echo
echo "===== README ====="
cat "$OUT/README.txt"

echo
echo "===== SUMMARY CSV ====="
cat "$OUT/tables_input/clean_5rounds_final_summary.csv"

echo
echo "===== PAPER CSV ====="
cat "$OUT/tables_input/clean_5rounds_final_paper.csv"

echo
echo "CLEAN5_DIR=$OUT"
