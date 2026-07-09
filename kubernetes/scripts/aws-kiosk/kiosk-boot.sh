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
#   - The rag-adapter's /data at /data/rag-adapter (static hostPath PV, see
#     manifests/rag-adapter-data-pv.yaml) — kiosk-config.json, persona prompt
#     override, standby videos, Settings password, and the knowledge base.
#     Without this every boot silently reset all live operator config (the
#     etcd wipe recreates the PVC empty; unlike the on-prem Dell appliance,
#     where /data persists because etcd is never reset).
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

# host-helper's k8s-deploy.yaml hostPath-mounts /run/user/1000/{gdm,pulse}
# (type: Directory — mount FAILS if absent). Those exist on the physical Dell
# appliance (GDM autologin session) but this AWS box is headless with no GDM
# installed. A plain mkdir is NOT enough: /run/user/1000 is a logind-managed
# tmpfs that only exists while a session is open and is torn down on logout
# (dirs created over SSH vanished the moment the session closed — discovered
# 2026-07-09 chasing host-helper stuck in ContainerCreating with "hostPath
# type check failed"). Enable lingering so the runtime dir stays mounted for
# the life of the boot, then a tmpfiles rule recreates the subdirs. The pod's
# audio/display features are no-ops here; GPU stats + Renny control still work.
loginctl enable-linger ubuntu
printf 'd /run/user/1000/gdm 0700 ubuntu ubuntu -\nd /run/user/1000/pulse 0700 ubuntu ubuntu -\n' \
  > /etc/tmpfiles.d/kiosk-host-helper.conf
# runtime dir appears asynchronously after enable-linger; wait briefly, then create
for _ in $(seq 1 30); do [ -d /run/user/1000 ] && break; sleep 1; done
systemd-tmpfiles --create /etc/tmpfiles.d/kiosk-host-helper.conf || true

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

log "Applying the static PVs (Gemma cache + rag-adapter data — must exist before their claimants)"
mkdir -p /data/nim-cache/gemma /data/rag-adapter
kubectl apply -f "$REPO/kubernetes/manifests/nim-gemma-cache-pv.yaml"
kubectl apply -f "$REPO/kubernetes/manifests/rag-adapter-data-pv.yaml"

# helm repo add/update need helm.ngc.nvidia.com — tolerable to fail (a
# transient NGC blip must not kill the boot) ONLY because the AMI bakes the
# repo index + chart cache from a previous successful run. Verify the chart is
# actually resolvable (from network OR cache) and fail fast with a real error
# instead of letting `helm upgrade` die later with something cryptic.
log "Installing GPU operator"
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || \
  log "WARNING: helm repo update failed (NGC unreachable?) — falling back to the AMI's cached chart index"
helm show chart nvidia/gpu-operator >/dev/null 2>&1 || {
  echo "FATAL: chart nvidia/gpu-operator not resolvable (network down AND no cached index in the AMI)" >&2
  exit 1
}
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
# Under set -e a for-loop that never breaks still falls through "successfully"
# — check the result explicitly so a broken GPU stack fails the boot loudly
# instead of deploying a stack whose GPU pods will sit Pending forever.
if [ -z "${gpu:-}" ] || [ "$gpu" = "0" ]; then
  echo "FATAL: GPU never became allocatable (gpu-operator broken? driver mismatch?) — aborting boot" >&2
  kubectl get pods -n gpu-operator >&2 || true
  exit 1
fi

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
if [ "${gpu:-}" != "6" ]; then
  echo "FATAL: time-slicing never took effect (allocatable=$gpu, expected 6) — Renny/Gemma/host-helper cannot coexist; aborting boot" >&2
  exit 1
fi

log "Installing NIM operator"
helm show chart nvidia/k8s-nim-operator >/dev/null 2>&1 || {
  echo "FATAL: chart nvidia/k8s-nim-operator not resolvable (network down AND no cached index in the AMI)" >&2
  exit 1
}
helm upgrade --install nim-operator nvidia/k8s-nim-operator --namespace nim-operator --create-namespace
for i in $(seq 1 30); do kubectl get crd nimservices.apps.nvidia.com >/dev/null 2>&1 && break; sleep 4; done
kubectl get crd nimservices.apps.nvidia.com >/dev/null 2>&1 || {
  echo "FATAL: NIM operator CRDs never appeared after 2 min — aborting boot" >&2
  exit 1
}

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
# Bind the rag-adapter's /data PVC to the static hostPath PV so operator
# config survives the per-boot etcd wipe (see rag-adapter-data-pv.yaml).
export RAG_DATA_STORAGE_CLASS=static-local
bash kubernetes/scripts/deploy-allinone.sh

# The whole point of the static PVs is defeated silently if the PVCs bind to
# the wrong thing (or sit Pending): Gemma re-pulls 30-90GB, operator config
# resets per boot. Verify the actual bindings and fail loudly on mismatch.
log "Verifying static PV bindings…"
verify_pvc_bound() {  # verify_pvc_bound <ns> <pvc> <expected-pv> (waits up to 5 min — WaitForFirstConsumer binds only once the pod schedules)
  local ns=$1 pvc=$2 want_pv=$3 phase= pv=
  for _ in $(seq 1 60); do
    phase=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    pv=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
    [ "$phase" = "Bound" ] && break
    sleep 5
  done
  if [ "$phase" != "Bound" ] || [ "$pv" != "$want_pv" ]; then
    echo "FATAL: PVC $ns/$pvc is '$phase' bound to '${pv:-<none>}' (expected Bound to $want_pv) — static hostPath data is NOT wired up" >&2
    kubectl -n "$ns" get pvc >&2 || true; kubectl get pv >&2 || true
    exit 1
  fi
  log "PVC $ns/$pvc bound to $want_pv ✓"
}
verify_pvc_bound nim-models gemma-cache-pvc gemma-cache-pv
verify_pvc_bound uneeq rag-adapter-data rag-adapter-data-pv

log "Boot sequence complete."
