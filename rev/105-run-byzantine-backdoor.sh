#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY="${SSH_KEY:-$HOME/byz-fed-ids-5g/keys/fl-ids-key.pem}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15"

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
BASELINE_NPZ="$RUN_DIR/baseline_clean_20rounds.npz"
[ -f "$BASELINE_NPZ" ] || { echo "ERROR: baseline introuvable"; exit 1; }

SPLITS_DIR="$RUN_DIR/splits_20"
N_ROUNDS=5
PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"
BASE_FABRIC="${BASE_FABRIC:-9995000}"

# Répertoire byzantin existant
BYZ_DIR=$(cat "$RUN_DIR/.last_byzantine_dir")
[ -d "$BYZ_DIR" ] || { echo "ERROR: byzantine dir introuvable: $BYZ_DIR"; exit 1; }

RESULTS_CSV="$BYZ_DIR/tables_input/byzantine_all_results.csv"
PAPER_CSV="$BYZ_DIR/tables_input/byzantine_paper.csv"

echo "================================================================"
echo "SCRIPT 105 — BACKDOOR + TABLE FINALE COMPLETE"
echo "BYZ_DIR=$BYZ_DIR"
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

  BYZ_LIST=""
  for ((i=0;i<BYZ_COUNT;i++)); do
    BYZ_LIST="$BYZ_LIST ${CIDS[$i]}"
  done
  BYZ_LIST="${BYZ_LIST# }"

  local SCEN_DIR="$BYZ_DIR/${ATTACK}_byz${BYZ_COUNT}"
  mkdir -p "$SCEN_DIR"/{agg_models,client_logs}

  echo "  [INIT] Push baseline vers $N clients..."
  for ((i=0;i<N;i++)); do
    scp $SSH_OPTS "$BASELINE_NPZ" ubuntu@"${IPS[$i]}":/opt/fl-client/models/${CIDS[$i]}_model.npz &
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

    local FAIL_R=0
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      scp $SSH_OPTS ubuntu@"$IP":/opt/fl-client/logs/fl-ids-${CID}-r${r}.json \
        "$ROUND_DIR/${CID}_r${r}.json" 2>/dev/null || FAIL_R=$((FAIL_R+1))
    done
    echo "  [A] fail=$FAIL_R"

    local GLOBAL_NPZ_BASE="$SCEN_DIR/agg_models/global_r${R2}"

    python3 - "$ROUND_DIR" "$GLOBAL_NPZ_BASE" "$RESULTS_CSV" \
      "$r" "$ATTACK" "$BYZ_RATIO" "$BYZ_COUNT" "$BYZ_LIST" "$SPLITS_DIR" <<'PY'
import sys, json, numpy as np, pathlib, time

round_dir   = pathlib.Path(sys.argv[1])
npz_base    = sys.argv[2]
results_csv = sys.argv[3]
round_num   = int(sys.argv[4])
attack      = sys.argv[5]
byz_ratio   = sys.argv[6]
byz_count   = int(sys.argv[7])
byz_list    = set(sys.argv[8].split()) if sys.argv[8] else set()
splits_dir  = sys.argv[9]

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

X = np.load(f"{splits_dir}/global_test_X.npy").astype(np.float32)
y = np.load(f"{splits_dir}/global_test_y.npy").astype(np.int32)

total = sum(u["n"] for u in updates)
w_avg = sum(u["w"]*(u["n"]/total) for u in updates).astype(np.float32)
b_avg = float(sum(u["b"]*(u["n"]/total) for u in updates))

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

def trimmedmean(updates, trim=0.1):
    ws = np.array([u["w"] for u in updates])
    bs = np.array([u["b"] for u in updates])
    n = len(updates); k = max(1, int(n*trim))
    return np.sort(ws,axis=0)[k:n-k].mean(axis=0).astype(np.float32), \
           float(np.sort(bs)[k:n-k].mean())

aggs = {}
t0=time.time(); aggs["fedavg"]      = (w_avg, b_avg, time.time()-t0, len(updates), 0)
t0=time.time(); wk,bk,sel=multikrum(updates, byz_count)
aggs["multikrum"]   = (wk, bk, time.time()-t0, sel, len(updates)-sel)
t0=time.time(); wt,bt=trimmedmean(updates)
aggs["trimmedmean"] = (wt, bt, time.time()-t0, len(updates), 0)

np.savez(f"{npz_base}_fedavg.npz", w=w_avg, b=np.array(b_avg, dtype=np.float32))

with open(results_csv, "a") as f:
    for agg_name, (w, b, agg_t, sel, rej) in aggs.items():
        res = eval_best(X, y, w, b)
        f.write(f"{attack},{byz_ratio},{byz_count},{round_num},{agg_name},{res['thr']},"
                f"{res['wf1']},{res['f1']},{res['acc']},{res['fpr']},{res['auc']}\n")
        print(f"    {agg_name:12s} wf1={res['wf1']:.6f} f1={res['f1']:.6f} "
              f"fpr={res['fpr']:.6f} roc_auc={res['auc']:.6f} sel={sel} rej={rej}")
PY

    NEXT_NPZ="$SCEN_DIR/agg_models/global_r${R2}_fedavg.npz"
    if [ -f "$NEXT_NPZ" ]; then
      for ((i=0;i<N;i++)); do
        scp $SSH_OPTS "$NEXT_NPZ" ubuntu@"${IPS[$i]}":/opt/fl-client/models/${CIDS[$i]}_model.npz &
      done
      wait
      echo "  [C] Global model poussé (round $r)"
    fi
  done
  echo "  SCENARIO $ATTACK byz=$BYZ_COUNT DONE"
}

run_scenario "backdoor" 4 "$BASE_FABRIC"
BASE_FABRIC=$((BASE_FABRIC + N_ROUNDS * 1000))
run_scenario "backdoor" 6 "$BASE_FABRIC"

# ─── Table paper finale COMPLÈTE (toutes attaques) ────────────────────────────
echo ""
echo "================================================================"
echo "TABLE PAPER FINALE COMPLETE (signflip+gaussian+scaling+random+backdoor)"
echo "================================================================"

python3 - "$RESULTS_CSV" "$PAPER_CSV" <<'PY'
import csv, sys

in_csv  = sys.argv[1]
out_csv = sys.argv[2]

rows = []
with open(in_csv) as f:
    rd = csv.DictReader(f)
    for row in rd:
        rows.append(row)

last = {}
for row in rows:
    key = (row["attack"], row["byz_ratio"], row["aggregator"])
    r = int(row["round"])
    if key not in last or r > int(last[key]["round"]):
        last[key] = row

fields = ["attack","byz_ratio","aggregator","threshold","weighted_f1","f1",
          "accuracy","fpr","roc_auc","aggregation_time_ms"]
with open(out_csv,"w",newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
    w.writeheader()
    for key in sorted(last.keys()):
        w.writerow({k: last[key].get(k,"") for k in fields})

print(f"PAPER_CSV={out_csv}")
print("")
print(f"{'Attack':<12} {'Ratio':<6} {'Aggregator':<12} {'F1':>8} {'FPR':>8} {'ROC-AUC':>9}")
print("-"*60)
for key in sorted(last.keys()):
    row = last[key]
    print(f"{row['attack']:<12} {row['byz_ratio']:<6} {row['aggregator']:<12} "
          f"{float(row['f1']):>8.4f} {float(row['fpr']):>8.4f} {float(row['roc_auc']):>9.4f}")
PY

echo ""
echo "DONE — tout sauvegardé dans $BYZ_DIR"
echo "RESULTS_CSV=$RESULTS_CSV"
echo "PAPER_CSV=$PAPER_CSV"
