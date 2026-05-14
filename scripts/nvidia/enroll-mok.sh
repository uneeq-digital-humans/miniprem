#!/bin/bash
# Enroll a Machine Owner Key (MOK) for Secure Boot kernel module signing
# Required before installing NVIDIA drivers via .run file on Secure Boot systems
# Usage: sudo bash nvidia-enroll-mok.sh
# After this script reboots, confirm enrollment in the UEFI MokManager screen,
# then run: sudo bash install-nvidia-580.sh

set -e
MOK_DIR=/root/nvidia-mok
LOG=/var/log/nvidia-install-580.82.09.log

exec > >(tee -a "$LOG") 2>&1

echo "=== MOK enrollment started: $(date) ==="

# Check Secure Boot status
if ! mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    echo "NOTE: Secure Boot does not appear to be enabled on this system."
    echo "MOK enrollment may not be required, but proceeding anyway."
fi

mkdir -p "$MOK_DIR"
chmod 700 "$MOK_DIR"

if [ -f "$MOK_DIR/mok.key" ] && [ -f "$MOK_DIR/mok.crt" ]; then
    echo "MOK key pair already exists at $MOK_DIR — skipping generation."
else
    echo "Generating MOK key pair..."
    openssl req -new -x509 -newkey rsa:2048 \
        -keyout "$MOK_DIR/mok.key" \
        -out "$MOK_DIR/mok.crt" \
        -days 36500 \
        -subj "/CN=NVIDIA Driver MOK/" \
        -nodes
    echo "Key pair generated."
fi

if [ ! -f "$MOK_DIR/mok.der" ]; then
    echo "Converting certificate to DER format for mokutil..."
    openssl x509 -in "$MOK_DIR/mok.crt" -outform DER -out "$MOK_DIR/mok.der"
fi

echo ""
echo "Enrolling MOK — you will be prompted to set a one-time password."
echo "Remember this password: you will enter it once in the UEFI MokManager on next boot."
echo ""
mokutil --import "$MOK_DIR/mok.der"

echo ""
echo "=== MOK enrollment queued ==="
echo ""
echo "On next boot you will see a blue UEFI screen (MokManager):"
echo "  1. Select 'Enroll MOK'"
echo "  2. Select 'Continue'"
echo "  3. Enter the password you just set"
echo "  4. Select 'Yes' to enroll"
echo "  5. Select 'Reboot'"
echo ""
echo "NOTE: On encrypted drives, the LUKS unlock prompt appears AFTER MokManager."
echo ""
echo "After that reboot, run: sudo bash install-nvidia-580.sh"
echo ""
echo "Rebooting in 10 seconds (Ctrl+C to cancel)..."
sleep 10
reboot
