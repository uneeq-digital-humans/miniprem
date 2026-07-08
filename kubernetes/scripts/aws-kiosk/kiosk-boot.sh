#!/usr/bin/env bash
# Runs ON the kiosk box itself (via the kiosk-boot systemd unit) on every boot.
#
# Why this exists: the AMI's baked-in k8s control plane (certs, etcd peer URLs,
# kubeconfigs) is bound to whatever private IP existed at `kubeadm init` time.
# AWS assigns a new IP on every boot (we no longer pin the instance to one
# fixed IP/AZ — see kiosk-instance.sh), so the baked cluster is DOA on a
# different IP: etcd fails to bind, apiserver never comes up. Fix: reset and
# re-init the control plane fresh on every boot (auto-detects the current IP),
# then redeploy the whole stack. Idempotent-ish; safe to re-run manually too.
#
# What DOES survive the reset (by design, not by accident):
#   - The Gemma NIM model cache at /data/nim-cache/gemma (static hostPath PV,
#     see manifests/nim-gemma-cache-pv.yaml) — a fresh PVC re-binds to it via
#     the non-default "static-nim" StorageClass, so the NIM operator's puller
#     finds the weights already there and skips the ~30-90GB NGC download.
#   - /home/admin/migration/creds.conf (host file, not a k8s object) — has
#     NGC_API_KEY/HARBOR_*/PLATFORM_KEY/TENANT_ID/DEEPGRAM_API_KEY/
#     ELEVENLABS_API_KEY baked into the AMI.
#   - The GPU driver (host-level, untouched by kubeadm reset).
#
# Typical time: ~10-15 min (control plane init + gpu/nim operator reconcile +
# pods scheduling + Gemma NIM loading into VRAM). NOT a 2-minute boot — the
# tradeoff for being able to launch in any AZ with g7e capacity instead of
# waiting on one pinned AZ.
set -euo pipefail
log() { printf '\033[1;36m[kiosk-boot]\033[0m %s\n' "$*"; }

REPO=/home/ubuntu/miniprem
MIG=/home/admin/migration
CALICO_VER="${CALICO_VER:-v3.28.0}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"

[ -f "$MIG/creds.conf" ] || { echo "FATAL: $MIG/creds.conf missing — cannot deploy" >&2; exit 1; }

log "Resetting any stale control plane from a previous boot's IP"
kubeadm reset -f 2>&1 | tail -5 || true
rm -rf /etc/cni/net.d
iptables -F 2>/dev/null || true; iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true; iptables -X 2>/dev/null || true
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true

log "kubeadm init (pod-cidr $POD_CIDR) — binds to whatever IP this boot got"
kubeadm init --pod-network-cidr="$POD_CIDR" --cri-socket unix:///run/containerd/containerd.sock

mkdir -p /home/ubuntu/.kube
cp -f /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
mkdir -p /root/.kube && cp -f /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

log "Installing Calico $CALICO_VER (vendored locally — a live boot must not depend on GitHub being reachable/not-rate-limited)"
kubectl apply -f "$REPO/kubernetes/manifests/vendor/calico-v3.28.0.yaml"

log "Installing local-path-provisioner as the default StorageClass (vendored locally)"
kubectl apply -f "$REPO/kubernetes/manifests/vendor/local-path-storage-v0.0.30.yaml"
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

# NOTE: containerd caches "no CNI configured" from before Calico wrote its
# conflist. Restarting kubelet alone is NOT enough — observed the node stuck
# reporting "cni plugin not initialized" for 5+ min with Calico already
# healthy, until containerd itself was restarted. Do both.
log "Restarting containerd + kubelet so the new CNI conflist is picked up"
systemctl restart containerd
sleep 5
systemctl restart kubelet

log "Waiting for the node to go Ready (up to 5 min)…"
kubectl wait --for=condition=Ready node --all --timeout=300s

log "Applying the static Gemma cache PV (must exist before the NIMCache CR)"
kubectl apply -f "$REPO/kubernetes/manifests/nim-gemma-cache-pv.yaml"

log "Installing GPU operator"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --create-namespace \
  --set operator.defaultRuntime=containerd \
  --set driver.enabled=false
kubectl apply -f "$REPO/kubernetes/manifests/gpu-operator.yaml" 2>/dev/null || true

log "Waiting for GPU to be allocatable (up to 5 min)…"
for i in $(seq 1 60); do
  gpu=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)
  [ -n "$gpu" ] && [ "$gpu" != "0" ] && break
  sleep 5
done

# These two steps were manual one-off actions on the original box (2026-07-06)
# that got baked into that AMI's etcd state — a fresh kubeadm init has neither.
# Without the label, Gemma's NIMService (nodeSelector uneeq.io/node-type=renderer)
# never schedules. Without time-slicing, only 1 pod can claim the single physical
# GPU at a time — Renny's other replicas and host-helper sit Pending forever on
# "Insufficient nvidia.com/gpu" even though gpu-operator reports allocatable=1.
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
log "Labeling node $NODE_NAME uneeq.io/node-type=renderer"
kubectl label node "$NODE_NAME" uneeq.io/node-type=renderer --overwrite

# 6 slots = 4 Renny replicas (renny-values-cns.yaml deployment.totalReplicas)
# + Gemma + host-helper, all GPU-requesting pods that need to coexist on this
# box's single physical GPU. Time-slicing only multiplies *scheduling* slots —
# it does NOT partition VRAM — so this unblocks scheduling; actual headroom
# depends on each pod's real memory footprint (Gemma's NIM_PASSTHROUGH_ARGS
# caps it at --gpu-memory-utilization 0.45 specifically to leave room here).
log "Applying GPU time-slicing (6 replicas/GPU — Renny x4 + Gemma + host-helper share the one physical GPU)"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: renny-time-slicing-config
  namespace: gpu-operator
data:
  renny: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 6
EOF
kubectl patch clusterpolicy cluster-policy --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"renny-time-slicing-config","default":"renny"}}}}'
kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset --ignore-not-found

log "Waiting for time-sliced GPU allocatable to reach 6 (up to 3 min)…"
for i in $(seq 1 36); do
  gpu=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)
  [ "$gpu" = "6" ] && break
  sleep 5
done

log "Installing NIM operator"
helm upgrade --install nim-operator nvidia/k8s-nim-operator --namespace nim-operator --create-namespace
for i in $(seq 1 30); do kubectl get crd nimservices.apps.nvidia.com >/dev/null 2>&1 && break; sleep 4; done

log "Installing ingress-nginx (deploy-allinone.sh doesn't do this — separate step)"
bash "$REPO/kubernetes/scripts/cns-reprovision/40-ingress.sh"

# helm install returns as soon as the release is applied, not when the
# controller pod (and its admission webhook) actually accepts connections.
# Without this wait, deploy-allinone.sh's Ingress creation races the webhook
# and fails: "dial tcp ...:443: connect: connection refused" (discovered
# 2026-07-07 — worked manually only because other commands ran in between
# by chance, never reproducible in a straight-through automated boot).
log "Waiting for the ingress-nginx admission webhook to be ready (up to 2 min)…"
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=120s

log "Running deploy-allinone.sh (Riva disabled, Gemma 26b, Deepgram STT, ElevenLabs TTS)"
cd "$REPO"
set -a; . "$MIG/creds.conf"; set +a
export DEPLOY_GPU_OPERATOR=no   # already done above
export DEPLOY_RAG=no            # matches the known-working config; RAG blueprint was never actually enabled
export RAG_ADAPTER_IMAGE="${RAG_ADAPTER_IMAGE:-cr.uneeq.io/dell-isg-containers/rag-adapter:0.549-6844d}"
export GEMMA_BACKEND=nim
export DEPLOY_RIVA_TTS=no
export DEPLOY_RIVA_STT=no
export STT_PROVIDER=deepgram
export KIOSK_INGRESS_HOST=digitalhuman.miniprem
bash kubernetes/scripts/deploy-allinone.sh

log "Boot sequence complete."
