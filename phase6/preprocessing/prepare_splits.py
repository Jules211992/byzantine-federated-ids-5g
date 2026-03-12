import csv, json, os, collections
import numpy as np

DATASET  = os.path.expanduser("~/byz-fed-ids-5g/phase6/dataset/UNSW_NB15_training-set.csv")
OUT_DIR  = os.path.expanduser("~/byz-fed-ids-5g/phase6/splits")
os.makedirs(OUT_DIR, exist_ok=True)

CLIENT_CLASSES = {
    "edge-client-1": ["Normal", "Generic", "Exploits"],
    "edge-client-2": ["Normal", "Fuzzers", "DoS"],
    "edge-client-3": ["Normal", "Reconnaissance", "Analysis"],
    "edge-client-4": ["Normal", "Backdoor", "Shellcode", "Worms"],
}

CATEGORICAL = {"proto", "service", "state"}
DROP        = {"id", "attack_cat", "label"}

print("=== Chargement UNSW-NB15 ===")
rows = []
with open(DATASET) as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    num_cols = [c for c in fieldnames if c not in DROP and c not in CATEGORICAL]
    cat_cols  = [c for c in fieldnames if c in CATEGORICAL]
    
    proto_vals   = set()
    service_vals = set()
    state_vals   = set()
    
    for row in reader:
        rows.append(row)
        proto_vals.add(row["proto"].strip())
        service_vals.add(row["service"].strip())
        state_vals.add(row["state"].strip())

proto_list   = sorted(proto_vals)
service_list = sorted(service_vals)
state_list   = sorted(state_vals)

print(f"  lignes        : {len(rows)}")
print(f"  features num  : {len(num_cols)}")
print(f"  proto vals    : {len(proto_list)}")
print(f"  service vals  : {len(service_list)}")
print(f"  state vals    : {len(state_list)}")
n_features = len(num_cols) + len(proto_list) + len(service_list) + len(state_list)
print(f"  total features: {n_features}")

def encode_row(row):
    feats = []
    for c in num_cols:
        try:
            feats.append(float(row[c]))
        except:
            feats.append(0.0)
    for v in proto_list:
        feats.append(1.0 if row["proto"].strip() == v else 0.0)
    for v in service_list:
        feats.append(1.0 if row["service"].strip() == v else 0.0)
    for v in state_list:
        feats.append(1.0 if row["state"].strip() == v else 0.0)
    return feats

print("\n=== Encodage et normalisation ===")
all_X = np.array([encode_row(r) for r in rows], dtype=np.float32)
all_y = np.array([int(r["label"]) for r in rows], dtype=np.int32)
all_cat = [r["attack_cat"].strip() for r in rows]

feat_min = all_X.min(axis=0)
feat_max = all_X.max(axis=0)
feat_range = feat_max - feat_min
feat_range[feat_range == 0] = 1.0
all_X_norm = (all_X - feat_min) / feat_range

np.save(f"{OUT_DIR}/feat_min.npy", feat_min)
np.save(f"{OUT_DIR}/feat_max.npy", feat_max)
with open(f"{OUT_DIR}/feature_names.json", "w") as f:
    json.dump({"num": num_cols, "proto": proto_list,
               "service": service_list, "state": state_list,
               "n_features": n_features}, f, indent=2)
print(f"  normalisation sauvegardée")

np.random.seed(42)
global_idx = np.random.permutation(len(rows))
split_80 = int(0.8 * len(rows))
test_idx  = global_idx[split_80:]

test_X = all_X_norm[test_idx]
test_y = all_y[test_idx]
np.save(f"{OUT_DIR}/global_test_X.npy", test_X)
np.save(f"{OUT_DIR}/global_test_y.npy", test_y)
print(f"  test global   : {len(test_X)} samples (20% stratifié)")

stats = {}
print("\n=== Splits Non-IID par client ===")
for client_id, classes in CLIENT_CLASSES.items():
    mask = np.array([cat in classes for cat in all_cat])
    idx  = np.where(mask)[0]
    
    np.random.seed(42)
    idx = np.random.permutation(idx)
    n_train = int(0.8 * len(idx))
    
    tr_idx = idx[:n_train]
    te_idx = idx[n_train:]
    
    tr_X = all_X_norm[tr_idx]
    tr_y = all_y[tr_idx]
    te_X = all_X_norm[te_idx]
    te_y = all_y[te_idx]
    
    np.save(f"{OUT_DIR}/{client_id}_train_X.npy", tr_X)
    np.save(f"{OUT_DIR}/{client_id}_train_y.npy", tr_y)
    np.save(f"{OUT_DIR}/{client_id}_test_X.npy",  te_X)
    np.save(f"{OUT_DIR}/{client_id}_test_y.npy",  te_y)
    
    n_attack = int(tr_y.sum())
    n_normal = len(tr_y) - n_attack
    cat_dist = collections.Counter([all_cat[i] for i in tr_idx])
    
    stats[client_id] = {
        "classes":       classes,
        "n_features":    n_features,
        "train_samples": len(tr_y),
        "train_normal":  n_normal,
        "train_attack":  n_attack,
        "test_samples":  len(te_y),
        "cat_dist":      dict(cat_dist),
    }
    print(f"  {client_id}: train={len(tr_y)} (normal={n_normal}, attack={n_attack}) "
          f"test={len(te_y)} classes={classes}")

with open(f"{OUT_DIR}/split_stats.json", "w") as f:
    json.dump(stats, f, indent=2)

print(f"\n✓ Splits sauvegardés dans {OUT_DIR}")
print(json.dumps({k: {
    "train": v["train_samples"],
    "normal": v["train_normal"],
    "attack": v["train_attack"],
    "classes": v["classes"]
} for k, v in stats.items()}, indent=2))
