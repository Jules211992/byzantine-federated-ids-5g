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
N_ROUNDS=5
PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"
BASE_FABRIC="${BASE_FABRIC:-9990000}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/byzantine_attacks_${TS}"
mkdir -p "$OUT"/{tables_input,figures_input,manifest}

echo "================================================================"
echo "SCRIPT 104 — ATTAQUES BYZANTINES"
echo "RUN_DIR=$RUN_DIR"
echo "BASELINE=$BASELINE_NPZ"
echo "OUT=$OUT"
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

RESULTS_CSV="$OUT/tables_input/byzantine_all_results.csv"
echo "attack,byz_ratio,byz_count,round,aggregator,threshold,weighted_f1,f1,accuracy,fpr,roc_auc" \
  > "$RESULTS_CSV"

PAPER_CSV="$OUT/tables_input/byzantine_paper.csv"
echo "attack,byz_ratio,aggregator,threshold,weighted_f1,f1,accuracy,fpr,roc_auc,aggregation_time_ms" \
  > "$PAPER_CSV"

# Fonction évaluation globale
eval_global () {
  local npz="$1"
  local out_csv="$2"
  local round_num="$3"
  local attack="$4"
  local byz_ratio="$5"
  local byz_count="$6"

  python3 - "$npz" "$SPLITS_DIR" "$out_csv" "$round_num" "$attack" "$byz_ratio" "$byz_count" <<'PY'
import sys, numpy as np

npz_path   = sys.argv[1]
splits_dir = sys.argv[2]
out_csv    = sys.argv[3]
round_num  = int(sys.argv[4])
attack     = sys.argv[5]
byz_ratio  = sys.argv[6]
byz_count  = int(sys.argv[7])

m = np.load(npz_path)
w = m["w"].astype(np.float32)
b = float(m["b"])

X = np.load(f"{splits_dir}/global_test_X.npy").astype(np.float32)
y = np.load(f"{splits_dir}/global_test_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

best_thr, best_wf1 = 0.5, -1
for t in [x/100 for x in range(5, 96)]:
    preds = (sigmoid(X @ w + b) >= t).astype(int)
    tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
    fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
    prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
    wf1  = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
    if wf1 > best_wf1: best_wf1, best_thr = wf1, t

preds = (sigmoid(X @ w + b) >= best_thr).astype(int)
tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
acc  = (tp+tn)/max(len(y),1); prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
scores = sigmoid(X @ w + b)
desc = np.argsort(-scores); tp_c = 0; auc = 0.0
tp_tot = int(np.sum(y==1)); fp_tot = int(np.sum(y==0))
for idx in desc:
    if y[idx]==1: tp_c += 1
    else: auc += tp_c
auc /= max(tp_tot*fp_tot,1)
wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)

with open(out_csv, "a") as f:
    f.write(f"{attack},{byz_ratio},{byz_count},{round_num},fedavg_inline,{best_thr:.2f},"
            f"{wf1_f:.6f},{f1:.6f},{acc:.6f},{fpr:.6f},{auc:.6f}\n")
print(f"    thr={best_thr:.2f} wf1={wf1_f:.6f} f1={f1:.6f} fpr={fpr:.6f} roc_auc={auc:.6f}")
PY
}

# Fonction run un scénario byzantin complet
run_scenario () {
  local ATTACK="$1"
  local BYZ_COUNT="$2"
  local SCENARIO_BASE_FABRIC="$3"

  local BYZ_RATIO
  BYZ_RATIO=$(python3 -c "print(f'{$BYZ_COUNT/$N:.0%}')")

  echo ""
  echo "========================================================"
  echo "SCENARIO: attack=$ATTACK byz=$BYZ_COUNT/$N ($BYZ_RATIO)"
  echo "========================================================"

  # Sélectionner les BYZ_COUNT premiers clients comme byzantins
  BYZ_LIST=""
  for ((i=0;i<BYZ_COUNT;i++)); do
    BYZ_LIST="$BYZ_LIST ${CIDS[$i]}"
  done
  BYZ_LIST="${BYZ_LIST# }"
  echo "  BYZ_CLIENTS=$BYZ_LIST"

  local SCEN_DIR="$OUT/${ATTACK}_byz${BYZ_COUNT}"
  mkdir -p "$SCEN_DIR"/{agg_models,client_logs}

  # Push du baseline vers tous les clients
  echo "  [INIT] Push baseline vers $N clients..."
  for ((i=0;i<N;i++)); do
    CID="${CIDS[$i]}"
    IP="${IPS[$i]}"
    scp $SSH_OPTS "$BASELINE_NPZ" ubuntu@"$IP":/opt/fl-client/models/${CID}_model.npz &
  done
  wait
  echo "  [INIT] Done."

  for ((r=1; r<=N_ROUNDS; r++)); do
    local R2
    R2=$(printf "%02d" "$r")
    local START_FABRIC=$((SCENARIO_BASE_FABRIC + (r - 1) * 1000))

    echo "  --- Round $r / $N_ROUNDS ---"

    local ROUND_DIR="$SCEN_DIR/client_logs/round${R2}"
    mkdir -p "$ROUND_DIR"

    # Entraînement parallèle
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      FABRIC_ROUND=$((START_FABRIC + i))
      ssh $SSH_OPTS ubuntu@"$IP" \
        "ATTACK_MODE=$ATTACK BYZ_CLIENTS='$BYZ_LIST' CLIENT_ID=$CID ROUND=$r \
         /opt/fl-client/run_fl_round.sh $CID $r $MSP $PEER_HOST $FABRIC_ROUND \
         > /opt/fl-client/logs/runfl_${CID}_r${r}.out 2>&1" &
    done
    wait

    # Récupérer JSONs
    local FAIL_R=0
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      scp $SSH_OPTS ubuntu@"$IP":/opt/fl-client/logs/fl-ids-${CID}-r${r}.json \
        "$ROUND_DIR/${CID}_r${r}.json" 2>/dev/null || {
        FAIL_R=$((FAIL_R+1))
      }
    done
    echo "  [A] fail=$FAIL_R"

    # Agrégation avec les 3 agrégateurs
    local GLOBAL_NPZ_BASE="$SCEN_DIR/agg_models/global_r${R2}"

    python3 - "$ROUND_DIR" "$GLOBAL_NPZ_BASE" "$RESULTS_CSV" \
      "$r" "$ATTACK" "$BYZ_RATIO" "$BYZ_COUNT" "$BYZ_LIST" <<'PY'
import sys, json, numpy as np, pathlib, time, csv

round_dir    = pathlib.Path(sys.argv[1])
npz_base     = sys.argv[2]
results_csv  = sys.argv[3]
round_num    = int(sys.argv[4])
attack       = sys.argv[5]
byz_ratio    = sys.argv[6]
byz_count    = int(sys.argv[7])
byz_list     = set(sys.argv[8].split()) if sys.argv[8] else set()

jsons = sorted(round_dir.glob("*.json"))
updates = []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        updates.append({
            "w": np.array(d["weights"], dtype=np.float32),
            "b": float(d["bias"]),
            "n": int(d.get("n_samples", 1)),
            "client": d.get("client_id", jf.stem)
        })
    except Exception as e:
        print(f"    WARN {jf.name}: {e}")

if not updates:
    raise SystemExit("ERROR: aucun update")

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def eval_best(X, y, w, b):
    best_thr, best_wf1 = 0.5, -1
    for t in [x/100 for x in range(5, 96)]:
        preds = (sigmoid(X @ w + b) >= t).astype(int)
        tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
        fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
        prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
        f1 = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
        wf1 = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
        if wf1 > best_wf1: best_wf1, best_thr = wf1, t
    preds = (sigmoid(X @ w + b) >= best_thr).astype(int)
    tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
    fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
    acc = (tp+tn)/max(len(y),1); prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1 = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
    scores = sigmoid(X @ w + b)
    desc = np.argsort(-scores); tp_c = 0; auc = 0.0
    for idx in desc:
        if y[idx]==1: tp_c += 1
        else: auc += tp_c
    auc /= max(int(np.sum(y==1))*int(np.sum(y==0)),1)
    wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
    return dict(thr=round(best_thr,2), f1=round(f1,6), acc=round(acc,6),
                fpr=round(fpr,6), auc=round(auc,6), wf1=round(wf1_f,6))

# Charger test global
import os
splits_dir = os.path.dirname(npz_base).replace("/agg_models","")
splits_dir = str(pathlib.Path(npz_base).parent.parent.parent.parent.parent) + \
             "/splits_20"
# Chercher splits_20 depuis RUN_DIR
rdir = pathlib.Path(npz_base).parent
while rdir != rdir.parent:
    sd = rdir / "splits_20"
    if sd.exists():
        splits_dir = str(sd)
        break
    rdir = rdir.parent

X = np.load(f"{splits_dir}/global_test_X.npy").astype(np.float32)
y = np.load(f"{splits_dir}/global_test_y.npy").astype(np.int32)

# FedAvg
total = sum(u["n"] for u in updates)
w_avg = sum(u["w"]*(u["n"]/total) for u in updates).astype(np.float32)
b_avg = float(sum(u["b"]*(u["n"]/total) for u in updates))

# MultiKrum
def multikrum(updates, f):
    ws = [u["w"] for u in updates]; n = len(ws)
    k = max(1, n - f - 2)
    scores = []
    for i in range(n):
        dists = sorted([float(np.sum((ws[i]-ws[j])**2)) for j in range(n) if j!=i])
        scores.append((sum(dists[:k]), i))
    scores.sort(); sel = [updates[scores[j][1]] for j in range(n-f)]
    ts = sum(u["n"] for u in sel)
    return sum(u["w"]*(u["n"]/ts) for u in sel).astype(np.float32), \
           float(sum(u["b"]*(u["n"]/ts) for u in sel)), len(sel)

# TrimmedMean
def trimmedmean(updates, trim=0.1):
    ws = np.array([u["w"] for u in updates])
    bs = np.array([u["b"] for u in updates])
    n = len(updates); k = max(1, int(n*trim))
    return np.sort(ws,axis=0)[k:n-k].mean(axis=0).astype(np.float32), \
           float(np.sort(bs)[k:n-k].mean())

f_byz = byz_count
aggs = {}
t0=time.time(); aggs["fedavg"]     = (w_avg, b_avg, time.time()-t0, len(updates), 0)
t0=time.time(); wk,bk,sel=multikrum(updates, f_byz)
aggs["multikrum"]  = (wk, bk, time.time()-t0, sel, len(updates)-sel)
t0=time.time(); wt,bt=trimmedmean(updates)
aggs["trimmedmean"]= (wt, bt, time.time()-t0, len(updates), 0)

# Sauvegarder le global model FedAvg pour le round suivant (push)
np.savez(f"{npz_base}_fedavg.npz", w=w_avg, b=np.array(b_avg, dtype=np.float32))

with open(results_csv, "a") as f:
    for agg_name, (w, b, agg_t, sel, rej) in aggs.items():
        res = eval_best(X, y, w, b)
        f.write(f"{attack},{byz_ratio},{byz_count},{round_num},{agg_name},{res['thr']},"
                f"{res['wf1']},{res['f1']},{res['acc']},{res['fpr']},{res['auc']}\n")
        print(f"    {agg_name:12s} wf1={res['wf1']:.6f} f1={res['f1']:.6f} "
              f"fpr={res['fpr']:.6f} roc_auc={res['auc']:.6f} sel={sel} rej={rej}")
PY

    # Push global FedAvg pour le round suivant
    NEXT_NPZ="$SCEN_DIR/agg_models/global_r${R2}_fedavg.npz"
    if [ -f "$NEXT_NPZ" ]; then
      for ((i=0;i<N;i++)); do
        CID="${CIDS[$i]}"
        IP="${IPS[$i]}"
        scp $SSH_OPTS "$NEXT_NPZ" ubuntu@"$IP":/opt/fl-client/models/${CID}_model.npz &
      done
      wait
      echo "  [C] Global model poussé (round $r)"
    fi

  done
  echo "  SCENARIO $ATTACK byz=$BYZ_COUNT DONE"
}

# ─── Scénarios ────────────────────────────────────────────────────────────────
# 4 attaques × 2 ratios byzantins (4/20=20% et 6/20=30%)

FABRIC_OFFSET=0

for ATTACK in signflip gaussian scaling random; do
  for BYZ_COUNT in 4 6; do
    SCEN_FABRIC=$((BASE_FABRIC + FABRIC_OFFSET))
    run_scenario "$ATTACK" "$BYZ_COUNT" "$SCEN_FABRIC"
    FABRIC_OFFSET=$((FABRIC_OFFSET + N_ROUNDS * 1000))
  done
done

# ─── Table paper finale ────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "TABLE PAPER FINALE"
echo "================================================================"

python3 - "$RESULTS_CSV" "$PAPER_CSV" <<'PY'
import csv, sys
from collections import defaultdict

in_csv  = sys.argv[1]
out_csv = sys.argv[2]

rows = []
with open(in_csv) as f:
    rd = csv.DictReader(f)
    for row in rd:
        rows.append(row)

# Garder seulement le dernier round (round=5) par scénario/agrégateur
last = {}
for row in rows:
    key = (row["attack"], row["byz_ratio"], row["aggregator"])
    r = int(row["round"])
    if key not in last or r > int(last[key]["round"]):
        last[key] = row

fields = ["attack","byz_ratio","aggregator","threshold","weighted_f1","f1","accuracy","fpr","roc_auc","aggregation_time_ms"]
with open(out_csv,"w",newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
    w.writeheader()
    for key in sorted(last.keys()):
        row = last[key]
        w.writerow({k: row.get(k,"") for k in fields})

print(f"PAPER_CSV={out_csv}")
print("")
print(f"{'Attack':<12} {'Ratio':<6} {'Aggregator':<12} {'F1':>8} {'FPR':>8} {'ROC-AUC':>9}")
print("-"*60)
for key in sorted(last.keys()):
    row = last[key]
    print(f"{row['attack']:<12} {row['byz_ratio']:<6} {row['aggregator']:<12} "
          f"{float(row['f1']):>8.4f} {float(row['fpr']):>8.4f} {float(row['roc_auc']):>9.4f}")
PY

echo "$OUT" > "$RUN_DIR/.last_byzantine_dir"
echo ""
echo "DONE"
echo "RESULTS_CSV=$RESULTS_CSV"
echo "PAPER_CSV=$PAPER_CSV"
echo "OUT=$OUT"
