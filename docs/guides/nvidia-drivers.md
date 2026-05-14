<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# NVIDIA Driver Guide

> Understanding driver requirements, recommended versions, and installation for MiniPrem

</div>

## Table of Contents

- [Why Driver Version Matters](#why-driver-version-matters)
- [Quick Reference](#quick-reference)
- [Recommended Versions](#recommended-versions)
- [How to Check Your Driver Version](#how-to-check-your-driver-version)
- [Installation Methods](#installation-methods)
- [GPU Compatibility Notes](#gpu-compatibility-notes)
- [Symptoms of Wrong Driver](#symptoms-of-wrong-driver)
- [NVIDIA Container Toolkit](#nvidia-container-toolkit)
- [License](#license)
- [Copyright](#copyright)

## Why Driver Version Matters

MiniPrem uses **NVENC hardware encoding** for Pixel Streaming — this is how Renny delivers real-time video to the browser. Certain NVIDIA driver versions have broken NVENC support, causing sessions to fail immediately even though the GPU appears healthy in `nvidia-smi`.

!> **Not all 580.x versions are equal.** The 580.126.x family breaks NVENC on all GPU types. Always verify you are running a known good version before troubleshooting session failures.

## Quick Reference

| Driver | Works with MiniPrem? | Notes |
|--------|---------------------|-------|
| **nouveau** (open-source) | No | No CUDA, no NVENC, no Vulkan. Will not work. |
| **NVIDIA proprietary < 580** | No | Missing required Vulkan and NVENC features. |
| **NVIDIA proprietary 580.82.x** | Yes | Recommended for all deployments. |
| **NVIDIA proprietary 580.126.x** | No | NVENC broken on all GPU types. |
| **NVIDIA proprietary 580+** (other) | Maybe | Test NVENC before deploying to production. |

## Recommended Versions

### Docker / Bare-Metal Deployments

| Version | Install Method | Best For |
|---------|---------------|----------|
| **580.82.07** | apt (Ubuntu package manager) | Most deployments (L4, A10G, T4) |
| **580.82.09** | .run installer (NVIDIA direct) | Newer GPU architectures (Blackwell/RTX PRO 6000) |

### Kubernetes Deployments

The NVIDIA GPU Operator handles driver installation automatically. It installs driver version 580+ by default. For details on GPU Operator configuration, see the [AWS EKS Deployment](kubernetes-eks.md) or [Azure AKS Deployment](kubernetes-aks.md) guides.

### Versions to Avoid

!> **580.126.x** (all variants) — breaks NVENC hardware encoding on **all** GPU types. Sessions connect but immediately fail because Pixel Streaming cannot encode video frames.

## How to Check Your Driver Version

```bash
nvidia-smi | head -3
```

Expected output (look for `Driver Version`):

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.82.07    Driver Version: 580.82.07    CUDA Version: 12.8               |
+-----------------------------------------------------------------------------------------+
```

?> **Tip** If `nvidia-smi` shows `NVIDIA-SMI has failed` or returns a command-not-found error, the proprietary driver is not installed. Check that nouveau is not loaded: `lsmod | grep nouveau`.

### Monitor NVENC During a Session

To verify NVENC is working during an active digital human session:

```bash
nvidia-smi dmon -s u
```

The `enc` column should show values **greater than 0%** during an active session. If it stays at 0%, the driver version likely has broken NVENC.

## Installation Methods

### Method 1: apt (Ubuntu Package Manager) — Recommended

The simplest approach for most deployments:

```bash
# Update package lists
sudo apt update

# List available NVIDIA drivers
ubuntu-drivers devices

# Install the recommended driver (ensure version is 580+)
sudo ubuntu-drivers install nvidia:580

# Reboot to load the new driver
sudo reboot
```

### Method 2: .run Installer (NVIDIA Direct)

Required for newer GPU architectures (e.g., Blackwell/RTX PRO 6000) where apt packages may not yet be available:

```bash
# Download the installer from NVIDIA
# Go to https://www.nvidia.com/Download/index.aspx
# Select your GPU model, Linux 64-bit, and download

# Stop the display manager
sudo systemctl stop gdm3

# Make the installer executable and run it
chmod +x NVIDIA-Linux-x86_64-580*.run
sudo ./NVIDIA-Linux-x86_64-580*.run --kernel-module-type=open

# Reboot
sudo reboot
```

!> **Important:** Use `--kernel-module-type=open` with the .run installer. This selects the open kernel module which is required for newer GPU architectures.

#### Secure Boot Systems

If UEFI Secure Boot is enabled (Dell workstations, most enterprise laptops), the `.run` installer will fail to load the kernel module on reboot — Secure Boot rejects unsigned modules. Use the provided scripts instead, which handle MOK key enrollment and module signing automatically:

```bash
# Step 1: Enroll signing key (triggers one reboot into UEFI MokManager)
sudo bash scripts/nvidia/enroll-mok.sh

# Step 2: Install driver with signed module (after confirming MOK enrollment on reboot)
sudo bash scripts/nvidia/install-nvidia-580.sh
```

On encrypted drives (LUKS), the MokManager screen appears **before** the drive unlock prompt — this is expected.

See [NVIDIA Driver Setup — Secure Boot](../NVIDIA-DRIVER-SETUP.md#method-2a-run-installer-on-secure-boot-systems) for the full walkthrough.

### Method 3: CUDA Toolkit (Includes Driver)

The CUDA toolkit installer bundles a compatible NVIDIA driver:

```bash
# Add NVIDIA CUDA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# Install CUDA toolkit (includes driver 580+)
sudo apt install cuda

# Reboot
sudo reboot
```

## GPU Compatibility Notes

| GPU | Cloud Instance | Driver Install | Status |
|-----|---------------|----------------|--------|
| **L4** | AWS g6 instances | 580.82.07 via apt | Verified |
| **A10G** | AWS g5 instances | 580.82.07 via apt | Verified |
| **T4** | Azure NC16as_T4_v3 | 580+ via GPU Operator | Verified |
| **RTX PRO 6000 (Blackwell)** | AWS g7e instances | 580.82.09 via .run installer | NVENC investigation ongoing |

?> **Blackwell GPUs (RTX PRO 6000):** These require the .run installer method. NVENC investigation is ongoing and Blackwell is not yet production-ready for MiniPrem.

## Symptoms of Wrong Driver

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `nvidia-smi` not found | Driver not installed | Install proprietary driver (see above) |
| `NVIDIA-SMI has failed` | Driver/kernel mismatch | Reinstall driver, reboot |
| `nouveau` in `lsmod` output | Open-source driver loaded | Blacklist nouveau, install proprietary driver |
| `enc: 0%` in `nvidia-smi dmon` during active session | NVENC broken (580.126.x) | Downgrade to 580.82.x |
| Session connects then immediately disconnects | Pixel Streaming cannot encode | Check driver version, downgrade if 580.126.x |
| Renny log: "HasActivePixelStreaming: false" | NVENC not functioning | Check driver version |

### Blacklisting nouveau

If the open-source `nouveau` driver is loaded, blacklist it before installing the NVIDIA proprietary driver:

```bash
# Create blacklist file
sudo bash -c 'echo -e "blacklist nouveau\noptions nouveau modeset=0" > /etc/modprobe.d/blacklist-nouveau.conf'

# Regenerate initramfs
sudo update-initramfs -u

# Reboot
sudo reboot
```

Verify nouveau is no longer loaded:

```bash
lsmod | grep nouveau
# Should return nothing
```

## NVIDIA Container Toolkit

The NVIDIA Container Toolkit is required for GPU access inside Docker containers. This is separate from the GPU driver itself.

### Installation (Ubuntu 24.04)

```bash
# Add NVIDIA container toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Verification

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

This should display the same `nvidia-smi` output as running it on the host. If it fails, the container toolkit is not properly configured.

---

## License

The MiniPrem documentation and installation scripts are open source under the MIT License - see the [LICENSE](../../LICENSE) file for details. Note: The Renny digital human application itself is commercially licensed by UneeQ and is not covered by this license.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
