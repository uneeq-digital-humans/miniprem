#!/bin/bash
set -euo pipefail

# upgrade_nvidia_driver.sh
#
# Install or upgrade the NVIDIA proprietary driver on an Ubuntu workstation
# to the R580 production branch (580.82.09 by default), so MiniPrem's >=580
# requirement is satisfied.
#
# Approach:
#   - Adds the graphics-drivers PPA (which tracks the latest .82.x patch).
#   - Purges any pre-existing NVIDIA driver packages cleanly.
#   - Installs nvidia-driver-580 + nvidia-utils-580 (workstation flavor).
#   - Disables Wayland in GDM (WaylandEnable=false) so the post-reboot session
#     is Xorg/X11 — required by AnyDesk and most other remote-access tools.
#     Override with: ALLOW_WAYLAND=yes sudo -E ./upgrade_nvidia_driver.sh
#   - Prompts for reboot, since the new driver isn't loaded until reboot.
#
# Run as root:    sudo ./docker/scripts/upgrade_nvidia_driver.sh
# Override target with:  TARGET_NVIDIA_VERSION=580.82.09 sudo -E ./...

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

TARGET_NVIDIA_VERSION="${TARGET_NVIDIA_VERSION:-580.82.09}"
TARGET_NVIDIA_MAJOR="580"
PPA="ppa:graphics-drivers/ppa"

# Force GDM to use Xorg (X11) instead of Wayland after reboot. Set
# ALLOW_WAYLAND=yes to opt out (e.g. if no remote-access tool needs X11).
ALLOW_WAYLAND="${ALLOW_WAYLAND:-no}"

# ---------------------------------------------------------------------------
# Helpers (lightweight; no project deps so the script is portable)
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

confirm() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N] " reply
    case "${reply,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Idempotently set WaylandEnable=false in /etc/gdm3/custom.conf so the system
# logs back into an Xorg session after reboot. Backs up the file with a
# timestamp before editing. Skipped when ALLOW_WAYLAND=yes or when GDM isn't
# installed (server installs, lightdm/sddm desktops).
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

    # Already correctly disabled? No-op.
    if grep -qE '^[[:space:]]*WaylandEnable=false[[:space:]]*$' "$conf"; then
        success "Wayland already disabled in $conf — no change needed."
        return 0
    fi

    local backup="${conf}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$conf" "$backup"
    info "Backed up current config: $backup"

    if grep -qE '^[[:space:]]*#[[:space:]]*WaylandEnable=' "$conf"; then
        # Commented-out line exists — uncomment and force value.
        sed -i -E 's|^[[:space:]]*#[[:space:]]*WaylandEnable=.*$|WaylandEnable=false|' "$conf"
        info "Uncommented existing WaylandEnable line, set to false."
    elif grep -qE '^[[:space:]]*WaylandEnable=' "$conf"; then
        # Active line with non-false value — force to false.
        sed -i -E 's|^[[:space:]]*WaylandEnable=.*$|WaylandEnable=false|' "$conf"
        info "Updated existing WaylandEnable line to false."
    elif grep -qE '^\[daemon\]' "$conf"; then
        # Has [daemon] section but no WaylandEnable line — insert after header.
        sed -i -E '/^\[daemon\]/a WaylandEnable=false' "$conf"
        info "Added WaylandEnable=false under existing [daemon] section."
    else
        # No [daemon] section — append both at end.
        printf '\n[daemon]\nWaylandEnable=false\n' >> "$conf"
        info "Appended [daemon] section with WaylandEnable=false."
    fi

    if grep -qE '^WaylandEnable=false[[:space:]]*$' "$conf"; then
        success "Wayland disabled — post-reboot session will be Xorg/X11."
    else
        err "Failed to set WaylandEnable=false in $conf. Restoring backup."
        cp "$backup" "$conf"
        err "Edit $conf manually to ensure WaylandEnable=false is under [daemon]."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    require_root
    require_ubuntu

    local current
    current="$(current_driver_version || true)"
    if [ -n "$current" ]; then
        info "Currently installed NVIDIA driver: $current"
    else
        info "No NVIDIA driver currently installed (or nvidia-smi not available yet)."
    fi
    info "Target NVIDIA driver:               $TARGET_NVIDIA_VERSION (apt: nvidia-driver-$TARGET_NVIDIA_MAJOR)"

    if [ "$current" = "$TARGET_NVIDIA_VERSION" ]; then
        success "Already at target version. Nothing to do."
        exit 0
    fi

    if ! confirm "Proceed with upgrade?"; then
        info "Aborted."
        exit 0
    fi

    # Secure Boot heads-up. apt's nvidia install will prompt for an MOK
    # enrollment password if Secure Boot is on; you'll be asked for the
    # password at the next reboot to enroll the kernel-module signing key.
    if [ -d /sys/firmware/efi ] && command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            warn "Secure Boot is ENABLED."
            warn "apt will prompt you to set an MOK password during install."
            warn "Remember it — you'll need it at the next reboot's blue MOK screen."
            echo
        fi
    fi

    info "Step 1/7: apt update + ensure prerequisites (kernel headers, software-properties-common)"
    apt-get update
    apt-get install -y \
        "linux-headers-$(uname -r)" \
        software-properties-common \
        ca-certificates \
        gnupg

    info "Step 2/7: add ${PPA} so the latest 580.82.x patch is available"
    if ! grep -rq "graphics-drivers" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        add-apt-repository -y "$PPA"
    else
        info "graphics-drivers PPA already present, skipping add"
    fi
    apt-get update

    info "Step 3/7: purge any existing NVIDIA driver packages (clean slate)"
    # apt-get purge with a glob can fail if nothing matches; tolerate that.
    apt-get purge -y 'nvidia-*' 'libnvidia-*' || true
    apt-get autoremove -y

    info "Step 4/7: install nvidia-driver-${TARGET_NVIDIA_MAJOR} + utils"
    apt-get install -y \
        "nvidia-driver-${TARGET_NVIDIA_MAJOR}" \
        "nvidia-utils-${TARGET_NVIDIA_MAJOR}"

    info "Step 5/7: report what apt actually installed"
    local installed_version
    installed_version="$(dpkg-query -W -f='${Version}\n' "nvidia-driver-${TARGET_NVIDIA_MAJOR}" 2>/dev/null || echo unknown)"
    info "apt package version:    nvidia-driver-${TARGET_NVIDIA_MAJOR} = ${installed_version}"

    if [ "$installed_version" != "unknown" ]; then
        # The Ubuntu package version embeds the upstream driver version
        # (e.g. "580.82.09-0ubuntu1"). Extract and compare.
        local upstream
        upstream="$(echo "$installed_version" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
        if [ "$upstream" = "$TARGET_NVIDIA_VERSION" ]; then
            success "Installed upstream version matches target: $upstream"
        else
            warn "apt installed $upstream, not the requested $TARGET_NVIDIA_VERSION."
            warn "This usually means the PPA is currently shipping a different patch."
            warn "Any 580.x version satisfies MiniPrem's >=580 requirement, so this is"
            warn "likely fine. If you specifically need $TARGET_NVIDIA_VERSION, install"
            warn "from NVIDIA's .run file at https://www.nvidia.com/en-us/drivers/ instead."
        fi
    fi

    info "Step 6/7: enforce X11 session (set WaylandEnable=false in GDM config)"
    disable_wayland_in_gdm

    info "Step 7/7: reboot to load the new kernel modules"
    echo
    success "Driver install complete. The new driver is NOT active until you reboot."
    echo
    if confirm "Reboot now?"; then
        info "Rebooting..."
        systemctl reboot
    else
        warn "Skipped reboot. nvidia-smi will keep showing the OLD driver until you reboot."
        warn "Reboot manually with: sudo reboot"
    fi
}

main "$@"
