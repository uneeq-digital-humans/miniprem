#!/usr/bin/env bash
# Run ON the T2. Deploys the NVIDIA Riva TTS NIM (magpie multilingual) as a
# Docker container on host network (gRPC :50051, http :9000) so that, when
# persona 114962fb's TTS is set to Riva in the UneeQ Admin Portal, the local
# Renny can reach it. Sources NGC_API_KEY from the box .env (never prints it).
set -u
ENVF=/home/admin/uneeq-llm-infra-dell/.env
set -a; . "$ENVF" 2>/dev/null; set +a
: "${NGC_API_KEY:?NGC_API_KEY not found in $ENVF}"

echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin >/dev/null 2>&1 || true

sudo docker rm -f riva-tts >/dev/null 2>&1 || true
echo "starting riva-tts (magpie) — first run pulls several GB..."
sudo docker run -d --name riva-tts \
  --runtime nvidia --network host --shm-size 4g --restart unless-stopped \
  -e NGC_API_KEY="$NGC_API_KEY" \
  -e NIM_HTTP_API_PORT=9000 \
  -e NIM_GRPC_API_PORT=50051 \
  -v nim-cache:/opt/nim/.cache \
  nvcr.io/nim/nvidia/magpie-tts-multilingual:latest >/dev/null

echo "container started; model load takes several minutes. Watch:"
echo "  sudo docker logs -f riva-tts"
