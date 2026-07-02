#!/usr/bin/env bash
# Deploy the MiniPrem Host Helper (localhost-only privileged agent).
#
# PRIVILEGED — this mounts the Docker socket (for NIM pulls) and the kiosk user's
# PulseAudio socket (for `pactl`). Review before running. The auto-mode safety
# classifier will gate this; an operator must run/approve it on the box.
#
# Audio note: PULSE_SERVER / the pulse socket belong to the user running the
# kiosk Chrome (its PulseAudio session). Set KIOSK_UID to that user's uid.
set -euo pipefail

KIOSK_UID="${KIOSK_UID:-$(id -u)}"
KIOSK_USER="${KIOSK_USER:-$(id -un)}"
PULSE_SOCK="/run/user/${KIOSK_UID}/pulse/native"
# X access for `xrandr` (display resolution/rotation). Auto-detect the LIVE X
# display socket (X0/X1/…) and its Xauthority — GDM stores the cookie under
# /run/user/<uid>/gdm/Xauthority; a manual startx uses ~/.Xauthority.
XSOCK="$(ls /tmp/.X11-unix/ 2>/dev/null | head -1)"
XDISPLAY=":${XSOCK#X}"; [ "$XDISPLAY" = ":" ] && XDISPLAY=":0"
XAUTH=""
for cand in "${XAUTHORITY:-}" "/run/user/${KIOSK_UID}/gdm/Xauthority" "/home/${KIOSK_USER}/.Xauthority"; do
  [ -n "$cand" ] && [ -f "$cand" ] && XAUTH="$cand" && break
done
echo "[host-helper] display=${XDISPLAY} xauth=${XAUTH:-none}"

sudo docker build -t host-helper:local .

sudo docker rm -f host-helper >/dev/null 2>&1 || true

# Optional: mount a kubeconfig so Renny logs/restart works on kubeadm deploys.
KUBE_MOUNT=()
[ -d /root/.kube ] && KUBE_MOUNT=(-v /root/.kube:/root/.kube:ro)

sudo docker run -d --name host-helper --restart unless-stopped \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${PULSE_SOCK}:${PULSE_SOCK}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  $( [ -n "${XAUTH}" ] && echo -v "${XAUTH}:/root/.Xauthority:ro" ) \
  "${KUBE_MOUNT[@]}" \
  -e "PULSE_SERVER=unix:${PULSE_SOCK}" \
  -e "DISPLAY=${XDISPLAY}" \
  -e "XAUTHORITY=/root/.Xauthority" \
  host-helper:local

echo "Host helper on http://127.0.0.1:8086 (kiosk reaches it via nginx /host-admin/)."
echo "Add to the kiosk nginx default.conf:"
echo '  location /host-admin/ { proxy_pass http://127.0.0.1:8086/; proxy_read_timeout 600s; }'
