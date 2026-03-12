#!/usr/bin/env python3
import numpy as np, csv, glob, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator, FormatStrFormatter
from collections import defaultdict

RUN_DIR = sorted(glob.glob(os.path.expanduser("~/byz-fed-ids-5g/rev/runs/rev_*_5g")))[-1]
SEEDS_DIR = sorted(glob.glob(os.path.join(RUN_DIR, "federated_3seeds_*")))[-1]
BYZ_DIR   = sorted(glob.glob(os.path.join(RUN_DIR, "byzantine_backdoor20r_*")))[-1]
AGG_DIR   = os.path.join(SEEDS_DIR, "AGGREGATE")
MEAN_STD_CSV  = os.path.join(AGG_DIR, "mean_std_paper.csv")
PER_ROUND_CSV = os.path.join(AGG_DIR, "per_round_all_seeds.csv")
BYZ_CSV = os.path.join(BYZ_DIR, "tables_input", "backdoor_all_rounds.csv")
OUT_FIG = os.path.join(RUN_DIR, "figures_106b")
OUT_TEX = os.path.join(RUN_DIR, "tables_106b")
os.makedirs(OUT_FIG, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)
print(f"SEEDS_DIR : {SEEDS_DIR}")
print(f"BYZ_DIR   : {BYZ_DIR}")

mean_std = {}
with open(MEAN_STD_CSV) as f:
    for row in csv.DictReader(f):
        agg = row["aggregator"]
        mean_std[agg] = {k: float(v) for k, v in row.items() if k != "aggregator"}

per_round = defaultdict(lambda: defaultdict(list))
with open(PER_ROUND_CSV) as f:
    for row in csv.DictReader(f):
        r = int(row["round"])
        per_round[r]["wf1"].append(float(row["weighted_f1"]))
        per_round[r]["f1"].append(float(row["f1"]))
        per_round[r]["roc_auc"].append(float(row["roc_auc"]))

rounds   = sorted(per_round.keys())
wf1_mean = [np.mean(per_round[r]["wf1"]) for r in rounds]
wf1_std  = [np.std(per_round[r]["wf1"])  for r in rounds]
f1_mean  = [np.mean(per_round[r]["f1"])  for r in rounds]
f1_std   = [np.std(per_round[r]["f1"])   for r in rounds]
auc_mean = [np.mean(per_round[r]["roc_auc"]) for r in rounds]
auc_std  = [np.std(per_round[r]["roc_auc"])  for r in rounds]

BASELINE_F1  = mean_std["fedavg"]["f1_mean"]
BASELINE_AUC = mean_std["fedavg"]["roc_auc_mean"]
BASELINE_FPR = mean_std["fedavg"]["fpr_mean"]
print(f"Baseline FedAvg: F1={BASELINE_F1:.6f} AUC={BASELINE_AUC:.6f}")

byz_backdoor = defaultdict(lambda: defaultdict(dict))
with open(BYZ_CSV) as f:
    for row in csv.DictReader(f):
        ratio = row["byz_ratio"]
        agg   = row["aggregator"]
        r     = int(row["round"])
        if r == max(int(x["round"]) for x in csv.DictReader(open(BYZ_CSV)) if x["byz_ratio"]==ratio and x["aggregator"]==agg):
            byz_backdoor[ratio][agg] = {"f1":float(row["f1"]),"fpr":float(row["fpr"]),"auc":float(row["roc_auc"])}

# Re-lire proprement le dernier round par ratio/agg
byz_last = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))
with open(BYZ_CSV) as f:
    for row in csv.DictReader(f):
        ratio = row["byz_ratio"]; agg = row["aggregator"]; r = int(row["round"])
        if r > byz_last[ratio][agg].get("round", 0):
            byz_last[ratio][agg] = {"round":r,"f1":float(row["f1"]),"fpr":float(row["fpr"]),"auc":float(row["roc_auc"])}

byz_other = {
    ("Gaussian","20%"):{"fedavg":(0.9624,0.0447,0.9800),"multikrum":(0.9596,0.0398,0.9799),"trimmedmean":(0.9613,0.0438,0.9796)},
    ("Gaussian","30%"):{"fedavg":(0.9616,0.0435,0.9800),"multikrum":(0.9587,0.0366,0.9783),"trimmedmean":(0.9609,0.0432,0.9797)},
    ("Random",  "20%"):{"fedavg":(0.9620,0.0448,0.9799),"multikrum":(0.9592,0.0396,0.9798),"trimmedmean":(0.9605,0.0430,0.9796)},
    ("Random",  "30%"):{"fedavg":(0.9623,0.0445,0.9800),"multikrum":(0.9593,0.0369,0.9782),"trimmedmean":(0.9619,0.0443,0.9797)},
    ("Scaling", "20%"):{"fedavg":(0.9626,0.0451,0.9800),"multikrum":(0.9593,0.0394,0.9800),"trimmedmean":(0.9604,0.0425,0.9797)},
    ("Scaling", "30%"):{"fedavg":(0.9625,0.0451,0.9800),"multikrum":(0.9588,0.0364,0.9782),"trimmedmean":(0.9617,0.0442,0.9797)},
    ("Signflip","20%"):{"fedavg":(0.9627,0.0451,0.9800),"multikrum":(0.9586,0.0383,0.9800),"trimmedmean":(0.9618,0.0446,0.9797)},
    ("Signflip","30%"):{"fedavg":(0.9622,0.0445,0.9800),"multikrum":(0.9594,0.0374,0.9782),"trimmedmean":(0.9617,0.0443,0.9796)},
}
byz_full = dict(byz_other)
for ratio_str in ["20%","30%"]:
    byz_full[("Backdoor",ratio_str)] = {}
    for agg in ["fedavg","multikrum","trimmedmean"]:
        d = byz_last[ratio_str][agg]
        byz_full[("Backdoor",ratio_str)][agg] = (d["f1"],d["fpr"],d["auc"])

print("byz_full Backdoor 20%:", byz_full[("Backdoor","20%")])
print("byz_full Backdoor 30%:", byz_full[("Backdoor","30%")])

IEEE_W1 = 3.5; DPI = 300
plt.rcParams.update({"font.family":"serif","font.size":8,"axes.labelsize":8,
    "xtick.labelsize":7,"ytick.labelsize":7,"legend.fontsize":6.5,
    "lines.linewidth":1.3,"lines.markersize":4,"axes.linewidth":0.6,
    "grid.linewidth":0.4,"grid.alpha":0.35,"savefig.dpi":DPI,
    "savefig.bbox":"tight","savefig.pad_inches":0.03})
C = {"fedavg":"#1f77b4","multikrum":"#d62728","trimmedmean":"#2ca02c"}
LABELS = {"fedavg":"FedAvg","multikrum":"Multi-Krum","trimmedmean":"TrimmedMean"}
agg_list = ["fedavg","multikrum","trimmedmean"]
attacks  = ["Backdoor","Gaussian","Random","Scaling","Signflip"]

def savefig(name):
    plt.savefig(os.path.join(OUT_FIG, name+".pdf"))
    plt.savefig(os.path.join(OUT_FIG, name+".png"), dpi=DPI)
    plt.close()
    print(f"  {name} OK")

rr = np.array(rounds)

# FIG 1
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.5))
ax.plot(rr, wf1_mean, color=C["fedavg"], marker="o", markersize=3.5, linewidth=1.4, label="Weighted F1 (mean)")
ax.fill_between(rr, np.array(wf1_mean)-np.array(wf1_std), np.array(wf1_mean)+np.array(wf1_std), color=C["fedavg"], alpha=0.15, label="±1 std (3 seeds)")
ax.plot(rr, f1_mean, color=C["trimmedmean"], marker="^", markersize=3.5, linewidth=1.0, linestyle="--", label="F1 (mean)", alpha=0.85)
ax.fill_between(rr, np.array(f1_mean)-np.array(f1_std), np.array(f1_mean)+np.array(f1_std), color=C["trimmedmean"], alpha=0.12)
ax.axhline(y=mean_std["fedavg"]["weighted_f1_mean"], color="gray", linestyle=":", linewidth=0.9, label="Convergence R20")
ax.set_xlabel("Federated Round"); ax.set_ylabel("Score")
ax.set_xlim(0.5,20.5); ax.set_ylim(0.944,0.967)
ax.xaxis.set_major_locator(MultipleLocator(4)); ax.xaxis.set_minor_locator(MultipleLocator(2))
ax.yaxis.set_major_locator(MultipleLocator(0.005))
ax.grid(True, which="major"); ax.grid(True, which="minor", linestyle=":", alpha=0.2)
ax.legend(loc="lower right", framealpha=0.85)
wf1_r20 = mean_std["fedavg"]["weighted_f1_mean"]
ax.annotate(f"{wf1_r20:.4f}", xy=(20, wf1_r20), xytext=(16.5, 0.9555),
    arrowprops=dict(arrowstyle="->", lw=0.7, color="gray"), fontsize=6, color="gray")
plt.tight_layout(pad=0.3)
savefig("fig1_wf1_progression")

# FIG 2
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.5))
ax.plot(rr, auc_mean, color=C["multikrum"], marker="s", markersize=3.5, linewidth=1.4, label="ROC-AUC (mean)")
ax.fill_between(rr, np.array(auc_mean)-np.array(auc_std), np.array(auc_mean)+np.array(auc_std), color=C["multikrum"], alpha=0.15, label="±1 std (3 seeds)")
ax.axhline(y=BASELINE_AUC, color="gray", linestyle=":", linewidth=0.9, label=f"R20 = {BASELINE_AUC:.4f}")
ax.set_xlabel("Federated Round"); ax.set_ylabel("ROC-AUC")
ax.set_xlim(0.5,20.5); ax.set_ylim(0.9748,0.9822)
ax.xaxis.set_major_locator(MultipleLocator(4)); ax.xaxis.set_minor_locator(MultipleLocator(2))
ax.yaxis.set_major_locator(MultipleLocator(0.002))
ax.grid(True, which="major"); ax.grid(True, which="minor", linestyle=":", alpha=0.2)
ax.legend(loc="lower right", framealpha=0.85)
plt.tight_layout(pad=0.3)
savefig("fig2_rocauc_progression")

# FIG 3
fig, axes = plt.subplots(2, 2, figsize=(IEEE_W1, 3.2))
axes = axes.flatten()
metrics_fig3 = [("f1","F1-Score",0.954,0.967),("accuracy","Accuracy",0.946,0.957),("fpr","FPR",0.025,0.052),("roc_auc","ROC-AUC",0.978,0.984)]
xpos = np.arange(3); xlabels = ["FedAvg","M-Krum","Trimmed"]
bar_colors = [C["fedavg"],C["multikrum"],C["trimmedmean"]]
for ax, (key, ylabel, ymin, ymax) in zip(axes, metrics_fig3):
    vals = [mean_std[a][f"{key}_mean"] for a in agg_list]
    stds = [mean_std[a][f"{key}_std"]  for a in agg_list]
    bars = ax.bar(xpos, vals, width=0.55, color=bar_colors, edgecolor="white", linewidth=0.4,
                  yerr=stds, capsize=3, error_kw={"linewidth":0.8,"capthick":0.8})
    span = ymax-ymin
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+span*0.012,
                f"{v:.4f}", ha="center", va="bottom", fontsize=5.2, rotation=90)
    ax.set_ylabel(ylabel, fontsize=7); ax.set_xticks(xpos); ax.set_xticklabels(xlabels, fontsize=6.5)
    ax.set_ylim(ymin, ymax+span*0.35)
    ax.yaxis.set_major_locator(MultipleLocator(span/3))
    ax.yaxis.set_major_formatter(FormatStrFormatter("%.3f"))
    ax.grid(True, axis="y", alpha=0.4); ax.set_axisbelow(True)
plt.tight_layout(pad=0.4, h_pad=0.9, w_pad=0.6)
savefig("fig3_clean_comparison")

# FIG 4
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.8))
byz_avg = {}
for atk in attacks:
    byz_avg[atk] = {}
    for agg in agg_list:
        v20 = byz_full[(atk,"20%")][agg][0]; v30 = byz_full[(atk,"30%")][agg][0]
        byz_avg[atk][agg] = (v20+v30)/2
xi = np.arange(len(attacks)); w = 0.22
for i, agg in enumerate(agg_list):
    vals = [byz_avg[atk][agg] for atk in attacks]
    ax.bar(xi+(i-1)*w, vals, width=w, label=LABELS[agg], color=C[agg], edgecolor="white", linewidth=0.4)
ax.axhline(y=BASELINE_F1, color="black", linestyle="--", linewidth=1.0, label=f"Baseline = {BASELINE_F1:.4f}")
ax.set_ylabel("F1-Score"); ax.set_xlabel("Byzantine Attack Type")
ax.set_xticks(xi); ax.set_xticklabels(attacks, fontsize=7)
ax.set_ylim(0.954,0.967)
ax.yaxis.set_major_locator(MultipleLocator(0.003))
ax.yaxis.set_major_formatter(FormatStrFormatter("%.3f"))
ax.grid(True, axis="y", alpha=0.4); ax.set_axisbelow(True)
ax.legend(loc="lower right", framealpha=0.88, ncol=2, fontsize=6.2)
ax.text(0.01,0.02,"Backdoor: 20 rounds; others: 5 rounds", transform=ax.transAxes, fontsize=5, color="gray")
plt.tight_layout(pad=0.3)
savefig("fig4_byzantine_by_attack")

# FIG 5
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(IEEE_W1, 2.6))
ratios = ["20%","30%"]; xr = np.arange(2); w = 0.22
for i, agg in enumerate(agg_list):
    f1v  = [np.mean([byz_full[(atk,r)][agg][0] for atk in attacks]) for r in ratios]
    fprv = [np.mean([byz_full[(atk,r)][agg][1] for atk in attacks]) for r in ratios]
    off  = (i-1)*w
    ax1.bar(xr+off, f1v, width=w, label=LABELS[agg], color=C[agg], edgecolor="white", linewidth=0.4)
    ax2.bar(xr+off, fprv, width=w, color=C[agg], edgecolor="white", linewidth=0.4)
ax1.axhline(y=BASELINE_F1, color="black", linestyle="--", linewidth=0.9, label="Baseline")
ax1.set_ylabel("F1-Score"); ax1.set_xlabel("Byzantine Ratio")
ax1.set_xticks(xr); ax1.set_xticklabels(ratios)
ax1.set_ylim(0.955,0.967)
ax1.yaxis.set_major_locator(MultipleLocator(0.004))
ax1.yaxis.set_major_formatter(FormatStrFormatter("%.3f"))
ax1.grid(True, axis="y", alpha=0.4); ax1.set_axisbelow(True)
ax1.legend(loc="lower right", fontsize=5.5, framealpha=0.85)
ax2.set_ylabel("FPR"); ax2.set_xlabel("Byzantine Ratio")
ax2.set_xticks(xr); ax2.set_xticklabels(ratios)
ax2.set_ylim(0.025,0.052)
ax2.yaxis.set_major_locator(MultipleLocator(0.005))
ax2.yaxis.set_major_formatter(FormatStrFormatter("%.3f"))
ax2.grid(True, axis="y", alpha=0.4); ax2.set_axisbelow(True)
plt.tight_layout(pad=0.3, w_pad=0.8)
savefig("fig5_byzantine_by_ratio")

# TABLES
def fmt(v,d=4): return f"{v:.{d}f}"
agg_display = {"fedavg":"FedAvg","multikrum":"Multi-Krum","trimmedmean":"TrimmedMean"}

lines = []
lines.append(r"\begin{table}[!t]")
lines.append(r"\renewcommand{\arraystretch}{1.15}")
lines.append(r"\caption{Global Model Performance (3 Seeds, Val/Holdout Split, Round~20)}")
lines.append(r"\label{tab:clean}")
lines.append(r"\centering\scriptsize\setlength{\tabcolsep}{3pt}")
lines.append(r"\begin{tabular}{lcccccc}")
lines.append(r"\hline")
lines.append(r"\textbf{Aggregator} & \textbf{Thr.} & \textbf{W-F1} & \textbf{F1} & \textbf{FPR} & \textbf{ROC-AUC} & \textbf{T\,(ms)} \\")
lines.append(r"\hline")
for agg in agg_list:
    d = mean_std[agg]
    thr = fmt(d["threshold_mean"],2)
    wf1 = fmt(d["weighted_f1_mean"])+" $\\pm$ "+fmt(d["weighted_f1_std"])
    f1v = fmt(d["f1_mean"])+" $\\pm$ "+fmt(d["f1_std"])
    fpr = fmt(d["fpr_mean"])+" $\\pm$ "+fmt(d["fpr_std"])
    auc = fmt(d["roc_auc_mean"])+" $\\pm$ "+fmt(d["roc_auc_std"])
    tms = fmt(d["aggregation_time_ms_mean"],3)
    lines.append(f"{agg_display[agg]} & {thr} & {wf1} & {f1v} & {fpr} & {auc} & {tms} \\\\")
lines.append(r"\hline\end{tabular}\end{table}")
t3 = "\n".join(lines)

lines2 = []
lines2.append(r"\begin{table*}[!t]")
lines2.append(r"\renewcommand{\arraystretch}{1.1}")
lines2.append(r"\caption{Byzantine Attack Impact. $\dag$~Backdoor: 20 rounds; others: 5 rounds. Baseline (clean, R20): F1\,=\,"+fmt(BASELINE_F1)+r", FPR\,=\,"+fmt(BASELINE_FPR)+r".}")
lines2.append(r"\label{tab:byzantine}")
lines2.append(r"\centering\footnotesize\setlength{\tabcolsep}{4pt}")
lines2.append(r"\begin{tabular}{llccccr}")
lines2.append(r"\hline")
lines2.append(r"\textbf{Attack} & \textbf{Ratio} & \textbf{Aggregator} & \textbf{F1} & \textbf{FPR} & \textbf{ROC-AUC} & \textbf{$\Delta$F1} \\")
lines2.append(r"\hline")
prev_atk = None
for atk in attacks:
    for ratio in ["20%","30%"]:
        for agg in agg_list:
            f1v, fpr, auc = byz_full[(atk,ratio)][agg]
            delta = f1v - BASELINE_F1
            if prev_atk and prev_atk != atk:
                lines2.append(r"\hline")
            suffix = r" $\dag$" if atk == "Backdoor" else ""
            lines2.append(f"{atk}{suffix} & {ratio} & {agg_display[agg]} & {fmt(f1v)} & {fmt(fpr)} & {fmt(auc)} & ${delta:+.4f}$ \\\\")
            prev_atk = atk
lines2.append(r"\hline\end{tabular}\end{table*}")
t4 = "\n".join(lines2)

for fname, content in [("table3_clean_updated.tex",t3),("table4_byzantine_updated.tex",t4)]:
    path = os.path.join(OUT_TEX, fname)
    with open(path,"w") as f: f.write(content)
    print(f"  {fname} OK")

print("DONE")
print(f"Figures : {OUT_FIG}")
print(f"Tables  : {OUT_TEX}")
