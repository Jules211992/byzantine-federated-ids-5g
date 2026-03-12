#!/usr/bin/env python3
"""
Script 106v4 — Figures IEEE + Tables LaTeX
Corrections:
- Fig 2 : zones supprimées
- Fig 6 : échelle log Y (p95 10MB visible)
- Table 6 : Caliper benchmark ajoutée
- Clean final corrigé avec les vraies valeurs finales
- Table 3 corrigée
- rounds_data aligné sur le vrai CSV clean final
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.ticker import MultipleLocator, FormatStrFormatter
import os, glob

# ─── Trouver FINAL_RESULTS ────────────────────────────────────────────────────
RUN_DIR = sorted(glob.glob(os.path.expanduser(
    "~/byz-fed-ids-5g/rev/runs/rev_*_5g")))[-1]
FINAL   = sorted(glob.glob(os.path.join(RUN_DIR, "FINAL_RESULTS_*")))[-1]

FIG_DIR = os.path.join(FINAL, "figures")
TEX_DIR = os.path.join(FINAL, "tables_tex")
os.makedirs(FIG_DIR, exist_ok=True)
os.makedirs(TEX_DIR, exist_ok=True)

print(f"RUN_DIR : {RUN_DIR}")
print(f"FINAL   : {FINAL}")
print(f"FIG_DIR : {FIG_DIR}")
print(f"TEX_DIR : {TEX_DIR}")

# ─── Config IEEE ──────────────────────────────────────────────────────────────
IEEE_W1 = 3.5
DPI     = 300

plt.rcParams.update({
    'font.family':        'serif',
    'font.size':          8,
    'axes.labelsize':     8,
    'axes.titlesize':     8,
    'xtick.labelsize':    7,
    'ytick.labelsize':    7,
    'legend.fontsize':    6.5,
    'lines.linewidth':    1.3,
    'lines.markersize':   4,
    'axes.linewidth':     0.6,
    'grid.linewidth':     0.4,
    'grid.alpha':         0.35,
    'savefig.dpi':        DPI,
    'savefig.bbox':       'tight',
    'savefig.pad_inches': 0.03,
})

C = {
    'fedavg':      '#1f77b4',
    'multikrum':   '#d62728',
    'trimmedmean': '#2ca02c',
    'min_lat':     '#2ca02c',
    'avg_lat':     '#1f77b4',
    'max_lat':     '#d62728',
    'store':       '#1f77b4',
    'get':         '#ff7f0e',
    'throughput':  '#9467bd',
}
LABELS = {
    'fedavg':      'FedAvg',
    'multikrum':   'Multi-Krum',
    'trimmedmean': 'TrimmedMean',
}
agg_list = ['fedavg', 'multikrum', 'trimmedmean']

# ═══════════════════════════════════════════════════════════════════════════════
# DONNÉES
# ═══════════════════════════════════════════════════════════════════════════════

rounds_data = [
    (1,  0.948554, 0.955584, 0.975210),
    (2,  0.953735, 0.955028, 0.977443),
    (3,  0.956159, 0.958539, 0.977855),
    (4,  0.956783, 0.958267, 0.978025),
    (5,  0.957512, 0.959265, 0.978205),
    (6,  0.958030, 0.960423, 0.978461),
    (7,  0.958503, 0.960957, 0.978733),
    (8,  0.959011, 0.961666, 0.979013),
    (9,  0.959344, 0.961171, 0.979284),
    (10, 0.959641, 0.961905, 0.979551),
    (11, 0.959804, 0.961624, 0.979807),
    (12, 0.960140, 0.955654, 0.980025),
    (13, 0.961047, 0.956964, 0.980389),
    (14, 0.961406, 0.957435, 0.980652),
    (15, 0.961843, 0.957640, 0.980854),
    (16, 0.962156, 0.958663, 0.981096),
    (17, 0.962547, 0.959591, 0.981291),
    (18, 0.962699, 0.960351, 0.981460),
    (19, 0.962834, 0.960491, 0.981588),
    (20, 0.963052, 0.963290, 0.981827),
]
rnd   = [x[0] for x in rounds_data]
wf1   = [x[1] for x in rounds_data]
f1r   = [x[2] for x in rounds_data]
rocau = [x[3] for x in rounds_data]

clean_final = {
    'fedavg':      {'thr':0.44,'wf1':0.963052,'f1':0.963290,'acc':0.955967,'fpr':0.037314,'auc':0.981827,'time':0.001},
    'multikrum':   {'thr':0.53,'wf1':0.963099,'f1':0.957886,'acc':0.949934,'fpr':0.045321,'auc':0.980518,'time':1.441},
    'trimmedmean': {'thr':0.45,'wf1':0.962980,'f1':0.962385,'acc':0.950617,'fpr':0.045353,'auc':0.981349,'time':0.280},
}
BASELINE_F1  = 0.963290
BASELINE_AUC = 0.981827

attacks = ['Backdoor','Gaussian','Random','Scaling','Signflip']
byz_full = {
    ('Backdoor','20%'):{'fedavg':(0.9625,0.0450,0.9799),'multikrum':(0.9584,0.0379,0.9798),'trimmedmean':(0.9614,0.0442,0.9796)},
    ('Backdoor','30%'):{'fedavg':(0.9621,0.0445,0.9800),'multikrum':(0.9590,0.0369,0.9782),'trimmedmean':(0.9616,0.0443,0.9797)},
    ('Gaussian','20%'):{'fedavg':(0.9624,0.0447,0.9800),'multikrum':(0.9596,0.0398,0.9799),'trimmedmean':(0.9613,0.0438,0.9796)},
    ('Gaussian','30%'):{'fedavg':(0.9616,0.0435,0.9800),'multikrum':(0.9587,0.0366,0.9783),'trimmedmean':(0.9609,0.0432,0.9797)},
    ('Random',  '20%'):{'fedavg':(0.9620,0.0448,0.9799),'multikrum':(0.9592,0.0396,0.9798),'trimmedmean':(0.9605,0.0430,0.9796)},
    ('Random',  '30%'):{'fedavg':(0.9623,0.0445,0.9800),'multikrum':(0.9593,0.0369,0.9782),'trimmedmean':(0.9619,0.0443,0.9797)},
    ('Scaling', '20%'):{'fedavg':(0.9626,0.0451,0.9800),'multikrum':(0.9593,0.0394,0.9800),'trimmedmean':(0.9604,0.0425,0.9797)},
    ('Scaling', '30%'):{'fedavg':(0.9625,0.0451,0.9800),'multikrum':(0.9588,0.0364,0.9782),'trimmedmean':(0.9617,0.0442,0.9797)},
    ('Signflip','20%'):{'fedavg':(0.9627,0.0451,0.9800),'multikrum':(0.9586,0.0383,0.9800),'trimmedmean':(0.9618,0.0446,0.9797)},
    ('Signflip','30%'):{'fedavg':(0.9622,0.0445,0.9800),'multikrum':(0.9594,0.0374,0.9782),'trimmedmean':(0.9617,0.0443,0.9796)},
}

ipfs_data = [
    ('1 KB',   69.477,  32.239, 43.941),
    ('10 KB',  76.207,  31.817, 41.687),
    ('100 KB', 73.305,  33.947, 41.344),
    ('1 MB',   73.486,  39.245, 48.862),
    ('10 MB',  128.740, 78.863, 388.515),
]
ipfs_labels  = [x[0] for x in ipfs_data]
ipfs_store   = [x[1] for x in ipfs_data]
ipfs_get_p50 = [x[2] for x in ipfs_data]
ipfs_get_p95 = [x[3] for x in ipfs_data]

caliper = [
    ('500',  0.17, 0.42, 0.79, 498.4),
    ('1000', 0.14, 0.49, 1.01, 613.4),
    ('2000', 0.15, 0.48, 0.99, 619.9),
    ('3000', 0.14, 0.48, 1.04, 614.0),
    ('4000', 0.16, 0.48, 0.97, 614.0),
]
c_label = [x[0] for x in caliper]
c_min   = [x[1] for x in caliper]
c_avg   = [x[2] for x in caliper]
c_max   = [x[3] for x in caliper]
c_tput  = [x[4] for x in caliper]

def savefig(name):
    plt.savefig(os.path.join(FIG_DIR, name + '.pdf'))
    plt.savefig(os.path.join(FIG_DIR, name + '.png'), dpi=DPI)
    plt.close()
    print(f"  {name}.pdf/.png ✓")

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 1 — Weighted-F1 + F1 progression
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.5))
ax.plot(rnd, wf1, color=C['fedavg'], marker='o', markersize=3.5,
        linewidth=1.4, label='Weighted F1')
ax.plot(rnd, f1r, color=C['trimmedmean'], marker='^', markersize=3.5,
        linewidth=1.0, linestyle='--', label='F1-Score', alpha=0.85)
ax.axhline(y=0.963052, color='gray', linestyle=':', linewidth=0.9,
           label='Convergence (R20)')
ax.set_xlabel('Federated Round')
ax.set_ylabel('Score')
ax.set_xlim(0.5, 20.5)
ax.set_ylim(0.944, 0.967)
ax.xaxis.set_major_locator(MultipleLocator(4))
ax.xaxis.set_minor_locator(MultipleLocator(2))
ax.yaxis.set_major_locator(MultipleLocator(0.005))
ax.grid(True, which='major')
ax.grid(True, which='minor', linestyle=':', alpha=0.2)
ax.legend(loc='lower right', framealpha=0.85)
ax.annotate('0.9631', xy=(20, 0.963052), xytext=(16.5, 0.9555),
            arrowprops=dict(arrowstyle='->', lw=0.7, color='gray'),
            fontsize=6, color='gray')
plt.tight_layout(pad=0.3)
savefig('fig1_wf1_progression')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 2 — ROC-AUC progression
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.5))
ax.plot(rnd, rocau, color=C['multikrum'], marker='s', markersize=3.5,
        linewidth=1.4, label='ROC-AUC')
ax.axhline(y=0.981827, color='gray', linestyle=':', linewidth=0.9,
           label='Convergence (R20)')
ax.set_xlabel('Federated Round')
ax.set_ylabel('ROC-AUC')
ax.set_xlim(0.5, 20.5)
ax.set_ylim(0.9748, 0.9822)
ax.xaxis.set_major_locator(MultipleLocator(4))
ax.xaxis.set_minor_locator(MultipleLocator(2))
ax.yaxis.set_major_locator(MultipleLocator(0.002))
ax.grid(True, which='major')
ax.grid(True, which='minor', linestyle=':', alpha=0.2)
ax.legend(loc='lower right', framealpha=0.85, fontsize=6.5)
ax.annotate('0.9818', xy=(20, 0.981827), xytext=(16, 0.9808),
            arrowprops=dict(arrowstyle='->', lw=0.7, color='gray'),
            fontsize=6, color='gray')
plt.tight_layout(pad=0.3)
savefig('fig2_rocauc_progression')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 3 — Clean comparison 2×2
# ═══════════════════════════════════════════════════════════════════════════════
fig, axes = plt.subplots(2, 2, figsize=(IEEE_W1, 3.2))
axes = axes.flatten()
metrics = [
    ('f1',  'F1-Score',  0.954, 0.967),
    ('acc', 'Accuracy',  0.946, 0.957),
    ('fpr', 'FPR',       0.030, 0.052),
    ('auc', 'ROC-AUC',   0.978, 0.984),
]
xpos       = np.arange(3)
bar_colors = [C['fedavg'], C['multikrum'], C['trimmedmean']]
xlabels    = ['FedAvg', 'M-Krum', 'Trimmed']

for ax, (key, ylabel, ymin, ymax) in zip(axes, metrics):
    vals = [clean_final[a][key] for a in agg_list]
    bars = ax.bar(xpos, vals, width=0.55,
                  color=bar_colors, edgecolor='white', linewidth=0.4)
    span = ymax - ymin
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2,
                bar.get_height() + span*0.012,
                f'{v:.4f}', ha='center', va='bottom',
                fontsize=5.2, rotation=90)
    ax.set_ylabel(ylabel, fontsize=7)
    ax.set_xticks(xpos)
    ax.set_xticklabels(xlabels, fontsize=6.5)
    ax.set_ylim(ymin, ymax + span*0.30)
    ax.yaxis.set_major_locator(MultipleLocator(span/3))
    ax.yaxis.set_major_formatter(FormatStrFormatter('%.3f'))
    ax.grid(True, axis='y', alpha=0.4)
    ax.set_axisbelow(True)
plt.tight_layout(pad=0.4, h_pad=0.9, w_pad=0.6)
savefig('fig3_clean_comparison')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 4 — Byzantine by attack
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.8))
byz_avg = {}
for atk in attacks:
    byz_avg[atk] = {}
    for agg in agg_list:
        v20 = byz_full[(atk,'20%')][agg][0]
        v30 = byz_full[(atk,'30%')][agg][0]
        byz_avg[atk][agg] = (v20 + v30) / 2

xi = np.arange(len(attacks))
w  = 0.22
for i, agg in enumerate(agg_list):
    vals = [byz_avg[atk][agg] for atk in attacks]
    ax.bar(xi + (i-1)*w, vals, width=w, label=LABELS[agg],
           color=C[agg], edgecolor='white', linewidth=0.4)
ax.axhline(y=BASELINE_F1, color='black', linestyle='--', linewidth=1.0,
           label=f'Baseline = {BASELINE_F1:.4f}')
ax.set_ylabel('F1-Score')
ax.set_xlabel('Byzantine Attack Type')
ax.set_xticks(xi)
ax.set_xticklabels(attacks, fontsize=7)
ax.set_ylim(0.954, 0.967)
ax.yaxis.set_major_locator(MultipleLocator(0.003))
ax.yaxis.set_major_formatter(FormatStrFormatter('%.3f'))
ax.grid(True, axis='y', alpha=0.4)
ax.set_axisbelow(True)
ax.legend(loc='lower right', framealpha=0.88, ncol=2, fontsize=6.2)
plt.tight_layout(pad=0.3)
savefig('fig4_byzantine_by_attack')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 5 — Byzantine by ratio F1 + FPR
# ═══════════════════════════════════════════════════════════════════════════════
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(IEEE_W1, 2.6))
ratios = ['20%', '30%']
xr = np.arange(2)
w  = 0.22
for i, agg in enumerate(agg_list):
    f1v  = [np.mean([byz_full[(atk,r)][agg][0] for atk in attacks]) for r in ratios]
    fprv = [np.mean([byz_full[(atk,r)][agg][1] for atk in attacks]) for r in ratios]
    off  = (i-1)*w
    ax1.bar(xr+off, f1v,  width=w, label=LABELS[agg],
            color=C[agg], edgecolor='white', linewidth=0.4)
    ax2.bar(xr+off, fprv, width=w,
            color=C[agg], edgecolor='white', linewidth=0.4)
ax1.axhline(y=BASELINE_F1, color='black', linestyle='--',
            linewidth=0.9, label='Baseline')
ax1.set_ylabel('F1-Score')
ax1.set_xlabel('Byzantine Ratio')
ax1.set_xticks(xr)
ax1.set_xticklabels(ratios)
ax1.set_ylim(0.955, 0.967)
ax1.yaxis.set_major_locator(MultipleLocator(0.004))
ax1.yaxis.set_major_formatter(FormatStrFormatter('%.3f'))
ax1.grid(True, axis='y', alpha=0.4)
ax1.set_axisbelow(True)
ax1.legend(loc='lower right', fontsize=5.5, framealpha=0.85)

ax2.set_ylabel('FPR')
ax2.set_xlabel('Byzantine Ratio')
ax2.set_xticks(xr)
ax2.set_xticklabels(ratios)
ax2.set_ylim(0.030, 0.052)
ax2.yaxis.set_major_locator(MultipleLocator(0.005))
ax2.yaxis.set_major_formatter(FormatStrFormatter('%.3f'))
ax2.grid(True, axis='y', alpha=0.4)
ax2.set_axisbelow(True)
plt.tight_layout(pad=0.3, w_pad=0.8)
savefig('fig5_byzantine_by_ratio')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 6 — IPFS latency log scale
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(IEEE_W1, 2.6))
xi = np.arange(len(ipfs_labels))
w  = 0.30
b1 = ax.bar(xi-w/2, ipfs_store,   width=w, label='Store latency',
            color=C['store'], edgecolor='white', linewidth=0.4)
b2 = ax.bar(xi+w/2, ipfs_get_p50, width=w, label='Get p50',
            color=C['get'], edgecolor='white', linewidth=0.4, alpha=0.9)

for j in range(len(ipfs_labels)):
    xc = xi[j] + w/2
    ax.plot([xc, xc], [ipfs_get_p50[j], ipfs_get_p95[j]],
            color='#444', linewidth=0.9)
    ax.plot([xc-0.06, xc+0.06], [ipfs_get_p95[j], ipfs_get_p95[j]],
            color='#444', linewidth=0.9)

ax.set_yscale('log')
ax.set_ylim(20, 500)
ax.yaxis.set_major_formatter(mticker.ScalarFormatter())
ax.yaxis.set_minor_formatter(mticker.NullFormatter())
ax.set_yticks([20, 40, 80, 150, 300, 500])

ax.set_ylabel('Latency (ms, log scale)')
ax.set_xlabel('File Size')
ax.set_xticks(xi)
ax.set_xticklabels(ipfs_labels, fontsize=7)
ax.grid(True, axis='y', which='major', alpha=0.4)
ax.set_axisbelow(True)

ax.annotate('FL update\n(~100 KB)', xy=(2, ipfs_store[2]),
            xytext=(3.1, 110),
            arrowprops=dict(arrowstyle='->', lw=0.7, color='gray'),
            fontsize=5.5, color='gray', ha='center')

ax.text(xi[4] + w/2 + 0.12, ipfs_get_p95[4], '389 ms',
        fontsize=5.5, va='center', color='#444')

p95_line = plt.Line2D([0],[0], color='#444', linewidth=0.9, label='Get p95')
ax.legend(handles=[b1, b2, p95_line], fontsize=6.5,
          loc='upper left', framealpha=0.88)
plt.tight_layout(pad=0.3)
savefig('fig6_ipfs_latency')

# ═══════════════════════════════════════════════════════════════════════════════
# FIGURE 7 — Caliper latency + throughput
# ═══════════════════════════════════════════════════════════════════════════════
fig, ax1 = plt.subplots(figsize=(IEEE_W1, 2.8))
xi = np.arange(len(c_label))
w  = 0.22
ax1.bar(xi-w, c_min, width=w, label='Min', color=C['min_lat'],
        edgecolor='white', linewidth=0.4)
ax1.bar(xi,   c_avg, width=w, label='Avg', color=C['avg_lat'],
        edgecolor='white', linewidth=0.4)
ax1.bar(xi+w, c_max, width=w, label='Max', color=C['max_lat'],
        edgecolor='white', linewidth=0.4, alpha=0.85)
ax1.set_ylabel('Latency (s)')
ax1.set_xlabel('Target Send Rate (TPS)')
ax1.set_xticks(xi)
ax1.set_xticklabels(c_label, fontsize=7)
ax1.set_ylim(0, 1.45)
ax1.yaxis.set_major_locator(MultipleLocator(0.25))
ax1.grid(True, axis='y', alpha=0.35)
ax1.set_axisbelow(True)

ax2 = ax1.twinx()
ax2.plot(xi, c_tput, color=C['throughput'], marker='D',
         markersize=4.5, linewidth=1.4, label='Throughput', zorder=5)
ax2.set_ylabel('Throughput (TPS)', color=C['throughput'], fontsize=7)
ax2.tick_params(axis='y', labelcolor=C['throughput'], labelsize=7)
ax2.set_ylim(0, 850)
ax2.yaxis.set_major_locator(MultipleLocator(200))
ax2.annotate('~619.9 TPS\n(saturation)', xy=(2, 619.9), xytext=(3.3, 700),
             arrowprops=dict(arrowstyle='->', lw=0.7, color=C['throughput']),
             fontsize=5.5, color=C['throughput'], ha='center')

ax1.text(0.03, 0.97, '250k tx — 0 failures',
         transform=ax1.transAxes, fontsize=5.5, va='top', ha='left',
         bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='gray', alpha=0.85))
h1,l1 = ax1.get_legend_handles_labels()
h2,l2 = ax2.get_legend_handles_labels()
ax1.legend(h1+h2, l1+l2, loc='upper right', fontsize=6,
           framealpha=0.88, ncol=2)
plt.tight_layout(pad=0.3)
savefig('fig7_caliper_latency')

# ═══════════════════════════════════════════════════════════════════════════════
# TABLES LATEX
# ═══════════════════════════════════════════════════════════════════════════════

t1 = r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.2}
\caption{Statistical Characteristics of the 5G-NIDD Dataset}
\label{tab:dataset}
\centering
\begin{tabular}{ll}
\hline
\textbf{Parameter} & \textbf{Value} \\
\hline
Dataset & 5G-NIDD \\
Total training samples & 972,700 \\
Total test samples & 243,160 \\
Features & 50 \\
FL clients & 20 \\
Samples per client (train/test) & 48,635 / 12,158 \\
Train benign / malicious & 19,109 / 29,526 per client \\
Test benign / malicious & 4,777 / 7,381 per client \\
Attack families (4) & Flooding, AppLayer, LowRateDoS, Scanning \\
Attack types (8) & UDPFlood, SYNFlood, ICMPFlood, HTTPFlood, \\
                  & SlowrateDoS, TCPConnectScan, SYNScan, UDPScan \\
Non-IID distribution & Each client specialised in 1 primary family \\
Train/Test split & 80\% / 20\% stratified \\
\hline
\end{tabular}
\end{table}
"""

t2 = r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.2}
\caption{Experimental Testbed Configuration}
\label{tab:setup}
\centering
\begin{tabular}{ll}
\hline
\textbf{Component} & \textbf{Configuration} \\
\hline
Blockchain & Hyperledger Fabric v2.5 \\
Organizations & 2 (Org1, Org2) \\
Peers & 2 (peer0.org1, peer0.org2) \\
Ordering service & Raft (1 orderer) \\
Channel / Chaincode & dtchannel / governance (Go) \\
Storage & IPFS + IPFS Cluster (5 nodes) \\
FL clients & 20 edge clients across 4 VMs \\
FL model & Logistic Regression (binary) \\
FL rounds (clean) & 20 \\
FL rounds (byzantine) & 5 per attack scenario \\
Byzantine attacks & Signflip, Gaussian, Scaling, Random, Backdoor \\
Byzantine ratios & 20\% (4/20), 30\% (6/20) \\
Aggregators & FedAvg, Multi-Krum, TrimmedMean \\
VM setup & 4 $\times$ Ubuntu 22.04, 8 vCPU, 16 GB RAM \\
Benchmark tool & Hyperledger Caliper v0.5 \\
\hline
\end{tabular}
\end{table}
"""

t3 = r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.2}
\caption{Global Model Performance of Three Aggregation Strategies After 20 Federated Rounds (Clean Setting)}
\label{tab:clean}
\centering
\begin{tabular}{lccccccc}
\hline
\textbf{Aggregator} & \textbf{Thr.} & \textbf{W-F1} & \textbf{F1} & \textbf{Acc.} & \textbf{FPR} & \textbf{ROC-AUC} & \textbf{Time (ms)} \\
\hline
FedAvg      & 0.44 & 0.9631 & \textbf{0.9633} & \textbf{0.9560} & \textbf{0.0373} & \textbf{0.9818} & 0.001 \\
Multi-Krum  & 0.53 & \textbf{0.9631} & 0.9579 & 0.9499 & 0.0453 & 0.9805 & 1.441 \\
TrimmedMean & 0.45 & 0.9630 & 0.9624 & 0.9506 & 0.0454 & 0.9813 & 0.280 \\
\hline
\end{tabular}
\end{table}
"""

rows_t4 = []
for atk in attacks:
    for ratio in ['20%', '30%']:
        for agg in agg_list:
            f1v, fpr, auc = byz_full[(atk, ratio)][agg]
            delta = f1v - BASELINE_F1
            rows_t4.append((atk, ratio, LABELS[agg],
                            f'{f1v:.4f}', f'{fpr:.4f}',
                            f'{auc:.4f}', f'{delta:+.4f}'))

t4_lines = []
t4_lines.append(r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.15}
\caption{Impact of Byzantine Attacks on Aggregator Performance (F1, FPR, ROC-AUC)}
\label{tab:byzantine}
\centering
\begin{tabular}{llccccr}
\hline
\textbf{Attack} & \textbf{Ratio} & \textbf{Aggregator} & \textbf{F1} & \textbf{FPR} & \textbf{ROC-AUC} & \textbf{$\Delta$F1} \\
\hline""")

prev_atk = None
for atk, ratio, agg, f1v, fpr, auc, delta in rows_t4:
    if prev_atk and prev_atk != atk:
        t4_lines.append(r'\hline')
    t4_lines.append(f'{atk} & {ratio} & {agg} & {f1v} & {fpr} & {auc} & {delta} \\\\')
    prev_atk = atk

t4_lines.append(r"""\hline
\multicolumn{3}{l}{\textit{Baseline (clean, R20)}} & \textit{0.9633} & \textit{0.0373} & \textit{0.9818} & -- \\
\hline
\end{tabular}
\end{table}""")
t4 = '\n'.join(t4_lines)

t5 = r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.2}
\caption{IPFS and Blockchain Transaction Latency (Baseline vs. Backdoor Scenario)}
\label{tab:infra}
\centering
\begin{tabular}{llcccc}
\hline
\textbf{Component} & \textbf{Scenario} & \textbf{p50 (ms)} & \textbf{p95 (ms)} & \textbf{p99 (ms)} & \textbf{Avg (ms)} \\
\hline
IPFS       & Baseline  &  96.00 & 110.00 & 114.01 &  96.04 \\
IPFS       & Backdoor  & 101.76 & 111.28 & 120.41 & 102.76 \\
\hline
Fabric tx  & Baseline  & 589.00 & 599.00 & 618.32 & 591.09 \\
Fabric tx  & Backdoor  & 686.00 & 705.20 & 719.01 & 687.61 \\
\hline
Total E2E  & Baseline  & 686.00 & 703.05 & 715.35 & 688.08 \\
Total E2E  & Backdoor  & 790.85 & 812.46 & 818.50 & 790.37 \\
\hline
\end{tabular}
\end{table}
"""

t6 = r"""\begin{table}[!t]
\renewcommand{\arraystretch}{1.2}
\caption{Hyperledger Fabric Throughput and Latency Under Varying Send Rates (Caliper Benchmark, 400ms Block Timeout, 10k Batch, 50MB Payload)}
\label{tab:caliper}
\centering
\begin{tabular}{lccccccr}
\hline
\textbf{Workload} & \textbf{Succ} & \textbf{Fail} & \textbf{Observed Rate} & \textbf{Min (s)} & \textbf{Avg (s)} & \textbf{Max (s)} & \textbf{Tput (TPS)} \\
\hline
500 TPS  & 50,000 & 0 & 499.9 & 0.17 & 0.42 & 0.79 & 498.4 \\
1000 TPS & 50,000 & 0 & 614.5 & 0.14 & 0.49 & 1.01 & 613.4 \\
2000 TPS & 50,000 & 0 & 621.2 & 0.15 & 0.48 & 0.99 & \textbf{619.9} \\
3000 TPS & 50,000 & 0 & 615.5 & 0.14 & 0.48 & 1.04 & 614.0 \\
4000 TPS & 50,000 & 0 & 617.8 & 0.16 & 0.48 & 0.97 & 614.0 \\
\hline
\multicolumn{8}{l}{\textit{Saturation observed at $\approx$614--620 TPS. Zero failures across 250,000 transactions.}} \\
\hline
\end{tabular}
\end{table}
"""

tables = {
    'table1_dataset.tex':                t1,
    'table2_experimental_setup.tex':     t2,
    'table3_clean_comparison.tex':       t3,
    'table4_byzantine_robustness.tex':   t4,
    'table5_infrastructure_latency.tex': t5,
    'table6_caliper_benchmark.tex':      t6,
}
for fname, content in tables.items():
    path = os.path.join(TEX_DIR, fname)
    with open(path, 'w') as f:
        f.write(content)
    print(f"  {fname} ✓")

print("\n" + "═"*55)
print("DONE")
print(f"Figures : {FIG_DIR}")
print(f"Tables  : {TEX_DIR}")
print("═"*55)
for fp in sorted(glob.glob(FIG_DIR+'/*') + glob.glob(TEX_DIR+'/*')):
    print(f"  {os.path.basename(fp):50s} {os.path.getsize(fp)//1024:>4} KB")
