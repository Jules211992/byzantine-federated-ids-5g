#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

mkdir -p \
  "$BUNDLE"/caliper/audit/tables \
  "$BUNDLE"/ipfs/audit \
  "$BUNDLE"/manifest

python3 - <<'PY' "$BUNDLE"
import json
import re
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
cal_sel = bundle / "caliper" / "selected"
cal_audit = bundle / "caliper" / "audit"
cal_tables = cal_audit / "tables"
ipfs_sel = bundle / "ipfs" / "selected"
ipfs_audit = bundle / "ipfs" / "audit"
manifest = bundle / "manifest"

import pandas as pd

def strip_html(s):
    s = re.sub(r'(?is)<script.*?>.*?</script>', ' ', s)
    s = re.sub(r'(?is)<style.*?>.*?</style>', ' ', s)
    s = re.sub(r'(?s)<[^>]+>', ' ', s)
    s = s.replace('&nbsp;', ' ').replace('&amp;', '&')
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def safe_float(x):
    try:
        return float(x)
    except Exception:
        return None

def pct(vals, p):
    vals = sorted(vals)
    if not vals:
        return None
    if len(vals) == 1:
        return vals[0]
    k = (len(vals)-1) * p
    lo = int(k)
    hi = min(lo + 1, len(vals)-1)
    frac = k - lo
    return vals[lo] + (vals[hi] - vals[lo]) * frac

caliper_reports = []
for f in sorted(cal_sel.glob("*.html")):
    item = {
        "name": f.name,
        "file": str(f),
        "tables": [],
        "snippets": [],
        "numeric_candidates": {}
    }

    try:
        dfs = pd.read_html(str(f))
    except Exception as e:
        dfs = []
        item["read_html_error"] = str(e)

    for i, df in enumerate(dfs, start=1):
        out_csv = cal_tables / f"{f.stem}_table{i:02d}.csv"
        df.to_csv(out_csv, index=False)
        preview = df.head(8).fillna("").astype(str).to_dict(orient="records")
        item["tables"].append({
            "index": i,
            "csv": str(out_csv),
            "n_rows": int(len(df)),
            "n_cols": int(len(df.columns)),
            "columns": [str(c) for c in df.columns],
            "preview": preview
        })

    html = f.read_text(errors="ignore")
    txt = strip_html(html)
    low = txt.lower()

    keywords = [
        "throughput", "tps", "latency", "send rate", "success",
        "fail", "createasset", "round", "transaction", "endorse", "commit"
    ]

    seen = set()
    for kw in keywords:
        for m in re.finditer(re.escape(kw), low):
            start = max(0, m.start() - 140)
            end = min(len(txt), m.end() + 220)
            snip = txt[start:end].strip()
            key = snip.lower()
            if key not in seen:
                seen.add(key)
                item["snippets"].append(snip)
            if len(item["snippets"]) >= 12:
                break
        if len(item["snippets"]) >= 12:
            break

    patterns = {
        "tps": [r'([\d.]+)\s*tps', r'throughput[^0-9]{0,20}([\d.]+)'],
        "latency_ms": [r'([\d.]+)\s*ms', r'latency[^0-9]{0,20}([\d.]+)'],
        "send_rate": [r'send rate[^0-9]{0,20}([\d.]+)'],
        "success_rate": [r'success[^0-9]{0,20}([\d.]+)'],
        "failure_rate": [r'fail(?:ure)?[^0-9]{0,20}([\d.]+)']
    }

    for k, pats in patterns.items():
        vals = []
        for pat in pats:
            vals.extend(re.findall(pat, low, flags=re.I))
        clean = sorted({v for v in (safe_float(x) for x in vals) if v is not None})
        item["numeric_candidates"][k] = clean[:30]

    caliper_reports.append(item)

(cal_audit / "CALIPER_AUDIT.json").write_text(json.dumps(caliper_reports, indent=2))

ipfs_reports = []
for f in sorted(ipfs_sel.iterdir()):
    if not f.is_file():
        continue
    item = {
        "name": f.name,
        "file": str(f),
        "suffix": f.suffix.lower()
    }

    if f.suffix.lower() == ".csv":
        try:
            df = pd.read_csv(f)
            item["n_rows"] = int(len(df))
            item["n_cols"] = int(len(df.columns))
            item["columns"] = [str(c) for c in df.columns]
            item["preview"] = df.head(8).fillna("").astype(str).to_dict(orient="records")
            num_cols = df.select_dtypes(include=["number"]).columns.tolist()
            item["numeric_columns"] = [str(c) for c in num_cols]
            stats = {}
            for c in num_cols[:20]:
                vals = [float(v) for v in df[c].dropna().tolist()]
                if vals:
                    stats[str(c)] = {
                        "avg": sum(vals)/len(vals),
                        "min": min(vals),
                        "max": max(vals),
                        "p50": pct(vals, 0.50),
                        "p95": pct(vals, 0.95)
                    }
            item["numeric_stats"] = stats
        except Exception as e:
            item["read_error"] = str(e)

    elif f.suffix.lower() == ".json":
        try:
            obj = json.loads(f.read_text())
            if isinstance(obj, dict):
                item["top_level_type"] = "dict"
                item["top_level_keys"] = list(obj.keys())[:40]
            elif isinstance(obj, list):
                item["top_level_type"] = "list"
                item["length"] = len(obj)
                if obj:
                    item["first_item_type"] = type(obj[0]).__name__
                    if isinstance(obj[0], dict):
                        item["first_item_keys"] = list(obj[0].keys())[:40]
            else:
                item["top_level_type"] = type(obj).__name__
        except Exception as e:
            item["read_error"] = str(e)

    ipfs_reports.append(item)

(ipfs_audit / "IPFS_AUDIT.json").write_text(json.dumps(ipfs_reports, indent=2))

summary = {
    "bundle": str(bundle),
    "caliper_selected_dir": str(cal_sel),
    "ipfs_selected_dir": str(ipfs_sel),
    "caliper_report_count": len(caliper_reports),
    "ipfs_file_count": len(ipfs_reports),
    "caliper_reports": [
        {
            "name": r["name"],
            "n_tables": len(r.get("tables", [])),
            "table_csvs": [t["csv"] for t in r.get("tables", [])[:10]],
            "sample_snippets": r.get("snippets", [])[:5]
        }
        for r in caliper_reports
    ],
    "ipfs_files": [
        {
            "name": r["name"],
            "suffix": r.get("suffix"),
            "n_rows": r.get("n_rows"),
            "columns": r.get("columns", [])[:20],
            "top_level_keys": r.get("top_level_keys", [])
        }
        for r in ipfs_reports
    ],
    "caliper_audit_json": str(cal_audit / "CALIPER_AUDIT.json"),
    "ipfs_audit_json": str(ipfs_audit / "IPFS_AUDIT.json")
}

(manifest / "SOURCE_AUDIT_SUMMARY.json").write_text(json.dumps(summary, indent=2))

print("BUNDLE=", bundle)
print("SOURCE_AUDIT_SUMMARY=", manifest / "SOURCE_AUDIT_SUMMARY.json")
print("CALIPER_AUDIT=", cal_audit / "CALIPER_AUDIT.json")
print("IPFS_AUDIT=", ipfs_audit / "IPFS_AUDIT.json")
PY
