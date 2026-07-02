#!/usr/bin/env bash
# Build + deploy the rag-adapter image on the kubeadm box (local containerd tag).
set -euo pipefail
BOX="${KIOSK_BOX:-admin@10.0.2.81}"
TAG="${1:-v9}"
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "1) sync source → box"
rsync -az --delete --exclude "*.pyc" --exclude ".pytest_cache" "$SRC/" "$BOX:/home/admin/adapter-build/"

echo "2) build rag-adapter:$TAG + roll deployment"
ssh "$BOX" "cd /home/admin/adapter-build && \
  sudo nerdctl -n k8s.io build -t rag-adapter:$TAG . 2>&1 | tail -2 && \
  kubectl set image deploy/rag-adapter -n uneeq '*=rag-adapter:$TAG' && \
  kubectl rollout status deploy/rag-adapter -n uneeq --timeout=180s | tail -1"

echo "3) listing test"
ssh "$BOX" "curl -s --max-time 20 -H 'Host: digitalhuman.miniprem' 'http://127.0.0.1/rag-admin/admin/documents?collection=multimodal_data' | head -c 300"
echo
