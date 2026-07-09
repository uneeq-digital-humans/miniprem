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

## MTP — validated and ON by default (T2, 2026-07-09)

`list-model-profiles` on `nvcr.io/nim/google/gemma-4-26b-a4b-it:latest` returns
ONLY standard profiles — no MTP/speculative/EAGLE/Medusa:

| profile | hash |
|---|---|
| vllm-nvfp4-tp1-pp1-fallback-1-48gib **(default)** | `98504107…` |
| vllm-bf16-tp1/tp2-pp1-fallback | `533c7a07…` / `452f22c6…` |
| vllm-{b200,h200,h20,l40s,dgx-spark}-…-throughput | (GPU-specific) |

That part of the earlier claim was correct — but the leap from "no packaged MTP
*profile*" to "MTP is not available" was wrong, and has been corrected. The
"-it-assistant" MTP drafter (`Gemma4AssistantForCausalLM`) ships **inside** the
pinned nvfp4 profile itself, at `/opt/nim/workspace/assistant` — it just isn't
exposed as its own `list-model-profiles` entry. And `/opt/nim/fallback.yaml` turns
out to be a full `AsyncEngineArgs` passthrough (its loader filters keys against
`fields(AsyncEngineArgs)` then calls `AsyncEngineArgs(**engine_args)`) — unlike
`NIM_PASSTHROUGH_ARGS`, which this build silently ignores (see the max_model_len
note below). Appending to `fallback.yaml`:
```yaml
speculative_config:
  model: /opt/nim/workspace/assistant
  num_speculative_tokens: 3
```
made vLLM build `SpeculativeConfig(method='mtp', …)` and load the drafter. The
chart wires this behind `mtp.enabled` (`templates/nim.yaml`) — no profile hash or
NIM_MODEL_PROFILE swap needed, since it's the same profile.

**Validated end-to-end (2026-07-09, RTX PRO 6000 Blackwell 96 GB).** With MTP on
at the default 262144 context and `gpuMemoryUtilization: 0.30`, gemma booted clean
(`SpeculativeConfig(method='mtp', num_spec_tokens=3)`, drafter loaded), reported a
**438,396-token KV cache (1.67x concurrency)**, and served a correct reply at
**~200 tok/s** (`curl /v1/chat/completions`, HTTP 200). It is now **on by default**.

**Correction to the earlier draft of this doc:** a previous version claimed MTP
was blocked because this NIM "sizes its KV cache from a fixed
`nim_num_kv_cache_seq_lens: 1.0` (~0.31 GiB), too small for the max_seq_len check."
**That was a misdiagnosis.** The crashloop that produced it was a three-changes-at-
once config (util 0.55 + `max_model_len: 16384` appended to fallback.yaml + MTP).
Isolating MTP alone proved the KV cache is healthy (438k tokens at util 0.30) and
`nim_num_kv_cache_seq_lens` stays at its 1.0 default. `kvCacheSeqLens` in
`values.yaml` is retained only as an escape hatch, not a requirement. Set
`mtp.enabled: false` on VRAM-constrained boxes (the drafter is a second model in
memory); re-validate on new hardware/images via `curl /v1/chat/completions` + pod
logs for `SpeculativeConfig(method='mtp'`.

To re-check the profile list on a newer NIM build:
```bash
nerdctl run --rm -e NGC_API_KEY=$NGC_API_KEY \
  nvcr.io/nim/google/gemma-4-26b-a4b-it:latest list-model-profiles | grep -i 'mtp\|specul\|eagle'
```

## After-boot verification (confirm the model is serving properly)

Run these once the `gemma` pod is `Running` (namespace `nim-models`). They confirm
the NV-FP4 profile is active — no NGC key needed, it reads the already-cached model.

```bash
POD=$(kubectl -n nim-models get pod -l app.kubernetes.io/name=gemma -o name | head -1)   # or: get pod | grep gemma

# 1) The env we feed vLLM (expect the NV-FP4 profile hash + KV-cache reuse):
kubectl -n nim-models get deploy gemma -o yaml | grep -A1 -E 'NIM_MODEL_PROFILE|KV_CACHE|RELAX_MEM'

# 2) The served model + context length (id google/gemma-4-26B-A4B-it; max_model_len
#    is the profile default 262144 — see the max_model_len note below):
kubectl -n nim-models exec $POD -- curl -s localhost:8000/v1/models | python3 -m json.tool

# 3) The profile the NIM actually selected at boot (expect the nvfp4 fallback):
kubectl -n nim-models logs $POD | grep -iE 'selected profile|nvfp4|quantization' | head

# 4) No NIM profile is MTP-branded, so this returns NOTHING even though MTP
#    itself works — the drafter is bundled inside the nvfp4 profile at
#    /opt/nim/workspace/assistant, not exposed as its own profile entry. See
#    the MTP section below before treating this as "MTP unavailable":
kubectl -n nim-models exec $POD -- list-model-profiles 2>/dev/null | grep -iE 'mtp|specul|eagle'
```

If `/v1/models` reports a different id, the served profile/image drifted from
`google/gemma-4-26B-A4B-it`.

**max_model_len note:** it will read **262144** (the nvfp4 profile default), and
that is expected. `NIM_PASSTHROUGH_ARGS="--max-model-len N"` was tested on the T2
(2026-07-08) and is **ignored** by this NIM build — the engine ignores it
(`engine_extra_args max_model_len:None`, `max_seq_len=262144`). There is no
working env-level context cap today; capping would require patching
`/opt/nim/fallback.yaml` and re-validating. Corollary for anyone adding
speculative/MTP config: `NIM_PASSTHROUGH_ARGS` is not a reliable channel on this
build — verify with `curl /v1/models` (or the engine_extra_args log) that any arg
you set actually took effect.
