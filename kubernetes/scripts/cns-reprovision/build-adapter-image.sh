#!/usr/bin/env bash
# Build the rag-adapter image straight into the kubeadm box's containerd (k8s.io
# namespace) using nerdctl + buildkit — the containerd-native builder, so we don't
# need (the now-disabled) Docker. Idempotent: installs nerdctl-full + buildkit once.
set -euo pipefail
log() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
CTX="${1:-/home/admin/rag-adapter}"
TAG="${TAG:-rag-adapter:local}"
NERDCTL_VER="${NERDCTL_VER:-1.7.7}"

if ! command -v nerdctl >/dev/null; then
  log "Installing nerdctl-full $NERDCTL_VER (bundles buildkit + CNI)"
  arch=$(dpkg --print-architecture)   # amd64 / arm64
  curl -fsSL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VER}/nerdctl-full-${NERDCTL_VER}-linux-${arch}.tar.gz" \
    | sudo tar -C /usr/local -xz
fi
# buildkitd (needed by `nerdctl build`).
sudo systemctl enable --now buildkit 2>/dev/null || {
  log "starting buildkitd via the bundled unit"
  sudo systemctl enable --now buildkitd 2>/dev/null || true
}
sleep 2

log "Building $TAG from $CTX into containerd (k8s.io)"
sudo nerdctl --namespace k8s.io build -t "$TAG" "$CTX"
log "Done. Image in k8s.io:"
sudo nerdctl --namespace k8s.io images 2>/dev/null | grep -i rag-adapter | head -2 || true
