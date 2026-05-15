<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# MiniPrem Troubleshooting Guide

> Solutions for common issues when running the MiniPrem platform

</div>

> **New to troubleshooting?** Start with our [First Steps](guides/first-steps.md) guide - a beginner-friendly walkthrough for gathering diagnostic information before contacting support.

## Table of Contents

- [General Troubleshooting Steps](#general-troubleshooting-steps)
- [NVIDIA Driver Issues](#nvidia-driver-issues)
- [vLLM Issues](#vllm-issues)
- [Flowise Issues](#flowise-issues)
- [Renny Issues](#renny-issues)
- [Monitoring Issues](#monitoring-issues)
- [Network Issues](#network-issues)
- [Resource Issues](#resource-issues)
- [License](#license)
- [Copyright](#copyright)

## General Troubleshooting Steps

1. **Check Service Status**:
   ```bash
   ./miniprem.sh status
   ```

2. **View Service Logs**:
   ```bash
   ./miniprem.sh logs
   # Or for a specific service
   ./miniprem.sh logs renny
   ```

3. **Restart Services**:
   ```bash
   ./miniprem.sh restart
   ```

4. **Check Docker Resources**:
   ```bash
   docker stats
   ```

## NVIDIA Driver Issues

### Symptoms

- NVENC shows 0% utilization during an active session
- Pixel Streaming fails — session connects briefly then disconnects
- Renny logs show: "Session failed to start. HasActivePixelStreaming: false"

### Check Your Current Driver

```bash
nvidia-smi | head -3
```

Look for the `Driver Version` in the output. The version number determines compatibility.

### Known Bad Versions

!> **580.126.x** (all variants) — breaks NVENC hardware encoding on **all** GPU types (L4, A10G, T4, RTX). Sessions will connect but immediately fail because Pixel Streaming cannot encode video frames.

### Known Good Versions

| Version | Install Method | Verified On | Notes |
|---------|---------------|-------------|-------|
| 580.142 | .run installer (NVIDIA direct) | RTX 6000 Ada + GPU Operator + NIM + vLLM | **Recommended** for mixed renny + NIM/Triton/vLLM workloads |
| 580.82.07 | apt (Ubuntu package manager) | L4 (AWS g6), A10G (AWS g5) | Renny-only. NIM workloads fail — see below. |
| 580.82.09 | .run installer (NVIDIA direct) | L4, RTX PRO 6000 | Same caveat as 580.82.07. |

### Quick Fix

If you are running a bad driver version, install the recommended version:

```bash
# Check current version
nvidia-smi | head -3

# Downgrade/upgrade to 580.142 via the included script (handles MOK signing,
# apt purge, CDI regeneration, persistence mode in one shot):
sudo bash scripts/nvidia/install-nvidia-580.sh
```

### Monitor NVENC During a Session

```bash
# Watch encoder utilization (enc column should be >0% during active session)
nvidia-smi dmon -s u
```

### CUDA error 35 / cuInit failed (error 999)

**Symptoms:**

- NIM/Triton/vLLM pods crashloop with one of:
  - `cuInit failed with error code 999: unknown error`
  - `RuntimeError: CUDA unknown error - this may be due to an incorrectly set up environment, e.g. changing env variable CUDA_VISIBLE_DEVICES after program start`
  - `Devices=0 Err=35 CUDA driver version is insufficient for CUDA runtime version`
- `nvidia-smi` on the host works fine
- The GPU Operator's `nvidia-cuda-validator` job completes successfully
- Renny (which uses Vulkan, not CUDA) works fine
- A bare `kubectl run --image=nvidia/cuda` pod **without** `runtimeClassName: nvidia` also fails

**Root cause:**

Either the CDI spec at `/var/run/cdi/nvidia.yaml` is stale (driver swap without
`nvidia-ctk cdi generate`), or your pod is missing `runtimeClassName: nvidia`.
In both cases the container ends up with only its bundled
`/usr/local/cuda/compat/libcuda.so.550.54.15` instead of the host driver's
`libcuda.so.<your-version>`. The runtime libraries in the container then
report the driver as too old to satisfy them, hence error 35.

**Diagnose:**

```bash
# Schedule a CUDA probe pod and check end-to-end
bash scripts/nvidia/verify-driver-install.sh
```

**Fix:**

```bash
# 1. Regenerate the CDI spec
sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml

# 2. Restart the device plugin so it re-reads the spec
kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset

# 3. If pods still fail, check they have `runtimeClassName: nvidia`:
kubectl get pod <pod-name> -o jsonpath='{.spec.runtimeClassName}'
# Expected: nvidia

# 4. Also confirm NVIDIA persistence mode is enabled:
sudo nvidia-smi -pm 1
```

### NIM/Triton container in CrashLoopBackOff while building TensorRT engines

**Symptoms:**

- Container logs show TRT engine compilation in progress: `[Step 4/4] Building TRT engine (this may take several minutes)...`
- Container is killed before compile finishes; restarts and tries again
- `kubectl get pod` shows many restarts (10+, 50+) but no obvious error
- Cold-start a NIM container easily takes 15–30 min on first model deploy

**Root cause:**

A long `livenessProbe.initialDelaySeconds` is not enough — once the delay
expires, the probe fires every `periodSeconds` and after `failureThreshold`
failures the kubelet kills the container. The container is making progress but
the probe interprets "gRPC port not yet open" as "container is wedged."

**Fix:**

Use a `startupProbe` instead, which disables the liveness/readiness probes
until startup succeeds. Once startup completes, the regular lean liveness
takes over.

```yaml
startupProbe:
  tcpSocket: { port: 50051 }          # or httpGet for HTTP services
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 80                # ~40 min total grace
  timeoutSeconds: 5
livenessProbe:
  tcpSocket: { port: 50051 }
  periodSeconds: 30
  failureThreshold: 3                 # tight once running
```

See `kubernetes/manifests/magpie-tts.yaml` and `vllm-gemma4.yaml` for the
pattern.

### Riva/Triton segfault inside libucs.so (digitalhuman-asr)

**Symptoms:**

- `digitalhuman-asr` pod stays at `1/2 Running` indefinitely with the
  `nemotron-asr` container not Ready
- Logs show Riva successfully reaching ready state, then dying:
  ```
  I0515 13:43:11 riva_server.cc:307] Riva Conversational AI Server listening on 0.0.0.0:50051
  INFO:inference:Riva gRPC Server is READY
  [pod:34398:0:34398] Caught signal 11 (Segmentation fault: address not mapped to object)
  ==== backtrace (tid: 34398) ====
   0  /opt/hpcx/ucx/lib/libucs.so.0(ucs_handle_error+0x2e4)
  tritonserver process has exited unexpectedly. Stopping container.
  W0515 13:43:16 riva_server.cc:340] Signal: 15
  ```
- After the crash the `riva_http_server` keeps logging `Failed to connect to
  remote host: connect: Connection refused (111)` against port 50051 because
  the Riva gRPC server is gone but the container itself is still alive

**Root cause:**

The NIM `nemotron-asr-streaming` image embeds Triton, which links HPC-X /
UCX (`libucs.so`). On startup UCX probes available transports. On hosts that
do **not** have RDMA/InfiniBand hardware, the RDMA-related probes can
segfault inside libucs, taking tritonserver down with them. This shows up
*after* Riva has bound port 50051 — making it especially confusing because
the pod looks like it succeeded.

**Fix:**

Whitelist only the UCX transports that work without specialized network
hardware. The chart now sets this by default via `nemotron.ucxTls`:

```yaml
# kubernetes/digitalhuman-asr/values.yaml
nemotron:
  ucxTls: "cuda_ipc,sm,tcp"   # default — works on single-GPU, multi-GPU same-host, and multi-host TCP
  ucxLogLevel: "warn"
```

The defaults are portable across deployment shapes:

| Transport | Used on |
|---|---|
| `cuda_ipc` | Multi-GPU same-host (NVLink / PCIe P2P) |
| `sm` | Shared memory (CPU-side, single-host) |
| `tcp` | Single-host fallback + multi-host comms |
| *excluded:* `rc, ud, rdmacm, ib, dc` | InfiniBand/RoCE — only enable on hosts with real RDMA fabric |

If you actually have InfiniBand hardware, override the values:

```yaml
nemotron:
  ucxTls: "cuda_ipc,sm,tcp,rc,ud"
```

**Quick patch on a running deployment** (e.g. while you're upgrading the chart):

```bash
kubectl set env -n uneeq deploy/digitalhuman-asr \
    -c nemotron-asr \
    UCX_TLS=cuda_ipc,sm,tcp UCX_LOG_LEVEL=warn
```

For full details on driver types, installation methods, and GPU compatibility, see the [NVIDIA Driver Guide](guides/nvidia-drivers.md).

## vLLM Issues

### vLLM Container Fails to Start

**Symptoms**: vLLM container stops immediately after starting

**Solutions**:
1. Check GPU availability:
   ```bash
   nvidia-smi
   ```

2. Verify NVIDIA runtime is properly configured:
   ```bash
   docker info | grep -i runtime
   ```

3. Check for port conflicts:
   ```bash
   sudo lsof -i :8000
   ```

4. Check vLLM logs:
   ```bash
   docker logs vllm
   ```

### Model Loading Issues

**Symptoms**: Error messages when trying to use the model

**Solutions**:
1. Check if model is downloaded:
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. Re-pull the model:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model facebook/opt-125m
   ```

3. Check for sufficient GPU memory:
   ```bash
   nvidia-smi
   ```

4. Try a smaller model for testing:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## Flowise Issues

### Flowise UI Not Accessible

**Symptoms**: Cannot access Flowise at http://localhost:3000

**Solutions**:
1. Check if the container is running:
   ```bash
   docker ps | grep flowise
   ```

2. Check container logs:
   ```bash
   docker logs flowise
   ```

3. Verify port availability:
   ```bash
   curl -I http://localhost:3000
   ```

### Chatflow Creation Failures

**Symptoms**: Cannot create or save chatflows

**Solutions**:
1. Check database connectivity:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. Check volume permissions:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. Try running the setup script manually:
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### API Authentication Issues

**Symptoms**: Unauthorized errors when accessing the API

**Solutions**:
1. Check if you're using the correct API key:
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. Reset the API key:
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   Then update the `FLOWISE_SECRETKEY_OVERWRITE` in the appropriate compose file (docker-compose.base.yml or docker-compose.extras.yml, depending on your install type).

## Renny Issues

### Renny Health Check Failures

**Symptoms**: Renny container reports unhealthy status

**Solutions**:
1. Check Renny logs:
   ```bash
   docker logs renny
   ```

2. Verify UneeQ platform connectivity:
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. Check internal speech processing:
   ```bash
   docker logs renny | grep -i speech
   ```

4. Verify configuration.dat file:
   ```bash
   cat docker/configuration.dat
   ```

### Speech Processing Issues

**Symptoms**: Facial animations or speech not working correctly

**Solutions**:
1. Check speech processing configuration:
   ```bash
   docker logs renny | grep -i "speech\|audio"
   ```

2. Verify NEW_SPEECH_OVERRIDE environment variable:
   ```bash
   docker exec -it renny env | grep NEW_SPEECH_OVERRIDE
   ```

3. Check Renny internal speech system status:
   ```bash
   curl -s http://localhost:8081/health | grep -i speech
   ```

## Monitoring Issues

### Prometheus Not Collecting Metrics

**Symptoms**: No metrics in Grafana dashboards

**Solutions**:
1. Check if Prometheus is running:
   ```bash
   docker ps | grep prometheus
   ```

2. Check Prometheus targets:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Verify Prometheus configuration:
   ```bash
   cat docker/prometheus.yml
   ```

### Grafana Login Issues

**Symptoms**: Cannot log in to Grafana

**Solutions**:
1. Use default credentials (admin/admin)

2. Reset admin password:
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Check Grafana logs:
   ```bash
   docker logs grafana
   ```

## Network Issues

### Port Conflicts

**Symptoms**: Services fail to start due to port already in use

**Solutions**:
1. Find which process is using the port:
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. Stop the conflicting process or modify the port in the appropriate compose file (docker-compose.base.yml or docker-compose.extras.yml).

3. Check firewall settings:
   ```bash
   sudo ufw status
   ```

### Docker Network Issues

**Symptoms**: Services cannot communicate with each other

**Solutions**:
1. Check Docker network:
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. Verify container connectivity:
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```

## Resource Issues

### Out of Memory

**Symptoms**: Services crashing with OOM errors

**Solutions**:
1. Check memory usage:
   ```bash
   free -h
   docker stats
   ```

2. Increase host swap space:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Adjust Docker memory limits:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### GPU Memory Issues

**Symptoms**: GPU out of memory errors

**Solutions**:
1. Monitor GPU usage:
   ```bash
   nvidia-smi -l 1
   ```

2. Use a smaller model:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. Prevent other applications from using the GPU during MiniPrem operation

If you want to add more services or change your install type, re-run the installer and select the desired option.

---

## License

The MiniPrem documentation and installation scripts are open source under the MIT License - see the [LICENSE](../LICENSE) file for details. Note: The Renny digital human application itself is commercially licensed by UneeQ and is not covered by this license.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>