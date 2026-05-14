#!/bin/bash
# Install NVIDIA 580.82.09 driver
# Fixes HW NVENC breakage introduced in 580.126.x
# Supports Secure Boot systems via MOK signing (run nvidia-enroll-mok.sh first)
# Usage: sudo bash install-nvidia-580.sh [/path/to/NVIDIA-Linux-x86_64-580.82.09.run]

set -e
LOG=/var/log/nvidia-install-580.82.09.log
DRIVER_VERSION="580.82.09"
DRIVER_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
MOK_DIR=/root/nvidia-mok

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

echo "[1/5] Stopping display manager and killing X server..."
systemctl stop gdm3 || true
sleep 2
pkill -9 -x Xorg || true
pkill -9 -x X || true
pkill -9 -x Xwayland || true
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
sleep 2

echo "[2/5] Removing existing apt-managed NVIDIA drivers..."
apt-get remove --purge -y \
    nvidia-driver-580 \
    nvidia-driver-575 \
    'nvidia-*' \
    'libnvidia-*' \
    || true
apt-get autoremove -y || true

echo "[3/5] Installing ${DRIVER_VERSION} from .run file..."

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

echo "[4/5] Pinning apt to prevent auto-upgrade to incompatible versions..."
cat > /etc/apt/preferences.d/nvidia-driver-hold <<'EOF'
Package: nvidia-driver-575 nvidia-driver-580 nvidia-driver-*
Pin: release *
Pin-Priority: -1
EOF

echo "[5/5] Done. Rebooting in 5 seconds..."
echo "Log saved to $LOG"
sleep 5
reboot
