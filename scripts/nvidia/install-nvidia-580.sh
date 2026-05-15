#!/bin/bash
# Install NVIDIA 580.x driver via .run file
# Fixes HW NVENC breakage introduced in 580.126.x
# Supports Secure Boot systems via MOK signing (run nvidia-enroll-mok.sh first)
#
# Usage:
#   sudo bash install-nvidia-580.sh                                    # uses default version
#   sudo bash install-nvidia-580.sh /path/to/NVIDIA-Linux-x86_64-X.Y.run
#   DRIVER_VERSION=580.142 sudo -E bash install-nvidia-580.sh          # override version
#
# Default version rationale: 580.142 ships a libcuda.so that the GPU Operator's
# container toolkit / CDI spec maps correctly into NIM/Triton/vLLM pods.
# 580.82.09 also loads cleanly but on this stack pods saw the in-image
# libcuda.so.550.54.15 compat library instead of the host driver, producing
# `cudaErrorInsufficientDriver` (error 35) in TensorRT init. Confirmed on
# Ubuntu 24.04 + RTX 6000 Ada + GPU Operator v24.9.0.
# 580.126.x is the known-bad NVENC version — do not use.

set -e

DRIVER_VERSION="${DRIVER_VERSION:-580.142}"
DRIVER_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
MOK_DIR=/root/nvidia-mok
LOG=/var/log/nvidia-install-${DRIVER_VERSION}.log
CDI_OUTPUT=/var/run/cdi/nvidia.yaml

exec > >(tee -a "$LOG") 2>&1

echo "=== NVIDIA ${DRIVER_VERSION} install started: $(date) ==="

# Locate or download the .run file
if [ -n "$1" ] && [ -f "$1" ]; then
    RUN_FILE="$1"
elif [ -f "NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run" ]; then
    RUN_FILE="$(pwd)/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
else
    echo "Run file not found locally — downloading from NVIDIA..."
    RUN_FILE="/tmp/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
    wget -O "$RUN_FILE" "$DRIVER_URL"
fi
echo "Using: $RUN_FILE"

echo "[1/7] Stopping display manager and killing X server..."
systemctl stop gdm3 gdm 2>/dev/null || true
systemctl stop xvfb.service 2>/dev/null || true
sleep 2
pkill -9 -x Xorg || true
pkill -9 -x X || true
pkill -9 -x Xwayland || true
pkill -9 -x Xvfb || true
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
sleep 2

echo "[2/7] Removing existing apt-managed NVIDIA drivers..."
apt-get remove --purge -y \
    nvidia-driver-580 \
    nvidia-driver-575 \
    'nvidia-*' \
    'libnvidia-*' \
    || true
apt-get autoremove -y || true

echo "[3/7] Installing ${DRIVER_VERSION} from .run file..."

SIGN_ARGS=""
if [ -f "$MOK_DIR/mok.key" ] && [ -f "$MOK_DIR/mok.crt" ]; then
    echo "MOK keys found — module will be signed for Secure Boot."
    SIGN_ARGS="--module-signing-secret-key=$MOK_DIR/mok.key --module-signing-public-key=$MOK_DIR/mok.crt"
else
    echo "No MOK keys found at $MOK_DIR."
    echo "If Secure Boot is enabled, the module will fail to load after reboot."
    echo "To fix: run nvidia-enroll-mok.sh, reboot to enroll, then re-run this script."
fi

chmod +x "$RUN_FILE"
# shellcheck disable=SC2086
"$RUN_FILE" \
    --silent \
    --run-nvidia-xconfig \
    --no-questions \
    --accept-license \
    --no-x-check \
    --kernel-module-type=open \
    $SIGN_ARGS

echo "[4/7] Enabling NVIDIA persistence mode..."
# Persistence mode keeps the driver loaded between CUDA contexts. Required for
# time-sliced GPU sharing — otherwise each pod re-init tears down the context
# and can trigger CUDA error 999 on heavily oversubscribed cards.
nvidia-smi -pm 1 || warning "Failed to enable persistence mode (will retry post-reboot)"
systemctl enable nvidia-persistenced.service 2>/dev/null || true

echo "[5/7] Regenerating GPU Operator CDI spec..."
# The Container Device Interface spec at $CDI_OUTPUT pins per-version filenames
# (e.g. libcuda.so.580.82.09). After any driver swap the spec is stale and
# `nvidia-container-cli` ends up not mounting the host libcuda into containers,
# so NIM/Triton/vLLM pods see only the in-image compat library and fail with
# cudaErrorInsufficientDriver. `nvidia-ctk cdi generate` rewrites the spec to
# match the just-installed driver version.
if command -v nvidia-ctk >/dev/null 2>&1; then
    mkdir -p "$(dirname "$CDI_OUTPUT")"
    nvidia-ctk cdi generate --output="$CDI_OUTPUT" || \
        echo "WARN: nvidia-ctk cdi generate failed; regenerate manually after reboot."
else
    echo "WARN: nvidia-ctk not present. After the GPU Operator installs its toolkit,"
    echo "      run: sudo nvidia-ctk cdi generate --output=$CDI_OUTPUT"
fi

echo "[6/7] Pinning apt to prevent auto-upgrade to incompatible versions..."
cat > /etc/apt/preferences.d/nvidia-driver-hold <<'EOF'
Package: nvidia-driver-575 nvidia-driver-580 nvidia-driver-*
Pin: release *
Pin-Priority: -1
EOF

echo "[7/7] Done. Rebooting in 5 seconds..."
echo ""
echo "After reboot:"
echo "  1. Verify driver: nvidia-smi --query-gpu=driver_version --format=csv,noheader"
echo "  2. Run the CUDA-in-container probe: bash scripts/nvidia/verify-driver-install.sh"
echo "  3. If using GPU Operator, restart the device plugin so it re-reads the CDI spec:"
echo "       kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset"
echo ""
echo "Log saved to $LOG"
sleep 5
reboot
