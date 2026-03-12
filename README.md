# Byzantine-Resilient Federated IDS for 5G IoT via Blockchain Governance and IPFS

> Reproducibility package — IEEE TNSM submission (revised)

---

## Overview

This repository contains the full experimental pipeline for a Byzantine-resilient federated intrusion detection system (IDS) for 5G IoT networks. The system integrates:

- **Federated Learning** with three aggregators: FedAvg, Multi-Krum, TrimmedMean
- **Hyperledger Fabric** (permissioned blockchain) for on-chain governance, anti-replay, anti-rollback, and Sybil resistance
- **IPFS** for content-addressed off-chain model persistence

Evaluated on a 10-VM OpenStack testbed (Béluga Research Cloud) with N=20 non-IID edge clients trained on the **5G-NIDD** dataset, under five Byzantine attack strategies at 20% and 30% adversarial ratios.

---

## Key Results

| Metric | Value |
|--------|-------|
| FedAvg F1 (clean, holdout) | 0.9627 ± 0.0009 |
| FedAvg ROC-AUC | 0.9817 ± 0.0001 |
| Max ΔF1 under Byzantine attacks | −0.0053 (Backdoor 20%, Multi-Krum) |
| On-chain throughput | 619.9 TPS |
| Security properties | 100% rejection — replay / rollback / Sybil |

Results are mean ± std over **3 independent seeds**, threshold selected on a held-out validation set, reported on a separate holdout set.

---

## Repository Structure

```
byz-fed-ids-5g/
├── phase2/                  # VM provisioning: NTP, Docker, monitoring
├── phase3/                  # Hyperledger Fabric deployment (Raft, 3 orderers)
├── phase6/preprocessing/    # 5G-NIDD dataset split generation (N=20 clients)
├── phase7/                  # FL client + Multi-Krum aggregator
├── phase8/                  # FedAvg / TrimmedMean aggregators, Caliper benchmark
├── caliper/                 # Hyperledger Caliper workload scripts (619.9 TPS)
├── scripts/                 # Utility: split distribution, global test set
└── rev/                     # Revision pipeline (all scripts below)
    ├── 103b-prepare-valtest-split.py       # One-shot val/holdout split
    ├── 103b-run-clean-3seeds.sh            # Clean baseline — 3 seeds × 20 rounds
    ├── 104b-run-backdoor-20rounds.sh       # Backdoor attack — 20 rounds
    ├── 106b-generate-updated-figures-tables.py  # Figures + LaTeX tables
    └── runs/
        └── rev_20260303_152740_5g/
            ├── federated_3seeds_*/          # Clean results (3 seeds)
            │   └── AGGREGATE/
            │       ├── mean_std_paper.csv
            │       └── per_round_all_seeds.csv
            ├── byzantine_backdoor20r_*/     # Backdoor results
            │   └── tables_input/backdoor_all_rounds.csv
            ├── figures_106b/                # PDF + PNG figures (fig1–fig5)
            └── tables_106b/                 # LaTeX tables (table3, table4)
```

---

## Testbed Infrastructure — 10-VM OpenStack Private Cloud

All experiments run on a **private 10-VM environment** provisioned on the **Béluga OpenStack Research Cloud** (Calcul Québec / Digital Research Alliance of Canada). VMs communicate over an isolated private network (`10.10.0.0/24`). The public orchestrator endpoint is `198.168.187.13`.

### VM Topology

| VM | Hostname | Private IP | vCPU | RAM | Disk | Role |
|----|----------|-----------|------|-----|------|------|
| vm1 | fl-ids-vm1-orch | 10.10.0.153 | 4 | 15 GB | 20 GB | **FL Orchestrator** — aggregation, threshold selection, IPFS daemon, result collection |
| vm2 | fl-ids-vm2-edge1 | 10.10.0.112 | 8 | 30 GB | 20 GB | Edge clients 1–5 + Fabric `peer1.org1.example.com` |
| vm3 | fl-ids-vm3-edge2 | 10.10.0.11 | 8 | 30 GB | 20 GB | Edge clients 6–10 + Fabric `peer1.org2.example.com` |
| vm4 | fl-ids-vm4-edge3 | 10.10.0.121 | 8 | 30 GB | 20 GB | Edge clients 11–15 |
| vm5 | fl-ids-vm5-edge4 | 10.10.0.10 | 8 | 30 GB | 20 GB | Edge clients 16–20 |
| vm6 | fl-ids-vm6-orderer1 | 10.10.0.52 | 8 | 30 GB | 20 GB | Fabric `orderer1.example.com` (Raft leader candidate) |
| vm7 | fl-ids-vm7-orderer2 | 10.10.0.106 | 8 | 30 GB | 20 GB | Fabric `orderer2.example.com` |
| vm8 | fl-ids-vm8-orderer3 | 10.10.0.57 | 8 | 30 GB | 20 GB | Fabric `orderer3.example.com` |
| vm9 | fl-ids-vm9-peer1 | 10.10.0.126 | 8 | 30 GB | 20 GB | Fabric `peer0.org1.example.com` |
| vm10 | fl-ids-vm10-peer2 | 10.10.0.82 | 8 | 30 GB | 20 GB | Fabric `peer0.org2.example.com` |

**Total cluster** — 76 vCPUs, 285 GB RAM, 200 GB disk across 10 VMs.  
Uptime during experiments: 15 days continuous (2,082 vCPU-hours, 7,997,067 RAM-hours logged by OpenStack).

### Design Notes

- **FL clients** — 20 logical edge clients distributed across 4 edge VMs (5 processes/VM), each holding a private non-IID partition of the 5G-NIDD dataset.
- **Hyperledger Fabric** — Raft consensus with 3 orderers (`vm6`, `vm7`, `vm8`), tolerating `f_crash = 1` orderer failure. Two organizations with 2 peers each (`vm2`, `vm9` for Org1; `vm3`, `vm10` for Org2).
- **IPFS** — daemon runs on the orchestrator (`vm1`); model weights are pinned as CIDs before on-chain commitment.
- **Byzantine adversaries** — injected at the FL client level on edge VMs; the Fabric layer remains non-Byzantine (CFT only).

---

## Experimental Parameters

| Parameter | Value |
|-----------|-------|
| Dataset | 5G-NIDD, splits_20 |
| Clients | N = 20 (non-IID) |
| Train per client | 48,635 samples |
| Validation set | 48,632 samples (global) |
| Holdout set | 194,528 samples (global) |
| Model | Logistic Regression (numpy), w ∈ ℝ⁵⁰ |
| Optimizer | SGD, lr = 0.01, E = 1 epoch/round |
| Threshold | Swept t ∈ {0.05,…,0.95}, best weighted F1 on val |
| Seeds | 42, 123, 2024 |
| Aggregators | FedAvg, Multi-Krum (f=4), TrimmedMean (trim=0.1) |
| Byzantine attacks | Signflip, Gaussian, Scaling, Random, Backdoor |
| Byzantine ratios | 20% (f=4), 30% (f=6) |
| Rounds — clean / non-Backdoor | 20 |
| Rounds — Backdoor | 20 |
| Blockchain | Hyperledger Fabric 2.x, Raft (3 orderers, f_crash=1) |
| Off-chain storage | IPFS (content-addressed) |

---

## Reproducing the Results

### Prerequisites

- Ubuntu 20.04+ VMs with Docker, Python 3.8+, Hyperledger Fabric 2.x
- IPFS daemon running on orchestrator
- 5G-NIDD dataset (see download instructions below)

### 1 — Prepare the dataset split

```bash
python rev/103b-prepare-valtest-split.py
```

Generates `splits_20/global_val_X.npy`, `global_val_y.npy`, `global_holdout_X.npy`, `global_holdout_y.npy`.

### 2 — Run clean baseline (3 seeds)

```bash
bash rev/103b-run-clean-3seeds.sh
```

Output: `runs/rev_*/federated_3seeds_*/AGGREGATE/mean_std_paper.csv`

### 3 — Run Byzantine Backdoor (20 rounds)

```bash
bash rev/104b-run-backdoor-20rounds.sh
```

Output: `runs/rev_*/byzantine_backdoor20r_*/tables_input/backdoor_all_rounds.csv`

### 4 — Generate figures and LaTeX tables

```bash
python rev/106b-generate-updated-figures-tables.py
```

Output: `runs/rev_*/figures_106b/` (PDF + PNG) and `runs/rev_*/tables_106b/` (`.tex`)

---

## Dataset

The **5G-NIDD** dataset is publicly available at:  
[https://ieee-dataport.org/documents/5g-nidd](https://ieee-dataport.org/documents/5g-nidd)

Place the raw files in `data/5gnidd/` before running the split script.

---

## Figures

| Figure | Content |
|--------|---------|
| `fig1_wf1_progression` | Weighted F1 + F1 over rounds with ±1 std shading (3 seeds) |
| `fig2_rocauc_progression` | ROC-AUC over rounds with ±1 std shading |
| `fig3_clean_comparison` | 2×2 bar chart — F1, FPR, AUC, latency across aggregators |
| `fig4_byzantine_by_attack` | F1 degradation per attack type (Backdoor=20r, others=5r) |
| `fig5_byzantine_by_ratio` | F1 + FPR by Byzantine ratio (20% vs 30%) |

---

## Citation

If you use this code or data, please cite:

```bibtex
@article{,
  title   = {Byzantine-Resilient Federated Intrusion Detection for 5G IoT
             via Blockchain Governance and IPFS},
  journal = {IEEE Transactions on Network and Service Management},
  year    = {2026},
  note    = {Under revision}
}
```

---

## License

Code released under the **MIT License**.  
The 5G-NIDD dataset is subject to its own terms — see the IEEE DataPort page.
