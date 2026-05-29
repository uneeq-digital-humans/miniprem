#!/bin/bash
# check-health.sh
#
# Host-level NVIDIA driver health check. Confirms the proprietary driver is
# actually BOUND TO THE HARDWARE — not merely that nvidia-smi exists. Catches
# the "zombie driver" / black-screen states where the install reported success
# but the module never claimed the GPU (nouveau still bound, DKMS module not
# loaded, Secure Boot blocked the unsigned module, kernel/driver mismatch).
#
# This is deliberately a LIGHTWEIGHT, host-only check. It does NOT touch
# Kubernetes or run a CUDA-in-pod probe — for the full end-to-end GPU-Operator
# validation on a cluster node, use scripts/nvidia/verify-driver-install.sh.
#
# Usage:
#   bash scripts/nvidia/check-health.sh [--expect <version>] [--quiet]
#
# Options:
#   --expect <version>   Assert the running driver equals this exact version
#                        (e.g. 580.82.09). Mismatch is a failure. Also honoured
#                        via the TARGET_NVIDIA_VERSION env var.
#   --quiet              Suppress per-check OK lines; still prints failures and
#                        the final summary.
#
# Exit codes:
#   0   healthy — driver loaded and bound to at least one GPU
#   1   unhealthy — see the failed checks printed above the summary
#   2   usage error
#
# Standalone: no external deps beyond coreutils + the nvidia userspace tools.
# Safe to copy into other projects (e.g. the ISO builder) and run bare.

set -uo pipefail

EXPECT_VERSION="${TARGET_NVIDIA_VERSION:-}"
QUIET="no"

# ---------------------------------------------------------------------------
# Output helpers (self-contained; degrade to plain text when not a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RED=$'\033[0;31m'; C_YEL=$'\033[0;33m'; C_GRN=$'\033[0;32m'
    C_BLU=$'\033[0;34m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_YEL=""; C_GRN=""; C_BLU=""; C_OFF=""
fi

FAILURES=0

info() { echo "${C_BLU}INFO:${C_OFF} $*"; }
ok()   { [ "$QUIET" = "yes" ] || echo "${C_GRN}OK:${C_OFF}   $*"; }
warn() { echo "${C_YEL}WARN:${C_OFF} $*" >&2; }
bad()  { echo "${C_RED}FAIL:${C_OFF} $*" >&2; FAILURES=$((FAILURES + 1)); }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --expect)  EXPECT_VERSION="${2:-}"; shift 2 || usage 2 ;;
        --expect=*) EXPECT_VERSION="${1#*=}"; shift ;;
        --quiet)   QUIET="yes"; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# 1. nvidia-smi present and runnable
# ---------------------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
    bad "nvidia-smi not found on PATH — the driver userspace is not installed."
    echo "     Install the driver first (scripts/nvidia/install-nvidia-580.sh or" >&2
    echo "     docker/scripts/upgrade_nvidia_driver.sh), then reboot." >&2
    echo "SUMMARY: UNHEALTHY (driver not installed)"
    exit 1
fi

SMI_OUT="$(nvidia-smi 2>&1)"
SMI_RC=$?
if [ $SMI_RC -ne 0 ]; then
    bad "nvidia-smi exited $SMI_RC — driver present but not functioning."
    # Surface the most common, diagnosable failure verbatim.
    if echo "$SMI_OUT" | grep -qiE "couldn't communicate|NVIDIA-SMI has failed|driver/library version mismatch"; then
        echo "     nvidia-smi said:" >&2
        echo "$SMI_OUT" | sed 's/^/       /' >&2
    fi
    if echo "$SMI_OUT" | grep -qi "driver/library version mismatch"; then
        echo "     => Kernel module and userspace library are different versions." >&2
        echo "        A reboot is usually required after a driver upgrade." >&2
    fi
    echo "SUMMARY: UNHEALTHY (nvidia-smi failed)"
    exit 1
fi
ok "nvidia-smi runs."

# ---------------------------------------------------------------------------
# 2. Driver bound to at least one GPU (the load-bearing check)
# ---------------------------------------------------------------------------
GPU_LIST="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null)"
GPU_COUNT="$(printf '%s\n' "$GPU_LIST" | grep -c '[^[:space:]]')"
if [ "${GPU_COUNT:-0}" -lt 1 ]; then
    bad "nvidia-smi reports NO GPUs bound to the driver (zombie/black-screen state)."
    echo "     The module may be loaded but not bound to the hardware — commonly" >&2
    echo "     nouveau still owns the GPU, or the DKMS module failed to load." >&2
    echo "SUMMARY: UNHEALTHY (no GPU bound)"
    exit 1
fi
RUNNING_VERSION="$(printf '%s\n' "$GPU_LIST" | head -1 | awk -F', *' '{print $2}' | tr -d '[:space:]')"
ok "Driver bound to ${GPU_COUNT} GPU(s); running driver: ${RUNNING_VERSION:-unknown}"
[ "$QUIET" = "yes" ] || printf '%s\n' "$GPU_LIST" | sed 's/^/       - /'

# ---------------------------------------------------------------------------
# 3. Kernel modules loaded (nvidia + nvidia_drm)
# ---------------------------------------------------------------------------
if command -v lsmod >/dev/null 2>&1; then
    LSMOD="$(lsmod 2>/dev/null)"
    if echo "$LSMOD" | grep -qE '^nvidia[[:space:]]'; then
        ok "Kernel module 'nvidia' is loaded."
    else
        bad "Kernel module 'nvidia' is NOT loaded."
    fi
    if echo "$LSMOD" | grep -qE '^nvidia_drm[[:space:]]'; then
        ok "Kernel module 'nvidia_drm' is loaded."
    else
        warn "Kernel module 'nvidia_drm' is not loaded (modeset may be off; usually fine for headless compute)."
    fi

    # ---------------------------------------------------------------------
    # 4. nouveau must NOT be loaded — if it is, it has the GPU and nvidia can't
    # ---------------------------------------------------------------------
    if echo "$LSMOD" | grep -qE '^nouveau[[:space:]]'; then
        bad "Open-source 'nouveau' driver is loaded — it blocks nvidia from binding the GPU."
        echo "     Blacklist nouveau and rebuild initramfs, then reboot:" >&2
        echo "       echo -e 'blacklist nouveau\\noptions nouveau modeset=0' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf" >&2
        echo "       sudo update-initramfs -u && sudo reboot" >&2
    else
        ok "nouveau is not loaded."
    fi
else
    warn "lsmod not available — skipping kernel-module checks."
fi

# ---------------------------------------------------------------------------
# 5. Kernel-side driver interface + device nodes present
# ---------------------------------------------------------------------------
if [ -r /proc/driver/nvidia/version ]; then
    ok "/proc/driver/nvidia/version present."
else
    warn "/proc/driver/nvidia/version missing — kernel side of the driver may not be active."
fi
if ls /dev/nvidia0 >/dev/null 2>&1 || ls /dev/nvidiactl >/dev/null 2>&1; then
    ok "NVIDIA device nodes present in /dev."
else
    warn "No /dev/nvidia* device nodes found — they are usually created on first use."
fi

# ---------------------------------------------------------------------------
# 6. Optional exact-version assertion (kernel/driver mismatch guard)
# ---------------------------------------------------------------------------
if [ -n "$EXPECT_VERSION" ]; then
    if [ "$RUNNING_VERSION" = "$EXPECT_VERSION" ]; then
        ok "Running driver matches expected version ($EXPECT_VERSION)."
    else
        bad "Driver version mismatch: running '$RUNNING_VERSION', expected '$EXPECT_VERSION'."
        echo "     If you just upgraded, a reboot is required to load the new modules." >&2
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if [ "$FAILURES" -eq 0 ]; then
    echo "${C_GRN}SUMMARY: HEALTHY${C_OFF} — driver ${RUNNING_VERSION:-?} bound to ${GPU_COUNT} GPU(s)."
    exit 0
fi
echo "${C_RED}SUMMARY: UNHEALTHY${C_OFF} — ${FAILURES} check(s) failed (see FAIL lines above)."
exit 1
