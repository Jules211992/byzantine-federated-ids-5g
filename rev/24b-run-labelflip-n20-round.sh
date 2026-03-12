#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
PEER_HOST=${PEER_HOST:-peer0.org1.example.com}
MSP=${MSP:-Org1MSP}

ROUND=${ROUND:-1}
START_FABRIC=${START_FABRIC:-70000}
BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }

RDIR="$RUN_DIR/p8_attacks/label_flip/round$(printf '%02d' "$ROUND")"
LOGS="$RDIR/client_logs"
mkdir -p "$LOGS" "$RUN_DIR/summary"

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "ROUND=$ROUND"
echo "START_FABRIC=$START_FABRIC"
echo "PEER_HOST=$PEER_HOST"
echo "MSP=$MSP"
echo "BYZ_CLIENTS=$BYZ_CLIENTS"
echo "OUT=$RDIR"
echo

i=0
ok=0
fail=0
: > "$LOGS/failures.txt"

while read -r c ip; do
  [ -z "${c:-}" ] && continue
  [ -z "${ip:-}" ] && continue

  fr=$((START_FABRIC + i))
  i=$((i+1))

  echo "===== $c @ $ip FABRIC_ROUND=$fr ====="

  set +e
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=12 ubuntu@"$ip" \
    "/opt/fl-client/run_fl_round.sh $c $ROUND $MSP $PEER_HOST $fr" \
    > "$LOGS/$c.runfl.out" 2>&1
  rc=$?
  set -e

  echo "$rc" > "$LOGS/$c.rc"
  echo "RC=$rc"

  if [ "$rc" -ne 0 ]; then
    fail=$((fail+1))
    echo "$c $ip rc=$rc" >> "$LOGS/failures.txt"
  else
    ok=$((ok+1))
  fi

  set +e
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_fabric_${c}_r${ROUND}.out" \
    "$LOGS/$c.fl_fabric.out" >/dev/null 2>&1
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_client_${c}_r${ROUND}.out" \
    "$LOGS/$c.fl_client.out" >/dev/null 2>&1
  set -e

  echo
done < "$MAP"

echo "SUMMARY OK=$ok FAIL=$fail"
[ "$fail" -eq 0 ] || { echo "ERROR: failures in $LOGS/failures.txt"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$RUN_DIR/summary/p8_labelflip_round$(printf '%02d' "$ROUND")_clients_${TS}.csv"
OUT_JSON="$RUN_DIR/summary/p8_labelflip_round$(printf '%02d' "$ROUND")_summary_${TS}.json"

python3 - "$OUT_CSV" "$OUT_JSON" "$LOGS" "$ROUND" "$BYZ_CLIENTS" <<'PY'
import sys, re, csv, json
from pathlib import Path
import statistics as st

out_csv = Path(sys.argv[1])
out_json = Path(sys.argv[2])
logs = Path(sys.argv[3])
round_num = int(sys.argv[4])
byz = set(sys.argv[5].split())

rx_run = re.compile(r'\[(?P<c>[^\]]+)\].*?CID=(?P<cid>\S+).*?F1=(?P<f1>[0-9.]+).*?FPR=(?P<fpr>[0-9.]+)', re.I)
rx_fab = re.compile(r'ipfs=(?P<ipfs>[0-9.]+)ms\s+tx=(?P<tx>[0-9.]+)ms\s+total=(?P<tot>[0-9.]+)ms', re.I)
rx_fr  = re.compile(r'round=(?P<fr>[0-9]+)')

rows=[]
for p in sorted(logs.glob("*.runfl.out")):
    c = p.name.replace(".runfl.out","")
    txt = p.read_text(errors="ignore")
    m = rx_run.search(txt)
    cid=f1=fpr=None
    if m:
        cid=m.group("cid")
        f1=float(m.group("f1"))
        fpr=float(m.group("fpr"))
    fab_p = logs / f"{c}.fl_fabric.out"
    ipfs=tx=tot=fr=None
    if fab_p.exists():
        ft = fab_p.read_text(errors="ignore")
        mf = rx_fab.search(ft)
        if mf:
            ipfs=float(mf.group("ipfs"))
            tx=float(mf.group("tx"))
            tot=float(mf.group("tot"))
        mfr = rx_fr.search(ft)
        if mfr:
            fr=int(mfr.group("fr"))
    rc_p = logs / f"{c}.rc"
    rc = int(rc_p.read_text().strip()) if rc_p.exists() else None
    rows.append({
        "round": round_num,
        "client_id": c,
        "is_byz": int(c in byz),
        "fabric_round": fr,
        "cid": cid,
        "f1": f1,
        "fpr": fpr,
        "ipfs_ms": ipfs,
        "tx_ms": tx,
        "total_ms": tot,
        "rc": rc
    })

out_csv.parent.mkdir(parents=True, exist_ok=True)
with out_csv.open("w", newline="") as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

def pct(vals, p):
    vals=[v for v in vals if v is not None]
    if not vals: return None
    vals=sorted(vals)
    k=(len(vals)-1)*p/100.0
    f=int(k); c=min(f+1, len(vals)-1)
    if f==c: return vals[f]
    return vals[f] + (vals[c]-vals[f])*(k-f)

def stats_block(rows, key):
    vals=[r[key] for r in rows if r[key] is not None]
    if not vals:
        return None
    return {
        "avg": sum(vals)/len(vals),
        "std": st.pstdev(vals) if len(vals)>1 else 0.0,
        "min": min(vals),
        "max": max(vals),
        "p50": pct(vals,50),
        "p95": pct(vals,95),
        "p99": pct(vals,99),
        "n": len(vals)
    }

byz_rows=[r for r in rows if r["is_byz"]==1]
hon_rows=[r for r in rows if r["is_byz"]==0]

summary = {
    "round": round_num,
    "n_clients": len(rows),
    "byz_clients": sorted(list(byz)),
    "f1_all": stats_block(rows,"f1"),
    "fpr_all": stats_block(rows,"fpr"),
    "f1_byz": stats_block(byz_rows,"f1"),
    "fpr_byz": stats_block(byz_rows,"fpr"),
    "f1_honest": stats_block(hon_rows,"f1"),
    "fpr_honest": stats_block(hon_rows,"fpr"),
    "ipfs_ms": stats_block(rows,"ipfs_ms"),
    "tx_ms": stats_block(rows,"tx_ms"),
    "total_ms": stats_block(rows,"total_ms"),
    "files": {"csv": str(out_csv), "json": str(out_json)}
}
out_json.write_text(json.dumps(summary, indent=2))
print("OK")
print("CSV=", out_csv)
print("JSON=", out_json)
print("F1_BYZ=", summary["f1_byz"])
print("F1_HONEST=", summary["f1_honest"])
print("FPR_BYZ=", summary["fpr_byz"])
print("FPR_HONEST=", summary["fpr_honest"])
PY
