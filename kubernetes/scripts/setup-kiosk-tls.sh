#!/usr/bin/env bash
# Give the on-box kiosk HTTPS over the LAN with a self-signed cert, so a LAN
# browser gets a SECURE CONTEXT — which unlocks the microphone + audio device
# selection (and full Settings, still password-gated). Without HTTPS, plain
# http://<LAN-IP> is not a secure context and the browser hides mic/device APIs.
#
# What it does (idempotent):
#   1. generates a self-signed cert with SANs for the kiosk hostname, localhost,
#      *.localhost, and THIS box's LAN IP(s)
#   2. stores it as the `kiosk-tls` secret in the uneeq namespace
#   3. points ingress-nginx's DEFAULT certificate at it, so HTTPS works on ANY
#      address (the LAN IP included, where there's no SNI host match)
#
# Operators see a one-time "not trusted" warning (self-signed) — click through,
# or import the cert onto the kiosk machines to trust it. For a CLOUD deploy use
# a REAL cert instead: create the `kiosk-tls` secret from your CA/Let's Encrypt
# cert (same name) and skip step 1.
set -euo pipefail
NS="${NS:-uneeq}"
HOST="${KIOSK_HOST:-digitalhuman.miniprem}"
SECRET="${TLS_SECRET:-kiosk-tls}"
KUBECTL="${KUBECTL:-kubectl}"

# Collect this box's LAN IPv4s for the cert SAN (so https://<ip> validates host).
IPS="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' || true)"
SAN="DNS:${HOST},DNS:localhost,DNS:*.localhost"
for ip in $IPS; do SAN="${SAN},IP:${ip}"; done
echo "[kiosk-tls] cert SANs: $SAN"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" -days 3650 \
  -subj "/CN=${HOST}" -addext "subjectAltName=${SAN}" >/dev/null 2>&1
echo "[kiosk-tls] generated self-signed cert (10y)"

$KUBECTL -n "$NS" create secret tls "$SECRET" \
  --cert="$TMP/tls.crt" --key="$TMP/tls.key" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
echo "[kiosk-tls] stored secret ${NS}/${SECRET}"

# Make it the ingress-nginx default cert → HTTPS on every host (incl. the LAN IP).
# ingress-nginx reads --default-ssl-certificate=<ns>/<secret>.
$KUBECTL -n ingress-nginx patch ds ingress-nginx-controller --type=json -p "[{
  \"op\":\"add\",
  \"path\":\"/spec/template/spec/containers/0/args/-\",
  \"value\":\"--default-ssl-certificate=${NS}/${SECRET}\"
}]" 2>/dev/null && echo "[kiosk-tls] set ingress-nginx default-ssl-certificate=${NS}/${SECRET}" \
  || echo "[kiosk-tls] NOTE: could not patch the controller args (already set, or it's a Deployment not a DaemonSet — adjust)."

echo "[kiosk-tls] done. The kiosk is now reachable over HTTPS:"
echo "  https://${HOST}    https://localhost    https://<box-ip>"
echo "  (self-signed → click through the one-time browser warning, or trust the cert)"
