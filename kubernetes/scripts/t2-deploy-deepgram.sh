#!/usr/bin/env bash
# Run ON the miniprem k8s box (e.g. t2 / Dell test box).
# Deploys the self-hosted Deepgram stack (uneeq-kit): api (stem) + STT engine +
# TTS engine + TTS adapter. Enables "Deepgram (local)" STT in the kiosk and
# "Deepgram (Self-Hosted)" TTS in the UneeQ Admin Portal for local Renny.
#
# Pre-steps (see docker/allinone/DEEPGRAM-LOCAL.md for details):
#   1. Self-hosted API key: Deepgram Console -> project -> API Keys -> Create.
#   2. Model files + configs on the NODE:
#        /opt/deepgram/config/{api,engine-stt,engine-tts}.toml
#        /opt/deepgram/models-stt/{flux-general-en.caf79279.dg,nova-3-general.en.streaming.40bd3654.dg}
#        /opt/deepgram/models-tts/flux-tts.f94b1bd5.dgv2
#   3. Harbor robot login + pull secret in ns deepgram (see below).
#   4. TTS adapter image present locally (built from docker/allinone/deepgram-adapter/Dockerfile).
#
# Usage:  t2-deploy-deepgram.sh <DEEPGRAM_API_KEY>
#         (or export DEEPGRAM_API_KEY first)
set -euo pipefail

KEY="${1:-${DEEPGRAM_API_KEY:-}}"
: "${KEY:?usage: $0 <DEEPGRAM_API_KEY>  (or export DEEPGRAM_API_KEY)}"
: "${HARBOR_USERNAME:?set HARBOR_USERNAME (robot) in the environment}"
: "${HARBOR_PASSWORD:?set HARBOR_PASSWORD (robot) in the environment}"

REGISTRY="${DEEPGRAM_REGISTRY:-cr.uneeq.io/deepgram}"
API_TAG="${DEEPGRAM_API_TAG:-1.192.31-6-gea727c0b2845}"
ENGINE_TAG="${DEEPGRAM_ENGINE_TAG:-3.128.0-35-g32f578ac8bdd}"

# --- sanity: models + configs on the node ------------------------------------
# Configs must carry the license key in [license] key (the engine reads ONLY
# the TOML, not the env var — verified on t2 2026-09-01). The rendered
# configs are scp'd to the node together with this script (see the runbook);
# to render them locally: DEEPGRAM_API_KEY=*** render-configs.sh --to <dir>.
for f in api engine-stt engine-tts; do
  if ! sudo grep -q "key = " "/opt/deepgram/config/$f.toml" 2>/dev/null; then
    echo "!! /opt/deepgram/config/$f.toml has no [license] key."
    echo "   render it (on the machine with the repo + key):"
    echo "   cd <miniprem>/docker/allinone && DEEPGRAM_API_KEY=*** render-configs.sh --to /tmp/dgconfig"
    echo "   scp /tmp/dgconfig/*.toml admin@<box>:/tmp/ && sudo cp /tmp/*.toml /opt/deepgram/config/"
    exit 1
  fi
done

for f in config/api.toml config/engine-stt.toml config/engine-tts.toml \
         models-stt/nova-3-general.en.streaming.40bd3654.dg models-stt/flux-general-en.caf79279.dg \
         models-tts/flux-tts.f94b1bd5.dgv2; do
  [ -f "/opt/deepgram/$f" ] || { echo "!! missing /opt/deepgram/$f"; exit 1; }
done

# --- harbor robot login + pull secrets ---------------------------------------
echo "$HARBOR_PASSWORD" | sudo docker login "$REGISTRY" -u "$HARBOR_USERNAME" --password-stdin >/dev/null
sudo docker pull "$REGISTRY/api-uneeq:$API_TAG"
sudo docker pull "$REGISTRY/engine-uneeq:$ENGINE_TAG"

# kubeadm nodes run containerd (k8s.io namespace) — docker's store is NOT
# visible to kubelet, so import the pulled images into containerd too.
import_to_k8s_runtime() {
  local img="$1" tar="/tmp/$(echo "$img" | tr '/:' '__').tar"
  sudo docker save "$img" -o "$tar"
  if command -v ctr >/dev/null 2>&1 && sudo ctr -n k8s.io version >/dev/null 2>&1; then
    sudo ctr -n k8s.io images import "$tar"
  fi
  rm -f "$tar"
}
import_to_k8s_runtime "$REGISTRY/api-uneeq:$API_TAG"
import_to_k8s_runtime "$REGISTRY/engine-uneeq:$ENGINE_TAG"

sudo kubectl create namespace deepgram --dry-run=client -o yaml | sudo kubectl apply -f -
sudo kubectl create secret docker-registry harbor -n deepgram \
  --docker-server="$REGISTRY" --docker-username="$HARBOR_USERNAME" \
  --docker-password="$HARBOR_PASSWORD" --dry-run=client -o yaml | sudo kubectl apply -f -
sudo kubectl create secret generic deepgram-creds -n deepgram \
  --from-literal=api-key="$KEY" --dry-run=client -o yaml | sudo kubectl apply -f -

# --- adapter image (build if missing) ----------------------------------------
if ! sudo docker image inspect deepgram-tts-adapter:local >/dev/null 2>&1; then
  ADAPTER_DIR="$(cd "$(dirname "$0")/../docker/allinone/deepgram-adapter" && pwd)"
  [ -d "$ADAPTER_DIR" ] || { echo "!! adapter build context not found: $ADAPTER_DIR"; exit 1; }
  sudo docker build -t deepgram-tts-adapter:local "$ADAPTER_DIR"
fi
import_to_k8s_runtime deepgram-tts-adapter:local

# --- deploy -------------------------------------------------------------------
MANIFEST="$(cd "$(dirname "$0")" && pwd)/manifests/deepgram.yaml"
sudo kubectl apply -f "$MANIFEST"

echo
echo "Up. Watch:"
echo "  sudo kubectl logs -n deepgram -l app=deepgram-engine-tts -f   (model load: several minutes)"
echo "  sudo kubectl logs -n deepgram -l app=deepgram-engine-stt -f"
echo

# --- verify (opt-in: t2-deploy-deepgram.sh <KEY> --verify) -------------------
# Waits for the engines to pass the license handshake + model load, then
# smoke-tests each endpoint. First boot takes several minutes (model
# decrypt/load) — this polls up to ~25 min before giving up.
if [ "${2:-}" = "--verify" ]; then
  echo "=== verify: waiting for pods (first boot decrypts models, several minutes) ==="
  for i in $(seq 1 50); do
    notready=$(sudo kubectl get pods -n deepgram --no-headers 2>/dev/null | grep -cv "Running" || true)
    if [ "$notready" -eq 0 ]; then
      echo "all 4 pods Running (after $((i*30))s)"
      break
    fi
    echo "  ...$((i*30))s: $notready pod(s) not yet Running"
    sleep 30
  done
  sudo kubectl get pods -n deepgram

  echo "=== verify: engine health ==="
  curl -sf "http://127.0.0.1:30080/v1/health" | head -c 300 && echo "  <- engine-stt OK" || echo "!! engine-stt /v1/health failed"
  curl -sf "http://127.0.0.1:30080/v1/health" >/dev/null 2>&1 || true
  for i in $(seq 1 40); do
    if curl -sf "http://127.0.0.1:30080/healthz" >/dev/null 2>&1 || curl -sf "http://127.0.0.1:30080/" >/dev/null 2>&1; then
      echo "engine-stt responding (after $((i*15))s)"
      break
    fi
    sleep 15
  done

  echo "=== verify: adapter TTS (expect 200 + audio) ==="
  code=$(curl -s -o /tmp/dg-adapter-smoke.pcm -w "%{http_code}" \
    -X POST "http://127.0.0.1:30086" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"Deepgram local TTS smoke test.\",\"preset\":\"flux-hannah-en\",\"apiKey\":\"$KEY\"}")
  echo "adapter http=$code bytes=$(wc -c < /tmp/dg-adapter-smoke.pcm 2>/dev/null || echo 0)"
  rm -f /tmp/dg-adapter-smoke.pcm
fi
echo "Endpoints (this box):"
echo "  Deepgram stem   ws://<box-ip>:30080/v1/listen   (kiosk STT — Deepgram (local))"
echo "  TTS adapter     http://<box-ip>:30086           (Portal TTS URL — Deepgram (Self-Hosted))"
echo
echo "Then:"
echo "  1. Kiosk Settings -> Advanced -> STT -> Deepgram (local) ->"
echo "       endpoint http://<box-ip>:30080  (or http://localhost:30080 on-box) + key -> Apply"
echo "  2. UneeQ Admin Portal -> persona -> TTS Provider 'Deepgram (Self-Hosted)'"
echo "       TTS URL http://<box-ip>:30086, API key = the same key, voice e.g. flux-hannah-en"
echo "  3. Test Speech in the portal; talk to the kiosk for the full loop"
