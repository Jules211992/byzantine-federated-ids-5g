from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

RUN_DIR = Path.home() / "byz-fed-ids-5g" / "rev" / "runs"
LATEST_RUN = sorted(RUN_DIR.glob("rev_*_5g"))[-1]

FINAL_DIRS = sorted(LATEST_RUN.glob("FINAL_RESULTS_*"))
if not FINAL_DIRS:
    raise SystemExit("ERROR: FINAL_RESULTS_* introuvable")
FINAL_DIR = FINAL_DIRS[-1]

PUB_DIRS = sorted(LATEST_RUN.glob("publication_bundle_*"))
if not PUB_DIRS:
    raise SystemExit("ERROR: publication_bundle_* introuvable")
PUB_DIR = PUB_DIRS[-1]

OUT = LATEST_RUN / "ieee_final_figures_tables"
OUT.mkdir(parents=True, exist_ok=True)

DPI = 300

clean_progress = FINAL_DIR / "clean_20rounds_progression.csv"
clean_paper = FINAL_DIR / "clean_20rounds_paper.csv"
clean_summary = FINAL_DIR / "clean_20rounds_summary.csv"
byz_paper = FINAL_DIR / "byzantine_all_attacks_paper.csv"
byz_full = FINAL_DIR / "byzantine_all_results_full.csv"
paper_main = PUB_DIR / "tables_input" / "paper_main_metrics.csv"

for p in [clean_progress, clean_paper, clean_summary, byz_paper, byz_full, paper_main]:
    if not p.exists():
        raise SystemExit(f"ERROR: fichier introuvable: {p}")

df_clean_progress = pd.read_csv(clean_progress)
df_clean_paper = pd.read_csv(clean_paper)
df_clean_summary = pd.read_csv(clean_summary)
df_byz_paper = pd.read_csv(byz_paper)
df_byz_full = pd.read_csv(byz_full)
df_main = pd.read_csv(paper_main)

def normalize_columns(df):
    df = df.copy()
    df.columns = [str(c).strip() for c in df.columns]
    rename_map = {}
    for c in df.columns:
        cl = c.strip().lower().replace("-", "_").replace(" ", "_")
        if cl == "attack":
            rename_map[c] = "Attack"
        elif cl == "ratio":
            rename_map[c] = "Ratio"
        elif cl == "aggregator":
            rename_map[c] = "Aggregator"
        elif cl == "f1":
            rename_map[c] = "F1"
        elif cl == "fpr":
            rename_map[c] = "FPR"
        elif cl in ("roc_auc", "rocauc", "auc"):
            rename_map[c] = "ROC-AUC"
        elif cl == "weighted_f1":
            rename_map[c] = "weighted_f1"
        elif cl == "accuracy":
            rename_map[c] = "accuracy"
        elif cl == "aggregation_time_ms":
            rename_map[c] = "aggregation_time_ms"
    df = df.rename(columns=rename_map)
    return df

df_clean_paper = normalize_columns(df_clean_paper)
df_clean_summary = normalize_columns(df_clean_summary)
df_byz_paper = normalize_columns(df_byz_paper)
df_byz_full = normalize_columns(df_byz_full)
df_main = normalize_columns(df_main)

required_byz = ["Attack", "Ratio", "Aggregator", "F1", "FPR", "ROC-AUC"]
missing = [c for c in required_byz if c not in df_byz_paper.columns]
if missing:
    print("Colonnes disponibles dans byzantine_all_attacks_paper.csv :", list(df_byz_paper.columns))
    raise SystemExit(f"ERROR: colonnes manquantes dans byz paper: {missing}")

def save_fig(fig, name, width_in, height_in):
    fig.set_size_inches(width_in, height_in)
    fig.tight_layout()
    fig.savefig(OUT / f"{name}.png", dpi=DPI, bbox_inches="tight")
    fig.savefig(OUT / f"{name}.pdf", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

def save_table_csv_tex(df, stem):
    df.to_csv(OUT / f"{stem}.csv", index=False)
    with open(OUT / f"{stem}.tex", "w") as f:
        cols = "l" + "c" * (len(df.columns) - 1)
        f.write("\\begin{tabular}{" + cols + "}\n")
        f.write("\\hline\n")
        f.write(" & ".join(map(str, df.columns)) + " \\\\\n")
        f.write("\\hline\n")
        for _, row in df.iterrows():
            vals = []
            for v in row:
                if isinstance(v, float):
                    vals.append(f"{v:.4f}")
                else:
                    vals.append(str(v))
            f.write(" & ".join(vals) + " \\\\\n")
        f.write("\\hline\n")
        f.write("\\end{tabular}\n")

def ieee_single():
    return 3.5, 2.2

def ieee_double():
    return 7.16, 2.6

save_table_csv_tex(df_clean_paper, "table_clean_final_paper")
save_table_csv_tex(df_clean_summary, "table_clean_final_summary")
save_table_csv_tex(df_byz_paper, "table_byzantine_paper")
save_table_csv_tex(df_main, "table_main_system_metrics")

dataset_table = pd.DataFrame([
    ["Dataset", "5G-NIDD"],
    ["Clients", "20"],
    ["Train samples total", "972700"],
    ["Global test samples", "243160"],
    ["Features", "50"],
    ["Classes", "2"],
    ["Training mode", "Federated learning"],
    ["Evaluation", "Global weighted-F1, F1, Accuracy, FPR, ROC-AUC"],
], columns=["Field", "Value"])
save_table_csv_tex(dataset_table, "table_dataset_description")

blockchain_table = pd.DataFrame([
    ["Consensus / network", "Hyperledger Fabric permissioned"],
    ["Load profile", "load-balanced5"],
    ["Selected point", "400ms-10k-50MB"],
    ["Send rate range", "500 to 4000 TPS"],
    ["Observed throughput", "619.9 TPS"],
    ["Latency range", "0.42 to 0.49 s"],
    ["Status", "Retained for final paper"],
], columns=["Field", "Value"])
save_table_csv_tex(blockchain_table, "table_blockchain_selected_point")

ipfs_table = pd.DataFrame([
    ["Storage layer", "IPFS / IPFS Cluster"],
    ["Largest retained size", "50 MB"],
    ["Integration mode", "Off-chain content-addressed storage"],
    ["Use in paper", "Performance table + architecture discussion"],
], columns=["Field", "Value"])
save_table_csv_tex(ipfs_table, "table_ipfs_description")

fig = plt.figure()
for metric, marker in [("weighted_f1", "o"), ("f1", "s"), ("accuracy", "^"), ("roc_auc", "d")]:
    if metric in df_clean_progress.columns:
        plt.plot(df_clean_progress["round"], df_clean_progress[metric], marker=marker, linewidth=1.5, markersize=4, label=metric.upper())
plt.xlabel("Round")
plt.ylabel("Score")
plt.xticks(df_clean_progress["round"])
plt.grid(True, alpha=0.3)
plt.legend(frameon=False, fontsize=7, ncol=2)
w, h = ieee_double()
save_fig(fig, "fig_clean_learning_progress", w, h)

fig = plt.figure()
plt.plot(df_clean_progress["round"], df_clean_progress["fpr"], marker="o", linewidth=1.5, markersize=4)
plt.xlabel("Round")
plt.ylabel("FPR")
plt.xticks(df_clean_progress["round"])
plt.grid(True, alpha=0.3)
w, h = ieee_single()
save_fig(fig, "fig_clean_fpr_progress", w, h)

fig = plt.figure()
x = np.arange(len(df_clean_paper))
barw = 0.18
for i, metric in enumerate(["weighted_f1", "accuracy", "roc_auc", "f1"]):
    col = metric
    if col in df_clean_paper.columns:
        plt.bar(x + (i - 1.5) * barw, df_clean_paper[col], width=barw, label=metric.upper())
plt.xticks(x, df_clean_paper["Aggregator"])
plt.ylabel("Score")
plt.grid(True, axis="y", alpha=0.3)
plt.legend(frameon=False, fontsize=7, ncol=2)
w, h = ieee_double()
save_fig(fig, "fig_clean_aggregator_comparison", w, h)

fig = plt.figure()
x = np.arange(len(df_clean_paper))
if "fpr" in df_clean_paper.columns:
    plt.bar(x - 0.15, df_clean_paper["fpr"], width=0.3, label="FPR")
if "aggregation_time_ms" in df_clean_paper.columns:
    plt.bar(x + 0.15, df_clean_paper["aggregation_time_ms"], width=0.3, label="Agg time (ms)")
plt.xticks(x, df_clean_paper["Aggregator"])
plt.ylabel("Value")
plt.grid(True, axis="y", alpha=0.3)
plt.legend(frameon=False, fontsize=7)
w, h = ieee_single()
save_fig(fig, "fig_clean_fpr_time", w, h)

attack_order = ["signflip", "gaussian", "scaling", "random", "backdoor"]
ratio_order = ["20%", "30%"]
agg_order = ["fedavg", "multikrum", "trimmedmean"]

df_byz_paper["Attack"] = df_byz_paper["Attack"].astype(str).str.strip().str.lower()
df_byz_paper["Ratio"] = df_byz_paper["Ratio"].astype(str).str.strip()
df_byz_paper["Aggregator"] = df_byz_paper["Aggregator"].astype(str).str.strip().str.lower()

df_byz_paper["Attack"] = pd.Categorical(df_byz_paper["Attack"], categories=attack_order, ordered=True)
df_byz_paper["Ratio"] = pd.Categorical(df_byz_paper["Ratio"], categories=ratio_order, ordered=True)
df_byz_paper["Aggregator"] = pd.Categorical(df_byz_paper["Aggregator"], categories=agg_order, ordered=True)
df_byz_paper = df_byz_paper.sort_values(["Attack", "Ratio", "Aggregator"])

pivot_f1 = df_byz_paper.pivot_table(index=["Attack", "Ratio"], columns="Aggregator", values="F1")
pivot_auc = df_byz_paper.pivot_table(index=["Attack", "Ratio"], columns="Aggregator", values="ROC-AUC")
pivot_fpr = df_byz_paper.pivot_table(index=["Attack", "Ratio"], columns="Aggregator", values="FPR")

labels = [f"{a}\n{r}" for a, r in pivot_f1.index]

fig = plt.figure()
x = np.arange(len(labels))
barw = 0.25
for i, agg in enumerate(agg_order):
    if agg in pivot_f1.columns:
        plt.bar(x + (i - 1) * barw, pivot_f1[agg].values, width=barw, label=agg)
plt.xticks(x, labels, fontsize=7)
plt.ylabel("F1")
plt.grid(True, axis="y", alpha=0.3)
plt.legend(frameon=False, fontsize=7, ncol=3)
w, h = ieee_double()
save_fig(fig, "fig_byzantine_f1_all_attacks", w, h)

fig = plt.figure()
x = np.arange(len(labels))
barw = 0.25
for i, agg in enumerate(agg_order):
    if agg in pivot_auc.columns:
        plt.bar(x + (i - 1) * barw, pivot_auc[agg].values, width=barw, label=agg)
plt.xticks(x, labels, fontsize=7)
plt.ylabel("ROC-AUC")
plt.grid(True, axis="y", alpha=0.3)
plt.legend(frameon=False, fontsize=7, ncol=3)
w, h = ieee_double()
save_fig(fig, "fig_byzantine_rocauc_all_attacks", w, h)

fig = plt.figure()
x = np.arange(len(labels))
barw = 0.25
for i, agg in enumerate(agg_order):
    if agg in pivot_fpr.columns:
        plt.bar(x + (i - 1) * barw, pivot_fpr[agg].values, width=barw, label=agg)
plt.xticks(x, labels, fontsize=7)
plt.ylabel("FPR")
plt.grid(True, axis="y", alpha=0.3)
plt.legend(frameon=False, fontsize=7, ncol=3)
w, h = ieee_double()
save_fig(fig, "fig_byzantine_fpr_all_attacks", w, h)

fig = plt.figure()
sub = df_byz_paper[df_byz_paper["Attack"] == "backdoor"].copy()
sub["Label"] = sub["Ratio"].astype(str) + "-" + sub["Aggregator"].astype(str)
plt.bar(np.arange(len(sub)), sub["F1"])
plt.xticks(np.arange(len(sub)), sub["Label"], rotation=25, ha="right", fontsize=7)
plt.ylabel("F1")
plt.grid(True, axis="y", alpha=0.3)
w, h = ieee_single()
save_fig(fig, "fig_backdoor_focus_f1", w, h)

fig = plt.figure()
sub = df_byz_paper[df_byz_paper["Attack"] == "backdoor"].copy()
sub["Label"] = sub["Ratio"].astype(str) + "-" + sub["Aggregator"].astype(str)
plt.bar(np.arange(len(sub)), sub["FPR"])
plt.xticks(np.arange(len(sub)), sub["Label"], rotation=25, ha="right", fontsize=7)
plt.ylabel("FPR")
plt.grid(True, axis="y", alpha=0.3)
w, h = ieee_single()
save_fig(fig, "fig_backdoor_focus_fpr", w, h)

readme = []
readme.append("IEEE FINAL FIGURES AND TABLES")
readme.append(f"OUT={OUT}")
readme.append("")
readme.append("FIGURES")
for p in sorted(OUT.glob("fig_*.png")):
    readme.append(p.name)
readme.append("")
readme.append("TABLES")
for p in sorted(OUT.glob("table_*.csv")):
    readme.append(p.name)
(OUT / "README.txt").write_text("\n".join(readme))

print(f"OUT={OUT}")
print("Colonnes byzantine:", list(df_byz_paper.columns))
for p in sorted(OUT.iterdir()):
    print(p.name)
