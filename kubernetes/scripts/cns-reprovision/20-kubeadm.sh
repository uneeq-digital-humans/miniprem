#!/usr/bin/env bash
# Phase 2 — kubeadm single-node control plane + Calico CNI. NETWORK-RISKY (rewrites
# iptables). Designed to run detached (nohup) so an SSH drop won't abort it.
# Logs to /home/admin/migration/kubeadm.log. Idempotent-ish (skips if already up).
set -euo pipefail
log() { printf '\033[1;36m[kubeadm]\033[0m %s\n' "$*"; }
MIG=/home/admin/migration
CALICO_VER="${CALICO_VER:-v3.28.0}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"

# SSH-allow insurance: keep port 22 reachable even as CNI rewrites iptables.
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true

if sudo test -f /etc/kubernetes/admin.conf; then
  log "Control plane already initialised; skipping kubeadm init."
else
  log "kubeadm init (pod-cidr $POD_CIDR)"
  sudo kubeadm init --pod-network-cidr="$POD_CIDR" \
    --cri-socket unix:///run/containerd/containerd.sock
fi

# kubeconfig for admin + root
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
sudo mkdir -p /root/.kube && sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG="$HOME/.kube/config"

# Single-node: allow scheduling on the control-plane node.
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# Calico CNI
if ! kubectl get ns calico-system >/dev/null 2>&1 && ! kubectl -n kube-system get ds calico-node >/dev/null 2>&1; then
  log "Installing Calico $CALICO_VER"
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VER}/manifests/calico.yaml"
fi

# local-path storage (default SC) — NIMCache PVC + Phoenix want a default class.
if ! kubectl get sc >/dev/null 2>&1 || ! kubectl get sc | grep -q '(default)'; then
  log "Installing local-path-provisioner as the default StorageClass"
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
  kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
fi

log "Waiting for the node to go Ready (up to 180s)…"
kubectl wait --for=condition=Ready node --all --timeout=180s || true
log "kubeadm phase complete."
kubectl get nodes -o wide || true
kubectl get pods -A || true
