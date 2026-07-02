# Kiosk architecture — RAG + Redis, and the remote-mic relay

Companion to [CHARTS.md](CHARTS.md). Two subsystems people most often ask about:
the conversation/RAG backend (with Redis memory) and the remote-mic proxy.

---

## 1. Conversation: RAG + Redis + NVIDIA

The **rag-adapter** is the middleware between the kiosk/renderer and NVIDIA's
retrieval + LLM. Two stores do two different jobs (commonly confused):

| Store | Role | Keyed by |
|---|---|---|
| **Milvus** (vector DB) | the **knowledge** — uploaded docs, chunked + embedded | collection |
| **Redis** | **short-term memory** — what was said *this visit* | `sessionId` |

Redis is NOT a vector store. It's the "remember within a visit" layer (names,
preferences, context) so a digital human can hold a coherent conversation.

### Per-turn flow (`_handle`)
1. **Parse** `{question, sessionId}` — `sessionId` is the UneeQ conversation thread.
2. **Redis fetch** — `store.history(sessionId)` → last *N* turns (`LRANGE`).
3. **System prompt** — `_effective_prompt()`: kiosk-edited persona override (stored
   in Redis) if present, else the ConfigMap persona file.
4. **Retrieve** (only if *Use knowledge base* is on) — embed the question with the
   **NVIDIA embedding NIM** (`nemoretriever-embedqa`), vector-search **Milvus** for
   top-k chunks.
5. **Assemble messages** = `[system + retrieved context]` + Redis history +
   inline history + `{user: question}`.
6. **Generate** — POST to the **Gemma NIM** (`LLM_URL`), streamed or not.
7. **Redis append** — `RPUSH` the (user, assistant) pair, `LTRIM` to the last N
   turns, `EXPIRE` (30-min idle TTL).

```
                         ┌─────────── rag-adapter ───────────┐
  kiosk / Renny  ──Q──▶  │ 1 parse  2 Redis history          │
  (sessionId)            │ 3 persona prompt                  │
                         │ 4 embed(Q) ─▶ Milvus top-k ◀─ docs│
                         │ 5 build messages                  │
                         │ 6 ─────────▶ Gemma NIM ──▶ answer │
                         │ 7 Redis append (TTL 30m)          │
                         └───────────────────────────────────┘
   Redis = memory (per sessionId)      Milvus = knowledge      Gemma NIM = generation
```

- **Modes:** `rag_mode: local` (adapter owns retrieval + calls the Gemma NIM directly —
  the all-in-one box) or `blueprint` (proxy to NVIDIA's full `rag-server`).
- **Graceful degradation:** no/unreachable Redis → stateless (conversations still work).
- Redis also persists the **kiosk-edited persona prompt** (survives pod restarts).
- All LLM calls are traced to **Phoenix** (OpenInference spans, keyed by sessionId).

---

## 2. Remote mic: the relay ("backend web proxy")

Goal: a visitor's **phone** drives the **kiosk's** digital human (no touching the screen).
Two backend pieces:

### (a) The WebSocket relay — the proxy
A **stateless message router** that pairs phone↔kiosk by id. Two options:
- **UneeQ-hosted** — AWS API-Gateway WebSocket + Lambda.
- **Self-hosted** — the on-box `remote-mic-relay` (`server.js`, dependency-free RFC-6455,
  runs from a ConfigMap on a stock node image; chart in `remote-mic-relay/`).

**Pairing handshake** (kiosk ActionFactory ⇄ relay ⇄ phone):
1. Kiosk opens the relay WS → relay assigns a random **`connectionId`**.
2. Kiosk encodes `connectionId` + relay `ws` URL + langs/mode/FAQs into the **QR**.
3. Phone scans → loads the kiosk's `/remote/:connectionId` page → connects to the
   **same relay** (`?ws=`) → `{type:'peerConnect', peerId:<kioskConnId>}`.
4. Relay pairs them → notifies the kiosk `{type:'RegisterRemote'}`.
5. Phone types/speaks → `{type:'peerMessage', peerId, payload}` → relay forwards
   `{type:'peerMessage', data}` to the kiosk → kiosk runs it through the DH
   (`chatPrompt` → LLM → `speak`).
6. Close/disconnect → `{CloseSession}` / `{PeerDisconnected}`.

```
   PHONE  ──peerConnect/peerMessage──▶  RELAY  ──forward──▶  KIOSK ──▶ digital human
   /remote/:id                      (routes by id)        (pairs by connectionId)
        ▲                                                      │
        └──────────── QR encodes connectionId + ws ◀───────────┘
```

The relay **only moves messages** — it is **STT-agnostic**. The phone's speech is
transcribed by the **kiosk-configured STT** (on-box Riva, or Deepgram), not the relay.

### (b) The HTTP token backend
`<httpEndpoint>/prod/service-token` — used **only** when STT = **Deepgram cloud**: the
phone fetches a **short-lived Deepgram token** so the raw key never ships to the browser.
Not used for Riva STT.

### Security + reachability
- Pairing = unguessable random `connectionId` + in-person QR + ephemeral session. The
  relay is a stateless multi-tenant router with **no per-kiosk auth** (self-hosted relay
  needs no key; only the Deepgram token backend uses the backend key).
- The relay handles *pairing*, but the phone must still **load `/remote` from a reachable
  host**: the **box LAN IP** for same-Wi-Fi phones (auto-derived from host-helper
  `/node-ip`), or a **public URL** for cellular. A `localhost` QR is never usable by a phone.
