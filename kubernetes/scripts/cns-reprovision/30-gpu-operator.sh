#!/usr/bin/env bash
# Phase 3 — NVIDIA GPU operator (host driver already installed) + GPU time-slicing
# so the NIM/Riva/RAG/Renny pods can share the one Blackwell GPU, + the node label
# the UneeQ/NVIDIA manifests select on (uneeq.io/node-type=renderer).
set -euo pipefail
log() { printf '\033[1;36m[gpu]\033[0m %s\n' "$*"; }
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
TS_REPLICAS="${TS_REPLICAS:-16}"

NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
log "Labelling node $NODE (uneeq.io/node-type=renderer)"
kubectl label node "$NODE" uneeq.io/node-type=renderer --overwrite

log "Installing GPU operator (driver.enabled=false; host driver in use)"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --set toolkit.version=v1.16.2-ubuntu20.04 \
  --set operator.defaultRuntime=containerd
# toolkit.version PINNED: container-toolkit >=1.17 rewrites /etc/containerd/config.toml
# to schema version=3, which containerd 1.7.x (config v2 max, what kubeadm uses here)
# CANNOT read → containerd crash-loops on the NEXT reboot → whole cluster fails to come
# up. v1.16.x writes version=2 configs, so the box survives reboots. Do NOT drop this
# pin unless the box's containerd is also on 2.x. (Learned the hard way 2026-07-01.)

log "Waiting for the device plugin to register (up to 300s)…"
for i in $(seq 1 50); do
  cap="$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  [ -n "$cap" ] && [ "$cap" != "0" ] && { log "GPU allocatable: $cap"; break; }
  sleep 6
done

# Time-slicing: split the one GPU into TS_REPLICAS schedulable units.
log "Configuring GPU time-slicing (replicas=$TS_REPLICAS)"
kubectl -n gpu-operator apply -f - <<TS
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: ${TS_REPLICAS}
TS
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}' || true

log "Phase 3 complete. Re-checking GPU allocatable in 30s…"
sleep 30
kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}{"\n"}' || true
kubectl -n gpu-operator get pods 2>/dev/null | tail -20 || true
