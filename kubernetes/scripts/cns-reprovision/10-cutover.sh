#!/usr/bin/env bash
# Phase 1 — Docker -> containerd cutover. DISRUPTIVE: stops the Docker stack and
# repoints containerd at the CRI for kubeadm. Saves the locally-built rag-adapter
# image first (so we can import it into k8s after). Run BEFORE 20-kubeadm.sh.
set -euo pipefail
log() { printf '\033[1;36m[cutover]\033[0m %s\n' "$*"; }
MIG=/home/admin/migration

# --- 1) Save the locally-built adapter image (has the Phoenix tracing proxy) ---
if sudo docker image inspect rag-adapter:local >/dev/null 2>&1; then
  log "Saving rag-adapter:local -> $MIG/rag-adapter-local.tar"
  sudo docker save rag-adapter:local -o "$MIG/rag-adapter-local.tar"
  sudo chown "$USER" "$MIG/rag-adapter-local.tar"
else
  log "WARN: rag-adapter:local not found; build it before k8s deploy."
fi

# --- 2) Stop the Docker stack + daemon (frees the GPU and host ports) ---
log "Stopping all Docker containers"
RUNNING="$(sudo docker ps -q)"; [ -n "$RUNNING" ] && sudo docker stop $RUNNING || true
log "Disabling the Docker daemon (keeps images for rollback)"
sudo systemctl stop docker.socket docker || true
sudo systemctl disable docker.socket docker || true

# --- 3) Point containerd at the CRI (kubeadm needs it; Docker had it disabled) ---
log "Writing a fresh containerd CRI config (SystemdCgroup=true)"
sudo cp -a /etc/containerd/config.toml "$MIG/containerd-config.toml.bak" 2>/dev/null || true
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/\(SystemdCgroup = \)false/\1true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sleep 3
sudo systemctl enable containerd

# --- 4) Import the adapter image into the k8s.io namespace containerd uses ---
if [ -f "$MIG/rag-adapter-local.tar" ]; then
  log "Importing rag-adapter:local into containerd (k8s.io namespace)"
  sudo ctr -n k8s.io images import "$MIG/rag-adapter-local.tar"
fi

log "Cutover complete. containerd CRI status:"
sudo crictl version 2>&1 | sed 's/^/  /' || true
sudo crictl images 2>/dev/null | grep -i rag-adapter || true
