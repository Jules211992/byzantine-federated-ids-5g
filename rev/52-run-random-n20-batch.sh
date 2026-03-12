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
BASE_FABRIC="${BASE_FABRIC:-6000000}"

PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"

OUT_ROOT="$RUN_DIR/p14_random"
mkdir -p "$OUT_ROOT"
mkdir -p "$RUN_DIR/summary"

declare -A C2IP
while read -r c ip; do
  [ -n "${c:-}" ] && [ -n "${ip:-}" ] && C2IP["$c"]="$ip"
done < "$MAP"

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

for r in $(seq "$START_ROUND" "$END_ROUND"); do
  fab_start=$((BASE_FABRIC + (r-START_ROUND)*20))
  round_dir="$OUT_ROOT/round$(printf '%02d' "$r")"
  logs_dir="$round_dir/client_logs"
  mkdir -p "$logs_dir"

  echo
  echo "=============================="
  echo "RUN random N=20 round=$r START_FABRIC=$fab_start"
  echo "=============================="

  failures="$round_dir/failures.txt"
  : > "$failures"

  TS=$(date -u +%Y%m%d_%H%M%S)
  out_csv="$RUN_DIR/summary/p14_random_round$(printf '%02d' "$r")_clients_${TS}.csv"
  out_json="$RUN_DIR/summary/p14_random_round$(printf '%02d' "$r")_summary_${TS}.json"

  echo "round,client_id,ip,fabric_round,rc,cid,f1,fpr,ipfs_ms,tx_ms,total_ms" > "$out_csv"

  for c in $(awk '{print $1}' "$MAP"); do
    ip="${C2IP[$c]}"
    fab=$((fab_start + ${c#edge-client-} - 1))

    out_runfl="$logs_dir/runfl_${c}_r${r}.out"
    out_ids="$logs_dir/fl-ids-${c}-r${r}.json"
    out_fabric="$logs_dir/fl_fabric_${c}_r${r}.out"

    echo
    echo "===== $c @ $ip FABRIC_ROUND=$fab ====="

    set +e
    ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" \
      "timeout 240 /opt/fl-client/run_fl_round.sh $c $r $MSP $PEER_HOST $fab" >"$out_runfl" 2>&1 </dev/null
    rc=$?
    set -e
    echo "RC=$rc"

    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl-ids-${c}-r${r}.json" "$out_ids" >/dev/null 2>&1 || true
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip":"/opt/fl-client/logs/fl_fabric_${c}_r${r}.out" "$out_fabric" >/dev/null 2>&1 || true

    if [ "$rc" -ne 0 ]; then
      echo "$c $ip rc=$rc fab=$fab" >> "$failures"
    fi

    python3 - "$r" "$c" "$ip" "$fab" "$rc" "$out_ids" "$out_fabric" >> "$out_csv" <<'PY'
import sys, json, re
r, c, ip, fab, rc, p_ids, p_fab = sys.argv[1:8]

cid=""
f1=""
fpr=""
ipfs_ms=""
tx_ms=""
total_ms=""

try:
    j=json.load(open(p_ids))
    cid = j.get("cid","")
    f1  = j.get("test_metrics",{}).get("f1","")
    fpr = j.get("test_metrics",{}).get("fpr","")
    ipfs_ms = j.get("latencies",{}).get("ipfs_add_ms","")
except Exception:
    pass

try:
    txt=open(p_fab, errors="ignore").read()
    m=re.search(r'avg=([0-9.]+)ms', txt)
    if m:
        tx_ms=float(m.group(1))
except Exception:
    tx_ms=""

try:
    if ipfs_ms != "" and tx_ms != "":
        total_ms=float(ipfs_ms)+float(tx_ms)
except Exception:
    total_ms=""

def s(x):
    if x is None: return ""
    if isinstance(x,(int,float)): return str(x)
    return str(x)

print(f"{r},{c},{ip},{fab},{rc},{cid},{s(f1)},{s(fpr)},{s(ipfs_ms)},{s(tx_ms)},{s(total_ms)}")
PY
  done

  python3 - "$out_csv" "$out_json" "$BYZ_CLIENTS" "$r" <<'PY'
import sys, csv, json, math
p_csv, p_json, byz, r = sys.argv[1], sys.argv[2], sys.argv[3].split(), int(sys.argv[4])
byz=set(byz)

rows=[]
with open(p_csv, newline="") as f:
    rd=csv.DictReader(f)
    for row in rd:
        rows.append(row)

def tofloat(x):
    try: return float(x)
    except: return None

def stats(vals):
    vals=[v for v in vals if v is not None]
    if not vals: return None
    avg=sum(vals)/len(vals)
    var=sum((v-avg)**2 for v in vals)/len(vals)
    s=sorted(vals)
    def pct(p):
        k=(len(s)-1)*(p/100.0)
        f=math.floor(k); c=math.ceil(k)
        if f==c: return s[int(k)]
        return s[f]*(c-k)+s[c]*(k-f)
    return {"avg":avg,"std":math.sqrt(var),"min":min(vals),"max":max(vals),"p50":pct(50),"p95":pct(95),"p99":pct(99),"n":len(vals)}

byz_f1=[tofloat(rw.get("f1","")) for rw in rows if rw.get("client_id","") in byz]
hon_f1=[tofloat(rw.get("f1","")) for rw in rows if rw.get("client_id","") and rw.get("client_id","") not in byz]
byz_fpr=[tofloat(rw.get("fpr","")) for rw in rows if rw.get("client_id","") in byz]
hon_fpr=[tofloat(rw.get("fpr","")) for rw in rows if rw.get("client_id","") and rw.get("client_id","") not in byz]

ipfs=[tofloat(rw.get("ipfs_ms","")) for rw in rows]
tx=[tofloat(rw.get("tx_ms","")) for rw in rows]
tot=[tofloat(rw.get("total_ms","")) for rw in rows]

out={
  "round": r,
  "n_clients": len(rows),
  "byz_clients": sorted(list(byz)),
  "f1_byz": stats(byz_f1),
  "f1_honest": stats(hon_f1),
  "fpr_byz": stats(byz_fpr),
  "fpr_honest": stats(hon_fpr),
  "ipfs_ms": stats(ipfs),
  "tx_ms": stats(tx),
  "total_ms": stats(tot),
  "files": {"csv": p_csv}
}

json.dump(out, open(p_json,"w"), indent=2)
print("OK")
print("CSV=", p_csv)
print("JSON=", p_json)
print("F1_BYZ=", out["f1_byz"])
print("F1_HONEST=", out["f1_honest"])
print("FPR_BYZ=", out["fpr_byz"])
print("FPR_HONEST=", out["fpr_honest"])
PY

  ok=$(tail -n +2 "$out_csv" | awk -F',' '$5==0{c++} END{print c+0}')
  fail=$(tail -n +2 "$out_csv" | awk -F',' '$5!=0{c++} END{print c+0}')
  echo "SUMMARY OK=$ok FAIL=$fail"
  [ "$fail" -eq 0 ] || echo "ERROR: failures in $round_dir"
done

echo DONE
