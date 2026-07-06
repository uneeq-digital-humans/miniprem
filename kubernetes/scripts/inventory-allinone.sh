#!/usr/bin/env bash
#
# inventory-allinone.sh — snapshot what's already running on a box before an
# all-in-one deploy, so deploy-allinone.sh can skip what exists.
#
# Usage (on the box, or scp it over and run):
#   bash inventory-allinone.sh
#
# Read-only. Reports: k8s presence, NIMs (Gemma/embed/rerank), Riva TTS/STT,
# NVIDIA RAG (rag-server / search / nv-ingest / vector DB), Renny, kiosk, and
# host-exposed ports — then prints the recommended deploy-allinone toggles.
set -uo pipefail

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

K=""
if have kubectl; then K=kubectl; elif have microk8s; then K="microk8s kubectl"; fi

say "Cluster"
if [ -n "$K" ]; then
  $K version --short 2>/dev/null | head -2 || true
  echo "Nodes:"; $K get nodes -o wide 2>/dev/null || echo "  (kubectl present but no cluster reachable)"
else
  echo "No kubectl/microk8s found — Docker-only box?"
fi

say "GPU"
if have nvidia-smi; then nvidia-smi --query-gpu=name,memory.total,memory.used,driver_version --format=csv,noheader || true; else echo "no nvidia-smi"; fi

if [ -n "$K" ]; then
  say "All pods (grep for stack components)"
  $K get pods -A 2>/dev/null | grep -Ei 'nim|gemma|embed|rerank|riva|magpie|asr|nemotron|rag|ingest|milvus|elastic|renny|interface|kiosk|redis|phoenix' || echo "  (none matched)"

  say "Services (note ports / NodePorts)"
  $K get svc -A 2>/dev/null | grep -Ei 'nim|gemma|embed|rerank|riva|magpie|asr|rag|ingest|milvus|elastic|renny|interface|kiosk|phoenix|search' || echo "  (none matched)"

  say "Ingresses"
  $K get ingress -A 2>/dev/null || echo "  (none)"
fi

say "Docker containers (bridge-exposed services)"
if have docker; then docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || echo "  (docker present, no perms?)"; else echo "no docker"; fi

say "Host-listening ports (for browser/kiosk reachability)"
( ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null ) | grep -E ':(3000|4000|8000|8001|8002|8003|8081|9200|7670|50051|8085)\b' || echo "  (none of the usual ports listening on host)"

say "Quick reachability probes (adjust host/ports to your box)"
HOST="${PROBE_HOST:-localhost}"
for p in 4000 8001 8002 8081 9200; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$HOST:$p/v1/models" 2>/dev/null || echo "---")
  echo "  http://$HOST:$p/v1/models -> $code"
done

say "Recommended deploy-allinone toggles"
cat <<'EOF'
Based on what you see above, set these when running deploy-allinone.sh:
  - Gemma NIM already running          -> DEPLOY_NIM=no
  - RAG blueprint pods present         -> DEPLOY_RAG=no  (else yes)
  - magpie-tts pod present             -> DEPLOY_RIVA_TTS=no (else yes)
  - digitalhuman-asr pod present       -> DEPLOY_RIVA_STT=no (else yes)
  - renny pod present                  -> DEPLOY_RENNY=no (else yes)
Always needed for this test: NGC_API_KEY, HARBOR_USERNAME, HARBOR_PASSWORD,
PLATFORM_KEY, TENANT_ID (Renny + kiosk persona).
EOF
