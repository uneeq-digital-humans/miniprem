# nim-gemma Helm chart

Serves the kiosk LLM via the **NVIDIA NIM Operator** (`NIMCache` + `NIMService`) —
fully NVIDIA-supported, no custom vLLM. Defaults to `gemma-4-26b-a4b-it` (26B MoE,
~25 GB), which fits alongside Riva STT/TTS + Renny + RAG on one Blackwell.

```bash
helm upgrade --install gemma ./nim-gemma -n nim-models
# point the rag-adapter LLM at it:  http://gemma-4-26b-a4b-it.nim-models:8000/v1
```

Requires the NIM Operator installed and two secrets in `nim-models`:
`ngc-api-secret` (generic NGC API key, model download) and `ngc-secret`
(docker-registry, nvcr.io pull).

## Why the relax-mem override

Every published profile for this model is "Incompatible with system" (they target
≥48 GiB). The chart forces `NIM_MODEL_PROFILE` + `NIM_RELAX_MEM_CONSTRAINTS=1` and
lowers `gpu_memory_utilization` (0.30) so it runs at ~25 GB on the shared 96 GB
card. Default profile `98504107…` = `vllm-nvfp4-tp1-pp1-fallback-1-48gib`.

## MTP — not available for this model (verified 2026-06-29)

`list-model-profiles` on `nvcr.io/nim/google/gemma-4-26b-a4b-it:latest` returns
ONLY standard profiles — no MTP/speculative/EAGLE/Medusa:

| profile | hash |
|---|---|
| vllm-nvfp4-tp1-pp1-fallback-1-48gib **(default)** | `98504107…` |
| vllm-bf16-tp1/tp2-pp1-fallback | `533c7a07…` / `452f22c6…` |
| vllm-{b200,h200,h20,l40s,dgx-spark}-…-throughput | (GPU-specific) |

So **MTP cannot be enabled here on the supported NIM stack.** MTP for Gemma‑4
DOES exist officially — Google ships an MTP drafter for the 26B‑A4B (and E2B/E4B/
31B) and NVIDIA's **NeMo‑AutoModel** exposes `Gemma4WithDrafter` — but ONLY via the
**vLLM / NeMo** serving path, NOT as a packaged NIM optimized profile. NVIDIA's own
`nvidia/Gemma-4-26B-A4B-NVFP4` checkpoint is documented "to serve with vLLM"
(TP=1 only), with no NIM and no MTP profile. Our "fully NVIDIA‑supported, no custom
vLLM" constraint therefore rules MTP out today. `mtp.*` in values is a forward hook
for if/when a future NIM build publishes an MTP/speculative profile (re‑check with
the `list-model-profiles` command below). Verified against official sources
2026‑06‑30 (build.nvidia.com NIM container profiles + HF NVFP4 card + NeMo‑AutoModel
Gemma 4 docs).

To re-check on a newer NIM build:
```bash
nerdctl run --rm -e NGC_API_KEY=$NGC_API_KEY \
  nvcr.io/nim/google/gemma-4-26b-a4b-it:latest list-model-profiles | grep -i 'mtp\|specul\|eagle'
```

## After-boot verification (confirm the model is serving properly)

Run these once the `gemma` pod is `Running` (namespace `nim-models`). They confirm
the NV-FP4 profile is active and the context cap took effect — no NGC key needed,
it reads the already-cached model.

```bash
POD=$(kubectl -n nim-models get pod -l app.kubernetes.io/name=gemma -o name | head -1)   # or: get pod | grep gemma

# 1) The env we feed vLLM (expect the NV-FP4 profile hash + KV-cache + max-model-len):
kubectl -n nim-models get deploy gemma -o yaml | grep -A1 -E 'NIM_MODEL_PROFILE|KV_CACHE|PASSTHROUGH|RELAX_MEM'

# 2) The served model + the ACTUAL context length the engine came up with
#    (expect id google/gemma-4-26B-A4B-it and max_model_len 16384, NOT 262144):
kubectl -n nim-models exec $POD -- curl -s localhost:8000/v1/models | python3 -m json.tool

# 3) The profile the NIM actually selected at boot (expect the nvfp4 fallback):
kubectl -n nim-models logs $POD | grep -iE 'selected profile|nvfp4|quantization' | head

# 4) MTP is not available for this model — this must return NOTHING:
kubectl -n nim-models exec $POD -- list-model-profiles 2>/dev/null | grep -iE 'mtp|specul|eagle'
```

If `max_model_len` still shows 262144, the `maxModelLen` value didn't reach the
NIM — check that `NIM_PASSTHROUGH_ARGS` is on the Deployment (step 1). If `/v1/models`
reports a different id, the served profile/image drifted from `google/gemma-4-26B-A4B-it`.
