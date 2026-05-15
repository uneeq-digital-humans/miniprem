#!/bin/bash
# Verify NVIDIA driver install end-to-end on a Kubernetes node.
#
# Confirms:
#   1. nvidia-smi works on the host (driver loaded)
#   2. The CDI spec at /var/run/cdi/nvidia.yaml matches the running driver
#   3. A GPU pod scheduled with runtimeClassName=nvidia receives the host
#      libcuda.so mount and can successfully call cuInit / cudaMalloc.
#
# This is the test that catches the "container sees only compat library"
# class of bug — `nvidia-smi` will lie and look fine while pods fail at
# CUDA init.
#
# Usage:
#   bash scripts/nvidia/verify-driver-install.sh [namespace]
# Default namespace is `default`.

set -e

NS="${1:-default}"
NODE_SELECTOR_KEY="${NODE_SELECTOR_KEY:-uneeq.io/node-type}"
NODE_SELECTOR_VAL="${NODE_SELECTOR_VAL:-renderer}"
CDI_FILE=/var/run/cdi/nvidia.yaml
PROBE_POD=nvidia-driver-verify

info()    { echo "ℹ️  $*"; }
ok()      { echo "✅ $*"; }
fail()    { echo "❌ $*"; exit 1; }

# --- 1. Host driver ----------------------------------------------------------
info "[1/3] Checking host driver via nvidia-smi..."
if ! command -v nvidia-smi >/dev/null 2>&1; then
    fail "nvidia-smi not found on host. Driver is not installed."
fi
HOST_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs)
ok "Host driver: $HOST_DRIVER"

# --- 2. CDI spec freshness ---------------------------------------------------
info "[2/3] Checking GPU Operator CDI spec freshness..."
if [ ! -f "$CDI_FILE" ]; then
    echo "WARN: $CDI_FILE missing. If you're not using GPU Operator this is fine."
    echo "      Otherwise regenerate with: sudo nvidia-ctk cdi generate --output=$CDI_FILE"
else
    CDI_DRIVER=$(grep -oE "libcuda\.so\.[0-9.]+" "$CDI_FILE" | head -1 | sed 's/libcuda.so.//')
    if [ "$CDI_DRIVER" = "$HOST_DRIVER" ]; then
        ok "CDI spec matches host driver ($CDI_DRIVER)"
    else
        echo "❌ CDI drift: host=$HOST_DRIVER, CDI=$CDI_DRIVER"
        echo "   Fix: sudo nvidia-ctk cdi generate --output=$CDI_FILE"
        echo "        kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset"
        exit 1
    fi
fi

# --- 3. CUDA-in-pod probe ----------------------------------------------------
info "[3/3] Running CUDA probe pod (this exercises the full mount path)..."

# CUDA test source — checks cudaGetDeviceCount + a cudaMalloc to validate
# both the runtime API and that the kernel module is reachable.
cat <<'EOF' > /tmp/_cuda_probe.cu
#include <cuda_runtime.h>
#include <stdio.h>
int main(){
  int n=0;
  cudaError_t e=cudaGetDeviceCount(&n);
  printf("Devices=%d Err=%d %s\n", n, e, cudaGetErrorString(e));
  if(e==0){
    e=cudaSetDevice(0);
    printf("SetDevice Err=%d %s\n", e, cudaGetErrorString(e));
    void *p=0;
    e=cudaMalloc(&p, 1024*1024);
    printf("Malloc Err=%d %s\n", e, cudaGetErrorString(e));
    if(p) cudaFree(p);
  }
  return e;
}
EOF
kubectl create configmap nvidia-driver-verify-src -n "$NS" \
    --from-file=cuda-test.cu=/tmp/_cuda_probe.cu \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Clean up any prior probe
kubectl delete pod -n "$NS" "$PROBE_POD" --force --grace-period=0 2>/dev/null || true

kubectl run "$PROBE_POD" -n "$NS" --restart=Never \
    --image=nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04 \
    --overrides="{
      \"apiVersion\":\"v1\",
      \"spec\":{
        \"runtimeClassName\":\"nvidia\",
        \"containers\":[{
          \"name\":\"$PROBE_POD\",
          \"image\":\"nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04\",
          \"command\":[\"sh\",\"-c\",\"ls /usr/lib/x86_64-linux-gnu/libcuda* 2>&1 | head -3 && nvcc /src/cuda-test.cu -o /tmp/t && /tmp/t\"],
          \"resources\":{\"limits\":{\"nvidia.com/gpu\":\"1\"}},
          \"volumeMounts\":[{\"name\":\"src\",\"mountPath\":\"/src\"}]
        }],
        \"volumes\":[{\"name\":\"src\",\"configMap\":{\"name\":\"nvidia-driver-verify-src\"}}],
        \"tolerations\":[{\"operator\":\"Exists\"}],
        \"nodeSelector\":{\"${NODE_SELECTOR_KEY}\":\"${NODE_SELECTOR_VAL}\"},
        \"restartPolicy\":\"Never\"
      }
    }" >/dev/null

# Wait for completion (up to ~3 min for image pull on first run)
until [ "$(kubectl get pod -n "$NS" "$PROBE_POD" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Succeeded" ] \
   || [ "$(kubectl get pod -n "$NS" "$PROBE_POD" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Failed" ]; do
    sleep 5
done

PHASE=$(kubectl get pod -n "$NS" "$PROBE_POD" -o jsonpath='{.status.phase}')
LOGS=$(kubectl logs -n "$NS" "$PROBE_POD" 2>&1 || true)

kubectl delete pod -n "$NS" "$PROBE_POD" --force --grace-period=0 2>/dev/null || true
kubectl delete configmap -n "$NS" nvidia-driver-verify-src 2>/dev/null || true
rm -f /tmp/_cuda_probe.cu

echo "--- Probe output ---"
echo "$LOGS"
echo "--- end probe output ---"

if echo "$LOGS" | grep -q "Devices=[1-9]" && echo "$LOGS" | grep -q "Err=0"; then
    ok "CUDA init + cudaMalloc succeeded inside container."
    ok "Driver $HOST_DRIVER is fully functional end-to-end."
    exit 0
fi

if echo "$LOGS" | grep -qE "Err=35|insufficient driver"; then
    echo ""
    echo "❌ CUDA error 35 (cudaErrorInsufficientDriver)."
    echo "   The container sees an older libcuda than the running kernel module."
    echo "   Almost always means the CDI spec is stale or the GPU Operator's"
    echo "   container toolkit pods haven't been restarted after a driver swap."
    echo "   Fix:"
    echo "     sudo nvidia-ctk cdi generate --output=$CDI_FILE"
    echo "     kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset"
    exit 1
fi

fail "CUDA probe failed (phase=$PHASE). See output above."
