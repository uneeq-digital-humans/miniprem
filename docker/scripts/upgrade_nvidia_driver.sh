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
#   Designed to run idempotently on a system where the stock Ubuntu nvidia
#   driver may already be loaded (Ubuntu 24.04 autoinstall activates 535.x
#   on boxes with an NVIDIA GPU by default). The .run installer is invoked
#   with --allow-installation-with-running-driver, which copies the new
#   driver to disk and registers DKMS modules without unloading the live
#   driver — there is no need to stop gdm3 or reboot before invocation.
#   The reboot at Step 9 activates the new modules. Verified against
#   nvidia-installer/kernel.c:1733 (the CONTINUE branch at the loaded-
#   modules prompt) on the upstream main branch.
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

# Stable path always pointing at the most recent run's log. Timestamped logs
# above are kept for history; log collectors / monitoring watch this single
# fixed path instead of having to glob-and-sort for the newest file.
LATEST_LOG_LINK="/var/log/miniprem_driver_latest.log"

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
fatal()   { err "$*"; err "Full apt/installer output: $LOG_FILE (latest: ${LATEST_LOG_LINK:-n/a})"; exit 1; }

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

# Report Secure Boot state without depending on mokutil. mokutil is NOT
# installed on a fresh/minimal Ubuntu, so gating detection on it silently
# skips the check on exactly the unattended boxes we care about. Read the
# UEFI SecureBoot variable directly; use mokutil only as a secondary signal
# when it happens to be present.
#
# Echoes one of: enabled | disabled | unsupported | unknown
#   enabled      SecureBoot data byte == 1
#   disabled     SecureBoot data byte == 0
#   unsupported  legacy/BIOS boot (no /sys/firmware/efi) — SB cannot apply
#   unknown      EFI present but state unreadable and no mokutil to confirm
secure_boot_state() {
    if [ ! -d /sys/firmware/efi ]; then
        echo "unsupported"
        return 0
    fi

    # The efivar payload is a 4-byte attribute header followed by the 1-byte
    # value; od prints all 5 decimal bytes, the last of which is the state.
    local efivar="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    if [ -r "$efivar" ]; then
        local last_byte
        last_byte="$(od -An -t u1 "$efivar" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | tail -1)"
        case "$last_byte" in
            1) echo "enabled";  return 0 ;;
            0) echo "disabled"; return 0 ;;
        esac
    fi

    # Fall back to mokutil if the efivar was unreadable.
    if command -v mokutil >/dev/null 2>&1; then
        local sb
        sb="$(mokutil --sb-state 2>/dev/null)"
        if echo "$sb" | grep -qi "enabled"; then
            echo "enabled";  return 0
        elif echo "$sb" | grep -qi "disabled"; then
            echo "disabled"; return 0
        fi
    fi

    echo "unknown"
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
# installing the apt-managed nvidia driver stack over the .run-managed
# install. The .run installer is the canonical owner of the driver bits;
# apt should stay out of the way.
#
# Important: do NOT use a catch-all `libnvidia-*` glob here. That pattern
# also matches `libnvidia-container-tools` and `libnvidia-container1`,
# which are part of the nvidia-container-toolkit stack (needed for Docker
# GPU support) and have nothing to do with the driver. Pinning them to -1
# breaks `apt install nvidia-container-toolkit` later in the miniprem
# install flow with "Depends: libnvidia-container-tools but it is not
# installable". Enumerate the driver-component patterns explicitly.
write_apt_pin() {
    cat > "$APT_PIN_FILE" <<EOF
# Managed by upgrade_nvidia_driver.sh
#
# The NVIDIA driver on this system was installed via NVIDIA's .run installer
# at a specific pinned version. Block apt from installing competing nvidia
# packages on future apt upgrades. To revert (e.g. switching back to apt-
# managed driver), delete this file and reinstall via apt.
#
# libnvidia-container* (container toolkit) is intentionally NOT pinned —
# nvidia-container-toolkit depends on it and it does not conflict with
# the .run-installed driver.
Package: nvidia-driver-* nvidia-dkms-* nvidia-utils-* nvidia-kernel-common-* nvidia-kernel-source-* xserver-xorg-video-nvidia-* nvidia-compute-utils-* nvidia-firmware-* libnvidia-gl-* libnvidia-compute-* libnvidia-decode-* libnvidia-encode-* libnvidia-cfg1-* libnvidia-common-* libnvidia-extra-* libnvidia-fbc1-* libnvidia-ifr1-* libnvidia-nscq-* libnvidia-egl-* libnvidia-ml-*
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
    # Point the stable "latest" symlink at this run's log (-n: don't follow an
    # existing link into a directory). Best-effort: never let this abort the run.
    ln -sfn "$LOG_FILE" "$LATEST_LOG_LINK" 2>/dev/null || \
        warn "Could not update latest-log symlink $LATEST_LOG_LINK"
    info "Verbose apt/installer output will be logged to: $LOG_FILE"
    info "  (also reachable at the stable path: $LATEST_LOG_LINK)"

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
    # unattended. Detect it WITHOUT relying on mokutil (absent on minimal
    # Ubuntu), so the check actually runs on the unattended boxes it protects.
    local sb_state
    sb_state="$(secure_boot_state)"
    case "$sb_state" in
        enabled)
            if [ "$ASSUME_YES" = "yes" ]; then
                fatal "Secure Boot is ENABLED. The .run installer's DKMS-signed modules will not load without manual MOK enrollment at the next boot, which is impossible under --yes. Either disable Secure Boot in firmware, or pre-enrol a MOK with scripts/nvidia/enroll-mok.sh and re-run."
            else
                warn "Secure Boot is ENABLED."
                warn "The .run installer's DKMS modules must be signed and the key"
                warn "enrolled manually at the blue MOK Manager screen on next reboot,"
                warn "which requires physical/IPMI access. See scripts/nvidia/enroll-mok.sh."
                if ! confirm "Continue anyway?"; then
                    info "Aborted."
                    exit 0
                fi
            fi
            ;;
        disabled)
            info "Secure Boot is disabled — .run/DKMS modules will load without MOK enrollment."
            ;;
        unsupported)
            info "Legacy/BIOS boot (no UEFI) — Secure Boot does not apply."
            ;;
        unknown)
            # EFI present but state unreadable and no mokutil to confirm.
            # Don't block an unattended run on an indeterminate reading; warn
            # loudly so it's in the log if the driver later fails to load.
            warn "Secure Boot state could not be determined (UEFI present, SecureBoot variable unreadable, mokutil absent)."
            warn "If Secure Boot turns out to be ENABLED, DKMS modules will fail to load on reboot until a MOK is enrolled (scripts/nvidia/enroll-mok.sh)."
            warn "Proceeding."
            ;;
    esac

    # ---- Step 1/9: ensure kernel headers, build toolchain, dkms, curl ----
    # build-essential pulls in gcc/g++/make/libc6-dev/dpkg-dev — DKMS
    # compiles the nvidia kernel module from source and needs all of it.
    # On a fresh Ubuntu install gcc is not present by default; previously
    # the apt-managed nvidia packages pulled it in transitively. Going via
    # the .run installer, we own this dependency explicitly.
    #
    # dkms itself is also required: the .run installer's --dkms flag
    # silently falls back to non-DKMS install if the dkms package isn't
    # present, which means modules land in /lib/modules/.../kernel/ rather
    # than .../updates/dkms/, and future kernel upgrades will break the
    # driver (no auto-rebuild). Installing dkms here guarantees --dkms
    # actually registers the modules for auto-rebuild on kernel update.
    info "Step 1/9: ensure prerequisites (kernel headers, build toolchain, dkms, curl)"
    quietly apt-get update
    quietly apt-get install -y \
        "linux-headers-$(uname -r)" \
        build-essential \
        dkms \
        curl \
        ca-certificates \
        || fatal "Failed to install build prerequisites"

    # ---- Step 2/9: pre-flight CDN check so we fail fast on bad version ----
    local url
    url="$(build_installer_url)"
    info "Step 2/9: verify NVIDIA CDN has $TARGET_NVIDIA_VERSION available"
    info "  URL: $url"
    if ! curl -sSf -I --max-time 10 "$url" >/dev/null 2>>"$LOG_FILE"; then
        fatal "NVIDIA CDN URL not reachable or version not published: $url"
    fi
    success "CDN URL reachable."

    # ---- Step 3/9: purge any apt-managed nvidia packages (clean slate) ----
    # No apt-get autoremove here. autoremove is more cleanup than necessity
    # — the nvidia purge does the actual work of clearing conflicting
    # packages. autoremove is well-meaning but can quietly yank packages
    # we want (we narrowly avoided losing build-essential's transitive
    # dependencies that way during testing). The disk-space saving is
    # negligible vs the risk of pulling out something we need.
    info "Step 3/9: purge any existing nvidia-* apt packages"
    # Glob may match nothing; tolerate that. Output goes to log.
    quietly bash -c "apt-get purge -y 'nvidia-*' 'libnvidia-*' || true"
    success "Existing nvidia packages removed."

    # ---- Step 4/9: download the .run installer ----
    local runfile="/tmp/NVIDIA-Linux-$(uname -m)-${TARGET_NVIDIA_VERSION}.run"
    info "Step 4/9: download .run installer to $runfile"
    # curl with progress bar visible (not in log) so operator sees download advance
    if ! curl -fL --retry 3 --retry-delay 5 -# -o "$runfile" "$url"; then
        fatal "Failed to download $url"
    fi
    chmod +x "$runfile"
    success "Downloaded $(du -h "$runfile" | cut -f1) installer."

    # ---- Step 5/9: run the silent installer ----
    info "Step 5/9: run NVIDIA installer (--silent --dkms)"
    # --silent implies --no-questions, --ui=none, and --accept-license.
    # --dkms registers the kernel module so future kernel upgrades rebuild it.
    # --disable-nouveau writes the modprobe.d blacklist for next boot.
    # --no-nouveau-check lets us proceed even though nouveau is currently
    #   bound to the GPU (it can't unload while bound; reboot will switch).
    # --no-x-check bypasses the abort that fires when X is running on a
    #   different driver. Production path has no X server running so this
    #   flag is a no-op there; it exists solely to unblock interactive
    #   testing. Safe because we always reboot after install.
    # --allow-installation-with-running-driver is the load-bearing flag.
    #   Ubuntu 24.04 autoinstall activates nvidia-driver-535 (or -595-open
    #   on newer images) on boxes with an NVIDIA GPU. Without this flag,
    #   the installer hits its "nvidia-drm appears to be already loaded"
    #   sanity check and aborts non-interactively because --silent picks
    #   the default answer (ABORT). With this flag, the CONTINUE branch
    #   is taken (nvidia-installer/kernel.c:1733), which also internally
    #   sets skip_module_load=TRUE — so the installer compiles + installs
    #   modules into /lib/modules/.../updates/dkms/ but does NOT attempt
    #   to load them over the live driver. The reboot at Step 9
    #   activates the new 580.82.09 modules cleanly.
    # Installer also writes its own log at /var/log/nvidia-installer.log.
    if ! "$runfile" --silent --dkms --disable-nouveau --no-nouveau-check \
            --no-x-check --allow-installation-with-running-driver \
            >>"$LOG_FILE" 2>&1; then
        err "NVIDIA installer failed. Last 30 lines of /var/log/nvidia-installer.log:"
        tail -n 30 /var/log/nvidia-installer.log 2>/dev/null || true
        fatal "Installer exited non-zero."
    fi
    success "NVIDIA installer completed."

    # Cleanup the downloaded .run file
    rm -f "$runfile"

    # ---- Step 6/9: write apt preferences pin ----
    info "Step 6/9: write apt preferences pin to protect the install"
    write_apt_pin

    # ---- Step 7/9: blacklist nouveau and rebuild initramfs ----
    # The .run installer's --disable-nouveau is unreliable on Ubuntu 24.04 +
    # kernel 6.17: the installer's internal update-initramfs invocation
    # errors out with "requires a file path argument" on this combination,
    # and the blacklist file doesn't end up where the running initramfs
    # picks it up. After reboot, nouveau loads early, claims the GPU, and
    # nvidia.ko can't bind (kernel messages: "GPU 0000:01:00.0 is already
    # bound to nouveau" / "No NVIDIA devices probed"). Take ownership of
    # nouveau blacklisting explicitly. Idempotent: re-running just
    # overwrites the file with the same content.
    info "Step 7/9: blacklist nouveau and rebuild initramfs"
    cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
# Managed by upgrade_nvidia_driver.sh
# Block nouveau so nvidia.ko can claim the GPU at boot.
blacklist nouveau
options nouveau modeset=0
EOF
    chmod 644 /etc/modprobe.d/blacklist-nouveau.conf
    info "  Wrote /etc/modprobe.d/blacklist-nouveau.conf"
    info "  Regenerating initramfs (this takes ~30 seconds)..."
    quietly update-initramfs -u || fatal "Failed to regenerate initramfs"
    success "nouveau blacklisted, initramfs regenerated."

    # ---- Step 8/9: enforce X11 (disable Wayland) ----
    info "Step 8/9: enforce X11 session (set WaylandEnable=false in GDM config)"
    disable_wayland_in_gdm

    # ---- Step 9/9: reboot (or skip) ----
    info "Step 9/9: reboot to load the new kernel modules"
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
