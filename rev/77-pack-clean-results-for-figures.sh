#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/final_graph_inputs_$TS"
mkdir -p "$OUT"/baseline "$OUT"/label_flip "$OUT"/backdoor

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

python3 - "$RUN_DIR" "$OUT" "$BYZ_CLIENTS" <<'PY'
import os, re, glob, csv, json, math, shutil, sys
from pathlib import Path

run_dir = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
byz_set = set(sys.argv[3].split())
summary_dir = run_dir / "summary"

def latest_by_round(pattern, rx):
    latest = {}
    cre = re.compile(rx)
    for p in sorted(summary_dir.glob(pattern)):
        m = cre.search(p.name)
        if not m:
            continue
        r = int(m.group(1))
        if r not in latest or p.name > latest[r].name:
            latest[r] = p
    return dict(sorted(latest.items()))

def copy_group(files_by_round, dst_dir, suffix):
    out = {}
    dst_dir.mkdir(parents=True, exist_ok=True)
    for r, src in sorted(files_by_round.items()):
        dst = dst_dir / f"round{r:02d}_{suffix}"
        shutil.copy2(src, dst)
        out[r] = str(dst)
    return out

def conv(x):
    if x is None:
        return None
    x = str(x).strip()
    if x == "" or x.lower() == "none":
        return None
    try:
        if "." in x:
            return float(x)
        return int(x)
    except:
        return None

def pctl(vals, p):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    xs = sorted(vals)
    if len(xs) == 1:
        return float(xs[0])
    k = (len(xs) - 1) * (p / 100.0)
    f = int(math.floor(k))
    c = int(math.ceil(k))
    if f == c:
        return float(xs[f])
    d = k - f
    return float(xs[f] + (xs[c] - xs[f]) * d)

def mean(vals):
    vals = [v for v in vals if v is not None]
    return (sum(vals) / len(vals)) if vals else None

def minv(vals):
    vals = [v for v in vals if v is not None]
    return min(vals) if vals else None

def maxv(vals):
    vals = [v for v in vals if v is not None]
    return max(vals) if vals else None

def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return {
        "avg": mean(vals),
        "min": min(vals),
        "max": max(vals),
        "p50": pctl(vals, 50),
        "p95": pctl(vals, 95),
        "p99": pctl(vals, 99),
        "n": len(vals)
    }

def read_csv_rows(path, scenario):
    rows = []
    with open(path, newline="") as f:
        rd = csv.DictReader(f)
        for row in rd:
            rr = {k: row.get(k) for k in row.keys()}
            rr["round"] = conv(row.get("round"))
            rr["fabric_round"] = conv(row.get("fabric_round"))
            rr["f1"] = conv(row.get("f1"))
            rr["fpr"] = conv(row.get("fpr"))
            rr["ipfs_ms"] = conv(row.get("ipfs_ms"))
            rr["tx_ms"] = conv(row.get("tx_ms"))
            rr["total_ms"] = conv(row.get("total_ms"))
            cid = row.get("client_id") or ""
            if "is_byz" in row and str(row.get("is_byz")).strip() not in ("", "None", "none"):
                rr["is_byz"] = int(float(row.get("is_byz")))
            else:
                rr["is_byz"] = 1 if (scenario != "baseline" and cid in byz_set) else 0
            rows.append(rr)
    return rows

def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2))

baseline_clients_src = latest_by_round("p7_baseline_round*_clients_*.csv", r"p7_baseline_round(\d+)_clients_")
baseline_lat_src = latest_by_round("p7_baseline_round*_latency_pct_*.json", r"p7_baseline_round(\d+)_latency_pct_")
label_clients_src = latest_by_round("p8_labelflip_round*_clients_*.csv", r"p8_labelflip_round(\d+)_clients_")
label_summary_src = latest_by_round("p8_labelflip_round*_summary_*.json", r"p8_labelflip_round(\d+)_summary_")
backdoor_clients_src = latest_by_round("p15_backdoor_round*_clients_*.csv", r"p15_backdoor_round(\d+)_clients_")
backdoor_summary_src = latest_by_round("p15_backdoor_round*_summary_*.json", r"p15_backdoor_round(\d+)_summary_")

baseline_clients_dst = copy_group(baseline_clients_src, out_dir / "baseline", "clients.csv")
baseline_lat_dst = copy_group(baseline_lat_src, out_dir / "baseline", "latency.json")
label_clients_dst = copy_group(label_clients_src, out_dir / "label_flip", "clients.csv")
label_summary_dst = copy_group(label_summary_src, out_dir / "label_flip", "summary.json")
backdoor_clients_dst = copy_group(backdoor_clients_src, out_dir / "backdoor", "clients.csv")
backdoor_summary_dst = copy_group(backdoor_summary_src, out_dir / "backdoor", "summary.json")

baseline_rows = []
for r in sorted(baseline_clients_dst):
    baseline_rows.extend(read_csv_rows(baseline_clients_dst[r], "baseline"))

label_rows = []
for r in sorted(label_clients_dst):
    label_rows.extend(read_csv_rows(label_clients_dst[r], "label_flip"))

backdoor_rows = []
for r in sorted(backdoor_clients_dst):
    backdoor_rows.extend(read_csv_rows(backdoor_clients_dst[r], "backdoor"))

baseline_clean = {
    "scenario": "baseline",
    "rounds": sorted(baseline_clients_dst.keys()),
    "n_files": len(baseline_clients_dst),
    "n_rows": len(baseline_rows),
    "f1": stats([r["f1"] for r in baseline_rows]),
    "fpr": stats([r["fpr"] for r in baseline_rows]),
    "ipfs_ms": stats([r["ipfs_ms"] for r in baseline_rows]),
    "tx_ms": stats([r["tx_ms"] for r in baseline_rows]),
    "total_ms": stats([r["total_ms"] for r in baseline_rows]),
    "inputs": list(baseline_clients_dst.values())
}
write_json(out_dir / "baseline" / "baseline_all_rounds_clean.json", baseline_clean)

def attack_clean(name, rows, inputs):
    honest = [r for r in rows if r["is_byz"] == 0]
    byz = [r for r in rows if r["is_byz"] == 1]
    return {
        "scenario": name,
        "rounds": sorted({r["round"] for r in rows if r["round"] is not None}),
        "n_rows": len(rows),
        "n_honest_rows": len(honest),
        "n_byz_rows": len(byz),
        "f1_all": stats([r["f1"] for r in rows]),
        "f1_honest": stats([r["f1"] for r in honest]),
        "f1_byz": stats([r["f1"] for r in byz]),
        "fpr_all": stats([r["fpr"] for r in rows]),
        "fpr_honest": stats([r["fpr"] for r in honest]),
        "fpr_byz": stats([r["fpr"] for r in byz]),
        "ipfs_ms": stats([r["ipfs_ms"] for r in rows]),
        "tx_ms": stats([r["tx_ms"] for r in rows]),
        "total_ms": stats([r["total_ms"] for r in rows]),
        "inputs": list(inputs.values())
    }

label_clean = attack_clean("label_flip", label_rows, label_clients_dst)
backdoor_clean = attack_clean("backdoor", backdoor_rows, backdoor_clients_dst)

write_json(out_dir / "label_flip" / "label_flip_all_rounds_clean.json", label_clean)
write_json(out_dir / "backdoor" / "backdoor_all_rounds_clean.json", backdoor_clean)

plot_rows = []

for rr in sorted({r["round"] for r in baseline_rows if r["round"] is not None}):
    rows = [r for r in baseline_rows if r["round"] == rr]
    plot_rows.append({
        "scenario": "baseline",
        "round": rr,
        "f1_avg": mean([r["f1"] for r in rows]),
        "f1_honest_avg": "",
        "f1_byz_avg": "",
        "fpr_avg": mean([r["fpr"] for r in rows]),
        "fpr_honest_avg": "",
        "fpr_byz_avg": "",
        "ipfs_ms_p50": pctl([r["ipfs_ms"] for r in rows], 50),
        "tx_ms_p50": pctl([r["tx_ms"] for r in rows], 50),
        "total_ms_p50": pctl([r["total_ms"] for r in rows], 50),
        "total_ms_p95": pctl([r["total_ms"] for r in rows], 95),
        "n_clients": len(rows),
        "n_honest": len(rows),
        "n_byz": 0
    })

for scenario, rows in [("label_flip", label_rows), ("backdoor", backdoor_rows)]:
    for rr in sorted({r["round"] for r in rows if r["round"] is not None}):
        x = [r for r in rows if r["round"] == rr]
        h = [r for r in x if r["is_byz"] == 0]
        b = [r for r in x if r["is_byz"] == 1]
        plot_rows.append({
            "scenario": scenario,
            "round": rr,
            "f1_avg": mean([r["f1"] for r in x]),
            "f1_honest_avg": mean([r["f1"] for r in h]),
            "f1_byz_avg": mean([r["f1"] for r in b]),
            "fpr_avg": mean([r["fpr"] for r in x]),
            "fpr_honest_avg": mean([r["fpr"] for r in h]),
            "fpr_byz_avg": mean([r["fpr"] for r in b]),
            "ipfs_ms_p50": pctl([r["ipfs_ms"] for r in x], 50),
            "tx_ms_p50": pctl([r["tx_ms"] for r in x], 50),
            "total_ms_p50": pctl([r["total_ms"] for r in x], 50),
            "total_ms_p95": pctl([r["total_ms"] for r in x], 95),
            "n_clients": len(x),
            "n_honest": len(h),
            "n_byz": len(b)
        })

plot_rows.sort(key=lambda z: (z["scenario"], z["round"]))

with open(out_dir / "plot_round_metrics.csv", "w", newline="") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "scenario","round",
            "f1_avg","f1_honest_avg","f1_byz_avg",
            "fpr_avg","fpr_honest_avg","fpr_byz_avg",
            "ipfs_ms_p50","tx_ms_p50","total_ms_p50","total_ms_p95",
            "n_clients","n_honest","n_byz"
        ]
    )
    w.writeheader()
    for r in plot_rows:
        w.writerow(r)

manifest = {
    "run_dir": str(run_dir),
    "output_dir": str(out_dir),
    "baseline": {
        "clients": baseline_clients_dst,
        "latency": baseline_lat_dst,
        "clean_summary": str(out_dir / "baseline" / "baseline_all_rounds_clean.json")
    },
    "label_flip": {
        "clients": label_clients_dst,
        "summary": label_summary_dst,
        "clean_summary": str(out_dir / "label_flip" / "label_flip_all_rounds_clean.json")
    },
    "backdoor": {
        "clients": backdoor_clients_dst,
        "summary": backdoor_summary_dst,
        "clean_summary": str(out_dir / "backdoor" / "backdoor_all_rounds_clean.json")
    },
    "plot_csv": str(out_dir / "plot_round_metrics.csv")
}
write_json(out_dir / "FINAL_MANIFEST.json", manifest)

readme = []
readme.append(f"RUN_DIR={run_dir}")
readme.append(f"OUTPUT_DIR={out_dir}")
readme.append("BASELINE attendu: 5 rounds x 20 clients = 100 lignes")
readme.append(f"BASELINE obtenu: {len(baseline_rows)} lignes")
readme.append(f"LABEL_FLIP obtenu: {len(label_rows)} lignes")
readme.append(f"BACKDOOR obtenu: {len(backdoor_rows)} lignes")
(out_dir / "README.txt").write_text("\n".join(readme) + "\n")
PY

echo "OUT=$OUT"
find "$OUT" -maxdepth 2 -type f | sort
