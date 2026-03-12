#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

START_ROUND="${START_ROUND:-1}"
END_ROUND="${END_ROUND:-5}"
BASE_FABRIC="${BASE_FABRIC:-110000}"

PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"

OUT_ROOT="$RUN_DIR/p12_scaling"
mkdir -p "$OUT_ROOT"

declare -A C2IP
while read -r c ip; do
  [ -n "${c:-}" ] && [ -n "${ip:-}" ] && C2IP["$c"]="$ip"
done < "$MAP"

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

for r in $(seq "$START_ROUND" "$END_ROUND"); do
  fab_start=$((BASE_FABRIC + (r-START_ROUND)*20))
  out_round="$OUT_ROOT/round$(printf '%02d' "$r")"
  mkdir -p "$out_round/client_logs"
  echo
  echo "=============================="
  echo "RUN scaling N=20 round=$r START_FABRIC=$fab_start"
  echo "=============================="

  ok=0
  fail=0

  for i in $(seq 1 20); do
    cid="edge-client-$i"
    ip="${C2IP[$cid]}"
    fab=$((fab_start + (i-1)))

    out_runfl="$out_round/client_logs/${cid}.runfl.out"
    out_fab="$out_round/client_logs/${cid}.fl_fabric.out"

    echo
    echo "===== $cid @ $ip FABRIC_ROUND=$fab ====="

    ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" \
      "timeout 300 /opt/fl-client/run_fl_round.sh $cid $r $MSP $PEER_HOST $fab" \
      >"$out_runfl" 2>&1 </dev/null || true

    if grep -q " OK" "$out_runfl"; then
      echo "RC=0"
      ok=$((ok+1))
    else
      echo "RC=1"
      fail=$((fail+1))
    fi

    ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" \
      "ls -1t /opt/fl-client/logs/fl_fabric_${cid}_r${r}.out 2>/dev/null | head -n 1 | xargs -r tail -n 120" \
      >"$out_fab" 2>&1 </dev/null || true
  done

  echo
  echo "SUMMARY OK=$ok FAIL=$fail"
  if [ "$fail" -ne 0 ]; then
    echo "ERROR: failures in $out_round"
    exit 1
  fi

  SUM_DIR="$RUN_DIR/summary"
  mkdir -p "$SUM_DIR"
  TS=$(date -u +%Y%m%d_%H%M%S)
  OUT_CSV="$SUM_DIR/p12_scaling_round$(printf '%02d' "$r")_clients_${TS}.csv"
  OUT_JSON="$SUM_DIR/p12_scaling_round$(printf '%02d' "$r")_summary_${TS}.json"

  python3 - "$MAP" "$out_round/client_logs" "$OUT_CSV" "$OUT_JSON" "$BYZ_CLIENTS" "$r" <<'PY'
import sys, csv, json, re, math
from pathlib import Path

mp = Path(sys.argv[1])
logdir = Path(sys.argv[2])
out_csv = Path(sys.argv[3])
out_json = Path(sys.argv[4])
byz = set(sys.argv[5].split())
round_num = int(sys.argv[6])

def pct(vals, p):
    if not vals: return None
    s=sorted(vals)
    k=(len(s)-1)*p/100.0
    f=math.floor(k); c=math.ceil(k)
    if f==c: return float(s[int(k)])
    return float(s[f] + (s[c]-s[f])*(k-f))

rows=[]
for p in sorted(logdir.glob("edge-client-*.runfl.out")):
    txt=p.read_text(errors="ignore")
    m=re.search(r'^\[(edge-client-\d+)\]\s+round=(\d+)\s+fabric_round=(\d+)\s+CID=([A-Za-z0-9]+)\.\.\.\s+F1=([0-9.]+)\s+FPR=([0-9.]+)\s+OK', txt, flags=re.M)
    if not m:
        continue
    cid=m.group(1)
    fab=int(m.group(3))
    f1=float(m.group(5))
    fpr=float(m.group(6))
    role="byz" if cid in byz else "honest"
    rows.append({"client_id":cid,"fabric_round":fab,"f1":f1,"fpr":fpr,"role":role})

rows=sorted(rows, key=lambda r: r["fabric_round"])

with out_csv.open("w", newline="") as f:
    w=csv.DictWriter(f, fieldnames=["client_id","fabric_round","role","f1","fpr"])
    w.writeheader()
    w.writerows(rows)

byz_f1=[r["f1"] for r in rows if r["role"]=="byz"]
hon_f1=[r["f1"] for r in rows if r["role"]=="honest"]
byz_fpr=[r["fpr"] for r in rows if r["role"]=="byz"]
hon_fpr=[r["fpr"] for r in rows if r["role"]=="honest"]

def pack(vals):
    if not vals: return None
    avg=sum(vals)/len(vals)
    var=sum((x-avg)**2 for x in vals)/len(vals)
    return {"avg":avg,"std":math.sqrt(var),"min":min(vals),"max":max(vals),"p50":pct(vals,50),"p95":pct(vals,95),"p99":pct(vals,99),"n":len(vals)}

out={
  "round": round_num,
  "n_clients": len(rows),
  "byz_clients": sorted(byz),
  "f1_byz": pack(byz_f1),
  "f1_honest": pack(hon_f1),
  "fpr_byz": pack(byz_fpr),
  "fpr_honest": pack(hon_fpr),
  "files": {"csv": str(out_csv), "json": str(out_json)},
}
out_json.write_text(json.dumps(out, indent=2))

print("OK")
print("CSV=", out_csv)
print("JSON=", out_json)
print("F1_BYZ=", out["f1_byz"])
print("F1_HONEST=", out["f1_honest"])
print("FPR_BYZ=", out["fpr_byz"])
print("FPR_HONEST=", out["fpr_honest"])
PY
done

echo OK
