# NVIDIA Driver Setup for MiniPrem CNS

## Critical Driver Requirements

**Recommended Driver Version: 580.142** (renny + NIM/Triton/vLLM workloads)

For **renny-only** deployments, **580.82.x** also works. For mixed workloads
that include NIM Magpie TTS, Nemotron ASR, or vLLM, use **580.142+** —
580.82.x has a known issue on the GPU Operator stack where containers end up
using the in-image `libcuda.so.550.54.15` compat library instead of the host
driver, producing `cudaErrorInsufficientDriver` (error 35) during TensorRT
initialization. See [troubleshooting.md](./troubleshooting.md#cuda-error-35--cuinit-failed-error-999).

> **WARNING:** Driver version **580.126.x is INCOMPATIBLE** with Renny. It breaks NVENC hardware video encoding on ALL GPU types.

| Driver Version | Status | Notes |
|----------------|--------|-------|
| 580.142 | **RECOMMENDED** | Renny + NIM/Triton/vLLM. Confirmed end-to-end on Blackwell + GPU Operator + NIM Magpie/Nemotron + vLLM. |
| 580.82.09 | OK for renny-only | Required for RTX PRO 6000 Blackwell. **NIM/Triton workloads fail** with `cudaErrorInsufficientDriver` — see [troubleshooting](./troubleshooting.md#cuda-error-35--cuinit-failed-error-999). |
| 580.82.07 | OK for renny-only | Same caveat as above. For A100, L4, T4, other GPUs. |
| 580.126.xx | **BROKEN** | Breaks NVENC - DO NOT USE |
| 575.xx | Compatible | Older, may lack features |
| < 550 | Not Recommended | Too old for optimal performance |

---

## Pre-Installation Checklist

Before installing the NVIDIA driver:

```bash
# 1. Check current driver (if any)
nvidia-smi

# 2. Check GPU hardware
lspci | grep -i nvidia

# 3. Check Ubuntu version
cat /etc/os-release

# 4. Ensure kernel headers are installed
sudo apt update
sudo apt install -y linux-headers-$(uname -r)
```

---

## Installation Methods

### Method 1: Ubuntu Package Manager (Recommended for A100, L4, T4)

For standard datacenter GPUs (A100, L4, T4):

```bash
# 1. Remove any existing NVIDIA packages
sudo apt remove --purge '^nvidia-.*'
sudo apt autoremove

# 2. Add NVIDIA PPA for latest drivers
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update

# 3. Install specific driver version (580.82.07)
sudo apt install nvidia-driver-580=580.82.07-0ubuntu1

# 4. Verify installation
nvidia-smi

# 5. Reboot
sudo reboot
```

### Method 2: NVIDIA .run Installer (Required for RTX PRO 6000 Blackwell)

For newer GPUs like RTX PRO 6000 Blackwell that need the latest driver:

```bash
# 1. Download the driver
cd /tmp
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run

# 2. Make executable
chmod +x NVIDIA-Linux-x86_64-580.82.09.run

# 3. Stop display manager (if running)
sudo systemctl stop gdm
# or
sudo systemctl stop lightdm

# 4. Switch to text mode (optional but recommended)
sudo systemctl isolate multi-user.target

# 5. Remove existing NVIDIA drivers
sudo apt remove --purge '^nvidia-.*'
sudo apt autoremove

# 6. Install build dependencies
sudo apt install -y build-essential dkms

# 7. Run the installer
sudo ./NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms

# 8. Reboot
sudo reboot
```

#### .run Installer Options

| Option | Description |
|--------|-------------|
| `--silent` | Non-interactive installation |
| `--dkms` | Install with DKMS for kernel update support |
| `--no-questions` | Accept defaults without prompts |
| `--disable-nouveau` | Automatically blacklist nouveau driver |

### Method 2a: .run Installer on Secure Boot Systems

If your system has **UEFI Secure Boot enabled** (common on Dell workstations, laptops, and enterprise hardware), the `.run` installer will build and load a kernel module. Secure Boot will **reject unsigned kernel modules**, causing the installation to fail at the last step with:

```
Loading of unsigned module is rejected
Key was rejected by service
```

This requires enrolling a Machine Owner Key (MOK) to sign the module before installing. The process requires **two reboots** — one to enroll the key, one after installation. On encrypted drives (LUKS/BitLocker), the LUKS unlock prompt appears *after* the MOK enrollment screen on each reboot.

Use the provided scripts (located in `scripts/nvidia/`):

```bash
# Phase 1: Generate and enroll signing key (requires one reboot)
sudo bash scripts/nvidia/enroll-mok.sh
```

On the next boot you will see a blue **MokManager** screen before your OS loads:
1. Select **Enroll MOK**
2. Select **Continue**
3. Enter the password you set during enrollment
4. Select **Yes** → **Reboot**

```bash
# Phase 2: Install the driver (signed with enrolled key)
sudo bash scripts/nvidia/install-nvidia-580.sh
```

The install script will:
- Auto-download the 580.82.09 `.run` file if not present locally
- Kill any remaining X/display server processes
- Remove existing apt-managed NVIDIA drivers
- Build and sign the kernel module with your enrolled MOK key
- Pin apt to prevent auto-upgrade to incompatible versions
- Reboot automatically

> **Note:** If Secure Boot is not enabled on your system, `install-nvidia-580.sh` still works — it simply skips the signing step.

### Method 3: NVIDIA CUDA Toolkit (Alternative)

If you need CUDA toolkit with the driver:

```bash
# 1. Download CUDA toolkit (includes driver)
wget https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.14_linux.run

# 2. Run installer
sudo sh cuda_12.4.0_550.54.14_linux.run

# Note: You may need to upgrade driver separately to 580.82.x after
```

---

## Post-Installation Verification

After driver installation and reboot:

```bash
# 1. Verify driver version
nvidia-smi

# Expected output:
# +-----------------------------------------------------------------------------+
# | NVIDIA-SMI 580.82.09    Driver Version: 580.82.09    CUDA Version: 12.8     |
# |-------------------------------+----------------------+----------------------+
# | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
# | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
# |===============================+======================+======================|
# |   0  NVIDIA RTX PRO ...  Off  | 00000000:01:00.0 Off |                  Off |
# | 30%   35C    P8    25W / 350W |      1MiB / 49140MiB |      0%      Default |
# +-------------------------------+----------------------+----------------------+

# 2. Check NVENC support (critical for Renny)
nvidia-smi -q | grep -i encoder

# 3. Verify driver kernel module
lsmod | grep nvidia

# 4. Check persistence mode (should be enabled for servers)
nvidia-smi -pm 1
```

---

## After-Install Steps (GPU Operator Deployments)

If you are running the NVIDIA GPU Operator (Kubernetes / CNS deployments), the
`.run` install is **not complete** until you also refresh the Container Device
Interface (CDI) spec. The CDI spec at `/var/run/cdi/nvidia.yaml` pins per-version
library filenames (e.g. `libcuda.so.580.82.09`). After any driver swap that
file is stale, and pods will receive only the in-image `libcuda.so` compat
library — surfacing as `cudaErrorInsufficientDriver` (CUDA error 35) during
CUDA/TensorRT init even though `nvidia-smi` works fine on the host.

```bash
# 1. Regenerate the CDI spec to reference the just-installed driver
sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml

# 2. Restart the device plugin so it re-reads the new spec
kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset

# 3. Verify end-to-end with the included probe script
bash scripts/nvidia/verify-driver-install.sh
```

The `verify-driver-install.sh` script schedules a CUDA pod with
`runtimeClassName: nvidia` and exercises `cudaGetDeviceCount` + `cudaMalloc`.
It is the only test that catches the in-image-compat-library issue described
above — `nvidia-smi` alone is not sufficient.

> **Note:** Pods that need GPU access must set `runtimeClassName: nvidia` in
> their PodSpec. Without it, the NVIDIA container runtime is not invoked and
> the host `libcuda.so` is not mounted. See [runtimeClassName](#runtimeclassname-nvidia-required-for-gpu-pods)
> below.

### runtimeClassName: nvidia (required for GPU pods)

The GPU Operator installs a `RuntimeClass` named `nvidia` that points containerd
at `/usr/bin/nvidia-container-runtime`. Pods that request `nvidia.com/gpu` but
do **not** set `runtimeClassName: nvidia` will be scheduled on the GPU node and
charged a slot, but will run under plain `runc` — the host driver libraries
are not mounted, and CUDA initialization fails (`Devices=0`, error 35).

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      runtimeClassName: nvidia   # ← required
      containers:
        - name: my-cuda-app
          resources:
            limits:
              nvidia.com/gpu: "1"
```

All manifests in `kubernetes/manifests/` follow this pattern.

---

## Driver-Swap Procedure (Live Cluster)

Swapping a driver under a running GPU Operator deployment requires draining the
GPU components and regenerating the CDI spec. Doing this in the wrong order
leaves the kernel module stuck in-use or the CDI spec stale.

```bash
# 1. Scale all GPU workloads to 0
kubectl scale -n uneeq deploy renny digitalhuman-asr --replicas=0
kubectl scale -n nim-models deploy magpie-tts vllm-gemma4 --replicas=0
kubectl scale -n gpu-operator deploy gpu-operator --replicas=0

# 2. Drain GPU Operator daemonsets from the node by clearing deploy labels
NODE=$(kubectl get node -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}')
for c in dcgm-exporter device-plugin container-toolkit operator-validator gpu-feature-discovery dcgm; do
  kubectl label node "$NODE" "nvidia.com/gpu.deploy.${c}=false" --overwrite
done

# 3. Stop host-side GPU consumers
sudo systemctl stop xvfb.service 2>/dev/null || true
sudo systemctl stop gdm

# 4. Run the install (handles driver removal, install, MOK signing, CDI regen)
sudo bash scripts/nvidia/install-nvidia-580.sh
# (System will reboot)

# 5. After reboot, re-enable GPU Operator components
for c in dcgm-exporter device-plugin container-toolkit operator-validator gpu-feature-discovery dcgm; do
  kubectl label node "$NODE" "nvidia.com/gpu.deploy.${c}=true" --overwrite
done
kubectl scale -n gpu-operator deploy gpu-operator --replicas=1

# 6. Verify with the probe
bash scripts/nvidia/verify-driver-install.sh

# 7. Scale workloads back up
kubectl scale -n uneeq deploy renny digitalhuman-asr --replicas=1
kubectl scale -n nim-models deploy magpie-tts vllm-gemma4 --replicas=1
```

---

## Vulkan Setup (Required for Renny)

Renny uses Unreal Engine 5 which requires Vulkan for rendering. The CNS deploy script handles this, but here's what it does:

### Install Vulkan Tools

```bash
# Ubuntu
sudo apt update
sudo apt install -y vulkan-tools libvulkan1 libvulkan-dev

# Verify Vulkan installation
vulkaninfo --summary
```

### Create NVIDIA Vulkan ICD File

If Vulkan doesn't detect NVIDIA GPU, create the ICD file manually:

```bash
# Check if ICD file exists
ls -la /usr/share/vulkan/icd.d/

# If nvidia_icd.json is missing, create it:
sudo mkdir -p /usr/share/vulkan/icd.d
sudo tee /usr/share/vulkan/icd.d/nvidia_icd.json << 'EOF'
{
    "file_format_version" : "1.0.0",
    "ICD" : {
        "library_path" : "libGLX_nvidia.so.0",
        "api_version" : "1.3.275"
    }
}
EOF
```

### Verify Vulkan with NVIDIA

```bash
# Test Vulkan (requires X display)
DISPLAY=:1 vulkaninfo --summary

# Expected output should show:
# GPU0: NVIDIA RTX PRO 6000 (or your GPU)
# apiVersion: 1.3.xxx
# driverVersion: 580.82.xx
```

---

## X11/Xvfb Setup (Required for Headless Rendering)

Renny requires an X display for GPU rendering, even on headless servers. The CNS deploy script sets this up, but here are the details:

### Install Xvfb

```bash
# Ubuntu
sudo apt install -y xvfb x11-xserver-utils
```

### Create Xvfb Systemd Service

```bash
sudo tee /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=X Virtual Framebuffer for Renny
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :1 -screen 0 1920x1080x24 +extension GLX
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable xvfb
sudo systemctl start xvfb
```

### Verify Xvfb is Running

```bash
# Check service status
sudo systemctl status xvfb

# Check X socket exists
ls -la /tmp/.X11-unix/

# Expected output:
# srwxrwxrwx 1 root root 0 ... X1

# Test display
DISPLAY=:1 xdpyinfo | head -10
```

### Manual Xvfb Start (Troubleshooting)

If systemd service fails:

```bash
# Kill any existing Xvfb
sudo pkill -9 Xvfb

# Remove stale lock files
sudo rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start manually
sudo Xvfb :1 -screen 0 1920x1080x24 +extension GLX &

# Wait for socket (may take a few seconds)
sleep 5

# Verify
ls -la /tmp/.X11-unix/X1
```

### Common Xvfb Issues

| Issue | Solution |
|-------|----------|
| `/tmp/.X11-unix/X1` not created | Wait longer (up to 20s on slow systems) |
| "Server is already active" | `sudo rm -f /tmp/.X1-lock` then restart |
| Permission denied | Check socket permissions, may need `chmod 777 /tmp/.X11-unix` |

---

## Troubleshooting

### Driver Installation Fails

```bash
# Check for nouveau conflict
lsmod | grep nouveau

# If nouveau is loaded, blacklist it:
sudo tee /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

sudo update-initramfs -u
sudo reboot

# Then retry driver installation
```

### nvidia-smi: command not found

```bash
# Add NVIDIA binaries to PATH
export PATH=$PATH:/usr/local/nvidia/bin:/usr/bin

# Or create symlink
sudo ln -sf /usr/bin/nvidia-smi /usr/local/bin/nvidia-smi
```

### NVENC Not Working

```bash
# Check NVENC capability
nvidia-smi -q | grep -i "encoder\|nvenc"
```

If driver is 580.126.x, you **must** downgrade. Use the method that matches your system:

**Without Secure Boot:**
```bash
sudo apt remove --purge '^nvidia-.*'
sudo apt install nvidia-driver-580=580.82.07-0ubuntu1
sudo reboot
```

**With Secure Boot (or to install 580.82.09 via .run):**
```bash
# Step 1 — enroll signing key (one reboot required)
sudo bash scripts/nvidia/enroll-mok.sh

# Step 2 — install driver (after MOK enrollment reboot)
sudo bash scripts/nvidia/install-nvidia-580.sh
```

### Vulkan Not Detecting NVIDIA GPU

```bash
# Check ICD files
ls -la /usr/share/vulkan/icd.d/

# Check library path
ls -la /usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.0

# If library is in different location, update ICD file:
# Find actual library location
find /usr -name "libGLX_nvidia.so*" 2>/dev/null

# Update ICD with correct path
```

### Xvfb Socket Not Created

```bash
# Check if Xvfb process is running
ps aux | grep Xvfb

# Check for error messages
journalctl -u xvfb -n 50

# Try running with verbose output
sudo Xvfb :1 -screen 0 1920x1080x24 +extension GLX -verbose

# Check /var/log for X errors
cat /var/log/Xorg.1.log 2>/dev/null
```

---

## Quick Reference

### Check Everything

```bash
#!/bin/bash
# driver-check.sh - Verify all driver requirements

echo "=== NVIDIA Driver ==="
nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv

echo ""
echo "=== NVENC Support ==="
nvidia-smi -q | grep -i "encoder" || echo "NVENC info not available"

echo ""
echo "=== Vulkan ==="
if command -v vulkaninfo &> /dev/null; then
    DISPLAY=:1 vulkaninfo --summary 2>/dev/null | head -20 || echo "Vulkan test failed (may need DISPLAY)"
else
    echo "vulkaninfo not installed"
fi

echo ""
echo "=== Xvfb ==="
if systemctl is-active xvfb &>/dev/null; then
    echo "Xvfb service: running"
else
    echo "Xvfb service: not running"
fi
ls -la /tmp/.X11-unix/X1 2>/dev/null || echo "X1 socket not found"

echo ""
echo "=== Driver Version Check ==="
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
if [[ "$DRIVER" == 580.126* ]]; then
    echo "WARNING: Driver $DRIVER is INCOMPATIBLE - breaks NVENC!"
elif [[ "$DRIVER" == 580.82* ]]; then
    echo "OK: Driver $DRIVER is compatible"
else
    echo "INFO: Driver $DRIVER - verify NVENC compatibility"
fi
```

Save as `driver-check.sh` and run:
```bash
chmod +x driver-check.sh
./driver-check.sh
```

---

## Driver Download Links

| GPU Type | Driver | Download |
|----------|--------|----------|
| RTX PRO 6000 Blackwell | 580.82.09 | [NVIDIA Download](https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run) |
| A100 / L4 / T4 | 580.82.07 | `apt install nvidia-driver-580=580.82.07-0ubuntu1` |
| All GPUs (archive) | Various | [NVIDIA Driver Archive](https://www.nvidia.com/Download/Find.aspx) |
