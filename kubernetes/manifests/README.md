# Kubernetes Manifests

Platform-agnostic Kubernetes resources used by MiniPrem CNS deployments. These
manifests assume an NVIDIA GPU node with the [GPU Operator](https://github.com/NVIDIA/gpu-operator)
already installed.

## GPU Pod Requirements

Any pod that requests `nvidia.com/gpu` **must** set `runtimeClassName: nvidia`
in its PodSpec. Without it, containerd schedules the pod under plain `runc`,
which does **not** invoke `nvidia-container-runtime`. The result: the host
driver libraries (`libcuda.so.<driver-version>`) are never mounted into the
container, and CUDA initialization fails with
`cudaErrorInsufficientDriver` (error 35) because the container falls back to
its bundled `/usr/local/cuda/compat/libcuda.so.550.54.15`.

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      runtimeClassName: nvidia      # required
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      nodeSelector:
        uneeq.io/node-type: renderer
      containers:
        - name: my-cuda-app
          resources:
            limits:
              nvidia.com/gpu: "1"
```

The `nvidia` RuntimeClass is installed automatically by the GPU Operator. You
can verify it exists with:

```bash
kubectl get runtimeclass nvidia
```

## Slow-Bootstrap Workloads (NIM / Triton / vLLM)

NIM Magpie TTS, Nemotron ASR, and vLLM all compile TensorRT engines on first
boot. This can take **15–30 minutes** for a cold start (model download + TRT
graph compile). Use a `startupProbe` rather than a long `initialDelaySeconds`
liveness probe — see `magpie-tts.yaml` and `vllm-gemma4.yaml` for the pattern.

A long-`initialDelay` liveness probe will eventually fire on its `periodSeconds`
cadence and kill the container mid-compile, looping forever. A `startupProbe`
disables liveness/readiness checks until it succeeds.

## Manifests in this directory

| File | Purpose |
|---|---|
| `magpie-tts.yaml` | NVIDIA Riva Magpie TTS NIM (gRPC port 50051, HTTP 9000). ~11 GB VRAM at batch_size=8. |
| `vllm-gemma4.yaml` | vLLM **fallback** backend (`GEMMA_BACKEND=vllm`) serving the configured `${GEMMA_MODEL}` (an HF checkpoint) at FP8. Standard backend is the gemma-4-26b-a4b-it NIM. |
| `gpu-operator.yaml` | GPU Operator install + time-slicing ConfigMap. |
| `autoscaler.yaml` / `autoscaler/` | HPA for renny + supporting resources. |
| `namespace.yaml` | Namespaces (uneeq, nim-models, observability, etc.). |

## Verifying GPU Pod Plumbing

After applying these manifests (or after any driver swap), run:

```bash
bash scripts/nvidia/verify-driver-install.sh
```

This schedules a transient CUDA probe pod with `runtimeClassName: nvidia` and
exercises `cudaGetDeviceCount` + `cudaMalloc`. It catches issues that
`nvidia-smi` does not — including stale CDI specs and missing `runtimeClassName`.

## See Also

- [NVIDIA Driver Setup](../../docs/NVIDIA-DRIVER-SETUP.md) — driver versions and install procedure
- [Troubleshooting](../../docs/troubleshooting.md) — CUDA error 35, NIM crashloops, NVENC issues
- [CNS Deployment Guide](../../docs/CNS-DEPLOYMENT-GUIDE.md) — end-to-end CNS setup
