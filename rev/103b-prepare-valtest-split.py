#!/usr/bin/env python3
"""
103b-prepare-valtest-split.py
Prend global_test_X.npy / global_test_y.npy et les divise en :
  - global_val_X.npy   / global_val_y.npy    (VAL_FRAC=0.20)
  - global_holdout_X.npy / global_holdout_y.npy  (80%)
Usage:
  python3 103b-prepare-valtest-split.py --splits-dir <SPLITS_DIR> [--seed 42]
"""
import argparse, pathlib, numpy as np, json, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--splits-dir", required=True)
    ap.add_argument("--seed",     type=int,   default=42)
    ap.add_argument("--val-frac", type=float, default=0.20)
    args = ap.parse_args()

    splits = pathlib.Path(args.splits_dir)
    test_X_path = splits / "global_test_X.npy"
    test_y_path = splits / "global_test_y.npy"

    if not test_X_path.exists():
        sys.exit(f"ERROR: introuvable: {test_X_path}")

    print(f"splits_dir : {splits}")
    print(f"seed       : {args.seed}")
    print(f"val_frac   : {args.val_frac}")

    X = np.load(test_X_path).astype(np.float32)
    y = np.load(test_y_path).astype(np.int32)
    N = len(y)
    print(f"global_test: N={N}, X.shape={X.shape}")
    print(f"  benign={int(np.sum(y==0))}, malicious={int(np.sum(y==1))}")

    rng = np.random.default_rng(args.seed)
    idx = rng.permutation(N)
    n_val  = int(N * args.val_frac)

    val_idx  = idx[:n_val]
    hold_idx = idx[n_val:]

    X_val  = X[val_idx];  y_val  = y[val_idx]
    X_hold = X[hold_idx]; y_hold = y[hold_idx]

    print(f"Val    : N={n_val}  benign={int(np.sum(y_val==0))}  malicious={int(np.sum(y_val==1))}")
    print(f"Holdout: N={len(hold_idx)} benign={int(np.sum(y_hold==0))} malicious={int(np.sum(y_hold==1))}")

    np.save(splits / "global_val_X.npy",     X_val)
    np.save(splits / "global_val_y.npy",     y_val)
    np.save(splits / "global_holdout_X.npy", X_hold)
    np.save(splits / "global_holdout_y.npy", y_hold)

    meta = {"seed": args.seed, "val_frac": args.val_frac,
            "N_total": N, "N_val": n_val, "N_holdout": len(hold_idx),
            "val_idx": val_idx.tolist(), "hold_idx": hold_idx.tolist()}
    with open(splits / "valtest_split_meta.json", "w") as f:
        json.dump(meta, f, indent=2)

    print("DONE — fichiers crees dans", splits)

if __name__ == "__main__":
    main()
