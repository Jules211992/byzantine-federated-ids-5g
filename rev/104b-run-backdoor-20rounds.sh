#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY="${SSH_KEY:-$HOME/byz-fed-ids-5g/keys/fl-ids-key.pem}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15"

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: MAP introuvable: $MAP"; exit 1; }

BASELINE_NPZ="$RUN_DIR/baseline_clean_20rounds.npz"
[ -f "$BASELINE_NPZ" ] || { echo "ERROR: baseline introuvable: $BASELINE_NPZ"; exit 1; }

SPLITS_DIR="$RUN_DIR/splits_20"

for f in global_val_X.npy global_holdout_X.npy; do
  [ -f "$SPLITS_DIR/$f" ] || {
    echo "ERROR: $f introuvable — lancer 103b-prepare-valtest-split.py d abord"
    exit 1
  }
done

N_ROUNDS="${N_ROUNDS:-20}"
ATTACK="backdoor"
PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"
BASE_FABRIC="${BASE_FABRIC:-9880000}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/byzantine_backdoor20r_${TS}"
mkdir -p "$OUT"/{tables_input,figures_input}

echo "================================================================"
echo "SCRIPT 104b — BACKDOOR 20 ROUNDS (VAL/HOLDOUT SEPARES)"
echo "RUN_DIR  = $RUN_DIR"
echo "BASELINE = $BASELINE_NPZ"
echo "N_ROUNDS = $N_ROUNDS"
echo "OUT      = $OUT"
echo "================================================================"

CIDS=()
IPS=()
while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  CIDS+=("$cid")
  IPS+=("$ip")
done < "$MAP"
N=${#CIDS[@]}
echo "N_CLIENTS=$N"

RESULTS_CSV="$OUT/tables_input/backdoor_all_rounds.csv"
echo "attack,byz_ratio,byz_count,round,aggregator,threshold,weighted_f1,f1,accuracy,fpr,roc_auc" \
  > "$RESULTS_CSV"

run_scenario () {
  local BYZ_COUNT="$1"
  local SCEN_FABRIC="$2"
  local BYZ_RATIO
  BYZ_RATIO=$(python3 -c "print(f'{$BYZ_COUNT/$N:.0%}')")

  echo ""
  echo "========================================================"
  echo "BACKDOOR byz=$BYZ_COUNT/$N ($BYZ_RATIO) — $N_ROUNDS rounds"
  echo "========================================================"

  BYZ_LIST=""
  for ((i=0;i<BYZ_COUNT;i++)); do BYZ_LIST="$BYZ_LIST ${CIDS[$i]}"; done
  BYZ_LIST="${BYZ_LIST# }"

  local SCEN_DIR="$OUT/backdoor_byz${BYZ_COUNT}"
  mkdir -p "$SCEN_DIR"/{agg_models,client_logs}

  echo "  [INIT] Push baseline → $N clients..."
  for ((i=0;i<N;i++)); do
    scp $SSH_OPTS "$BASELINE_NPZ" ubuntu@"${IPS[$i]}":/opt/fl-client/models/${CIDS[$i]}_model.npz &
  done
  wait
  echo "  [INIT] Done."

  for ((r=1; r<=N_ROUNDS; r++)); do
    local R2; R2=$(printf "%02d" "$r")
    local START_FABRIC=$((SCEN_FABRIC + (r-1)*1000))
    echo "  --- Round $r / $N_ROUNDS ---"

    local ROUND_DIR="$SCEN_DIR/client_logs/round${R2}"
    mkdir -p "$ROUND_DIR"

    for ((i=0;i<N;i++)); do
      local CID="${CIDS[$i]}" IP="${IPS[$i]}"
      local FABRIC_ROUND=$((START_FABRIC + i))
      ssh $SSH_OPTS ubuntu@"$IP" \
        "ATTACK_MODE=$ATTACK BYZ_CLIENTS='$BYZ_LIST' CLIENT_ID=$CID ROUND=$r \
         /opt/fl-client/run_fl_round.sh $CID $r $MSP $PEER_HOST $FABRIC_ROUND \
         > /opt/fl-client/logs/runfl_${CID}_r${r}.out 2>&1" &
    done
    wait

    local FAIL_R=0
    for ((i=0;i<N;i++)); do
      scp $SSH_OPTS ubuntu@"${IPS[$i]}":/opt/fl-client/logs/fl-ids-${CIDS[$i]}-r${r}.json \
        "$ROUND_DIR/${CIDS[$i]}_r${r}.json" 2>/dev/null || FAIL_R=$((FAIL_R+1))
    done
    echo "  [A] fail=$FAIL_R"

    local NPZ_BASE="$SCEN_DIR/agg_models/global_r${R2}"

    python3 - "$ROUND_DIR" "$NPZ_BASE" "$RESULTS_CSV" \
      "$r" "$ATTACK" "$BYZ_RATIO" "$BYZ_COUNT" "$SPLITS_DIR" <<'PY'
import sys, json, numpy as np, pathlib, time

round_dir   = pathlib.Path(sys.argv[1])
npz_base    = sys.argv[2]
results_csv = sys.argv[3]
round_num   = int(sys.argv[4])
attack      = sys.argv[5]
byz_ratio   = sys.argv[6]
byz_count   = int(sys.argv[7])
splits_dir  = sys.argv[8]

jsons = sorted(round_dir.glob("*.json"))
updates = []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        updates.append({"w": np.array(d["weights"], dtype=np.float32),
                        "b": float(d["bias"]),
                        "n": int(d.get("n_samples", 1))})
    except Exception as e:
        print(f"    WARN {jf.name}: {e}")

if not updates:
    raise SystemExit("ERROR: aucun update")

# VAL pour threshold, HOLDOUT pour metriques
X_val  = np.load(f"{splits_dir}/global_val_X.npy").astype(np.float32)
y_val  = np.load(f"{splits_dir}/global_val_y.npy").astype(np.int32)
X_hld  = np.load(f"{splits_dir}/global_holdout_X.npy").astype(np.float32)
y_hld  = np.load(f"{splits_dir}/global_holdout_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def eval_model(w, b):
    best_thr, best_wf1 = 0.5, -1
    for t in [x/100 for x in range(5, 96)]:
        preds = (sigmoid(X_val @ w + b) >= t).astype(int)
        tp = int(np.sum((preds==1)&(y_val==1))); fp = int(np.sum((preds==1)&(y_val==0)))
        fn = int(np.sum((preds==0)&(y_val==1))); tn = int(np.sum((preds==0)&(y_val==0)))
        prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
        f1 = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
        wf1 = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_val),1)
        if wf1 > best_wf1: best_wf1, best_thr = wf1, t
    preds = (sigmoid(X_hld @ w + b) >= best_thr).astype(int)
    tp = int(np.sum((preds==1)&(y_hld==1))); fp = int(np.sum((preds==1)&(y_hld==0)))
    fn = int(np.sum((preds==0)&(y_hld==1))); tn = int(np.sum((preds==0)&(y_hld==0)))
    acc = (tp+tn)/max(len(y_hld),1); prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1 = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
    scores = sigmoid(X_hld @ w + b)
    desc = np.argsort(-scores); tp_c = 0; auc = 0.0
    for idx in desc:
        if y_hld[idx]==1: tp_c += 1
        else: auc += tp_c
    auc /= max(int(np.sum(y_hld==1))*int(np.sum(y_hld==0)), 1)
    wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_hld),1)
    return dict(thr=round(best_thr,2), f1=round(f1,6), acc=round(acc,6),
                fpr=round(fpr,6), auc=round(auc,6), wf1=round(wf1_f,6))

total = sum(u["n"] for u in updates)
w_avg = sum(u["w"]*(u["n"]/total) for u in updates).astype(np.float32)
b_avg = float(sum(u["b"]*(u["n"]/total) for u in updates))

def multikrum(updates, f):
    ws = [u["w"] for u in updates]; n = len(ws)
    k = max(1, n-f-2); scores = []
    for i in range(n):
        dists = sorted([float(np.sum((ws[i]-ws[j])**2)) for j in range(n) if j!=i])
        scores.append((sum(dists[:k]), i))
    scores.sort(); sel = [updates[scores[j][1]] for j in range(n-f)]
    ts = sum(u["n"] for u in sel)
    return (sum(u["w"]*(u["n"]/ts) for u in sel).astype(np.float32),
            float(sum(u["b"]*(u["n"]/ts) for u in sel)), len(sel))

def trimmedmean(updates, trim=0.1):
    ws = np.array([u["w"] for u in updates])
    bs = np.array([u["b"] for u in updates])
    n = len(updates); k = max(1, int(n*trim))
    return (np.sort(ws,axis=0)[k:n-k].mean(axis=0).astype(np.float32),
            float(np.sort(bs)[k:n-k].mean()))

aggs = {}
aggs["fedavg"]      = (w_avg, b_avg, len(updates))
wk,bk,sel = multikrum(updates, byz_count)
aggs["multikrum"]   = (wk, bk, sel)
wt,bt = trimmedmean(updates)
aggs["trimmedmean"] = (wt, bt, len(updates))

np.savez(f"{npz_base}_fedavg.npz",
         w=w_avg, b=np.array(b_avg, dtype=np.float32))

with open(results_csv, "a") as f:
    for agg_name, (w, b, sel) in aggs.items():
        res = eval_model(w, b)
        f.write(f"{attack},{byz_ratio},{byz_count},{round_num},{agg_name},"
                f"{res['thr']},{res['wf1']},{res['f1']},{res['acc']},"
                f"{res['fpr']},{res['auc']}\n")
        print(f"    {agg_name:12s} thr={res['thr']:.2f}(val) "
              f"f1={res['f1']:.6f} fpr={res['fpr']:.6f} "
              f"auc={res['auc']:.6f} [holdout]")
PY

    local NEXT_NPZ="$SCEN_DIR/agg_models/global_r${R2}_fedavg.npz"
    if [ -f "$NEXT_NPZ" ]; then
      for ((i=0;i<N;i++)); do
        scp $SSH_OPTS "$NEXT_NPZ" \
          ubuntu@"${IPS[$i]}":/opt/fl-client/models/${CIDS[$i]}_model.npz &
      done
      wait
    fi
  done
  echo "  BACKDOOR byz=$BYZ_COUNT DONE"
}

run_scenario 4 "$BASE_FABRIC"
run_scenario 6 $((BASE_FABRIC + N_ROUNDS * 1000))

echo ""
echo "================================================================"
echo "RÉSUMÉ FINAL — Backdoor 20 rounds"
echo "================================================================"
python3 - "$RESULTS_CSV" <<'PY'
import csv, sys
from collections import defaultdict

rows = []
with open(sys.argv[1]) as f:
    for row in csv.DictReader(f):
        rows.append(row)

print(f"\n{'Ratio':<6} {'Aggregator':<12} {'Round':<6} {'F1':>8} {'FPR':>8} {'AUC':>9}")
print("-"*55)
for byz in ["20%","30%"]:
    for agg in ["fedavg","multikrum","trimmedmean"]:
        subset = [r for r in rows if r["byz_ratio"]==byz and r["aggregator"]==agg]
        if not subset: continue
        last = max(subset, key=lambda x: int(x["round"]))
        print(f"{byz:<6} {agg:<12} R{last['round']:<5} "
              f"{float(last['f1']):>8.4f} {float(last['fpr']):>8.4f} "
              f"{float(last['roc_auc']):>9.4f}")
PY

echo "$OUT" > "$RUN_DIR/.last_byzantine_backdoor_dir"
echo "DONE — OUT=$OUT"
