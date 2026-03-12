#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }

START_ROUND="${START_ROUND:-1}"
END_ROUND="${END_ROUND:-5}"
BASE_FABRIC="${BASE_FABRIC:-81000}"

PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"
BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
ATTACK_MODE="${ATTACK_MODE:-label_flip}"

N_CLIENTS=$(wc -l < "$MAP" | tr -d ' ')
[ "$N_CLIENTS" -ge 1 ] || { echo "ERROR: map vide"; exit 1; }

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "ROUNDS=$START_ROUND..$END_ROUND"
echo "BASE_FABRIC=$BASE_FABRIC"
echo "PEER_HOST=$PEER_HOST"
echo "MSP=$MSP"
echo "BYZ_CLIENTS=$BYZ_CLIENTS"
echo "ATTACK_MODE=$ATTACK_MODE"
echo "N_CLIENTS=$N_CLIENTS"

mkdir -p "$RUN_DIR/p8_labelflip"
mkdir -p "$RUN_DIR/summary"

run_round() {
  local r="$1"
  local start_fab="$2"

  local round_dir="$RUN_DIR/p8_labelflip/round$(printf '%02d' "$r")"
  local logs_dir="$round_dir/client_logs"
  mkdir -p "$logs_dir"
  : > "$round_dir/failures.txt"

  echo
  echo "=============================="
  echo "RUN label-flip N=$N_CLIENTS round=$r START_FABRIC=$start_fab"
  echo "=============================="

  local i=0
  local ok=0
  local fail=0

  while read -r cid ip; do
    [ -n "${cid:-}" ] || continue
    [ -n "${ip:-}" ] || continue

    local fab=$(( start_fab + i ))
    local out_runfl="$logs_dir/${cid}.runfl.out"

    echo
    echo "===== $cid @ $ip FABRIC_ROUND=$fab ====="

    set +e
    ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" \
      "ATTACK_MODE=$ATTACK_MODE BYZ_CLIENTS=\"$BYZ_CLIENTS\" timeout 300 /opt/fl-client/run_fl_round.sh $cid $r $MSP $PEER_HOST $fab" \
      >"$out_runfl" 2>&1 </dev/null
    local rc=$?
    set -e

    echo "RC=$rc"
    if [ "$rc" -eq 0 ]; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
      echo "$cid $ip $fab rc=$rc" >> "$round_dir/failures.txt"
      tail -n 80 "$out_runfl" || true
    fi

    i=$((i+1))
  done < <(sort -V "$MAP")

  echo
  echo "SUMMARY OK=$ok FAIL=$fail"
  if [ "$fail" -ne 0 ]; then
    echo "ERROR: failures saved to $round_dir/failures.txt"
    exit 1
  fi

  TS=$(date -u +%Y%m%d_%H%M%S)
  OUT_CSV="$RUN_DIR/summary/p8_labelflip_round$(printf '%02d' "$r")_clients_${TS}.csv"
  OUT_JSON="$RUN_DIR/summary/p8_labelflip_round$(printf '%02d' "$r")_summary_${TS}.json"

  python3 - "$MAP" "$logs_dir" "$OUT_CSV" "$OUT_JSON" "$r" "$BYZ_CLIENTS" <<'PY'
import sys, re, csv, json, math
from pathlib import Path

map_path = Path(sys.argv[1])
logs_dir = Path(sys.argv[2])
out_csv  = Path(sys.argv[3])
out_json = Path(sys.argv[4])
round_num = int(sys.argv[5])
byz_set = set(sys.argv[6].split())

c2ip = {}
for line in map_path.read_text().splitlines():
    line=line.strip()
    if not line:
        continue
    c, ip = line.split()
    c2ip[c]=ip

rx_main = re.compile(r'\[(?P<cid>edge-client-\d+)\].*fabric_round=(?P<fab>\d+).*F1=(?P<f1>[0-9.]+).*FPR=(?P<fpr>[0-9.]+).*OK')
rx_lat  = re.compile(r'ipfs=(?P<ipfs>[0-9.]+)ms\s+tx=(?P<tx>[0-9.]+)ms\s+total=(?P<tot>[0-9.]+)ms')

rows=[]
for f in sorted(logs_dir.glob("edge-client-*.runfl.out"), key=lambda p: [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', p.name)]):
    txt = f.read_text(errors="ignore")
    m = rx_main.search(txt)
    cid = f.name.replace(".runfl.out","")
    ip = c2ip.get(cid,"")
    is_byz = 1 if cid in byz_set else 0
    fab=f1=fpr=None
    ipfs=tx=tot=None
    if m:
        fab=int(m.group("fab"))
        f1=float(m.group("f1"))
        fpr=float(m.group("fpr"))
    m2 = rx_lat.search(txt)
    if m2:
        ipfs=float(m2.group("ipfs"))
        tx=float(m2.group("tx"))
        tot=float(m2.group("tot"))
    rows.append({
        "round": round_num,
        "client_id": cid,
        "ip": ip,
        "fabric_round": fab,
        "is_byz": is_byz,
        "f1": f1,
        "fpr": fpr,
        "ipfs_ms": ipfs,
        "tx_ms": tx,
        "total_ms": tot
    })

with out_csv.open("w", newline="") as fp:
    w=csv.DictWriter(fp, fieldnames=list(rows[0].keys()) if rows else ["round","client_id","ip","fabric_round","is_byz","f1","fpr","ipfs_ms","tx_ms","total_ms"])
    w.writeheader()
    for r in rows:
        w.writerow(r)

def stats(vals):
    vals=[v for v in vals if v is not None]
    if not vals:
        return None
    vals=sorted(vals)
    n=len(vals)
    avg=sum(vals)/n
    var=sum((x-avg)*(x-avg) for x in vals)/n
    def pct(p):
        if n==1:
            return vals[0]
        k=(n-1)*p
        lo=int(math.floor(k))
        hi=int(math.ceil(k))
        if lo==hi:
            return vals[lo]
        return vals[lo] + (vals[hi]-vals[lo])*(k-lo)
    return {
        "avg": avg,
        "std": math.sqrt(var),
        "min": vals[0],
        "max": vals[-1],
        "p50": pct(0.50),
        "p95": pct(0.95),
        "p99": pct(0.99),
        "n": n
    }

byz = [r for r in rows if r["is_byz"]==1]
hon = [r for r in rows if r["is_byz"]==0]

summary = {
    "round": round_num,
    "n_clients": len(rows),
    "byz_clients": sorted(list(byz_set)),
    "attack_mode": "label_flip",
    "f1_all": stats([r["f1"] for r in rows]),
    "fpr_all": stats([r["fpr"] for r in rows]),
    "f1_byz": stats([r["f1"] for r in byz]),
    "fpr_byz": stats([r["fpr"] for r in byz]),
    "f1_honest": stats([r["f1"] for r in hon]),
    "fpr_honest": stats([r["fpr"] for r in hon]),
    "ipfs_ms": stats([r["ipfs_ms"] for r in rows]),
    "tx_ms": stats([r["tx_ms"] for r in rows]),
    "total_ms": stats([r["total_ms"] for r in rows]),
    "files": {"csv": str(out_csv), "json": str(out_json)}
}

out_json.write_text(json.dumps(summary, indent=2))

print("OK")
print("CSV=", str(out_csv))
print("JSON=", str(out_json))
print("F1_BYZ=", summary["f1_byz"])
print("F1_HONEST=", summary["f1_honest"])
print("FPR_BYZ=", summary["fpr_byz"])
print("FPR_HONEST=", summary["fpr_honest"])
PY
}

for r in $(seq "$START_ROUND" "$END_ROUND"); do
  off=$(( (r - START_ROUND) * N_CLIENTS ))
  start_fab=$(( BASE_FABRIC + off ))
  run_round "$r" "$start_fab"
done

TS=$(date -u +%Y%m%d_%H%M%S)
TABLE="$RUN_DIR/summary/p8_labelflip_1_5_table_${TS}.csv"
POOLED="$RUN_DIR/summary/p8_labelflip_all_rounds_${TS}.json"

python3 - "$RUN_DIR/summary" "$TABLE" "$POOLED" <<'PY'
import sys, re, json, csv, math
from pathlib import Path

sdir=Path(sys.argv[1])
table=Path(sys.argv[2])
pooled=Path(sys.argv[3])

pat=re.compile(r'p8_labelflip_round(\d+)_clients_.*\.csv$')
files=[]
for p in sorted(sdir.glob("p8_labelflip_round*_clients_*.csv")):
    m=pat.match(p.name)
    if m:
        files.append((int(m.group(1)), p))

latest={}
for r,p in files:
    latest[r]=p
picked=[latest[r] for r in sorted(latest.keys())]

rows=[]
for p in picked:
    with p.open() as f:
        rd=csv.DictReader(f)
        for row in rd:
            for k in ["round","fabric_round","is_byz"]:
                if row.get(k) not in (None,""):
                    row[k]=int(float(row[k]))
            for k in ["f1","fpr","ipfs_ms","tx_ms","total_ms"]:
                if row.get(k) in (None,""):
                    row[k]=None
                else:
                    row[k]=float(row[k])
            rows.append(row)

with table.open("w", newline="") as fp:
    w=csv.DictWriter(fp, fieldnames=rows[0].keys() if rows else [])
    if rows:
        w.writeheader()
        for r in rows:
            w.writerow(r)

def stats(vals):
    vals=[v for v in vals if v is not None]
    if not vals:
        return None
    vals=sorted(vals)
    n=len(vals)
    avg=sum(vals)/n
    var=sum((x-avg)*(x-avg) for x in vals)/n
    def pct(p):
        if n==1:
            return vals[0]
        k=(n-1)*p
        lo=int(math.floor(k))
        hi=int(math.ceil(k))
        if lo==hi:
            return vals[lo]
        return vals[lo] + (vals[hi]-vals[lo])*(k-lo)
    return {
        "avg": avg,
        "std": math.sqrt(var),
        "min": vals[0],
        "max": vals[-1],
        "p50": pct(0.50),
        "p95": pct(0.95),
        "p99": pct(0.99),
        "n": n
    }

hon=[r for r in rows if r["is_byz"]==0]
byz=[r for r in rows if r["is_byz"]==1]

summary = {
    "scenario": "label_flip",
    "rounds": sorted({r["round"] for r in rows}),
    "n_rows": len(rows),
    "n_honest_rows": len(hon),
    "n_byz_rows": len(byz),
    "f1_all": stats([r["f1"] for r in rows]),
    "f1_honest": stats([r["f1"] for r in hon]),
    "f1_byz": stats([r["f1"] for r in byz]),
    "fpr_all": stats([r["fpr"] for r in rows]),
    "fpr_honest": stats([r["fpr"] for r in hon]),
    "fpr_byz": stats([r["fpr"] for r in byz]),
    "ipfs_ms": stats([r["ipfs_ms"] for r in rows]),
    "tx_ms": stats([r["tx_ms"] for r in rows]),
    "total_ms": stats([r["total_ms"] for r in rows]),
    "inputs": [str(p) for p in picked]
}

pooled.write_text(json.dumps(summary, indent=2))
print("OK")
print("TABLE_CSV=", str(table))
print("POOLED_JSON=", str(pooled))
PY
