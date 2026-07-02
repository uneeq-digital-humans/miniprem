#!/usr/bin/env bash
# Phase 0 — SAFE prep for the Docker->kubeadm reprovision of the MiniPrem box.
# Additive only: installs the k8s toolchain + helm, loads kernel modules, sets
# sysctls, disables swap. Does NOT touch Docker or networking yet (no SSH-loss
# risk) and does NOT touch any credentials. Idempotent.
#
# Credentials for the deploy phase (NGC_API_KEY, HARBOR_USERNAME/PASSWORD,
# PLATFORM_KEY, TENANT_ID) are NOT harvested here — the operator supplies them at
# the deploy step (e.g. write them into /home/admin/migration/creds.env).
set -euo pipefail
log() { printf '\033[1;36m[prep]\033[0m %s\n' "$*"; }

MIG=/home/admin/migration
sudo mkdir -p "$MIG"
sudo chown "$USER" "$MIG"

# --- Kernel modules + sysctl for k8s networking ---
log "Loading kernel modules + sysctls"
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
sudo modprobe overlay || true
sudo modprobe br_netfilter || true
sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<'SYS'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYS
sudo sysctl --system >/dev/null

# --- Disable swap (kubelet requirement) ---
log "Disabling swap"
sudo swapoff -a || true
sudo sed -i.bak '/\bswap\b/ s/^/#/' /etc/fstab || true

# --- Install the Kubernetes toolchain (pkgs.k8s.io, v1.30) ---
K8S_MINOR="${K8S_MINOR:-v1.30}"
if ! command -v kubeadm >/dev/null; then
  log "Installing kubeadm/kubelet/kubectl ($K8S_MINOR)"
  sudo apt-get update -qq
  sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg conntrack
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl
else
  log "kubeadm already present: $(kubeadm version -o short 2>/dev/null)"
fi

# --- crictl (CRI debugging) ---
if ! command -v crictl >/dev/null; then
  log "Installing crictl"
  CRICTL_VER="v1.30.0"
  curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-amd64.tar.gz" \
    | sudo tar -C /usr/local/bin -xz
fi

# --- Helm ---
if ! command -v helm >/dev/null; then
  log "Installing helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
fi

log "Phase 0 complete."
kubeadm version -o short 2>/dev/null || true
helm version --short 2>/dev/null || true
crictl --version 2>/dev/null || true
