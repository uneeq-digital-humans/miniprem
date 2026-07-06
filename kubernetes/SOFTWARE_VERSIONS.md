# MiniPrem CNS — Software Bill of Materials (SBOM)

**Document type:** Software Bill of Materials / Version Manifest
**Deployment target:** On-premises Kubernetes (kubeadm) and MicroK8s with NVIDIA GPU acceleration
**Document version:** 1.0
**Last reviewed:** 2026-05-14
**Owner:** MiniPrem Platform Engineering

---

## 1. Purpose and Scope

This document is the authoritative version manifest for the MiniPrem Cloud Native Stack (CNS) on-premises deployment. It enumerates every third-party software component installed by the deployment automation, the exact version pinned, the upstream source of record, and the component's role in the stack.

Scope:

- Host operating system packages installed by the deployment playbook
- Kubernetes control-plane and node components
- Container runtime and CNI
- NVIDIA GPU stack (kernel driver, container toolkit, operator, time-slicing)
- Platform add-ons (Helm, observability, NIM operator)
- MiniPrem application charts and container images

Out of scope:

- Customer-side conversational AI workloads (LLMs, ASR, TTS) — sized and supplied separately
- End-user browser, network appliances, identity providers

All versions below are enforced by the deployment automation in `kubernetes/ansible/vars/cns_versions.yml` and the CNS install scripts under `kubernetes/scripts/cns/`. Drift from these values requires a controlled change in that file.

---

## 2. Version Pinning Policy

| Policy | Statement |
|---|---|
| **Source of truth** | `kubernetes/ansible/vars/cns_versions.yml` |
| **Default behavior** | All versions are pinned. APT packages are placed on `hold`. Helm charts are deployed with explicit `--version` flags. Container images are tagged by digest-stable tags (no `latest` for production-critical components). |
| **Upgrade cadence** | Component versions are reviewed quarterly. NVIDIA driver and GPU Operator are validated against the Renny renderer compatibility matrix before promotion. |
| **Security patches** | Out-of-band patch releases are accepted within a pinned minor version (e.g., containerd `1.7.x`) and require a regression run of the validation playbook (`ansible/playbooks/validate.yml`). |
| **Exceptions** | Components marked "tracking" in the table below intentionally float to the upstream stable channel; they are non-load-bearing and used only for operator tooling. |

---

## 3. Supported Host Platforms

| OS | Version | Status | Notes |
|---|---|---|---|
| Ubuntu LTS | 22.04 | Supported (primary) | Recommended for production |
| Ubuntu LTS | 24.04 | Supported | Required for newer GPU SKUs |
| Ubuntu | 22.04 / 24.04 | **Supported (validated)** | The digital-human appliance target |
| RHEL | 8.7+ | CNS-compatible, **not validated** | Cluster layer only — renny + kiosk OS controls (audio/display) are Ubuntu-validated; MicroK8s path unsupported |
| Kernel | 5.15+ (Ubuntu 22.04) / 6.8+ (Ubuntu 24.04) | Required | Required for containerd cgroup v2 and current NVIDIA driver |

Hardware floor: x86_64, 8 GB RAM minimum (16 GB+ recommended), 100 GB SSD, one or more NVIDIA datacenter GPUs (A10G, A100, H100, L4, L40, T4, RTX PRO 6000 / Blackwell on driver 580.82+).

---

## 4. Component Manifest

### 4.1 Operating-System Packages (installed by Ansible)

| Component | Version | Source | License | Role |
|---|---|---|---|---|
| `curl` | Distribution-current | Distribution repo | MIT/curl | HTTP client for installer downloads |
| `wget` | Distribution-current | Distribution repo | GPL-3.0 | HTTP client for installer downloads |
| `apt-transport-https` | Distribution-current | Distribution repo | GPL-2.0 | TLS for APT |
| `ca-certificates` | Distribution-current | Distribution repo | MPL-2.0 | Root CA bundle |
| `gnupg` | Distribution-current | Distribution repo | GPL-3.0 | Repository signature verification |
| `lsb-release` | Distribution-current | Distribution repo | GPL-2.0 | OS detection |
| `software-properties-common` | Distribution-current | Distribution repo | GPL-2.0 | APT repository management |
| `jq` | Distribution-current | Distribution repo | MIT | JSON parsing in install scripts |
| `git` | Distribution-current | Distribution repo | GPL-2.0 | Artifact retrieval |
| `conntrack` | Distribution-current | Distribution repo | GPL-2.0 | Required by kube-proxy |
| `snapd` | Distribution-current | Distribution repo | GPL-3.0 | MicroK8s install path only |
| Google Chrome (stable) | Tracking upstream stable | `dl.google.com/linux` | Proprietary (free) | Kiosk-mode browser for digital-human UI |

### 4.2 Kubernetes Platform

| Component | Version | Source | License | Role |
|---|---|---|---|---|
| Kubernetes (kubeadm path) | 1.31 (latest 1.31.x patch) | `pkgs.k8s.io/core:/stable:/v1.31` | Apache-2.0 | Control plane and node components |
| `kubelet` | 1.31.x (held) | `pkgs.k8s.io` | Apache-2.0 | Node agent |
| `kubeadm` | 1.31.x (held) | `pkgs.k8s.io` | Apache-2.0 | Cluster bootstrap |
| `kubectl` | 1.31.x (held) | `pkgs.k8s.io` | Apache-2.0 | CLI |
| MicroK8s (MicroK8s path) | Channel `1.31/stable` | Snap Store | Apache-2.0 | Single-node alternative to kubeadm |
| Calico CNI | v3.28.0 | `github.com/projectcalico/calico` | Apache-2.0 | Pod networking, network policy |
| containerd | 1.7.x (pinned, held) | `download.docker.com/linux/ubuntu` (`containerd.io` package) | Apache-2.0 | Container runtime. Pinned to 1.7.x — 2.x is incompatible with kubeadm 1.31 CRI v1. |
| Helm | 3 (tracking stable installer) | `get-helm-3` upstream script | Apache-2.0 | Package manager for cluster add-ons |

Cluster topology defaults: single control-plane node; pod CIDR `192.168.0.0/16`; `SystemdCgroup = true`; CRI plugin explicitly re-enabled (Docker's `containerd.io` package ships with CRI disabled).

### 4.3 NVIDIA GPU Stack

| Component | Version | Source | License | Role |
|---|---|---|---|---|
| NVIDIA Driver | 580.82.09 | `nvidia.github.io` / OEM driver runfile | NVIDIA proprietary | Kernel-mode GPU driver. Validated against Renny renderer; `580.126.x` is known-incompatible and blocked by the installer. |
| CUDA | 12.4 | Bundled with driver / GPU Operator | NVIDIA proprietary | GPU compute runtime |
| NVIDIA Container Toolkit | 1.16.0 | `nvidia.github.io/libnvidia-container` | Apache-2.0 | OCI runtime hook for containerized GPU access |
| NVIDIA GPU Operator (Helm) | v24.9.0 | `helm.ngc.nvidia.com/nvidia` chart `gpu-operator` | Apache-2.0 | Manages driver, toolkit, device plugin, DCGM exporter, MIG/time-slicing |
| NVIDIA Device Plugin | Bundled in GPU Operator v24.9.0 | NVIDIA | Apache-2.0 | Exposes `nvidia.com/gpu` resource |
| NVIDIA DCGM Exporter | Bundled in GPU Operator v24.9.0 | NVIDIA | Apache-2.0 | GPU telemetry to Prometheus |
| GPU Time-Slicing Config | Generated from `gpu_timeslice_replicas` (default 4) | MiniPrem `cns-install.yml` | n/a | Allows multiple pods per physical GPU |
| NVIDIA NIM Operator (Helm) | 1.0.0 | `helm.ngc.nvidia.com/nvidia` chart `k8s-nim-operator` | Apache-2.0 | Manages NIM model microservice deployments |

### 4.4 Observability and Platform Add-ons

| Component | Version | Source | License | Role |
|---|---|---|---|---|
| Prometheus | v2.45.0 | `prometheus.io` | Apache-2.0 | Metrics scraping and storage |
| Grafana | 10.2.0 | `grafana.com` | AGPL-3.0 | Metrics visualization |
| Arize Phoenix | Tracking `latest` (image `arizephoenix/phoenix:latest`) | Docker Hub | Elastic-2.0 | LLM trace and evaluation observability. Floating tag; pin to a digest before regulated-environment deployment. |

### 4.5 MiniPrem Application

| Component | Version | Source | License | Role |
|---|---|---|---|---|
| Renny Helm chart | 0.1184-2f3b7 | Internal registry `cr.uneeq.io` | Commercial (UneeQ) | Digital human renderer deployment |
| Renny renderer image | `cr.uneeq.io/uneeq/renny-renderer:0.1184-2f3b7` | Internal registry | Commercial (UneeQ) | Renderer container |
| Digital Human Interface chart | Floating `:latest` tag in default values | Internal registry | Commercial (UneeQ) | Kiosk UI. Pin to a numbered tag before regulated-environment deployment. |
| Digital Human WebSocket API chart | Floating `:latest` tag in default values | Internal registry | Commercial (UneeQ) | Edge WebSocket gateway. Pin before regulated-environment deployment. |
| Digital Human ASR chart | Floating `:latest` tag in default values | Internal registry / NVIDIA NGC | Commercial (UneeQ / NVIDIA) | Speech recognition. Includes `nvcr.io/nim/nvidia/nemotron-asr-streaming:latest`. Pin before regulated-environment deployment. |

### 4.6 Cluster Namespaces Created

| Namespace | Purpose |
|---|---|
| `kube-system` | Kubernetes control-plane and Calico |
| `gpu-operator` | NVIDIA GPU Operator and device plugin |
| `nim-operator` | NVIDIA NIM Operator and `ngc-api-key` secret |
| `nim-models` | NIM model microservices |
| `nim-rag` | NIM RAG components |
| `uneeq` (default `renny_namespace`) | Renny renderer workloads |
| `observability` | Arize Phoenix |
| `monitoring` | Prometheus and Grafana |

---

## 5. Validated Version Combinations

The following combination is the reference baseline for partner validation:

| Layer | Reference Value |
|---|---|
| OS | Ubuntu 22.04 LTS, kernel 5.15+ |
| Kubernetes | 1.31.x (kubeadm) |
| Container runtime | containerd 1.7.x with `SystemdCgroup = true` |
| CNI | Calico v3.28.0 |
| NVIDIA driver | 580.82.09 |
| NVIDIA Container Toolkit | 1.16.0 |
| NVIDIA GPU Operator | v24.9.0 |
| NIM Operator | 1.0.0 |
| Helm | 3.x |
| Renny chart | 0.1184-2f3b7 |

Known incompatibilities enforced by the installer:

- **containerd 2.x** with kubeadm 1.31 → CRI v1 incompatibility; installer pins `containerd.io=1.7.*` and places it on hold.
- **NVIDIA driver 580.126.x** with Renny renderer → installer halts with remediation guidance.
- **Drivers older than the 5xx series** on Blackwell / RTX PRO 6000 → installer warns; 580.82.x is required.
- **MicroK8s coexisting with kubeadm** → installer halts; ports 10250/10257/10259 conflict.

---

## 6. Verification

After installation, the validation playbook (`ansible/playbooks/validate.yml`) confirms the running versions match this manifest. The commands below can be run independently for audit purposes:

```bash
# OS and kernel
lsb_release -a && uname -r

# Kubernetes
kubectl version --output=yaml
kubeadm version -o short

# Container runtime
containerd --version
crictl version

# CNI
kubectl -n kube-system get pods -l k8s-app=calico-node -o jsonpath='{.items[0].spec.containers[0].image}'

# NVIDIA stack
nvidia-smi --query-gpu=driver_version,name --format=csv
nvidia-ctk --version
helm -n gpu-operator list -o yaml | grep -E 'chart|app_version'

# NIM Operator
helm -n nim-operator list -o yaml | grep -E 'chart|app_version'

# Helm
helm version --short

# Renny
helm -n uneeq list -o yaml | grep -E 'chart|app_version'
```

---

## 7. Change Control

All changes to pinned versions must:

1. Update `kubernetes/ansible/vars/cns_versions.yml`.
2. Update the corresponding row in this document and bump the document version.
3. Pass the validation playbook against the reference hardware profile before release.
4. Be recorded in the release notes accompanying the MiniPrem CNS bundle.

---

## 8. Document History

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-05-14 | Initial SBOM published for MiniPrem CNS. |
