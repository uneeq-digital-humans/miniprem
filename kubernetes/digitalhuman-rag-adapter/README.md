# digitalhuman-rag-adapter

A tiny middleware that lets a UneeQ digital human (Renny) converse through the
local **NVIDIA RAG** stack — and lets us **drop Flowise** from the kiosk path.

It is a **Flowise-prediction-compatible facade** in front of NVIDIA RAG:

```
Kiosk ── STT ──► Renny ──(conversation endpoint set in UneeQ Admin Portal)──►  THIS ADAPTER
                                                                                   │
                       {question, history, overrideConfig:{sessionId}}             │ translate
                                                                                   ▼
                                          NVIDIA RAG  POST /v1/chat/completions
                                          {messages, use_knowledge_base, collection_name}
                                                                                   │
                       Flowise-style SSE  ◄── re-emit ◄── OpenAI SSE delta chunks ─┘
                                   │
                                   ▼
                       Renny → TTS → animates <uneeq:...> tags
```

Renny still owns TTS and animates the inline `<uneeq:action_* />` /
`<uneeq:emotion_*_* />` tags the model emits. **The adapter never strips or
rewrites those tags** — it passes the model output through verbatim.

## Why this exists
- UneeQ/Flowise speaks `POST /prompt/openai` (or `/api/v1/prediction/{id}`) with
  `{"question", "overrideConfig":{"sessionId"}}`.
- NVIDIA RAG speaks OpenAI `POST /v1/chat/completions` with `{"messages":[...]}`
  plus `use_knowledge_base` / `collection_name`.
- The adapter translates both directions (incl. SSE streaming) and adds:
  - **Persona prompt injection** — the digital-human system prompt (identity +
    emoji→UneeQ-tag rules), mounted from a ConfigMap and **editable from the
    kiosk Settings panel** with hot reload (no pod restart).
  - **Redis session memory** — keyed by `sessionId` so the digital human
    remembers context within a visit ("my name is Doug" → later recall).
    Degrades to stateless if Redis is absent.

## Endpoints
| Method | Path | Notes |
|---|---|---|
| POST | `/prompt/openai` | Primary conversation endpoint |
| POST | `/prompt/openai/{id}` | Dynamic id accepted (ignored) |
| POST | `/api/v1/prediction/{id}` | Flowise alias |
| GET | `/health` | RAG target, collection, redis status, prompt size |

Request (Flowise shape): `{"question": "...", "streaming": true,
"overrideConfig": {"sessionId": "...", "collectionName": "...",
"useKnowledgeBase": true}}`. Streaming replies are `text/event-stream` with
`data:{"event":"start|token|end|error","data":...}` frames.

## Configuration
All via env (see `app/config.py`); the Helm chart wires them from `values.yaml`.
Key ones: `RAG_BASE_URL`, `RAG_CHAT_PATH`, `RAG_MODEL`, `COLLECTION_NAME`,
`USE_KNOWLEDGE_BASE`, `REDIS_URL`, `PROMPT_FILE`, `STREAM_FORMAT`.

## Deploy (MiniPrem)
```sh
helm upgrade --install rag-adapter ./chart -n uneeq \
  --set rag.baseUrl=http://rag-server.advanced-rag.svc.cluster.local:8081 \
  --set rag.model=google/gemma-4-26B-A4B-it \
  --set rag.collectionName=multimodal_data
```
Then in the **UneeQ Admin Portal**, set the persona's conversation endpoint to:
`http://rag-adapter.uneeq.svc.cluster.local:8085/prompt/openai`

## Local dev
```sh
pip install -r requirements.txt
RAG_BASE_URL=http://localhost:8081 PROMPT_FILE=prompts/digital-human-system-prompt.md \
  uvicorn app.main:app --port 8085
```

## Tests
`tests/test_translate.py` proves the headline guarantee: UneeQ inline tags
survive translation + SSE re-emission. Run with `pytest`, or the dependency-free
smoke check in the repo notes.

## ⚠️ Required live validation before shipping
1. **Renny SSE compatibility.** The streaming frame format here matches Flowise's
   documented SSE. Confirm against a live Renny that tokens render and the stream
   closes cleanly. If Renny expects a different frame shape, set
   `STREAM_FORMAT=openai` or adjust `translate.sse_flowise`.
2. **Riva-TTS gesture bug (known, upstream).** Gesture tags animate correctly
   with ElevenLabs/Azure TTS but are dropped on **NVIDIA Riva TTS**. This is a
   Renny/Riva-side issue, *not* this adapter (the tags leave the adapter intact —
   see tests). Tracked with the UneeQ NZ platform team. Until patched, use
   ElevenLabs/Azure TTS for the gesture demo path.

## Alternative pattern (not used here): Direct Speak
The captured `{"action":"speak","data":{"prompt":"...<uneeq:action_wavehello />..."}}`
payloads are UneeQ **Direct Speak** (`docs/integrations/direct-speak.md`), where
an orchestrator composes text and pushes it to Renny over the data channel. We
chose the **Traditional** pattern (Renny calls this endpoint) because the goal is
to configure the conversation endpoint in the Admin Portal. If we later want
multi-output agentic flows, a Direct-Speak orchestrator can reuse the same
translation + session modules.
