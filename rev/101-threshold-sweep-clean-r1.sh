#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

CLEAN=$(ls -dt "$RUN_DIR"/clean_agg_r1_weighted_* 2>/dev/null | head -n 1 || true)
[ -n "${CLEAN:-}" ] || { echo "ERROR: clean_agg_r1_weighted introuvable"; exit 1; }

SPLITS="$RUN_DIR/splits_20"
[ -f "$SPLITS/global_test_X.npy" ] || { echo "ERROR: global_test_X.npy introuvable"; exit 1; }
[ -f "$SPLITS/global_test_y.npy" ] || { echo "ERROR: global_test_y.npy introuvable"; exit 1; }

OUT="$RUN_DIR/clean_threshold_sweep_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

python3 - <<'PY' "$CLEAN" "$SPLITS" "$OUT"
import csv
import json
import math
import sys
from pathlib import Path
import numpy as np

clean = Path(sys.argv[1])
splits = Path(sys.argv[2])
out = Path(sys.argv[3])

X = np.load(splits / "global_test_X.npy")
y = np.load(splits / "global_test_y.npy").astype(int)

def sigmoid(z):
    z = np.clip(z, -20, 20)
    return 1.0 / (1.0 + np.exp(-z))

def metrics_at_threshold(probs, y, thr):
    pred = (probs >= thr).astype(int)
    tp = int(np.sum((pred == 1) & (y == 1)))
    fp = int(np.sum((pred == 1) & (y == 0)))
    fn = int(np.sum((pred == 0) & (y == 1)))
    tn = int(np.sum((pred == 0) & (y == 0)))
    n = len(y)
    acc = (tp + tn) / n if n else 0.0
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    fpr = fp / (fp + tn) if (fp + tn) else 0.0
    return {
        "threshold": round(float(thr), 4),
        "accuracy": round(float(acc), 6),
        "precision": round(float(prec), 6),
        "recall": round(float(rec), 6),
        "f1": round(float(f1), 6),
        "fpr": round(float(fpr), 6),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn
    }

def rankdata(a):
    order = np.argsort(a)
    ranks = np.empty(len(a), dtype=float)
    i = 0
    while i < len(a):
        j = i
        while j + 1 < len(a) and a[order[j + 1]] == a[order[i]]:
            j += 1
        avg_rank = (i + j + 2) / 2.0
        for k in range(i, j + 1):
            ranks[order[k]] = avg_rank
        i = j + 1
    return ranks

def roc_auc_score_manual(y_true, scores):
    y_true = np.asarray(y_true).astype(int)
    scores = np.asarray(scores).astype(float)
    pos = int(np.sum(y_true == 1))
    neg = int(np.sum(y_true == 0))
    if pos == 0 or neg == 0:
        return None
    ranks = rankdata(scores)
    sum_pos = float(np.sum(ranks[y_true == 1]))
    auc = (sum_pos - pos * (pos + 1) / 2.0) / (pos * neg)
    return round(float(auc), 6)

aggs = {
    "fedavg": clean / "fedavg" / "raw" / "baseline_fedavg_r01.json",
    "multikrum": clean / "multikrum" / "raw" / "baseline_multikrum_r01.json",
    "trimmedmean": clean / "trimmedmean" / "raw" / "baseline_trimmedmean_r01.json",
}

thresholds = [i / 100.0 for i in range(1, 100)]
summary_rows = []
full_rows = []

for agg, fp in aggs.items():
    j = json.loads(fp.read_text())
    w = np.array(j["weights"], dtype=np.float32)
    b = float(j["bias"])
    probs = sigmoid(X @ w + b)
    auc = roc_auc_score_manual(y, probs)

    best_f1 = None
    best_acc = None

    for thr in thresholds:
        m = metrics_at_threshold(probs, y, thr)
        m["aggregator"] = agg
        m["roc_auc"] = auc
        full_rows.append(m)

        if best_f1 is None or (m["f1"] > best_f1["f1"]) or (m["f1"] == best_f1["f1"] and m["accuracy"] > best_f1["accuracy"]):
            best_f1 = dict(m)

        if best_acc is None or (m["accuracy"] > best_acc["accuracy"]) or (m["accuracy"] == best_acc["accuracy"] and m["f1"] > best_acc["f1"]):
            best_acc = dict(m)

    default_m = metrics_at_threshold(probs, y, 0.5)
    default_m["aggregator"] = agg
    default_m["roc_auc"] = auc

    summary_rows.append({
        "aggregator": agg,
        "roc_auc": auc,
        "default_thr": 0.5,
        "default_f1": default_m["f1"],
        "default_accuracy": default_m["accuracy"],
        "default_fpr": default_m["fpr"],
        "best_f1_thr": best_f1["threshold"],
        "best_f1": best_f1["f1"],
        "best_f1_accuracy": best_f1["accuracy"],
        "best_f1_fpr": best_f1["fpr"],
        "best_acc_thr": best_acc["threshold"],
        "best_acc": best_acc["accuracy"],
        "best_acc_f1": best_acc["f1"],
        "best_acc_fpr": best_acc["fpr"],
    })

with open(out / "threshold_sweep_full.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "aggregator","threshold","accuracy","precision","recall","f1","fpr","tp","fp","fn","tn","roc_auc"
    ])
    w.writeheader()
    w.writerows(full_rows)

with open(out / "threshold_sweep_summary.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "aggregator","roc_auc",
        "default_thr","default_f1","default_accuracy","default_fpr",
        "best_f1_thr","best_f1","best_f1_accuracy","best_f1_fpr",
        "best_acc_thr","best_acc","best_acc_f1","best_acc_fpr"
    ])
    w.writeheader()
    w.writerows(summary_rows)

(out / "THRESHOLD_SWEEP.json").write_text(json.dumps({
    "clean_dir": str(clean),
    "splits_dir": str(splits),
    "n_samples": int(len(y)),
    "summary": summary_rows
}, indent=2))

with open(out / "README.txt", "w") as f:
    f.write("CLEAN R1 THRESHOLD SWEEP\n")
    f.write(f"clean_dir={clean}\n")
    f.write(f"splits_dir={splits}\n")
    f.write(f"n_samples={len(y)}\n")
    f.write(f"summary_csv={out / 'threshold_sweep_summary.csv'}\n")
    f.write(f"full_csv={out / 'threshold_sweep_full.csv'}\n")

print(f"OUT={out}")
print(f"SUMMARY_CSV={out / 'threshold_sweep_summary.csv'}")
print(f"FULL_CSV={out / 'threshold_sweep_full.csv'}")
print(f"JSON={out / 'THRESHOLD_SWEEP.json'}")
PY

LATEST=$(ls -dt "$RUN_DIR"/clean_threshold_sweep_* | head -n 1)

echo "===== README ====="
cat "$LATEST/README.txt"

echo
echo "===== SUMMARY CSV ====="
cat "$LATEST/threshold_sweep_summary.csv"

echo
echo "===== JSON ====="
cat "$LATEST/THRESHOLD_SWEEP.json"
