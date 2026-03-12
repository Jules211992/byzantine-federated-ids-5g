#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
PEER_HOST=${PEER1_HOST:-peer0.org1.example.com}
MSP=${MSP_DEFAULT:-Org1MSP}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -z "${RUN_DIR:-}" ] && { echo "ERROR: aucun RUN_DIR rev_*_5g"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ ! -f "$MAP" ] && { echo "ERROR: map introuvable: $MAP"; exit 1; }

ROUND=${ROUND:-1}
START_FABRIC=${START_FABRIC:-20000}
FABRIC_ROUND=$((START_FABRIC + ROUND - 1))

OUT_DIR="$RUN_DIR/p7_baseline/round$(printf '%02d' "$ROUND")"
mkdir -p "$OUT_DIR"/{edge_logs,clients,summary}

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "ROUND=$ROUND"
echo "FABRIC_ROUND=$FABRIC_ROUND"
echo "PEER_HOST=$PEER_HOST"
echo "MSP=$MSP"
echo

python3 - <<'PY' "$MAP" > "$OUT_DIR/plan.json"
import json, sys
mp=sys.argv[1]
plan={}
with open(mp) as f:
    for line in f:
        line=line.strip()
        if not line: 
            continue
        cid, ip = line.split()
        plan.setdefault(ip, []).append(cid)
for ip in plan:
    plan[ip]=sorted(plan[ip], key=lambda s: int(s.split("-")[-1]))
print(json.dumps(plan, indent=2))
PY

echo "PLAN:"
cat "$OUT_DIR/plan.json"
echo

FAIL=0
PIDS=()

while read -r ip; do
  [ -z "${ip:-}" ] && continue
  clients=$(python3 - <<'PY' "$OUT_DIR/plan.json" "$ip"
import json, sys
plan=json.load(open(sys.argv[1]))
ip=sys.argv[2]
print(" ".join(plan.get(ip, [])))
PY
)
  [ -z "${clients:-}" ] && continue

  (
    echo "EDGE=$ip CLIENTS=$clients"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
for cid in $clients; do
  bash /opt/fl-client/run_fl_round.sh \$cid $ROUND $MSP $PEER_HOST $FABRIC_ROUND
done
"
  ) > "$OUT_DIR/edge_logs/edge_${ip}.log" 2>&1 &

  PIDS+=("$!")
done < <(python3 - <<'PY' "$OUT_DIR/plan.json"
import json, sys
plan=json.load(open(sys.argv[1]))
for ip in sorted(plan.keys()):
    print(ip)
PY
)

for pid in "${PIDS[@]}"; do
  wait "$pid" || FAIL=1
done

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "ERROR: au moins un EDGE a échoué. Voir $OUT_DIR/edge_logs/"
  exit 1
fi

echo
echo "=== Collect 20 client json logs ==="
OKN=0
BADN=0
while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  [ -z "${ip:-}" ] && continue
  SRC="/opt/fl-client/logs/fl-ids-${cid}-r${ROUND}.json"
  DST="$OUT_DIR/clients/${cid}.json"
  if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip":"$SRC" "$DST" >/dev/null 2>&1; then
    OKN=$((OKN+1))
  else
    echo "MISSING $cid from $ip ($SRC)"
    BADN=$((BADN+1))
  fi
done < "$MAP"

echo "COLLECT_OK=$OKN COLLECT_MISSING=$BADN"
[ "$BADN" -ne 0 ] && exit 1

echo
echo "=== Build baseline summary (FedAvg) ==="
python3 - <<'PY' "$OUT_DIR/clients" "$RUN_DIR/splits_20" "$OUT_DIR/summary/p7_baseline_round$(printf "%02d" "$ROUND").json"
import os, sys, json, glob, math
import numpy as np

clients_dir=sys.argv[1]
splits_dir=sys.argv[2]
out_json=sys.argv[3]

paths=sorted(glob.glob(os.path.join(clients_dir,"edge-client-*.json")), key=lambda p: int(os.path.basename(p).split("-")[-1].split(".")[0]))
if len(paths)!=20:
    raise SystemExit(f"expected 20 client logs, got {len(paths)}")

items=[]
for p in paths:
    j=json.load(open(p))
    items.append(j)

w=np.array([j["weights"] for j in items], dtype=float)
b=np.array([j["bias"] for j in items], dtype=float)
w_avg=w.mean(axis=0)
b_avg=float(b.mean())

Xg=None
yg=None
gx=os.path.join(splits_dir,"global_test_X.npy")
gy=os.path.join(splits_dir,"global_test_y.npy")
if os.path.isfile(gx) and os.path.isfile(gy):
    Xg=np.load(gx, mmap_mode="r")
    yg=np.load(gy, mmap_mode="r")
else:
    Xs=[]
    ys=[]
    for cid in range(1,21):
        Xs.append(np.load(os.path.join(splits_dir,f"edge-client-{cid}_test_X.npy"), mmap_mode="r"))
        ys.append(np.load(os.path.join(splits_dir,f"edge-client-{cid}_test_y.npy"), mmap_mode="r"))
    Xg=np.vstack(Xs)
    yg=np.concatenate(ys)

z=Xg.dot(w_avg)+b_avg
p=1/(1+np.exp(-z))
yhat=(p>=0.5).astype(int)
ytrue=yg.astype(int)

tp=int(((yhat==1)&(ytrue==1)).sum())
tn=int(((yhat==0)&(ytrue==0)).sum())
fp=int(((yhat==1)&(ytrue==0)).sum())
fn=int(((yhat==0)&(ytrue==1)).sum())

acc=(tp+tn)/max(1,(tp+tn+fp+fn))
prec=tp/max(1,(tp+fp))
rec=tp/max(1,(tp+fn))
f1=(2*prec*rec)/max(1e-12,(prec+rec))
fpr=fp/max(1,(fp+tn))

out={
  "phase":"P7_BASELINE",
  "round": int(os.path.basename(out_json).split("round")[-1].split(".")[0]),
  "n_clients": 20,
  "fedavg": {
    "weights_dim": int(w_avg.shape[0]),
    "bias": b_avg
  },
  "global_metrics": {
    "accuracy": round(acc, 4),
    "f1": round(f1, 4),
    "precision": round(prec, 4),
    "recall": round(rec, 4),
    "fpr": round(fpr, 4),
    "tp": tp, "fp": fp, "fn": fn, "tn": tn,
    "n_samples": int(len(ytrue))
  }
}

json.dump(out, open(out_json,"w"), indent=2)
print("SAVED", out_json)
print(json.dumps(out, indent=2)[:1200])
PY

echo
echo "OK: baseline smoke done"
echo "EDGE_LOGS=$OUT_DIR/edge_logs"
echo "CLIENT_JSONS=$OUT_DIR/clients"
echo "SUMMARY=$OUT_DIR/summary"
