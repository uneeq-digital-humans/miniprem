#!/bin/bash
set -euo pipefail

# upgrade_nvidia_driver.sh
#
# Install a SPECIFIC, PINNED version of the NVIDIA proprietary driver on an
# Ubuntu workstation. The Renny digital-human renderer is benchmarked and
# tested against a named driver version (default: 580.82.09), so this script
# guarantees that exact version — not a "current 580.x" approximation.
#
# Approach:
#   - Downloads NVIDIA's official .run installer for TARGET_NVIDIA_VERSION
#     directly from download.nvidia.com (NVIDIA preserves these URLs as
#     historical artifacts; the apt + PPA path drifts as the PPA refreshes).
#   - Purges any pre-existing apt-managed nvidia-* packages first (clean slate).
#   - Runs the installer with --silent --dkms so kernel updates automatically
#     trigger module rebuilds without operator intervention.
#   - Writes /etc/apt/preferences.d/nvidia-pin-runfile so future apt upgrades
#     do not clobber the .run-managed install.
#   - Disables Wayland in GDM (WaylandEnable=false) so the post-reboot session
#     is Xorg/X11 — required by AnyDesk and most other remote-access tools.
#     Override with: ALLOW_WAYLAND=yes
#
# Flags / env vars:
#   --yes, -y                       Auto-confirm. Equivalent to MINIPREM_ASSUME_YES=yes.
#                                   Implies auto-reboot at the end unless --no-reboot
#                                   is also set.
#   --no-reboot                     Skip the final reboot. Use this when the script
#                                   runs as a step inside Ubuntu autoinstall
#                                   (late-commands), so the provisioning runner can
#                                   handle the single end-of-install reboot.
#                                   Equivalent to MINIPREM_NO_REBOOT=yes.
#
# Config env vars (set before invocation, or pass via sudo -E):
#   TARGET_NVIDIA_VERSION=580.82.09 (default)  Exact pinned version.
#   ALLOW_WAYLAND=no                (default)  Set to yes to leave Wayland on.
#
# Examples:
#   # Inside Ubuntu autoinstall (no in-script reboot — let subiquity reboot):
#   sudo ./docker/scripts/upgrade_nvidia_driver.sh --yes --no-reboot
#
#   # Manual unattended run on a system where no nvidia module is loaded
#   # (reboots automatically):
#   sudo ./docker/scripts/upgrade_nvidia_driver.sh --yes
#
#   # Interactive run (prompts to confirm + reboot):
#   sudo ./docker/scripts/upgrade_nvidia_driver.sh
#
#   # Pin a different version:
#   sudo TARGET_NVIDIA_VERSION=580.95.05 -E ./docker/scripts/upgrade_nvidia_driver.sh --yes
#
# Assumed operating context:
#   This script runs in a state where no NVIDIA kernel modules are loaded into
#   the running kernel — typically Ubuntu autoinstall late-commands (running
#   under the live ISO kernel, not the target kernel), or first-boot
#   provisioning before any nvidia driver has been activated. If invoked on a
#   system with nvidia.ko already loaded into the running kernel, the .run
#   installer will abort at its sanity check ("nvidia-drm appears to be
#   already loaded") and the script will exit non-zero with a clear message.
#   The script does not attempt to remediate that case — the operator must
#   either run it from a context with no loaded modules, or reboot first
#   with the nvidia driver uninstalled.
#
# Note on kernel pinning: a .run-installed driver relies on DKMS to rebuild
# its kernel modules when the kernel updates. If you need maximum stability
# against kernel surprises, apt-mark hold the kernel meta-packages outside
# this script (e.g. in your provisioning manifest). That policy is
# intentionally out of scope here.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

TARGET_NVIDIA_VERSION="${TARGET_NVIDIA_VERSION:-580.82.09}"
TARGET_NVIDIA_MAJOR="580"
ALLOW_WAYLAND="${ALLOW_WAYLAND:-no}"
ASSUME_YES="${MINIPREM_ASSUME_YES:-no}"
NO_REBOOT="${MINIPREM_NO_REBOOT:-no}"

# Per-run log file for verbose apt/installer output. The script prints the
# path at startup so operators know where to look on failure.
LOG_FILE="/var/log/upgrade_nvidia_driver-$(date +%Y%m%d-%H%M%S).log"

# Where to keep the apt preferences pin that prevents future apt upgrades
# from clobbering the .run-managed install.
APT_PIN_FILE="/etc/apt/preferences.d/nvidia-pin-runfile"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

C_RED=$'\033[0;31m'
C_YELLOW=$'\033[0;33m'
C_GREEN=$'\033[0;32m'
C_BLUE=$'\033[0;34m'
C_OFF=$'\033[0m'

info()    { echo "${C_BLUE}INFO:${C_OFF}    $*"; }
warn()    { echo "${C_YELLOW}WARN:${C_OFF}    $*" >&2; }
err()     { echo "${C_RED}ERROR:${C_OFF}   $*" >&2; }
success() { echo "${C_GREEN}OK:${C_OFF}      $*"; }
fatal()   { err "$*"; err "Full apt/installer output: $LOG_FILE"; exit 1; }

# Run a noisy command, redirect its stdout+stderr to the log file. The
# script's own info/success/warn messages remain on the terminal.
quietly() {
    if ! "$@" >>"$LOG_FILE" 2>&1; then
        err "Command failed: $*"
        return 1
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This script must be run as root. Re-run with: sudo $0"
        exit 1
    fi
}

require_ubuntu() {
    if [ ! -r /etc/os-release ]; then
        err "Cannot read /etc/os-release; not a recognized Linux distribution."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        err "This script targets Ubuntu (detected ID=${ID:-unknown})."
        exit 1
    fi
    info "Detected Ubuntu ${VERSION_ID:-?} (${VERSION_CODENAME:-?})"
}

current_driver_version() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null \
            | head -1 \
            | tr -d '[:space:]'
    fi
}

# Returns 0 (yes) if the operator confirmed, 1 (no) otherwise.
# Auto-confirms when --yes / MINIPREM_ASSUME_YES=yes is in effect.
confirm() {
    local prompt="$1"
    if [ "$ASSUME_YES" = "yes" ]; then
        info "[--yes] $prompt -> yes"
        return 0
    fi
    local reply
    read -r -p "$prompt [y/N] " reply
    case "${reply,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Resolve the NVIDIA CDN URL for the requested version + this machine's arch.
build_installer_url() {
    local arch_name
    case "$(uname -m)" in
        x86_64)        arch_name="Linux-x86_64" ;;
        aarch64|arm64) arch_name="Linux-aarch64" ;;
        *) fatal "Unsupported architecture: $(uname -m)" ;;
    esac
    echo "https://download.nvidia.com/XFree86/${arch_name}/${TARGET_NVIDIA_VERSION}/NVIDIA-${arch_name}-${TARGET_NVIDIA_VERSION}.run"
}

# Idempotently set WaylandEnable=false in /etc/gdm3/custom.conf so the system
# logs into an Xorg session after reboot. Backs up the file with a timestamp
# before editing. Skipped when ALLOW_WAYLAND=yes or when GDM isn't installed
# (server installs, lightdm/sddm desktops).
disable_wayland_in_gdm() {
    if [ "${ALLOW_WAYLAND:-no}" = "yes" ]; then
        warn "ALLOW_WAYLAND=yes — leaving Wayland enabled."
        warn "Tools that require X11 (AnyDesk, TeamViewer, x2go, most VNC) may not work."
        return 0
    fi

    local conf="/etc/gdm3/custom.conf"
    if [ ! -f "$conf" ]; then
        info "GDM config $conf not found (server install or non-GDM desktop); skipping."
        return 0
    fi

    if grep -qE '^[[:space:]]*WaylandEnable=false[[:space:]]*$' "$conf"; then
        success "Wayland already disabled in $conf — no change needed."
        return 0
    fi

    local backup="${conf}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$conf" "$backup"
    info "Backed up current config: $backup"

    if grep -qE '^[[:space:]]*#[[:space:]]*WaylandEnable=' "$conf"; then
        sed -i -E 's|^[[:space:]]*#[[:space:]]*WaylandEnable=.*$|WaylandEnable=false|' "$conf"
        info "Uncommented existing WaylandEnable line, set to false."
    elif grep -qE '^[[:space:]]*WaylandEnable=' "$conf"; then
        sed -i -E 's|^[[:space:]]*WaylandEnable=.*$|WaylandEnable=false|' "$conf"
        info "Updated existing WaylandEnable line to false."
    elif grep -qE '^\[daemon\]' "$conf"; then
        sed -i -E '/^\[daemon\]/a WaylandEnable=false' "$conf"
        info "Added WaylandEnable=false under existing [daemon] section."
    else
        printf '\n[daemon]\nWaylandEnable=false\n' >> "$conf"
        info "Appended [daemon] section with WaylandEnable=false."
    fi

    if grep -qE '^WaylandEnable=false[[:space:]]*$' "$conf"; then
        success "Wayland disabled — post-reboot session will be Xorg/X11."
    else
        err "Failed to set WaylandEnable=false in $conf. Restoring backup."
        cp "$backup" "$conf"
        return 1
    fi
}

# Write an apt preferences pin that blocks future apt upgrades from
# installing nvidia-driver / libnvidia-* / nvidia-dkms-* packages over the
# .run-managed install. The .run installer is the canonical owner of the
# driver bits; apt should stay out of the way.
write_apt_pin() {
    cat > "$APT_PIN_FILE" <<EOF
# Managed by upgrade_nvidia_driver.sh
#
# The NVIDIA driver on this system was installed via NVIDIA's .run installer
# at a specific pinned version. Block apt from installing competing nvidia
# packages on future apt upgrades. To revert (e.g. switching back to apt-
# managed driver), delete this file and reinstall via apt.
Package: nvidia-driver-* nvidia-dkms-* nvidia-utils-* libnvidia-* nvidia-kernel-common-* nvidia-kernel-source-* xserver-xorg-video-nvidia-* nvidia-compute-utils-*
Pin: release *
Pin-Priority: -1
EOF
    chmod 644 "$APT_PIN_FILE"
    success "Wrote apt preferences pin: $APT_PIN_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)         ASSUME_YES="yes"; shift ;;
            --no-reboot)      NO_REBOOT="yes"; shift ;;
            -h|--help)
                sed -n '1,/^# ---/p' "$0" | sed 's/^# \{0,1\}//' | head -n 70
                exit 0
                ;;
            *)  err "Unknown argument: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"

    require_root
    require_ubuntu

    # Open the log file early so all subsequent quietly() calls can append.
    : > "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    info "Verbose apt/installer output will be logged to: $LOG_FILE"

    local current
    current="$(current_driver_version || true)"
    if [ -n "$current" ]; then
        info "Currently installed NVIDIA driver: $current"
    else
        info "No NVIDIA driver currently installed (or nvidia-smi not available yet)."
    fi
    info "Target NVIDIA driver (pinned):      $TARGET_NVIDIA_VERSION"

    if [ "$current" = "$TARGET_NVIDIA_VERSION" ]; then
        success "Already at target version. Nothing to do."
        exit 0
    fi

    if ! confirm "Proceed with upgrade to NVIDIA $TARGET_NVIDIA_VERSION?"; then
        info "Aborted."
        exit 0
    fi

    # Secure Boot would silently break a .run-installed driver: DKMS signs
    # modules with a self-generated MOK that requires manual enrollment at
    # the next reboot via the blue MOK Manager screen — impossible
    # unattended. Fail fast with a clear message.
    if [ -d /sys/firmware/efi ] && command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            if [ "$ASSUME_YES" = "yes" ]; then
                fatal "Secure Boot is ENABLED. The .run installer's DKMS-signed modules will not load without manual MOK enrollment at the next boot, which is impossible under --yes. Disable Secure Boot in BIOS and re-run."
            else
                warn "Secure Boot is ENABLED."
                warn "You will be asked to set an MOK password during install,"
                warn "and you'll need to enrol it manually at the blue MOK Manager"
                warn "screen on next reboot — this requires physical/IPMI access."
                if ! confirm "Continue anyway?"; then
                    info "Aborted."
                    exit 0
                fi
            fi
        fi
    fi

    # ---- Step 1/8: ensure kernel headers, build toolchain, curl ----
    # build-essential pulls in gcc/g++/make/libc6-dev/dpkg-dev — DKMS
    # compiles the nvidia kernel module from source and needs all of it.
    # On a fresh Ubuntu install gcc is not present by default; previously
    # the apt-managed nvidia packages pulled it in transitively. Going via
    # the .run installer, we own this dependency explicitly.
    info "Step 1/8: ensure prerequisites (kernel headers, build toolchain, curl)"
    quietly apt-get update
    quietly apt-get install -y \
        "linux-headers-$(uname -r)" \
        build-essential \
        curl \
        ca-certificates \
        || fatal "Failed to install build prerequisites"

    # ---- Step 2/8: pre-flight CDN check so we fail fast on bad version ----
    local url
    url="$(build_installer_url)"
    info "Step 2/8: verify NVIDIA CDN has $TARGET_NVIDIA_VERSION available"
    info "  URL: $url"
    if ! curl -sSf -I --max-time 10 "$url" >/dev/null 2>>"$LOG_FILE"; then
        fatal "NVIDIA CDN URL not reachable or version not published: $url"
    fi
    success "CDN URL reachable."

    # ---- Step 3/8: purge any apt-managed nvidia packages (clean slate) ----
    # No apt-get autoremove here. autoremove is more cleanup than necessity
    # — the nvidia purge does the actual work of clearing conflicting
    # packages. autoremove is well-meaning but can quietly yank packages
    # we want (we narrowly avoided losing build-essential's transitive
    # dependencies that way during testing). The disk-space saving is
    # negligible vs the risk of pulling out something we need.
    info "Step 3/8: purge any existing nvidia-* apt packages"
    # Glob may match nothing; tolerate that. Output goes to log.
    quietly bash -c "apt-get purge -y 'nvidia-*' 'libnvidia-*' || true"
    success "Existing nvidia packages removed."

    # ---- Step 4/8: download the .run installer ----
    local runfile="/tmp/NVIDIA-Linux-$(uname -m)-${TARGET_NVIDIA_VERSION}.run"
    info "Step 4/8: download .run installer to $runfile"
    # curl with progress bar visible (not in log) so operator sees download advance
    if ! curl -fL --retry 3 --retry-delay 5 -# -o "$runfile" "$url"; then
        fatal "Failed to download $url"
    fi
    chmod +x "$runfile"
    success "Downloaded $(du -h "$runfile" | cut -f1) installer."

    # ---- Step 5/8: run the silent installer ----
    info "Step 5/8: run NVIDIA installer (--silent --dkms)"
    # --silent implies --no-questions and --accept-license.
    # --dkms registers the kernel module so future kernel upgrades rebuild it.
    # --disable-nouveau writes the modprobe.d blacklist for next boot.
    # --no-nouveau-check lets us proceed even though nouveau is currently
    #   bound to the GPU (it can't unload while bound; reboot will switch).
    # --no-x-check bypasses the abort that fires when X is running on a
    #   different driver (e.g. nouveau after a pre-purge + reboot during
    #   interactive testing). Production path (autoinstall late-commands)
    #   has no X server running, so this flag is a no-op there; it exists
    #   solely to unblock interactive testing. Safe because we always
    #   reboot after install — any half-applied X-side state is wiped by
    #   the reboot.
    # --skip-module-load tells the installer to compile and install the
    #   kernel modules but NOT attempt the post-install modprobe. Without
    #   this, the installer would try to load the freshly-built nvidia.ko
    #   and fail because the GPU is currently bound to nouveau (or to an
    #   older nvidia driver). With --skip-module-load, files land in
    #   /lib/modules/.../updates/dkms/, --disable-nouveau writes the
    #   blacklist for next boot, and the reboot at Step 8 activates the
    #   new driver cleanly. Flag names verified against NVIDIA/nvidia-
    #   installer option_table.h on GitHub.
    # Installer also writes its own log at /var/log/nvidia-installer.log.
    if ! "$runfile" --silent --dkms --disable-nouveau --no-nouveau-check \
            --no-x-check --skip-module-load \
            >>"$LOG_FILE" 2>&1; then
        err "NVIDIA installer failed. Last 30 lines of /var/log/nvidia-installer.log:"
        tail -n 30 /var/log/nvidia-installer.log 2>/dev/null || true
        fatal "Installer exited non-zero."
    fi
    success "NVIDIA installer completed."

    # Cleanup the downloaded .run file
    rm -f "$runfile"

    # ---- Step 6/8: write apt preferences pin ----
    info "Step 6/8: write apt preferences pin to protect the install"
    write_apt_pin

    # ---- Step 7/8: enforce X11 (disable Wayland) ----
    info "Step 7/8: enforce X11 session (set WaylandEnable=false in GDM config)"
    disable_wayland_in_gdm

    # ---- Step 8/8: reboot (or skip) ----
    info "Step 8/8: reboot to load the new kernel modules"
    echo

    # Note: nvidia-smi will still report the OLD driver until reboot because
    # the old modules are still loaded in the running kernel. Skip the post-
    # install version check here; the operator (or the autoinstall runner)
    # verifies after reboot.
    success "Driver install complete. The new driver is NOT active until reboot."
    success "After reboot, verify with: nvidia-smi --query-gpu=driver_version --format=csv,noheader"
    success "Expected: $TARGET_NVIDIA_VERSION"
    echo

    if [ "$NO_REBOOT" = "yes" ]; then
        info "[--no-reboot] Skipping reboot — caller (e.g. autoinstall runner) will handle it."
        exit 0
    fi

    if confirm "Reboot now?"; then
        info "Rebooting..."
        systemctl reboot
    else
        warn "Skipped reboot. nvidia-smi will keep showing the OLD driver until you reboot."
        warn "Reboot manually with: sudo reboot"
    fi
}

main "$@"
