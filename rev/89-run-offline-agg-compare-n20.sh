#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

AGG=$(cat rev/.last_n20_agg_compare_dir 2>/dev/null || true)
[ -n "${AGG:-}" ] || { echo "ERROR: rev/.last_n20_agg_compare_dir introuvable"; exit 1; }
[ -d "${AGG:-}" ] || { echo "ERROR: dossier AGG introuvable: $AGG"; exit 1; }

rm -rf "$AGG"/fedavg/raw/*
rm -rf "$AGG"/multikrum/raw/*
rm -rf "$AGG"/trimmedmean/raw/*
rm -f "$AGG"/tables_input/agg_compare_summary.csv
rm -f "$AGG"/tables_input/agg_compare_paper_table.csv
rm -f "$AGG"/figures_input/agg_compare_round_metrics.csv
rm -f "$AGG"/manifest/OFFLINE_AGG_COMPARE_MANIFEST.json
rm -f "$AGG"/README_OFFLINE_AGG_COMPARE.txt

mkdir -p \
  "$AGG"/fedavg/raw \
  "$AGG"/multikrum/raw \
  "$AGG"/trimmedmean/raw \
  "$AGG"/summary \
  "$AGG"/figures_input \
  "$AGG"/tables_input \
  "$AGG"/manifest \
  "$AGG"/logs

python3 - <<'PY' "$AGG"
import csv
import importlib.util
import json
import math
import re
import sys
import time
from pathlib import Path

import numpy as np

agg_dir = Path(sys.argv[1]).resolve()
repo = Path.home() / "byz-fed-ids-5g"
run_dir = agg_dir.parent
splits_dir = run_dir / "splits_20"

if not splits_dir.exists():
    raise SystemExit(f"ERROR: splits_20 introuvable: {splits_dir}")

byz_clients = {"edge-client-1", "edge-client-6", "edge-client-11", "edge-client-16"}

def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

mk = load_module(repo / "phase7" / "multi_krum_aggregator.py", "mkmod_n20")
tm = load_module(repo / "phase8" / "trimmed_mean_aggregator.py", "tmmod_n20")

def natural_key(s: str):
    return [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', s)]

def pct(vals, p):
    vals = sorted(vals)
    if not vals:
        return None
    if len(vals) == 1:
        return vals[0]
    k = (len(vals) - 1) * p
    lo = int(math.floor(k))
    hi = int(math.ceil(k))
    if lo == hi:
        return vals[lo]
    return vals[lo] + (vals[hi] - vals[lo]) * (k - lo)

def stats(vals):
    vals = [float(v) for v in vals if v is not None]
    if not vals:
        return None
    avg = sum(vals) / len(vals)
    return {
        "avg": avg,
        "min": min(vals),
        "max": max(vals),
        "p50": pct(vals, 0.50),
        "p95": pct(vals, 0.95),
        "n": len(vals),
    }

def build_global_test(sdir: Path):
    x_files = sorted(sdir.glob("edge-client-*_test_X.npy"), key=lambda p: natural_key(p.name))
    y_files = sorted(sdir.glob("edge-client-*_test_y.npy"), key=lambda p: natural_key(p.name))

    if len(x_files) != 20:
        raise SystemExit(f"ERROR: attendu 20 test_X, obtenu {len(x_files)} dans {sdir}")
    if len(y_files) != 20:
        raise SystemExit(f"ERROR: attendu 20 test_y, obtenu {len(y_files)} dans {sdir}")

    xs = [np.load(str(p)) for p in x_files]
    ys = [np.load(str(p)).reshape(-1) for p in y_files]

    X = np.concatenate(xs, axis=0).astype(np.float32)
    y = np.concatenate(ys, axis=0).astype(np.int32)

    return X, y, x_files, y_files

GLOBAL_X, GLOBAL_Y, GX_FILES, GY_FILES = build_global_test(splits_dir)

def eval_global_local(weights, bias, X, y):
    w = np.asarray(weights, dtype=np.float32).reshape(-1)
    b = float(bias)

    if X.shape[1] != w.shape[0]:
        raise SystemExit(f"ERROR: dimension mismatch X={X.shape} weights={w.shape}")

    t0 = time.perf_counter()
    z = X @ w + b
    pred = (z >= 0.0).astype(np.int32)
    t1 = time.perf_counter()

    tp = int(np.sum((pred == 1) & (y == 1)))
    fp = int(np.sum((pred == 1) & (y == 0)))
    fn = int(np.sum((pred == 0) & (y == 1)))
    tn = int(np.sum((pred == 0) & (y == 0)))

    n = len(y)
    accuracy = (tp + tn) / n if n else 0.0
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    fpr = fp / (fp + tn) if (fp + tn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0

    return {
        "accuracy": float(accuracy),
        "f1": float(f1),
        "precision": float(precision),
        "recall": float(recall),
        "fpr": float(fpr),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
        "n_samples": int(n),
        "eval_ms": float((t1 - t0) * 1000.0),
    }

def load_updates(scenario: str, round_num: int):
    r2 = f"round{round_num:02d}"
    d = agg_dir / "raw" / scenario / r2
    if not d.exists():
        raise SystemExit(f"ERROR: dossier introuvable: {d}")

    files = sorted(d.glob("*.json"), key=lambda p: natural_key(p.name))
    if len(files) != 20:
        raise SystemExit(f"ERROR: {scenario} {r2} attend 20 json, obtenu {len(files)} dans {d}")

    updates = []
    for p in files:
        j = json.loads(p.read_text())
        cid = j.get("client_id")
        if not cid:
            m = re.search(r'(edge-client-\d+)', p.name)
            cid = m.group(1) if m else p.stem
            j["client_id"] = cid

        is_byz = 0
        if scenario != "baseline":
            if cid in byz_clients or p.name.startswith("fl-byz-"):
                is_byz = 1

        j["is_byz"] = is_byz

        if "weights" not in j or "bias" not in j:
            raise SystemExit(f"ERROR: weights/bias absents dans {p}")

        updates.append(j)

    return updates, files

def run_fedavg(updates):
    idx = list(range(len(updates)))
    t0 = time.perf_counter()
    w, b = mk.fedavg(updates, idx)
    t1 = time.perf_counter()
    metrics = eval_global_local(w, b, GLOBAL_X, GLOBAL_Y)
    return {
        "algorithm": "FedAvg",
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz_count": 0,
        "byzantine_detected": False,
        "aggregation_time_ms": (t1 - t0) * 1000.0,
        "global_metrics": metrics,
        "weights": list(map(float, w)),
        "bias": float(b),
    }

def run_multikrum(updates, f_assumed):
    t0 = time.perf_counter()
    selected_idx, rejected_idx, scores = mk.multi_krum(updates, f_assumed)
    w, b = mk.fedavg(updates, selected_idx)
    t1 = time.perf_counter()
    metrics = eval_global_local(w, b, GLOBAL_X, GLOBAL_Y)

    selected = [updates[i]["client_id"] for i in selected_idx]
    rejected = [updates[i]["client_id"] for i in rejected_idx]
    rejected_byz = sum(1 for c in rejected if c in byz_clients)

    return {
        "algorithm": "Multi-Krum",
        "selected": selected,
        "rejected": rejected,
        "krum_scores": {updates[i]["client_id"]: float(scores[i]) for i in range(len(updates))},
        "rejected_byz_count": int(rejected_byz),
        "byzantine_detected": bool(rejected_byz > 0),
        "aggregation_time_ms": (t1 - t0) * 1000.0,
        "global_metrics": metrics,
        "weights": list(map(float, w)),
        "bias": float(b),
    }

def run_trimmedmean(updates, f_assumed):
    t0 = time.perf_counter()
    w = tm.trimmed_mean_weights(updates, f_assumed)
    b = tm.trimmed_mean_bias(updates, f_assumed)
    t1 = time.perf_counter()
    metrics = eval_global_local(w, b, GLOBAL_X, GLOBAL_Y)

    return {
        "algorithm": "TrimmedMean",
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz_count": 0,
        "byzantine_detected": False,
        "aggregation_time_ms": (t1 - t0) * 1000.0,
        "global_metrics": metrics,
        "weights": list(map(float, w)),
        "bias": float(b),
    }

rows = []
scenarios = ["baseline", "label_flip", "backdoor"]

for scenario in scenarios:
    f_assumed = 0 if scenario == "baseline" else 4

    for round_num in range(1, 6):
        updates, files = load_updates(scenario, round_num)

        fed = run_fedavg(updates)
        mkm = run_multikrum(updates, f_assumed)
        trm = run_trimmedmean(updates, f_assumed)

        for key, result in [("fedavg", fed), ("multikrum", mkm), ("trimmedmean", trm)]:
            out_dir = agg_dir / key / "raw" / scenario
            out_dir.mkdir(parents=True, exist_ok=True)
            out_file = out_dir / f"{scenario}_{key}_r{round_num:02d}.json"

            payload = {
                "scenario": scenario,
                "round": round_num,
                "n_clients": len(updates),
                "f_assumed": f_assumed,
                "input_files": [str(p) for p in files],
                "global_eval_source": {
                    "n_samples": int(len(GLOBAL_Y)),
                    "test_x_files": [str(p) for p in GX_FILES],
                    "test_y_files": [str(p) for p in GY_FILES],
                },
                **result,
            }
            out_file.write_text(json.dumps(payload, indent=2))

            gm = result["global_metrics"]
            rows.append({
                "scenario": scenario,
                "aggregator": key,
                "round": round_num,
                "n_clients": len(updates),
                "f_assumed": f_assumed,
                "global_f1": gm.get("f1"),
                "global_fpr": gm.get("fpr"),
                "global_accuracy": gm.get("accuracy"),
                "global_recall": gm.get("recall"),
                "selected_count": len(result["selected"]),
                "rejected_count": len(result["rejected"]),
                "rejected_byz_count": result["rejected_byz_count"],
                "byzantine_detected": int(bool(result["byzantine_detected"])),
                "aggregation_time_ms": result["aggregation_time_ms"],
                "source_json": str(out_file),
            })

per_round_csv = agg_dir / "figures_input" / "agg_compare_round_metrics.csv"
with per_round_csv.open("w", newline="") as fp:
    fieldnames = list(rows[0].keys())
    w = csv.DictWriter(fp, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(rows)

summary_rows = []
for scenario in scenarios:
    for aggregator in ["fedavg", "multikrum", "trimmedmean"]:
        sub = [r for r in rows if r["scenario"] == scenario and r["aggregator"] == aggregator]

        f1s = stats([r["global_f1"] for r in sub])
        fprs = stats([r["global_fpr"] for r in sub])
        accs = stats([r["global_accuracy"] for r in sub])
        recs = stats([r["global_recall"] for r in sub])
        sels = stats([r["selected_count"] for r in sub])
        rejs = stats([r["rejected_count"] for r in sub])
        rejb = stats([r["rejected_byz_count"] for r in sub])
        aggs = stats([r["aggregation_time_ms"] for r in sub])

        summary_rows.append({
            "scenario": scenario,
            "aggregator": aggregator,
            "rounds": len(sub),
            "avg_f1": f1s["avg"],
            "min_f1": f1s["min"],
            "max_f1": f1s["max"],
            "avg_fpr": fprs["avg"],
            "avg_accuracy": accs["avg"],
            "avg_recall": recs["avg"],
            "avg_selected": sels["avg"],
            "avg_rejected": rejs["avg"],
            "avg_rejected_byz": rejb["avg"],
            "detect_rounds": int(sum(int(r["byzantine_detected"]) for r in sub)),
            "avg_aggregation_time_ms": aggs["avg"],
        })

summary_csv = agg_dir / "tables_input" / "agg_compare_summary.csv"
with summary_csv.open("w", newline="") as fp:
    fieldnames = list(summary_rows[0].keys())
    w = csv.DictWriter(fp, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(summary_rows)

paper_rows = []
for scenario in ["label_flip", "backdoor"]:
    for aggregator in ["fedavg", "multikrum", "trimmedmean"]:
        sub = [r for r in summary_rows if r["scenario"] == scenario and r["aggregator"] == aggregator][0]
        paper_rows.append({
            "scenario": scenario,
            "aggregator": aggregator,
            "avg_f1": sub["avg_f1"],
            "avg_fpr": sub["avg_fpr"],
            "avg_rejected": sub["avg_rejected"],
            "avg_rejected_byz": sub["avg_rejected_byz"],
            "detect_rounds": sub["detect_rounds"],
            "avg_aggregation_time_ms": sub["avg_aggregation_time_ms"],
        })

paper_csv = agg_dir / "tables_input" / "agg_compare_paper_table.csv"
with paper_csv.open("w", newline="") as fp:
    fieldnames = list(paper_rows[0].keys())
    w = csv.DictWriter(fp, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(paper_rows)

manifest = {
    "agg_dir": str(agg_dir),
    "splits_dir": str(splits_dir),
    "global_eval": {
        "n_samples": int(len(GLOBAL_Y)),
        "test_x_files": [str(p) for p in GX_FILES],
        "test_y_files": [str(p) for p in GY_FILES],
    },
    "per_round_csv": str(per_round_csv),
    "summary_csv": str(summary_csv),
    "paper_csv": str(paper_csv),
    "scenarios": scenarios,
    "f_assumed": {
        "baseline": 0,
        "label_flip": 4,
        "backdoor": 4
    }
}
(agg_dir / "manifest" / "OFFLINE_AGG_COMPARE_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = [
    "COMPARAISON OFFLINE N20 DES AGREGATEURS",
    f"agg_dir={agg_dir}",
    f"splits_dir={splits_dir}",
    f"global_test_n={len(GLOBAL_Y)}",
    "baseline: f_assumed=0",
    "label_flip: f_assumed=4",
    "backdoor: f_assumed=4",
    f"per_round_csv={per_round_csv}",
    f"summary_csv={summary_csv}",
    f"paper_csv={paper_csv}",
]
(agg_dir / "README_OFFLINE_AGG_COMPARE.txt").write_text("\n".join(readme) + "\n")

print("AGG_DIR=", agg_dir)
print("PER_ROUND_CSV=", per_round_csv)
print("SUMMARY_CSV=", summary_csv)
print("PAPER_CSV=", paper_csv)
print("MANIFEST=", agg_dir / "manifest" / "OFFLINE_AGG_COMPARE_MANIFEST.json")
PY
