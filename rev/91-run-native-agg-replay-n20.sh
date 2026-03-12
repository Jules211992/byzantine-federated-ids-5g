#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

AGG=$(cat rev/.last_n20_agg_compare_dir 2>/dev/null || true)
[ -n "${AGG:-}" ] || { echo "ERROR: rev/.last_n20_agg_compare_dir introuvable"; exit 1; }
[ -d "${AGG:-}" ] || { echo "ERROR: dossier AGG introuvable: $AGG"; exit 1; }

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SPLITS="$RUN_DIR/splits_20"
[ -f "$SPLITS/global_test_X.npy" ] || { echo "ERROR: global_test_X.npy introuvable"; exit 1; }
[ -f "$SPLITS/global_test_y.npy" ] || { echo "ERROR: global_test_y.npy introuvable"; exit 1; }

rm -rf "$AGG/fedavg/raw"/*
rm -rf "$AGG/multikrum/raw"/*
rm -rf "$AGG/trimmedmean/raw"/*
rm -f "$AGG/figures_input/agg_compare_round_metrics_native.csv"
rm -f "$AGG/tables_input/agg_compare_summary_native.csv"
rm -f "$AGG/tables_input/agg_compare_paper_table_native.csv"
rm -f "$AGG/manifest/NATIVE_REPLAY_MANIFEST.json"
rm -f "$AGG/README_NATIVE_REPLAY.txt"

mkdir -p \
  "$AGG/fedavg/raw" \
  "$AGG/multikrum/raw" \
  "$AGG/trimmedmean/raw" \
  "$AGG/figures_input" \
  "$AGG/tables_input" \
  "$AGG/manifest" \
  "$AGG/logs"

python3 - <<'PY' "$AGG" "$SPLITS"
import csv
import importlib.util
import json
import math
import re
import sys
import time
from pathlib import Path

agg_dir = Path(sys.argv[1])
splits_dir = Path(sys.argv[2])

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

mk = load_module("multi_krum_mod", Path.home() / "byz-fed-ids-5g" / "phase7" / "multi_krum_aggregator.py")
tm = load_module("trimmed_mean_mod", Path.home() / "byz-fed-ids-5g" / "phase8" / "trimmed_mean_aggregator.py")

byz_clients = {"edge-client-1", "edge-client-6", "edge-client-11", "edge-client-16"}
scenarios = ["baseline", "label_flip", "backdoor"]
rounds = [1, 2, 3, 4, 5]
f_assumed = {"baseline": 0, "label_flip": 4, "backdoor": 4}

def natkey(s):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r'(\d+)', s)]

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

def cid_from_name(name):
    m = re.search(r'(edge-client-\d+)', name)
    return m.group(1) if m else name

def load_updates(raw_dir, scenario):
    files = sorted(raw_dir.glob("*.json"), key=lambda p: natkey(p.name))
    updates = []
    for fp in files:
        j = json.loads(fp.read_text())
        cid = j.get("client_id") or cid_from_name(fp.name)
        is_byz = bool(j.get("byzantine", False)) or (scenario != "baseline" and cid in byz_clients)
        updates.append({
            "client_id": cid,
            "weights": j["weights"],
            "bias": j["bias"],
            "test_metrics": j.get("test_metrics", {}),
            "train_metrics": j.get("train_metrics", {}),
            "latencies": j.get("latencies", {}),
            "byzantine": is_byz,
            "attack_type": j.get("attack_type"),
            "source_file": str(fp),
        })
    return updates

def eval_global(weights, bias):
    return mk.evaluate_global(weights, bias, str(splits_dir))

def run_fedavg(updates):
    t0 = time.perf_counter()
    selected_idx = list(range(len(updates)))
    w_global, b_global = mk.fedavg(updates, selected_idx)
    metrics = eval_global(w_global, b_global)
    dt = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect": False,
        "aggregation_time_ms": dt,
        "global_metrics": metrics,
        "weights": w_global.tolist(),
        "bias": float(b_global),
    }

def run_multikrum(updates, f):
    t0 = time.perf_counter()
    selected_idx, rejected_idx, scores = mk.multi_krum(updates, f)
    w_global, b_global = mk.fedavg(updates, selected_idx)
    metrics = eval_global(w_global, b_global)
    dt = (time.perf_counter() - t0) * 1000.0
    rejected = [updates[i]["client_id"] for i in rejected_idx]
    rejected_byz = sum(1 for i in rejected_idx if updates[i]["byzantine"])
    return {
        "selected": [updates[i]["client_id"] for i in selected_idx],
        "rejected": rejected,
        "rejected_byz": rejected_byz,
        "detect": len(rejected) > 0,
        "aggregation_time_ms": dt,
        "global_metrics": metrics,
        "weights": w_global.tolist(),
        "bias": float(b_global),
        "scores": scores,
    }

def run_trimmedmean(updates, f):
    t0 = time.perf_counter()
    w_tm = tm.trimmed_mean_weights(updates, f)
    b_tm = tm.trimmed_mean_bias(updates, f)
    metrics = eval_global(w_tm, b_tm)
    dt = (time.perf_counter() - t0) * 1000.0
    return {
        "selected": [u["client_id"] for u in updates],
        "rejected": [],
        "rejected_byz": 0,
        "detect": False,
        "aggregation_time_ms": dt,
        "global_metrics": metrics,
        "weights": w_tm.tolist(),
        "bias": float(b_tm),
    }

per_round_rows = []

for scenario in scenarios:
    for rnd in rounds:
        raw_dir = agg_dir / "raw" / scenario / f"round{rnd:02d}"
        if not raw_dir.is_dir():
            raise SystemExit(f"ERROR: raw dir introuvable: {raw_dir}")
        updates = load_updates(raw_dir, scenario)
        if len(updates) != 20:
            raise SystemExit(f"ERROR: {scenario} round {rnd} expected 20 updates, got {len(updates)}")
        f = f_assumed[scenario]

        results = {
            "fedavg": run_fedavg(updates),
            "multikrum": run_multikrum(updates, f),
            "trimmedmean": run_trimmedmean(updates, f),
        }

        for agg_name, res in results.items():
            out_dir = agg_dir / agg_name / "raw"
            out_dir.mkdir(parents=True, exist_ok=True)
            out_json = out_dir / f"{scenario}_{agg_name}_r{rnd:02d}.json"
            payload = {
                "scenario": scenario,
                "round": rnd,
                "aggregator": agg_name,
                "f_assumed": f,
                "n_clients": len(updates),
                "selected": res["selected"],
                "rejected": res["rejected"],
                "rejected_byz": res["rejected_byz"],
                "byzantine_detected": res["detect"],
                "aggregation_time_ms": res["aggregation_time_ms"],
                "global_metrics": res["global_metrics"],
                "source_files": [u["source_file"] for u in updates],
            }
            if "scores" in res:
                payload["scores"] = res["scores"]
            out_json.write_text(json.dumps(payload, indent=2))

            gm = res["global_metrics"]
            per_round_rows.append({
                "scenario": scenario,
                "aggregator": agg_name,
                "round": rnd,
                "global_f1": gm.get("f1"),
                "global_fpr": gm.get("fpr"),
                "global_accuracy": gm.get("accuracy"),
                "global_precision": gm.get("precision"),
                "global_recall": gm.get("recall"),
                "selected_count": len(res["selected"]),
                "rejected_count": len(res["rejected"]),
                "rejected_byz": res["rejected_byz"],
                "detect_round": 1 if res["detect"] else 0,
                "aggregation_time_ms": res["aggregation_time_ms"],
                "source_json": str(out_json),
            })

per_round_csv = agg_dir / "figures_input" / "agg_compare_round_metrics_native.csv"
with per_round_csv.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(per_round_rows[0].keys()))
    w.writeheader()
    w.writerows(per_round_rows)

summary_rows = []
for scenario in scenarios:
    for agg_name in ["fedavg", "multikrum", "trimmedmean"]:
        rows = [r for r in per_round_rows if r["scenario"] == scenario and r["aggregator"] == agg_name]
        summary_rows.append({
            "scenario": scenario,
            "aggregator": agg_name,
            "rounds": len(rows),
            "avg_f1": stats([r["global_f1"] for r in rows])["avg"],
            "min_f1": stats([r["global_f1"] for r in rows])["min"],
            "max_f1": stats([r["global_f1"] for r in rows])["max"],
            "avg_fpr": stats([r["global_fpr"] for r in rows])["avg"],
            "avg_accuracy": stats([r["global_accuracy"] for r in rows])["avg"],
            "avg_recall": stats([r["global_recall"] for r in rows])["avg"],
            "avg_selected": stats([r["selected_count"] for r in rows])["avg"],
            "avg_rejected": stats([r["rejected_count"] for r in rows])["avg"],
            "avg_rejected_byz": stats([r["rejected_byz"] for r in rows])["avg"],
            "detect_rounds": int(sum(r["detect_round"] for r in rows)),
            "avg_aggregation_time_ms": stats([r["aggregation_time_ms"] for r in rows])["avg"],
        })

summary_csv = agg_dir / "tables_input" / "agg_compare_summary_native.csv"
with summary_csv.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
    w.writeheader()
    w.writerows(summary_rows)

paper_rows = [r for r in summary_rows if r["scenario"] in ("label_flip", "backdoor")]
paper_csv = agg_dir / "tables_input" / "agg_compare_paper_table_native.csv"
with paper_csv.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "scenario","aggregator","avg_f1","avg_fpr","avg_rejected",
        "avg_rejected_byz","detect_rounds","avg_aggregation_time_ms"
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
            "avg_aggregation_time_ms": r["avg_aggregation_time_ms"],
        })

manifest = {
    "agg_dir": str(agg_dir),
    "splits_dir": str(splits_dir),
    "per_round_csv": str(per_round_csv),
    "summary_csv": str(summary_csv),
    "paper_csv": str(paper_csv),
    "scenarios": scenarios,
    "rounds": rounds,
    "f_assumed": f_assumed,
    "note": "native replay from real raw N20 rounds"
}

manifest_path = agg_dir / "manifest" / "NATIVE_REPLAY_MANIFEST.json"
manifest_path.write_text(json.dumps(manifest, indent=2))

readme = "\n".join([
    "COMPARAISON NATIVE REPLAY N20 DES AGREGATEURS",
    f"agg_dir={agg_dir}",
    f"splits_dir={splits_dir}",
    "source=real raw rounds already measured",
    f"per_round_csv={per_round_csv}",
    f"summary_csv={summary_csv}",
    f"paper_csv={paper_csv}",
])

(agg_dir / "README_NATIVE_REPLAY.txt").write_text(readme + "\n")

print(f"AGG_DIR={agg_dir}")
print(f"PER_ROUND_CSV={per_round_csv}")
print(f"SUMMARY_CSV={summary_csv}")
print(f"PAPER_CSV={paper_csv}")
print(f"MANIFEST={manifest_path}")
PY
