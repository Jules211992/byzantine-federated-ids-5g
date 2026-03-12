#!/bin/bash
# =====================================================================
# 103b-run-clean-3seeds.sh
# =====================================================================
# Version révisée du script 103 pour répondre aux reviewers :
#
#   CORRECTIF 1 — Séparation val / holdout
#     Le seuil de décision est sélectionné sur global_val_X/y (20%)
#     Les métriques finales sont rapportées sur global_holdout_X/y (80%)
#     → supprime la fuite d'information signalée par les reviewers
#
#   CORRECTIF 2 — 3 runs indépendants (seeds 42, 43, 44)
#     Chaque run repart de zéro (modèles clients effacés)
#     La stochasticité du mini-batch SGD sur les clients produit
#     des runs différents → mean ± std sur F1, ROC-AUC, FPR
#
#   CORRECTIF 3 — 20 rounds (au lieu de 5)
#     Identique au scénario propre original
#
# Prérequis :
#   103b-prepare-valtest-split.py doit avoir été exécuté une fois :
#     python3 103b-prepare-valtest-split.py --splits-dir <SPLITS_DIR>
#
# Paramètres configurables :
#   N_ROUNDS=20  SEEDS="42 43 44"  BASE_FABRIC=9950000
#
# Sorties :
#   $RUN_DIR/federated_3seeds_<TS>/
#     seed_42/  seed_43/  seed_44/
#       figures_input/federated_round_metrics.csv
#       tables_input/federated_final_summary.csv
#       tables_input/federated_final_paper.csv
#     AGGREGATE/
#       mean_std_paper.csv    ← tableau principal pour le papier
#       per_round_all_seeds.csv
# =====================================================================
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY="${SSH_KEY:-$HOME/byz-fed-ids-5g/keys/fl-ids-key.pem}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15"

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: MAP introuvable: $MAP"; exit 1; }

SPLITS_DIR="$RUN_DIR/splits_20"

# Vérifier que les splits val/holdout existent
if [ ! -f "$SPLITS_DIR/global_val_X.npy" ] || [ ! -f "$SPLITS_DIR/global_holdout_X.npy" ]; then
  echo "ERROR: splits val/holdout introuvables dans $SPLITS_DIR"
  echo "       Exécuter d'abord : python3 103b-prepare-valtest-split.py --splits-dir $SPLITS_DIR"
  exit 1
fi

N_ROUNDS="${N_ROUNDS:-20}"
SEEDS="${SEEDS:-42 43 44}"
BASE_FABRIC="${BASE_FABRIC:-9950000}"
PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"

TS=$(date -u +%Y%m%d_%H%M%S)
MASTER_OUT="$RUN_DIR/federated_3seeds_${TS}"
mkdir -p "$MASTER_OUT/AGGREGATE"

echo "================================================================"
echo "SCRIPT 103b — FL FEDERE 3 SEEDS (VAL/HOLDOUT SÉPARÉS)"
echo "RUN_DIR  = $RUN_DIR"
echo "SPLITS   = $SPLITS_DIR"
echo "N_ROUNDS = $N_ROUNDS"
echo "SEEDS    = $SEEDS"
echo "MASTER_OUT = $MASTER_OUT"
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

# ─── Boucle sur les 3 seeds ──────────────────────────────────────────
for SEED in $SEEDS; do
  echo ""
  echo "################################################################"
  echo "SEED = $SEED"
  echo "################################################################"

  OUT="$MASTER_OUT/seed_${SEED}"
  mkdir -p "$OUT"/{tables_input,figures_input,manifest,agg_models,client_logs}

  # ── Nettoyage modèles initiaux (reset complet entre seeds) ──────────
  echo "=== STEP 0: Reset modèles clients (seed=$SEED) ==="
  for ((i=0;i<N;i++)); do
    IP="${IPS[$i]}"
    CID="${CIDS[$i]}"
    ssh $SSH_OPTS ubuntu@"$IP" "rm -f /opt/fl-client/models/${CID}_model.npz" 2>/dev/null || true
  done
  echo "OK"

  ROUND_METRICS_CSV="$OUT/figures_input/federated_round_metrics.csv"
  echo "round,aggregator,threshold,weighted_f1,f1,accuracy,precision,recall,fpr,roc_auc" \
    > "$ROUND_METRICS_CSV"

  # ── Boucle sur les rounds ────────────────────────────────────────────
  for ((r=1; r<=N_ROUNDS; r++)); do
    R2=$(printf "%02d" "$r")
    START_FABRIC=$((BASE_FABRIC + (SEED - 42) * 100000 + (r - 1) * 1000))

    echo ""
    echo "  ────────────────────────────────────"
    echo "  SEED=$SEED  ROUND $r / $N_ROUNDS"
    echo "  ────────────────────────────────────"

    ROUND_DIR="$OUT/client_logs/round${R2}"
    mkdir -p "$ROUND_DIR"

    # [A] Entraînement local — seed transmis comme variable d'env
    echo "  [A] Entraînement local $N clients (SEED=$SEED)..."
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      FABRIC_ROUND=$((START_FABRIC + i))
      ssh $SSH_OPTS ubuntu@"$IP" \
        "SEED=$SEED CLIENT_ID=$CID ROUND=$r \
         /opt/fl-client/run_fl_round.sh $CID $r $MSP $PEER_HOST $FABRIC_ROUND \
         > /opt/fl-client/logs/runfl_${CID}_r${r}_s${SEED}.out 2>&1" &
    done
    wait

    FAIL_R=0
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      scp $SSH_OPTS ubuntu@"$IP":/opt/fl-client/logs/fl-ids-${CID}-r${r}.json \
        "$ROUND_DIR/${CID}_r${r}.json" 2>/dev/null || {
        echo "  WARN: JSON manquant pour $CID"
        FAIL_R=$((FAIL_R+1))
      }
    done
    echo "  [A] Done. fail=$FAIL_R"

    # [B] Agrégation FedAvg (pour warm-start clients)
    echo "  [B] Agrégation FedAvg round $r..."
    GLOBAL_NPZ="$OUT/agg_models/global_r${R2}.npz"

    python3 - "$ROUND_DIR" "$GLOBAL_NPZ" <<'PY'
import sys, json, numpy as np, pathlib

round_dir = pathlib.Path(sys.argv[1])
out_npz   = sys.argv[2]

jsons = sorted(round_dir.glob("*.json"))
if not jsons:
    raise SystemExit(f"ERROR: aucun JSON dans {round_dir}")

ws, bs, ns = [], [], []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        ws.append(np.array(d["weights"], dtype=np.float32))
        bs.append(float(d["bias"]))
        ns.append(int(d.get("n_samples", 1)))
    except Exception as e:
        print(f"  WARN skip {jf.name}: {e}")

if not ws:
    raise SystemExit("ERROR: aucun update valide")

total = sum(ns)
w_agg = sum(ws[i]*(ns[i]/total) for i in range(len(ws))).astype(np.float32)
b_agg = float(sum(bs[i]*(ns[i]/total) for i in range(len(bs))))
np.savez(out_npz, w=w_agg, b=np.array(b_agg, dtype=np.float32))
print(f"  FedAvg OK: n={len(ws)} total={total} b={b_agg:.4f}")
PY
    echo "  [B] Done."

    # [C] Push global model vers les clients
    echo "  [C] Push global model → $N clients..."
    for ((i=0;i<N;i++)); do
      CID="${CIDS[$i]}"
      IP="${IPS[$i]}"
      scp $SSH_OPTS "$GLOBAL_NPZ" ubuntu@"$IP":/opt/fl-client/models/${CID}_model.npz &
    done
    wait
    echo "  [C] Done."

    # [D] Évaluation globale — threshold sur VAL, métriques sur HOLDOUT
    echo "  [D] Évaluation round $r (thr→val, métriques→holdout)..."
    python3 - "$GLOBAL_NPZ" "$SPLITS_DIR" "$ROUND_METRICS_CSV" "$r" <<'PY'
import sys, numpy as np

npz_path   = sys.argv[1]
splits_dir = sys.argv[2]
out_csv    = sys.argv[3]
round_num  = int(sys.argv[4])

m = np.load(npz_path)
w = m["w"].astype(np.float32)
b = float(m["b"])

# VAL : pour sélection du seuil uniquement
X_val = np.load(f"{splits_dir}/global_val_X.npy").astype(np.float32)
y_val = np.load(f"{splits_dir}/global_val_y.npy").astype(np.int32)

# HOLDOUT : pour les métriques finales (jamais vu pendant la calibration)
X_hld = np.load(f"{splits_dir}/global_holdout_X.npy").astype(np.float32)
y_hld = np.load(f"{splits_dir}/global_holdout_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

# Sélection du seuil sur VAL
best_thr, best_wf1 = 0.5, -1
for t in [x/100 for x in range(5, 96)]:
    preds = (sigmoid(X_val @ w + b) >= t).astype(int)
    tp = int(np.sum((preds==1)&(y_val==1)))
    fp = int(np.sum((preds==1)&(y_val==0)))
    fn = int(np.sum((preds==0)&(y_val==1)))
    tn = int(np.sum((preds==0)&(y_val==0)))
    prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9)
    fpr  = fp/max(fp+tn,1)
    wf1  = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_val),1)
    if wf1 > best_wf1:
        best_wf1, best_thr = wf1, t

# Métriques sur HOLDOUT avec le seuil choisi sur VAL
preds = (sigmoid(X_hld @ w + b) >= best_thr).astype(int)
tp = int(np.sum((preds==1)&(y_hld==1)))
fp = int(np.sum((preds==1)&(y_hld==0)))
fn = int(np.sum((preds==0)&(y_hld==1)))
tn = int(np.sum((preds==0)&(y_hld==0)))
acc  = (tp+tn)/max(len(y_hld),1)
prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
f1   = 2*prec*rec/max(prec+rec,1e-9)
fpr  = fp/max(fp+tn,1)

scores = sigmoid(X_hld @ w + b)
desc   = np.argsort(-scores)
tp_c   = 0; auc = 0.0
tp_tot = int(np.sum(y_hld==1)); fp_tot = int(np.sum(y_hld==0))
for idx in desc:
    if y_hld[idx]==1: tp_c += 1
    else: auc += tp_c
auc /= max(tp_tot*fp_tot, 1)
wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_hld),1)

print(f"  R{round_num}: thr={best_thr:.2f}(val) "
      f"wf1={wf1_f:.6f} f1={f1:.6f} acc={acc:.6f} "
      f"fpr={fpr:.6f} auc={auc:.6f} [holdout N={len(y_hld)}]")

with open(out_csv, "a") as f:
    f.write(f"{round_num},fedavg,{best_thr:.2f},{wf1_f:.6f},{f1:.6f},"
            f"{acc:.6f},{prec:.6f},{rec:.6f},{fpr:.6f},{auc:.6f}\n")
PY
    echo "  [D] Done."

  done  # fin rounds

  # ── Résumé final du seed (tous agrégateurs, round final) ────────────
  echo ""
  echo "=== RÉSUMÉ FINAL seed=$SEED (round $N_ROUNDS, tous agrégateurs) ==="
  FINAL_ROUND_DIR="$OUT/client_logs/round$(printf "%02d" "$N_ROUNDS")"
  SUMMARY_CSV="$OUT/tables_input/federated_final_summary.csv"
  PAPER_CSV="$OUT/tables_input/federated_final_paper.csv"

  python3 - "$FINAL_ROUND_DIR" "$SPLITS_DIR" "$SUMMARY_CSV" "$PAPER_CSV" "$N_ROUNDS" "$SEED" <<'PY'
import sys, json, numpy as np, pathlib, csv, time

round_dir  = pathlib.Path(sys.argv[1])
splits_dir = sys.argv[2]
sum_csv    = sys.argv[3]
paper_csv  = sys.argv[4]
final_r    = int(sys.argv[5])
seed_id    = int(sys.argv[6])

jsons = sorted(round_dir.glob("*.json"))
updates = []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        updates.append({
            "w": np.array(d["weights"], dtype=np.float32),
            "b": float(d["bias"]),
            "n": int(d.get("n_samples", 1))
        })
    except Exception as e:
        print(f"  WARN {jf.name}: {e}")

# VAL pour seuil, HOLDOUT pour métriques
X_val  = np.load(f"{splits_dir}/global_val_X.npy").astype(np.float32)
y_val  = np.load(f"{splits_dir}/global_val_y.npy").astype(np.int32)
X_hld  = np.load(f"{splits_dir}/global_holdout_X.npy").astype(np.float32)
y_hld  = np.load(f"{splits_dir}/global_holdout_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def eval_model(w, b, X_val, y_val, X_hld, y_hld):
    """Seuil optimisé sur VAL, métriques sur HOLDOUT."""
    best_thr, best_wf1 = 0.5, -1
    for t in [x/100 for x in range(5, 96)]:
        preds = (sigmoid(X_val @ w + b) >= t).astype(int)
        tp = int(np.sum((preds==1)&(y_val==1))); fp = int(np.sum((preds==1)&(y_val==0)))
        fn = int(np.sum((preds==0)&(y_val==1))); tn = int(np.sum((preds==0)&(y_val==0)))
        prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
        f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
        wf1  = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_val),1)
        if wf1 > best_wf1: best_wf1, best_thr = wf1, t
    # métriques sur HOLDOUT
    preds = (sigmoid(X_hld @ w + b) >= best_thr).astype(int)
    tp = int(np.sum((preds==1)&(y_hld==1))); fp = int(np.sum((preds==1)&(y_hld==0)))
    fn = int(np.sum((preds==0)&(y_hld==1))); tn = int(np.sum((preds==0)&(y_hld==0)))
    acc  = (tp+tn)/max(len(y_hld),1); prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
    scores = sigmoid(X_hld @ w + b)
    desc = np.argsort(-scores); tp_c = 0; auc = 0.0
    tp_tot = int(np.sum(y_hld==1)); fp_tot = int(np.sum(y_hld==0))
    for idx in desc:
        if y_hld[idx]==1: tp_c += 1
        else: auc += tp_c
    auc /= max(tp_tot*fp_tot, 1)
    wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y_hld),1)
    return dict(thr=round(best_thr,2), accuracy=round(acc,6),
                precision=round(prec,6), recall=round(rec,6),
                f1=round(f1,6), fpr=round(fpr,6),
                roc_auc=round(auc,6), weighted_f1=round(wf1_f,6),
                tp=tp, fp=fp, fn=fn, tn=tn)

# ── Agrégateurs ────────────────────────────────────────────────────
total = sum(u["n"] for u in updates)
w_avg = sum(u["w"]*(u["n"]/total) for u in updates).astype(np.float32)
b_avg = float(sum(u["b"]*(u["n"]/total) for u in updates))

def multikrum(updates, f=4):
    ws = [u["w"] for u in updates]; n = len(ws)
    k  = max(1, n - f - 2)
    scores = []
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
    n  = len(updates); k = max(1, int(n*trim))
    return (np.sort(ws, axis=0)[k:n-k].mean(axis=0).astype(np.float32),
            float(np.sort(bs)[k:n-k].mean()))

aggs = {}
t0 = time.time()
aggs["fedavg"]      = (w_avg, b_avg, time.time()-t0, len(updates), 0)
t0 = time.time(); wk, bk, sel = multikrum(updates)
aggs["multikrum"]   = (wk, bk, time.time()-t0, sel, len(updates)-sel)
t0 = time.time(); wt, bt = trimmedmean(updates)
aggs["trimmedmean"] = (wt, bt, time.time()-t0, len(updates), 0)

rows = []
for agg_name, (w, b, agg_t, sel, rej) in aggs.items():
    res = eval_model(w, b, X_val, y_val, X_hld, y_hld)
    rows.append({"seed": seed_id, "aggregator": agg_name, "round": final_r,
                 "threshold": res["thr"], "weighted_f1": res["weighted_f1"],
                 "f1": res["f1"], "accuracy": res["accuracy"],
                 "precision": res["precision"], "recall": res["recall"],
                 "fpr": res["fpr"], "roc_auc": res["roc_auc"],
                 "selected_count": sel, "rejected_count": rej,
                 "aggregation_time_ms": round(agg_t*1000,3),
                 "tp": res["tp"], "fp": res["fp"], "fn": res["fn"], "tn": res["tn"]})
    print(f"  seed={seed_id} {agg_name:12s} thr={res['thr']:.2f} "
          f"wf1={res['weighted_f1']:.6f} f1={res['f1']:.6f} "
          f"fpr={res['fpr']:.6f} auc={res['roc_auc']:.6f}")

fields = ["seed","aggregator","round","threshold","weighted_f1","f1","accuracy",
          "precision","recall","fpr","roc_auc","selected_count","rejected_count",
          "aggregation_time_ms","tp","fp","fn","tn"]
with open(sum_csv,"w",newline="") as f:
    wr = csv.DictWriter(f, fieldnames=fields); wr.writeheader(); wr.writerows(rows)

paper_fields = ["seed","aggregator","threshold","weighted_f1","f1","accuracy",
                "fpr","roc_auc","aggregation_time_ms"]
with open(paper_csv,"w",newline="") as f:
    wr = csv.DictWriter(f, fieldnames=paper_fields)
    wr.writeheader()
    wr.writerows([{k:r[k] for k in paper_fields} for r in rows])

print(f"SUMMARY_CSV={sum_csv}")
print(f"PAPER_CSV={paper_csv}")
PY
  echo "=== SEED $SEED DONE ==="
  echo "$OUT" >> "$MASTER_OUT/.seed_dirs"

done  # fin seeds

# ─── Agrégation mean ± std sur les 3 seeds ───────────────────────────
echo ""
echo "================================================================"
echo "AGRÉGATION FINALE — mean ± std (3 seeds)"
echo "================================================================"

python3 - "$MASTER_OUT" "$SEEDS" <<'PY'
import sys, csv, pathlib, numpy as np, json
from collections import defaultdict

master = pathlib.Path(sys.argv[1])
seeds  = [int(s) for s in sys.argv[2].split()]

# Charger tous les paper CSV des seeds
all_rows = []
for s in seeds:
    pcsv = master / f"seed_{s}" / "tables_input" / "federated_final_paper.csv"
    if not pcsv.exists():
        print(f"  WARN: introuvable {pcsv}"); continue
    with open(pcsv) as f:
        for row in csv.DictReader(f):
            all_rows.append(row)

# Grouper par agrégateur
metrics = ["weighted_f1","f1","accuracy","fpr","roc_auc","aggregation_time_ms"]
by_agg  = defaultdict(lambda: defaultdict(list))
for row in all_rows:
    agg = row["aggregator"]
    for m in metrics:
        by_agg[agg][m].append(float(row[m]))
    by_agg[agg]["threshold"].append(float(row["threshold"]))

# Calculer mean ± std
agg_order = ["fedavg","multikrum","trimmedmean"]
out_rows  = []
print(f"\n{'Aggregator':12s} | {'Thr(mean)':9s} | {'W-F1 mean±std':18s} | {'F1 mean±std':18s} | {'FPR mean±std':15s} | {'AUC mean±std':15s} | {'Time(ms)':8s}")
print("-"*110)
for agg in agg_order:
    d = by_agg[agg]
    if not d: continue
    row = {"aggregator": agg}
    for m in metrics + ["threshold"]:
        vals = np.array(d[m])
        row[f"{m}_mean"] = round(float(vals.mean()),6)
        row[f"{m}_std"]  = round(float(vals.std()),6)
        row[f"{m}_min"]  = round(float(vals.min()),6)
        row[f"{m}_max"]  = round(float(vals.max()),6)
    out_rows.append(row)
    print(f"{agg:12s} | {row['threshold_mean']:.2f}      "
          f"| {row['weighted_f1_mean']:.4f}±{row['weighted_f1_std']:.4f}    "
          f"| {row['f1_mean']:.4f}±{row['f1_std']:.4f}    "
          f"| {row['fpr_mean']:.4f}±{row['fpr_std']:.4f}  "
          f"| {row['roc_auc_mean']:.4f}±{row['roc_auc_std']:.4f}  "
          f"| {row['aggregation_time_ms_mean']:.3f}")

# Sauvegarder
out_csv = master / "AGGREGATE" / "mean_std_paper.csv"
fields  = (["aggregator"] +
           [f"{m}_{s}" for m in ["threshold","weighted_f1","f1","accuracy","fpr","roc_auc","aggregation_time_ms"]
            for s in ["mean","std","min","max"]])
with open(out_csv, "w", newline="") as f:
    wr = csv.DictWriter(f, fieldnames=fields)
    wr.writeheader(); wr.writerows(out_rows)
print(f"\nMEAN_STD_CSV={out_csv}")

# Charger aussi les per-round metrics pour les figures
per_round_out = master / "AGGREGATE" / "per_round_all_seeds.csv"
pr_rows = []
for s in seeds:
    rcsv = master / f"seed_{s}" / "figures_input" / "federated_round_metrics.csv"
    if not rcsv.exists(): continue
    with open(rcsv) as f:
        for row in csv.DictReader(f):
            row["seed"] = s
            pr_rows.append(row)
if pr_rows:
    pfields = ["seed"] + list(pr_rows[0].keys())[:-1]  # seed en premier
    pfields = list(dict.fromkeys(["seed","round","aggregator","threshold",
                                  "weighted_f1","f1","accuracy","fpr","roc_auc"]))
    with open(per_round_out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=pfields, extrasaction="ignore")
        wr.writeheader(); wr.writerows(pr_rows)
    print(f"PER_ROUND_CSV={per_round_out}")

print(f"\nDONE — résultats dans {master}/AGGREGATE/")
PY

echo ""
echo "================================================================"
echo "SCRIPT 103b TERMINÉ"
echo "MASTER_OUT=$MASTER_OUT"
echo "================================================================"
echo "$MASTER_OUT" > "$RUN_DIR/.last_federated_3seeds_dir"
