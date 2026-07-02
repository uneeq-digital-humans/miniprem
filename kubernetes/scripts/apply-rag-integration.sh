#!/usr/bin/env bash
# Align the NVIDIA RAG blueprint with the kiosk's loaded LLM + enable multimodal
# ingestion — the runtime configuration discovered/fixed on the appliance
# (2026-07-02). Idempotent; run on the box (or with KUBECONFIG pointed at it).
#
#   MODEL     = the exact id the LLM NIM serves at /v1/models (case-sensitive)
#   LLM_URL   = the NIM's chat-completions URL (cluster DNS)
set -euo pipefail
MODEL="${MODEL:-google/gemma-4-26B-A4B-it}"
LLM_CHAT_URL="${LLM_CHAT_URL:-http://gemma.nim-models.svc.cluster.local:8000/v1/chat/completions}"
# Captions go through the rag-adapter's format shim, NOT straight to the NIM:
# nv-ingest speaks the NVIDIA-VLM dialect ('<img src="data:..."/>' inline in a
# text message, one message per image). OpenAI-style NIMs (Gemma) read that
# base64 as literal TEXT -> hallucinated captions -> poisoned image embeddings.
# The shim rewrites each message into proper image_url parts (adapter v14+).
CAPTION_URL="${CAPTION_URL:-http://rag-adapter.uneeq.svc.cluster.local:8085/caption/v1/chat/completions}"
NS="${NS:-advanced-rag}"

echo "1) nim-llm alias service (blueprint's default LLM hostname -> the loaded NIM)"
kubectl apply -f "$(dirname "$0")/../nvidia-rag-integration.yaml"

echo "2) rag-server: ALL LLM roles -> $MODEL (chat, query-rewriter, filter-generator)"
kubectl set env deploy/rag-server -n "$NS" \
  APP_LLM_MODELNAME="$MODEL" \
  APP_QUERYREWRITER_MODELNAME="$MODEL" \
  APP_FILTEREXPRESSIONGENERATOR_MODELNAME="$MODEL"

echo "3) ingestor: multimodal extraction ON + LOCAL image captioning + summary -> $MODEL"
#    - EXTRACTIMAGES/INFOGRAPHICS default False => scanned/image docs silently yield
#      'No records with Embeddings to insert'.
#    - CAPTIONENDPOINTURL default empty => nv-ingest falls back to NVIDIA's hosted
#      API (integrate.api.nvidia.com) => 403 without an NGC key. The Gemma NIM is
#      vision-capable, so captioning runs locally on the SAME model — via the
#      adapter's /caption shim (see CAPTION_URL above for why).
kubectl set env deploy/ingestor-server -n "$NS" \
  APP_NVINGEST_EXTRACTIMAGES=True \
  APP_NVINGEST_EXTRACTINFOGRAPHICS=True \
  APP_NVINGEST_CAPTIONENDPOINTURL="$CAPTION_URL" \
  APP_NVINGEST_CAPTIONMODELNAME="$MODEL" \
  SUMMARY_LLM="$MODEL"

echo "4) rag-nv-ingest: ships requesting ALL node CPUs (24) -> unschedulable; cap request"
kubectl patch deploy rag-nv-ingest -n "$NS" --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"2"}]' || true

echo "5) rag-adapter: shared store + blueprint ingest pipeline (two-way documents)"
kubectl set env deploy/rag-adapter -n uneeq \
  MILVUS_DB_PATH="${MILVUS_URL:-http://milvus.advanced-rag.svc.cluster.local:19530}" \
  INGESTOR_URL="${INGESTOR_URL:-http://ingestor-server.advanced-rag.svc.cluster.local:8082}"

echo "Done. Collections must be blueprint-created (ingestor POST /v1/collections)"
echo "for portal queries to work — adapter-created legacy collections lack the"
echo "blueprint schema ('field source not exist')."
