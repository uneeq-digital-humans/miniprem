# Running More Rennys per GPU

Renny 0.1704 changed how several renderers share one GPU. In the UneeQ cloud the same change doubled the number of
live sessions a node holds at a 20 FPS floor. This guide covers what changed, how to turn it on for a MiniPrem
deployment (Docker or Kubernetes), how to find the right number of Rennys for your GPU, and how to roll back.

## What changed in renny 0.1704

Several Rennys on one GPU share it through **GPU submission serialization**: a lock that lets one renderer at a time
submit work, so the driver never has to switch between busy GPU contexts. Without it, three or more Rennys on one GPU
lose most of the card to context switching.

0.1704 makes two changes to that lock:

- **One ticket per frame.** A renderer records its whole frame, takes the lock once, submits it and releases it.
  Before, it took the lock for a fixed number of submissions, which split frames across turns and left the GPU idle
  between them.
- **Session start stays serialized.** A renderer starting a session used to leave the lock until the session was live.
  Its first frames then competed unserialized with the sessions already running, which dropped those to about 12 FPS
  for close to a minute every time someone joined. They now dip for a few seconds at most.

Both only apply when the lock is on. With the lock off, 0.1704 behaves exactly like earlier images.

Measured in the UneeQ cloud (live speaking sessions, ray-traced scene at 1280x720, 20 FPS floor on the weakest
session, NVIDIA driver 580.159.03):

| GPU | Rennys per GPU before | With 0.1704 | VRAM per live Renny (measured) |
|---|---|---|---|
| NVIDIA L40S 48 GB | 3 | 6 | about 6.3 GB |
| NVIDIA RTX PRO 6000 Blackwell 96 GB | 3 | 6 | not limiting |
| NVIDIA A10G 24 GB | 2 | 4 | about 4.1 GB |
| NVIDIA L4 24 GB | 2 | 3 (VRAM and its 72 W power cap) | about 5.8 GB |
| NVIDIA T4 16 GB | 1 | 1 (a second ray-traced Renny faults the GPU) | not measured |

**These are starting points, not targets for MiniPrem.** MiniPrem often renders at higher quality (`qualityLevel:
miniprem`) and higher resolution (up to 4K), and some installs share the GPU with a local LLM. Each of those lowers
how many Rennys fit. Always validate on the site's hardware (see [Finding the right count](#finding-the-right-count)).

## Requirements

- `renny-renderer` **0.1704 or newer** for the behaviour above. The lock itself works from 0.1428-6654b; older images
  ignore it.
- A datacenter or workstation NVIDIA GPU. On consumer cards (for example an RTX 4070 that also drives a display), lab
  runs collapsed at three Rennys even with careful pacing, so treat anything above two there as experimental.
- Host CPU: about 1.5 cores per live Renny was the peak measured under load. Plan at least 1.5 cores per Renny plus
  headroom for the OS and other services.

## Docker

1. **Use a 0.1704+ image.** Set the renderer image tag in `docker/docker-compose.env` (or your install's override) to
   0.1704 or newer and pull it.
2. **Turn on the lock.** For multiple instances, `docker/scripts/setup_multiple_rennys.sh` already does this: it adds
   `RENNY_GPU_LOCK_PATH=/run/renny-gpu-lock` to `docker/docker-compose.env` when the line is missing, creates the lock
   directory and keeps it across reboots. For a hand-built setup, add that line yourself and make sure
   `/run/renny-gpu-lock` exists on the host and is mounted into every Renny container (the stock
   `docker-compose.yml` mounts it).
3. **Choose the number of instances** with `setup_multiple_rennys.sh`, starting from the table above and the
   validation steps below.
4. **Start and check.** Each Renny container's log should print
   `GPU submission serialization on (lock dir: /run/renny-gpu-lock)` at startup.

## Kubernetes

The settings live in your values file (`kubernetes/values/renny-values.yaml`, `renny-values-cns.yaml`,
`renny-values-aks.yaml`, or your own copy).

1. **Use a 0.1704+ image** (`image.tag` or your registry override).
2. **Turn on the lock:**

   ```yaml
   renderer:
     gpuLockPath: "/run/renny-gpu-lock"
   ```

   The chart then mounts the directory, fixes its ownership with an init container and starts Renny with
   serialization on. CNS installs already set this.
3. **Lower the CPU request, keep the limit.** Kubernetes places pods by their requests, so a 3200m+ request stops a
   16-core server from scheduling more than four Rennys. Measured peak use was about 1.4 cores per Renny:

   ```yaml
   resources:
     requests:
       cpu: "1500m"
     limits:
       cpu: "3200m"   # keep your current limit for bursts
   ```

4. **Set the GPU slices and the replica count together.** `gpuTimeSlicing.replicasPerGpu` is how many Rennys the GPU
   operator lets share one GPU; `deployment.totalReplicas` is how many run. Raise both, one step at a time:

   ```yaml
   gpuTimeSlicing:
     replicasPerGpu: 4
   deployment:
     totalReplicas: 4   # replicasPerGpu x number of GPUs, or fewer
   ```

5. **Apply** with your usual deploy script (`./scripts/deploy.sh` regenerates the time-slicing ConfigMap from
   `replicasPerGpu` and restarts the GPU device plugin), or `helm upgrade` with your values file.
6. **Check that the GPU operator picked up the new slice count.** The device plugin does not always re-advertise a
   changed count on a node that is already running:

   ```bash
   kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
   ```

   If the number is still the old one, restart the device plugin (`kubectl -n gpu-operator delete pod -l
   app=nvidia-device-plugin-daemonset`) or reboot the node, then check again. Pods beyond the old count stay
   `Pending` until it updates.

## Finding the right count

Raise the number of Rennys one at a time with real sessions running (people talking to the avatars, at the
production scene and resolution):

1. Run every Renny with a live session for at least five minutes.
2. Watch the weakest session's frame rate. Hold the floor you need (UneeQ sizes the cloud at 20 FPS) on every
   session, not on average.
3. Watch VRAM with `nvidia-smi`. Keep about 1 GB free for a session starting while the others run: a starting Renny
   allocates more than a running one, and a Renny that cannot allocate keeps retrying and drags the others down.
4. Check the kernel log for GPU faults (`sudo dmesg | grep -i xid`). An `Xid 109 CTX SWITCH TIMEOUT` means the GPU
   could not switch between Rennys in time; go back a step.
5. Start one more session while the others are running and confirm the running ones stay smooth.

Stop at the last step that passed all five checks.

## Rolling back

- **Turn the lock off:** `renderer.gpuLockPath: ""` (Kubernetes) or `RENNY_GPU_LOCK_PATH=` (Docker). Above two
  Rennys per GPU, also lower the count.
- **Restore the old session-start behaviour only:**
  - Kubernetes: `renderer.extraCmdArgs: "-ini:Engine:[ConsoleVariables]:r.Renny.GpuSerialization.SuspendDuringSessionStart=1"`
  - Docker: `RENNY_EXTRA_ARGS=-ini:Engine:[ConsoleVariables]:r.Renny.GpuSerialization.SuspendDuringSessionStart=1`
    in `docker/docker-compose.env`
- **Restore the old per-submission lock:** the same mechanism with `r.Renny.GpuSerialization.ReleaseOnFrameBoundary=0`
  (also set `SuspendDuringSessionStart=1`, which that mode needs).
