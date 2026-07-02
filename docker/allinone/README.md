# UneeQ + NVIDIA all-in-one (single-box Docker appliance)

The turnkey Dell-sellable bundle: one box, one `docker compose`, a working
digital human powered by the local NVIDIA stack — **no Flowise, no Kubernetes,
zero endpoint configuration** (everything is localhost).

```
Riva STT (localhost:8009) ─► Kiosk owns the conversation ─► Gemma NIM (localhost:8000)
                                      │   (+ inline buffer memory, persona prompt)
                                      └─► [optional] NVIDIA RAG (localhost:8081) for docs
                                      ▼
                              uneeq.speak(answer)  ─►  Renny (renders + animates <uneeq:> tags)
```

## Why it's zero-config
The kiosk's Chrome runs **on the box**, so every service is at `localhost` on a
fixed port. No IPs to enter, no HTTPS/Traefik needed (localhost is a Chrome
secure context, so even streaming works). Renny dials **out** to UneeQ DHOP, so
it needs no inbound ports.

## Quick start
```sh
cp .env.example .env          # fill NGC_API_KEY, PLATFORM_KEY, TENANT_ID, TTS key
docker login cr.uneeq.io      # UneeQ Harbor (Renny + kiosk + ws-proxy images)
./up.sh                       # core stack
# add document retrieval:
#   set RAG_COMPOSE in .env, then:  ./up.sh rag
```
Then set the **persona ID** in `kiosk/config.yaml`
(`brands.dell.personas.en.miniprem.id`) and `docker compose restart kiosk`.

## What runs (fixed localhost ports)
| Service | Port | Notes |
|---|---|---|
| Kiosk (nginx) | 80 | Chrome opens `http://localhost/` |
| Gemma NIM | 8000 | OpenAI chat-completions |
| Riva TTS | 9000 / 50051 | Renny can also use ElevenLabs/Azure |
| Riva STT ws-proxy | 8009 | `ws://localhost:8009/api/asr/v1/stream` |
| Renny | — | dials out to DHOP (cloud) |
| RAG server | 8081 | `--profile rag`: `/v1/generate`, `/v1/search` |
| nv-ingest / embed / rerank / milvus / es | 7670 / 8002 / 8004 / … | `--profile rag` |

## Conversation modes (in `kiosk/config.yaml`, editable in the kiosk Brain tab)
- `generation: nim` (default) — retrieve from RAG, **generate with the Gemma NIM**
  directly. Full prompt/persona/memory control. With no RAG profile, retrieval
  is skipped → pure LLM + buffer memory (proven on the T2).
- `generation: rag` — NVIDIA RAG bundled `/v1/generate` (server-side prompt).
- `memory: inline` — folds recent turns into the question so the digital human
  remembers names/context (NVIDIA RAG keeps none on its own; no Redis needed).

## Building the kiosk image
The kiosk image is built once from the `uneeq-kiosk` source (bakes the brand +
the conversation/RAG/Riva features), then the appliance just pulls it:
```sh
KIOSK_SRC=/path/to/uneeq-kiosk KIOSK_BRAND=dell kiosk/build-and-push.sh latest
```

## RAG profile
The NVIDIA RAG blueprint (rag-server + nv-ingest + Milvus + Elasticsearch +
embed + rerank) is heavy and maintained by NVIDIA. Clone it, point its LLM at
the local Gemma (`http://gemma:8000/v1`), set `RAG_COMPOSE` in `.env` to its
compose path, and run `./up.sh rag`. Documents are then managed from the kiosk
Brain tab (upload → nv-ingest) and answered with citations.

## ISO / Dell distribution
The `miniprem-autoinstall` ISO provisions the box (NVIDIA driver, Chrome kiosk),
drops this bundle in, and runs `./up.sh`. The per-customer brain config travels
as the kiosk **Brain-tab export JSON** (or this `kiosk/config.yaml`), so each
customer's persona/prompt/endpoints bake in. Secrets come from the ISO seed.

## Notes / validate-on-box
- NIM image tags (Gemma/Riva/embed/rerank) — confirm against your NGC entitlement.
- GPU/VRAM: Gemma-26B (~26GB) + Riva + embed/rerank + Renny must fit the card;
  size accordingly (RTX PRO 6000 96GB is comfortable).
- Renny gestures animate on ElevenLabs/Azure TTS; Riva TTS currently drops the
  `<uneeq:>` tags (upstream issue) — use ElevenLabs/Azure for the gesture demo.
