"""UneeQ <-> NVIDIA RAG adapter.

A Flowise-prediction-compatible facade in front of the NVIDIA RAG server so the
UneeQ Admin Portal can point a persona's conversation endpoint straight at the
local RAG stack and drop Flowise. Renny still owns TTS and animates the inline
<uneeq:...> tags the model emits.

Conversation endpoints (accept the Flowise prediction body):
    POST /prompt/openai
    POST /prompt/openai/{id}
    POST /api/v1/prediction/{id}   (Flowise alias)

Kiosk admin endpoints (power the in-kiosk Settings panel):
    GET    /admin/prompt           -> current persona prompt (+ whether overridden)
    PUT    /admin/prompt           -> set persona prompt (rebrand the digital human)
    DELETE /admin/prompt           -> revert to the ConfigMap default
    GET    /admin/documents        -> list ingested RAG collections/documents
    POST   /admin/documents        -> upload a document into the RAG collection
    DELETE /admin/documents/{name} -> remove a document from the collection

    GET  /health
"""
from __future__ import annotations

import asyncio
import io
import json
import logging
import os
import re

from fastapi import FastAPI, File, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse

import httpx

from . import chunking, embeddings, llm, tracing, vectorstore
from .config import settings
from .http_client import close_shared_client, shared_client
from .prompt import prompt_store
from .rag_client import complete_chat, stream_chat
from .sessions import store
from .translate import (
    build_rag_payload,
    extract_token,
    flowise_final_json,
    parse_request,
    sse_flowise,
)

logging.basicConfig(level=settings.log_level.upper())
log = logging.getLogger("rag-adapter")

app = FastAPI(title="UneeQ NVIDIA RAG Adapter", version="0.2.0")

# CORS: the kiosk may call the conversation proxy / admin API cross-origin when the
# adapter is reached at an absolute URL (e.g. http://localhost:8085 from a kiosk
# served at http://localhost in the bridge-networked all-in-one appliance). On the
# host-networked box the kiosk uses a same-origin nginx /v1/ proxy and this is moot.
# Default "*" is fine: the adapter is an on-box service, and /admin/* has its own
# password gate. Restrict via CORS_ALLOW_ORIGINS (comma-separated) if desired.
_cors = os.getenv("CORS_ALLOW_ORIGINS", "*").strip()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if _cors == "*" else [o.strip() for o in _cors.split(",") if o.strip()],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def _init_tracing() -> None:
    """Wire up OpenInference -> Phoenix tracing for the conversation proxy."""
    tracing.init()


@app.on_event("shutdown")
async def _close_http_pool() -> None:
    """Drain the shared httpx connection pool (see http_client.py)."""
    await close_shared_client()


async def _effective_prompt() -> str:
    """Kiosk-edited persona prompt if set, else the ConfigMap default."""
    override = await store.get_prompt_override()
    return override or prompt_store.text


def _check_admin(authorization: str | None) -> None:
    """Enforce the optional admin shared secret on /admin/* routes."""
    if not settings.admin_api_key:
        return  # open (on-box kiosk only)
    expected = f"Bearer {settings.admin_api_key}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="invalid admin credentials")


def _strip_repeated_lines(md: str) -> str:
    """Remove lines that repeat many times across the doc (page headers/footers)."""
    from collections import Counter
    lines = md.splitlines()
    counts = Counter(l.strip() for l in lines if l.strip())
    boiler = {l for l, n in counts.items() if n >= 3 and len(l) <= 120}
    out, blanks = [], 0
    for l in lines:
        if l.strip() in boiler:
            continue
        if not l.strip():
            blanks += 1
            if blanks > 1:
                continue
        else:
            blanks = 0
        out.append(l)
    return "\n".join(out).strip()


def _to_markdown(content: bytes, filename: str) -> str:
    """Convert an uploaded file to clean markdown. Plain text passes through."""
    name = (filename or "upload").lower()
    if name.endswith((".txt", ".md", ".markdown")):
        return content.decode("utf-8", errors="replace")
    from markitdown import MarkItDown  # lazy import
    ext = "." + name.rsplit(".", 1)[-1] if "." in name else ""
    result = MarkItDown().convert_stream(io.BytesIO(content), file_extension=ext)
    return _strip_repeated_lines(result.text_content or "")


async def _retrieve(question: str, collection: str, k: int | None = None):
    """Top-k chunks for the question. PREFERS the RAG server's /v1/search — it is
    schema/metric-agnostic and fast (~100 ms) for blueprint-created collections,
    where a raw Milvus search from here fails with a metric mismatch (COSINE vs L2)
    only after Milvus burns ~6 SECONDS retrying internally. That 6 s hit every chat
    AND voice turn ("slow and not referencing"). Falls back to embed+Milvus for
    adapter-schema (legacy) collections or when the RAG server is down. Best-effort:
    degrade to NO context within bounded time rather than stall the turn."""
    top_k = k or 4
    if settings.rag_base_url:
        try:
            async with httpx.AsyncClient(timeout=6) as client:
                r = await client.post(
                    f"{settings.rag_base_url.rstrip('/')}/v1/search",
                    json={"query": question, "collection_names": [collection],
                          "top_k": top_k},
                )
            if r.status_code == 200:
                hits = []
                for res in r.json().get("results", []):
                    if res.get("document_type", "text") == "text":
                        # text chunk: the content IS the text
                        text = res.get("content") or ""
                    else:
                        # image/chart/table element: content is base64 pixels —
                        # useless as LLM context. Use the VLM caption written at
                        # ingest time (metadata.description) so facts that only
                        # exist INSIDE images (OCR-style) are still answerable.
                        text = (res.get("metadata") or {}).get("description") or ""
                        if text:
                            text = f"(from an image in this document) {text}"
                    if text:
                        hits.append({"doc_name": res.get("document_name", "?"),
                                     "text": text,
                                     "score": res.get("score", 0.0)})
                if hits:
                    return hits[:top_k]
        except Exception as exc:
            log.warning("rag-server search failed (%s) — trying direct store", exc)
    try:
        qvec = await asyncio.wait_for(
            embeddings.embed_one(question, input_type="query"), timeout=8
        )
        return await asyncio.wait_for(
            asyncio.to_thread(vectorstore.search, collection, qvec, k), timeout=8
        )
    except Exception as exc:
        log.warning("retrieval unavailable (%s) — answering without knowledge base", exc)
        return []


def _augmented_system(system_prompt: str, hits: list[dict]) -> str:
    """Fold retrieved context into the persona/system prompt."""
    if not hits:
        return system_prompt
    ctx = "\n\n".join(
        f"[{i+1}] (source: {h.get('doc_name','?')})\n{h.get('text','')}"
        for i, h in enumerate(hits)
    )
    return (
        f"{system_prompt}\n\n"
        "Use the following retrieved context to answer the user's question. "
        "If the answer is not contained in the context, say you don't have that "
        "information rather than guessing.\n\n"
        f"<context>\n{ctx}\n</context>"
    )


# --------------------------------------------------------------------------- #
# Conversation
# --------------------------------------------------------------------------- #

async def _handle(body: dict):
    question, inline_history, session_id, streaming, override = parse_request(body)
    if not question:
        return JSONResponse({"error": "missing 'question'"}, status_code=400)

    remembered = await store.history(session_id)
    system_prompt = await _effective_prompt()

    # Phoenix span context for the MiniPrem/Renny conversation path (persona's
    # endpoint -> /prompt/openai). Same OpenInference spans + session as the kiosk's
    # /v1/chat/completions, so BOTH entrypoints to the local NVIDIA model are traced.
    _model = await _served_model() or settings.llm_model
    _params = {
        "temperature": settings.temperature,
        "top_p": settings.top_p,
        "max_tokens": settings.max_tokens,
    }
    _span_name = os.getenv("SPAN_NAME", "chat")

    # ---- Local RAG path: retrieve from Milvus Lite + answer with local LLM ----
    if settings.rag_mode == "local":
        collection = override.get("collectionName", settings.collection_name)
        use_kb = override.get("useKnowledgeBase", _effective_use_kb())
        hits = await _retrieve(question, collection) if use_kb else []
        log.info(
            "local-rag session=%s stream=%s coll=%s hits=%d q=%r",
            session_id, streaming, collection, len(hits), question[:80],
        )
        messages = [{"role": "system", "content": _augmented_system(system_prompt, hits)}]
        messages.extend(remembered)
        messages.extend(inline_history)
        messages.append({"role": "user", "content": question})

        span = tracing.start_llm_span(
            _model, messages, _params, session_id=session_id,
            span_name=_span_name, metadata={"source": "prompt", "mode": "local"},
        )
        if not streaming:
            try:
                answer = await llm.generate(messages)
            except Exception as exc:
                tracing.fail_llm_span(span, exc)
                raise
            tracing.end_llm_span(span, answer)
            await store.append(session_id, question, answer)
            return JSONResponse(flowise_final_json(answer, question, inline_history))

        async def local_stream():
            collected: list[str] = []
            yield sse_flowise("start", "")
            try:
                async for tok in llm.stream(messages):
                    collected.append(tok)
                    yield sse_flowise("token", tok)
                tracing.end_llm_span(span, "".join(collected))
            except Exception as exc:
                log.exception("local RAG stream failed")
                tracing.fail_llm_span(span, exc)
                yield sse_flowise("error", str(exc))
            await store.append(session_id, question, "".join(collected))
            yield sse_flowise("end", "[DONE]")

        return StreamingResponse(local_stream(), media_type="text/event-stream")

    # ---- Blueprint path: proxy to a full NVIDIA RAG server --------------------
    payload = build_rag_payload(
        question, remembered, inline_history, streaming, override, system_prompt,
        use_kb_default=_effective_use_kb(),
    )
    log.info(
        "prompt session=%s stream=%s kb=%s coll=%s q=%r",
        session_id, streaming, payload["use_knowledge_base"],
        payload["collection_name"], question[:80],
    )

    _bp_messages = (
        [{"role": "system", "content": system_prompt}]
        + remembered + inline_history + [{"role": "user", "content": question}]
    )
    span = tracing.start_llm_span(
        _model, _bp_messages, _params, session_id=session_id,
        span_name=_span_name, metadata={"source": "prompt", "mode": "blueprint"},
    )
    if not streaming:
        try:
            resp = await complete_chat(payload)
        except Exception as exc:
            tracing.fail_llm_span(span, exc)
            raise
        answer = extract_token(resp)
        tracing.end_llm_span(span, answer)
        await store.append(session_id, question, answer)
        return JSONResponse(flowise_final_json(answer, question, inline_history))

    async def event_stream():
        collected: list[str] = []
        yield sse_flowise("start", "")
        try:
            async for chunk in stream_chat(payload):
                token = extract_token(chunk)
                if token:
                    collected.append(token)
                    yield sse_flowise("token", token)
            tracing.end_llm_span(span, "".join(collected))
        except Exception as exc:  # surface backend failures to the client
            log.exception("RAG stream failed")
            tracing.fail_llm_span(span, exc)
            yield sse_flowise("error", str(exc))
        answer = "".join(collected)
        await store.append(session_id, question, answer)
        yield sse_flowise("end", "[DONE]")

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@app.post("/prompt/openai")
async def prompt_openai(request: Request):
    return await _handle(await request.json())


@app.post("/prompt/openai/{flow_id}")
async def prompt_openai_id(flow_id: str, request: Request):
    return await _handle(await request.json())


@app.post("/api/v1/prediction/{flow_id}")
async def flowise_prediction(flow_id: str, request: Request):
    return await _handle(await request.json())


# --------------------------------------------------------------------------- #
# Instrumented OpenAI-compatible proxy (kiosk "Local/NVIDIA" conversation path)
# --------------------------------------------------------------------------- #
# The kiosk SPA (ConversationService.ts, generation="nim") owns the conversation
# and POSTs OpenAI chat-completions to the same-origin /v1/chat/completions. When
# the kiosk nginx points /v1/ at this adapter (instead of straight at vLLM), each
# call is proxied transparently to the local vLLM *and* recorded as an
# OpenInference LLM span -> Phoenix (full prompt + answer + token usage), so the
# conversation history is readable/sortable in the Phoenix UI. vLLM's own
# gen_ai spans (no text) are unaffected and stay in the "default" project.

_PROXY_PARAM_KEYS = (
    "temperature", "top_p", "max_tokens", "n", "stop",
    "frequency_penalty", "presence_penalty", "seed", "response_format",
)

# Served-model auto-discovery: ask the upstream NIM/vLLM's /v1/models once and
# cache it, so the conversation + Phoenix tracing work for ANY model the box runs
# (NOT a hardcoded gemma4). The kiosk's configured model name becomes irrelevant —
# we normalise each request to whatever the NIM actually serves, so swapping the
# NIM (different Gemma, Llama, Nemotron, …) needs no kiosk/adapter config change.
# Set LLM_MODEL_AUTODISCOVER=false to instead trust the request's model verbatim.
_served_model_cache: dict = {"id": None}
_AUTODISCOVER = os.getenv("LLM_MODEL_AUTODISCOVER", "true").strip().lower() in {"1", "true", "yes", "on"}


async def _served_model() -> str | None:
    """First model id reported by the upstream's /v1/models (cached)."""
    if not _AUTODISCOVER:
        return None
    if _served_model_cache["id"]:
        return _served_model_cache["id"]
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(settings.llm_url.rstrip("/") + "/v1/models")
            r.raise_for_status()
            data = r.json().get("data") or []
            if data:
                _served_model_cache["id"] = data[0].get("id")
                log.info("discovered served LLM model: %s", _served_model_cache["id"])
    except Exception:
        log.warning("served-model discovery failed; using request/config model")
    return _served_model_cache["id"]


_IMG_TAG_RE = re.compile(
    r'(.*?)<img\s+src="data:image/([a-zA-Z0-9.+-]+);base64,([^"]+)"\s*/?>', re.S
)


@app.post("/caption/v1/chat/completions")
async def caption_shim(request: Request):
    """VLM-caption format shim for nv-ingest → Gemma NIM.

    nv-ingest's VLMModelInterface (APP_NVINGEST_CAPTIONENDPOINTURL) speaks the
    NVIDIA-VLM dialect: ONE user message PER IMAGE, each a plain string
    '{prompt} <img src="data:image/png;base64,..." />', and expects ONE choice
    per image back. OpenAI-style NIMs (our Gemma) do NOT parse that tag — the
    base64 reaches the model as literal text and every caption comes back as
    hallucinated garbage ("a light blue block"), which then poisons the image
    element's embedding. This endpoint rewrites each message into proper
    OpenAI `image_url` content parts, captions the images concurrently against
    LLM_URL, and returns choices in message order.
    """
    body = await request.json()
    served = await _served_model()
    model = served or body.get("model") or settings.llm_model
    upstream = settings.llm_url.rstrip("/") + "/v1/chat/completions"

    async def _caption_one(client: httpx.AsyncClient, content: str) -> str:
        m = _IMG_TAG_RE.match(content or "")
        if not m:  # no image tag — pass the text through as a normal prompt
            parts = [{"type": "text", "text": content or ""}]
        else:
            prompt, mime, b64 = m.group(1).strip(), m.group(2), m.group(3)
            parts = [
                {"type": "image_url",
                 "image_url": {"url": f"data:image/{mime};base64,{b64}"}},
                {"type": "text", "text": prompt or "Caption the content of this image:"},
            ]
        r = await client.post(upstream, json={
            "model": model,
            "messages": [{"role": "user", "content": parts}],
            "max_tokens": body.get("max_tokens", 512),
            # 0 for faithful transcription — nv-ingest defaults temperature=1.0,
            # which is exactly wrong for OCR-style captioning.
            "temperature": 0.0,
        })
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]

    messages = body.get("messages") or []
    try:
        client = shared_client()
        captions = await asyncio.gather(
            *(_caption_one(client, m.get("content")) for m in messages)
        )
    except Exception as exc:
        log.warning("caption shim failed: %s", exc)
        return JSONResponse({"error": f"caption shim: {exc}"}, status_code=502)
    log.info("caption shim: captioned %d image(s)", len(captions))
    return {
        "id": "caption-shim",
        "object": "chat.completion",
        "model": model,
        "choices": [
            {"index": i, "message": {"role": "assistant", "content": c},
             "finish_reason": "stop"}
            for i, c in enumerate(captions)
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions_proxy(request: Request):
    body = await request.json()
    messages = body.get("messages") or []
    stream = bool(body.get("stream"))

    # ---- Kiosk RAG (on-box Milvus Lite) ------------------------------------
    # The kiosk's /v1 chat is a plain LLM call by default. When the knowledge base
    # is on, retrieve the top chunks for the latest user turn from the kiosk-OWNED
    # Milvus-Lite store and inject them as context — so the digital human answers
    # from documents uploaded through the kiosk. No NVIDIA RAG blueprint, no
    # nv-ingest; identical on kubeadm and docker.
    if settings.rag_mode == "local" and body.get("use_knowledge_base", _effective_use_kb()) and messages:
        collection = body.get("collection_name") or (body.get("collection_names") or [settings.collection_name])[0]
        last_user = next((m.get("content", "") for m in reversed(messages) if m.get("role") == "user"), "")
        if last_user:
            try:
                hits = await _retrieve(last_user, collection)
            except Exception as exc:
                hits = []
                log.warning("kiosk-rag retrieve failed coll=%s: %s", collection, exc)
            if hits:
                ctx_msg = {"role": "system", "content": _augmented_system("", hits).strip()}
                idx = next((i for i, m in enumerate(messages) if m.get("role") == "system"), -1)
                messages.insert(idx + 1, ctx_msg)
                body["messages"] = messages
                log.info("kiosk-rag: injected %d chunks from '%s'", len(hits), collection)
    # Adapter-level fields must NOT reach the upstream NIM — they are ours, not
    # OpenAI's (a strict server could reject the request). The kiosk sends
    # use_knowledge_base=false explicitly when the BROWSER already retrieved
    # (collection checkboxes live there); absence falls back to the server flag.
    for _kb_key in ("use_knowledge_base", "collection_name", "collection_names"):
        body.pop(_kb_key, None)
    # Normalise the model to whatever the NIM serves (model-agnostic); fall back to
    # the request's model, then the configured default.
    served = await _served_model()
    model = served or body.get("model") or settings.llm_model
    body["model"] = model
    params = {k: body[k] for k in _PROXY_PARAM_KEYS if k in body}
    upstream = settings.llm_url.rstrip("/") + "/v1/chat/completions"

    # Conversation context for Phoenix grouping/labels. The kiosk can send these
    # headers (graceful if absent); session id also falls back to the OpenAI `user`
    # field. The session id is the shared thread the kiosk's STT/speak spans reuse.
    h = request.headers
    session_id = h.get("x-session-id") or body.get("user")
    persona = h.get("x-persona")
    language = h.get("x-language")
    # Stable, readable span title for the kiosk LLM chat. The persona varies (and
    # may be unset), so it's recorded in metadata — NOT baked into the title.
    # Override the label via the SPAN_NAME env if a deployment wants a custom one.
    span_name = os.getenv("SPAN_NAME", "chat")
    span = tracing.start_llm_span(
        model, messages, params,
        session_id=session_id,
        user_id=body.get("user"),
        metadata={"persona": persona, "language": language},
        span_name=span_name,
    )

    # ---- Non-streaming: forward, capture answer + usage, return verbatim -----
    if not stream:
        try:
            resp = await shared_client().post(upstream, json=body)
        except Exception as exc:
            tracing.fail_llm_span(span, exc)
            raise
        answer, usage = "", None
        try:
            data = resp.json()
            answer = (data.get("choices") or [{}])[0].get("message", {}).get("content") or ""
            usage = data.get("usage")
        except Exception:
            pass
        tracing.end_llm_span(span, answer, usage)
        return Response(
            content=resp.content,
            status_code=resp.status_code,
            media_type=resp.headers.get("content-type", "application/json"),
        )

    # ---- Streaming: passthrough SSE bytes; parse a copy for the span ---------
    # Ask vLLM to append a usage chunk so token counts land on the span. The
    # kiosk's SSE reader ignores chunks with no delta.content, so it's harmless.
    body.setdefault("stream_options", {"include_usage": True})

    async def gen():
        buf, collected, usage = "", [], None
        try:
            async with shared_client().stream(
                "POST", upstream, json=body,
                headers={"Accept": "text/event-stream"},
            ) as resp:
                async for chunk in resp.aiter_bytes():
                    yield chunk  # transparent passthrough to the kiosk
                    buf += chunk.decode("utf-8", "ignore")
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        line = line.strip()
                        if not line.startswith("data:"):
                            continue
                        payload = line[len("data:"):].strip()
                        if not payload or payload == "[DONE]":
                            continue
                        try:
                            j = json.loads(payload)
                        except Exception:
                            continue
                        tok = (j.get("choices") or [{}])[0].get("delta", {}).get("content")
                        if tok:
                            collected.append(tok)
                        if j.get("usage"):
                            usage = j["usage"]
        except Exception as exc:
            log.exception("chat-completions proxy stream failed")
            tracing.fail_llm_span(span, exc)
            raise
        finally:
            tracing.end_llm_span(span, "".join(collected), usage)

    return StreamingResponse(gen(), media_type="text/event-stream")


# --------------------------------------------------------------------------- #
# Admin: persona prompt management (kiosk Settings panel "rebrand" feature)
# --------------------------------------------------------------------------- #

@app.get("/admin/prompt")
async def get_prompt(authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    override = await store.get_prompt_override()
    return {
        "prompt": override or prompt_store.text,
        "is_override": override is not None,
        "persisted": store.enabled,  # false => edits can't be saved (no Redis)
    }


@app.put("/admin/prompt")
async def put_prompt(request: Request, authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    body = await request.json()
    text = (body.get("prompt") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="missing 'prompt'")
    if not await store.set_prompt_override(text):
        raise HTTPException(
            status_code=503,
            detail="prompt edits require Redis session memory to persist",
        )
    return {"ok": True, "is_override": True}


@app.delete("/admin/prompt")
async def delete_prompt(authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    await store.clear_prompt_override()
    return {"ok": True, "is_override": False, "prompt": prompt_store.text}


# --------------------------------------------------------------------------- #
# Admin: document management — embedded RAG (markitdown -> chunk -> embed ->
# Milvus Lite). Powers the kiosk Brain-tab knowledge-base manager.
# --------------------------------------------------------------------------- #

@app.get("/admin/documents")
async def list_documents(
    collection: str | None = None,
    authorization: str | None = Header(default=None),
):
    _check_admin(authorization)
    coll = collection or settings.collection_name
    docs: list[dict] = []
    # Blueprint-ingested documents: the ingestor's own listing is authoritative and
    # schema-agnostic. Without this, docs ingested via nv-ingest are INVISIBLE here —
    # the blueprint's Milvus schema doesn't carry the adapter's legacy field names, so
    # the direct-store query below returns nothing for them ("uploaded but not listed").
    if settings.ingestor_url:
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(
                    f"{settings.ingestor_url.rstrip('/')}/v1/documents",
                    params={"collection_name": coll},
                )
                if r.status_code == 200:
                    for d in r.json().get("documents", []):
                        name = d.get("document_name") or ""
                        if name:
                            docs.append({"name": name, "chunks": None})
        except Exception as exc:
            log.warning("ingestor document listing failed (%s) — falling back to direct store", exc)
    # Direct-store listing (legacy/markdown-embedded docs) — merge, dedupe by name.
    try:
        legacy = await asyncio.to_thread(vectorstore.list_docs, coll)
    except Exception:
        legacy = []
    seen = {d["name"] for d in docs}
    docs += [d for d in legacy if d.get("name") not in seen]
    for d in docs:
        d["has_original"] = _os_mod.path.exists(_original_path(coll, d["name"]))
    return {"collection": coll, "documents": docs}


# Original uploads are retained under /data/originals/<collection>/<name> so the
# kiosk can offer "download original" alongside the extracted markdown.
import os as _os_mod

_ORIGINALS_ROOT = "/data/originals"


def _safe_name(name: str) -> str:
    return _os_mod.path.basename(name or "upload").replace("/", "_").replace("\\", "_")


def _original_path(coll: str, name: str) -> str:
    safe_coll = _safe_name(coll)
    d = _os_mod.path.join(_ORIGINALS_ROOT, safe_coll)
    return _os_mod.path.join(d, _safe_name(name))


def _save_original(coll: str, name: str, content: bytes) -> None:
    try:
        p = _original_path(coll, name)
        _os_mod.makedirs(_os_mod.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(content)
    except Exception:
        log.exception("could not retain original for %s", name)


# --- Upload progress (staged per-file indicator for the kiosk) --------------
# The kiosk POSTs a file and polls /admin/documents/progress to show
# uploading -> parsing -> embedding -> storing -> done. In-memory (the adapter is
# a single replica); terminal entries are pruned after a short TTL.
import time as _time

_upload_progress: dict[str, dict] = {}
_PROGRESS_TTL_S = 180.0


def _prog_key(coll: str, name: str) -> str:
    return f"{coll}/{name}"


def _set_progress(coll: str, name: str, stage: str, **extra) -> None:
    _upload_progress[_prog_key(coll, name)] = {"stage": stage, "ts": _time.time(), **extra}
    cutoff = _time.time() - _PROGRESS_TTL_S
    for k in [k for k, v in _upload_progress.items()
              if v.get("stage") in ("done", "error") and v.get("ts", 0) < cutoff]:
        _upload_progress.pop(k, None)


@app.get("/admin/documents/progress")
async def upload_progress(collection: str | None = None, name: str = "",
                          authorization: str | None = Header(default=None)):
    """Current stage for an in-flight (or just-finished) upload, for the kiosk's
    staged indicator. Returns {"stage": "idle"} if unknown."""
    _check_admin(authorization)
    coll = collection or settings.collection_name
    return _upload_progress.get(_prog_key(coll, name), {"stage": "idle"})


@app.post("/admin/documents")
async def upload_document(
    file: UploadFile = File(...),
    collection: str | None = None,
    authorization: str | None = Header(default=None),
):
    _check_admin(authorization)
    coll = collection or settings.collection_name
    fname = file.filename or "upload"
    _set_progress(coll, fname, "parsing")
    content = await file.read()

    # Preferred path: route through the NVIDIA RAG blueprint's ingestion server so the
    # document REGISTERS in the blueprint (visible in rag-frontend) AND embeds into the
    # shared Milvus collection. Falls back to the adapter's own embed path if no
    # ingestor is configured or the call fails (so a stand-alone kiosk still works).
    if settings.ingestor_url:
        import json as _json
        # blocking=False: the ingestor accepts the file and runs nv-ingest ASYNC, then
        # registers the doc. A blocking call holds the HTTP request through the whole
        # (slow) pipeline and 504s at the ingress. The kiosk shows "processing"; the doc
        # appears in the blueprint once nv-ingest finishes.
        # FULL payload shape — the ingestor silently rejects the request if
        # custom_metadata / generate_summary are omitted (returns no task_id).
        data = _json.dumps({"collection_name": coll, "blocking": False,
                            "split_options": {"chunk_size": 512, "chunk_overlap": 150},
                            # Full multimodal extraction — without this the ingestor's
                            # defaults skip image OCR, so scanned/image-only PDFs yield
                            # "No records with Embeddings to insert" and silently fail.
                            "extraction_options": {"extract_text": True,
                                                    "extract_tables": True,
                                                    "extract_charts": True,
                                                    "extract_images": True,
                                                    "extract_infographics": True},
                            "custom_metadata": [], "generate_summary": False})
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                r = await client.post(
                    f"{settings.ingestor_url.rstrip('/')}/v1/documents",
                    files={"documents": (fname, content)}, data={"data": data})
            if r.status_code >= 300:
                raise RuntimeError(f"ingestor HTTP {r.status_code}: {r.text[:200]}")
            await asyncio.to_thread(_save_original, coll, fname, content)
            _set_progress(coll, fname, "processing")   # async ingest; registers when done
            log.info("submitted %s to blueprint ingestor (async) for %s", fname, coll)
            return {"ok": True, "document": fname, "collection": coll, "via": "ingestor", "status": "processing"}
        except Exception as exc:
            log.warning("ingestor upload failed for %s (%s) — falling back to direct embed", fname, exc)

    try:
        md = await asyncio.to_thread(_to_markdown, content, fname)
    except Exception as exc:
        _set_progress(coll, fname, "error", error=str(exc))
        log.exception("convert failed for %s", fname)
        raise HTTPException(status_code=415, detail=f"Could not read {fname}: {exc}")
    chunks = chunking.chunk_text(md)
    if not chunks:
        _set_progress(coll, fname, "error", error="no text")
        raise HTTPException(status_code=400, detail="document produced no text")
    _set_progress(coll, fname, "embedding", chunks=len(chunks))
    vectors = await embeddings.embed(chunks, input_type="passage")
    _set_progress(coll, fname, "storing", chunks=len(chunks))
    n = await asyncio.to_thread(vectorstore.ingest, coll, fname, chunks, vectors)
    await asyncio.to_thread(_save_original, coll, fname, content)
    _set_progress(coll, fname, "done", chunks=n)
    log.info("ingested %s -> %d chunks into %s", fname, n, coll)
    return {"ok": True, "document": fname, "chunks": n, "collection": coll}


@app.get("/admin/documents/{name}/original")
async def document_original(
    name: str,
    collection: str | None = None,
    authorization: str | None = Header(default=None),
):
    """Download the original uploaded file (if retained)."""
    _check_admin(authorization)
    coll = collection or settings.collection_name
    p = _original_path(coll, name)
    if not _os_mod.path.exists(p):
        raise HTTPException(status_code=404, detail="original not retained (uploaded before retention, or removed)")
    return FileResponse(p, filename=_safe_name(name))


@app.delete("/admin/documents/{name}")
async def delete_document(
    name: str,
    collection: str | None = None,
    authorization: str | None = Header(default=None),
):
    _check_admin(authorization)
    coll = collection or settings.collection_name
    deleted = await asyncio.to_thread(vectorstore.delete_doc, coll, name)
    try:
        p = _original_path(coll, name)
        if _os_mod.path.exists(p):
            _os_mod.remove(p)
    except Exception:
        log.exception("could not remove original for %s", name)
    return {"ok": True, "deleted": name, "chunks_removed": deleted, "collection": coll}


# ---------------------------------------------------------------------------
# Idle-video library: multiple looping standby videos stored on the box. Each is
# audio-stripped on ingest (ffmpeg -an) so nothing ever plays sound on the kiosk
# idle screen, and a JPEG thumbnail is generated for the picker. The file/thumb
# GETs are intentionally UNAUTHENTICATED so the kiosk's <video>/<img> tags (which
# can't send an auth header) can load them; list/upload/delete stay admin-gated.
# ---------------------------------------------------------------------------
STANDBY_DIR = "/data/standby"
STANDBY_INDEX = "/data/standby/index.json"


def _standby_load() -> list:
    import json as _json
    try:
        with open(STANDBY_INDEX) as f:
            return _json.load(f)
    except Exception:
        return []


def _standby_save(items: list) -> None:
    import os as _os, json as _json
    _os.makedirs(STANDBY_DIR, exist_ok=True)
    with open(STANDBY_INDEX, "w") as f:
        _json.dump(items, f)


def _standby_paths(vid: str, ext: str) -> tuple[str, str]:
    import os as _os
    return _os.path.join(STANDBY_DIR, vid + ext), _os.path.join(STANDBY_DIR, vid + ".jpg")


@app.post("/admin/standby-videos")
async def upload_standby_video(
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
):
    """Ingest an idle/standby video: strip its audio track and generate a thumbnail.
    Returns the library entry {id, name, url, thumb}."""
    _check_admin(authorization)
    import os as _os, uuid as _uuid, subprocess as _sp
    name = file.filename or "video.mp4"
    ext = ("." + name.rsplit(".", 1)[-1].lower()) if "." in name else ".mp4"
    if ext not in (".mp4", ".webm"):
        # NOTE: only browser-playable containers. AVI won't play in an HTML5
        # <video> element, so we don't accept it (would need transcoding).
        raise HTTPException(415, "use .mp4 or .webm (AVI can't play in a browser)")
    vid = _uuid.uuid4().hex[:12]
    _os.makedirs(STANDBY_DIR, exist_ok=True)
    tmp = _os.path.join(STANDBY_DIR, f"_up_{vid}{ext}")
    out, thumb = _standby_paths(vid, ext)
    with open(tmp, "wb") as f:
        f.write(await file.read())
    # Strip audio (-an). Try a fast stream-copy first; fall back to re-encode.
    faststart = ["-movflags", "+faststart"] if ext == ".mp4" else []
    try:
        _sp.run(["ffmpeg", "-y", "-i", tmp, "-an", "-c:v", "copy", *faststart, out],
                check=True, capture_output=True, timeout=180)
    except Exception:
        try:
            _sp.run(["ffmpeg", "-y", "-i", tmp, "-an", *faststart, out],
                    check=True, capture_output=True, timeout=300)
        except Exception:
            log.exception("ffmpeg audio-strip failed for %s", name)
            try: _os.remove(tmp)
            except Exception: pass
            raise HTTPException(422, "could not process video (ffmpeg failed)")
    # First-frame thumbnail (best-effort).
    try:
        _sp.run(["ffmpeg", "-y", "-i", out, "-ss", "00:00:01", "-vframes", "1",
                 "-vf", "scale=320:-1", thumb], check=True, capture_output=True, timeout=60)
    except Exception:
        log.warning("thumbnail generation failed for %s (continuing)", vid)
    try: _os.remove(tmp)
    except Exception: pass
    items = _standby_load()
    items.append({"id": vid, "name": name, "ext": ext})
    _standby_save(items)
    return {"ok": True, "id": vid, "name": name,
            "url": f"/rag-admin/admin/standby-videos/{vid}",
            "thumb": f"/rag-admin/admin/standby-videos/{vid}/thumb"}


@app.get("/admin/standby-videos")
async def list_standby_videos(authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    return [
        {"id": it["id"], "name": it.get("name", it["id"]),
         "url": f"/rag-admin/admin/standby-videos/{it['id']}",
         "thumb": f"/rag-admin/admin/standby-videos/{it['id']}/thumb"}
        for it in _standby_load()
    ]


@app.get("/admin/standby-videos/{vid}")
async def get_standby_video(vid: str):
    """Serve the (audio-stripped) video file. Unauthenticated — loaded by the
    kiosk's <video src>."""
    import os as _os
    for it in _standby_load():
        if it["id"] == vid:
            p, _ = _standby_paths(vid, it["ext"])
            if _os.path.exists(p):
                return FileResponse(p, media_type="video/mp4" if it["ext"] == ".mp4" else "video/webm")
    raise HTTPException(404, "no such standby video")


@app.get("/admin/standby-videos/{vid}/thumb")
async def get_standby_thumb(vid: str):
    """Serve the JPEG thumbnail. Unauthenticated — loaded by the picker's <img src>."""
    import os as _os
    _, thumb = _standby_paths(vid, ".jpg")
    if _os.path.exists(thumb):
        return FileResponse(thumb, media_type="image/jpeg")
    raise HTTPException(404, "no thumbnail")


@app.delete("/admin/standby-videos/{vid}")
async def delete_standby_video(vid: str, authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    import os as _os
    items = _standby_load()
    keep, removed = [], None
    for it in items:
        if it["id"] == vid:
            removed = it
        else:
            keep.append(it)
    if removed is None:
        raise HTTPException(404, "no such standby video")
    for p in _standby_paths(vid, removed["ext"]):
        try:
            if _os.path.exists(p):
                _os.remove(p)
        except Exception:
            log.warning("could not remove %s", p)
    _standby_save(keep)
    return {"ok": True, "deleted": vid}


# --- Settings password (MiniPrem) -----------------------------------------
# Verified server-side so it (a) works over LAN, and (b) is resettable from the
# terminal (delete /data/settings-password.json → reverts to the default).
# The factory default is 'digitalhuman' unless the installer/ISO sets a custom
# one via the KIOSK_SETTINGS_PASSWORD env var on this container.
_PW_FILE = "/data/settings-password.json"
import os as _os_pw
_PW_DEFAULT = _os_pw.environ.get("KIOSK_SETTINGS_PASSWORD", "digitalhuman")


def _pw_hash(pw: str) -> str:
    import hashlib
    return hashlib.sha256(pw.encode("utf-8")).hexdigest()


@app.post("/admin/verify-settings-password")
async def verify_settings_password(body: dict):
    import os as _os, json as _json, time as _time
    pw = (body or {}).get("password", "")
    stored = None
    if _os.path.exists(_PW_FILE):
        try:
            stored = _json.load(open(_PW_FILE)).get("hash")
        except Exception:
            stored = None
    ok = (_pw_hash(pw) == stored) if stored else (pw == _PW_DEFAULT)
    if not ok:
        # Throttle guesses WITHOUT blocking the event loop: time.sleep() here
        # froze every in-flight SSE stream/health probe for 0.4s per bad attempt.
        await asyncio.sleep(0.4)
        raise HTTPException(401, "invalid password")
    return {"ok": True, "isDefault": stored is None}


@app.post("/admin/settings-password")
async def set_settings_password(
    body: dict, authorization: str | None = Header(default=None)
):
    """Set the kiosk Settings password (called from Settings, already unlocked).

    Gated by _check_admin like every other /admin mutation: when ADMIN_API_KEY is
    set, a LAN client without the bearer must not be able to overwrite the
    password through the catch-all ingress and lock the operator out. If the
    caller provides currentPassword we verify it too (defense in depth; the
    kiosk UI may omit it, so absence is not an error)."""
    import os as _os, json as _json
    _check_admin(authorization)
    pw = (body or {}).get("password", "")
    if len(pw) < 4:
        raise HTTPException(400, "password must be at least 4 characters")
    current = (body or {}).get("currentPassword")
    if current is not None:
        stored = None
        if _os.path.exists(_PW_FILE):
            try:
                stored = _json.load(open(_PW_FILE)).get("hash")
            except Exception:
                stored = None
        current_ok = (_pw_hash(current) == stored) if stored else (current == _PW_DEFAULT)
        if not current_ok:
            await asyncio.sleep(0.4)
            raise HTTPException(401, "current password incorrect")
    _os.makedirs("/data", exist_ok=True)
    with open(_PW_FILE, "w") as f:
        _json.dump({"hash": _pw_hash(pw)}, f)
    return {"ok": True}


@app.get("/admin/theme")
async def get_theme():
    """Serve the saved kiosk theme (colors + logo) for this box. Unauthenticated —
    the kiosk applies it at load. Returns {} if none saved."""
    import os as _os, json as _json
    p = "/data/theme.json"
    if _os.path.exists(p):
        try:
            with open(p) as f:
                return _json.load(f)
        except Exception:
            return {}
    return {}


@app.post("/admin/theme")
async def save_theme(body: dict, authorization: str | None = Header(default=None)):
    """Persist the kiosk theme on the box (survives cache-clear; deployment default)."""
    _check_admin(authorization)
    import os as _os, json as _json
    _os.makedirs("/data", exist_ok=True)
    with open("/data/theme.json", "w") as f:
        _json.dump(body or {}, f)
    return {"ok": True}


# --- Server-side kiosk config (MiniPrem) ------------------------------------
# The kiosk's deployment config (personas, languages, welcome text, FAQs, etc.)
# lives on the box so it can be edited from any device on the LAN, survives a
# browser cache-clear, and is the single source of truth for THIS appliance.
# (Web deployments keep their config in browser localStorage instead.)
# A monotonic `_rev` lets the kiosk detect a remote change and re-apply it the
# next time it's idle. Reset from the terminal: rm /data/kiosk-config.json
_KIOSK_CONFIG_FILE = "/data/kiosk-config.json"
# Optional hand-editable defaults seed, layered UNDER the UI-saved overrides in
# kiosk-config.json. Lets an operator set box defaults from the terminal (persona,
# RAG endpoints, etc.) that survive a Harbor image pull, WITHOUT being able to flip
# deploy-type (build-baked) — `deployType`/`_rev` are stripped from defaults.
# Example: /data/kiosk-defaults.json = {"conversation": {"rag": {"searchEndpoint": "..."}}}
_KIOSK_DEFAULTS_FILE = "/data/kiosk-defaults.json"


def _deep_merge(base: dict, over: dict) -> dict:
    """Recursively merge `over` onto `base` (over wins). Used to layer the UI
    overrides on top of the on-box defaults seed."""
    out = dict(base)
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


@app.get("/admin/kiosk-config")
async def get_kiosk_config():
    """Serve the saved kiosk config for this box. Unauthenticated — the kiosk
    fetches it at load and polls it while idle. Returns {"_rev": 0} if none.
    Layers a hand-editable /data/kiosk-defaults.json UNDER the UI overrides."""
    import os as _os, json as _json
    defaults: dict = {}
    if _os.path.exists(_KIOSK_DEFAULTS_FILE):
        try:
            with open(_KIOSK_DEFAULTS_FILE) as f:
                defaults = _json.load(f) or {}
        except Exception:
            defaults = {}
    # Defaults must never seed deploy-type (build-baked) or the rev counter.
    defaults.pop("deployType", None)
    defaults.pop("_rev", None)
    user: dict = {}
    if _os.path.exists(_KIOSK_CONFIG_FILE):
        try:
            with open(_KIOSK_CONFIG_FILE) as f:
                user = _json.load(f) or {}
        except Exception:
            user = {}
    if not defaults:
        return user or {"_rev": 0}
    merged = _deep_merge(defaults, user)
    # Preserve the user's rev (or 0) so the kiosk's change-detection still works;
    # editing the defaults file alone won't bump _rev (restart/re-save to apply).
    merged["_rev"] = int(user.get("_rev", 0))
    return merged


@app.post("/admin/kiosk-config")
async def save_kiosk_config(body: dict, authorization: str | None = Header(default=None)):
    """Persist the kiosk config on the box and bump _rev so idle kiosks re-apply."""
    _check_admin(authorization)
    import os as _os, json as _json
    _os.makedirs("/data", exist_ok=True)
    prev_rev = 0
    if _os.path.exists(_KIOSK_CONFIG_FILE):
        try:
            with open(_KIOSK_CONFIG_FILE) as f:
                prev_rev = int((_json.load(f) or {}).get("_rev", 0))
        except Exception:
            prev_rev = 0
    payload = dict(body or {})
    payload["_rev"] = prev_rev + 1
    with open(_KIOSK_CONFIG_FILE, "w") as f:
        _json.dump(payload, f)
    return {"ok": True, "_rev": payload["_rev"]}


async def _gpu_vram() -> dict:
    """VRAM totals from the host helper (it can reach the GPU via `docker exec`;
    this adapter container has no nvidia-smi). Returns {} if unavailable."""
    try:
        async with httpx.AsyncClient(timeout=4.0) as client:
            r = await client.get("http://127.0.0.1:8086/gpu")
            if r.status_code == 200:
                return r.json()
    except Exception:
        pass
    return {}


@app.get("/admin/stt-health")
async def stt_health(authorization: str | None = Header(default=None)):
    """Is the local Riva STT (ASR NIM) up? Used by the Audio tab indicator."""
    _check_admin(authorization)
    online = False
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            # Probe the ASR SERVICE (separate pod), not adapter-localhost. The
            # riva-ws-proxy answers /health=200 once the pod (NIM + proxy) is Ready.
            r = await client.get(settings.stt_health_url)
            online = r.status_code == 200
    except Exception:
        online = False
    # VRAM used by the Riva/Triton ASR processes (best-effort, from /admin/system).
    sysinfo = await asyncio.to_thread(_collect_system)
    procs = [p for p in sysinfo.get("procs", []) if any(k in p["name"].lower() for k in ("triton", "riva"))]
    gpu = (sysinfo.get("gpus") or [{}])[0]
    if gpu.get("vram_total_gb") is None:
        gpu = await _gpu_vram()      # adapter has no nvidia-smi; ask the host helper
    return {
        "riva_online": online,
        "vram_total_gb": gpu.get("vram_total_gb"),
        "vram_free_gb": gpu.get("vram_free_gb"),
        "procs": procs,
    }


@app.get("/admin/tts-health")
async def tts_health(authorization: str | None = Header(default=None)):
    """Is the local Riva TTS NIM (:9000) up? Used by the Audio tab indicator."""
    _check_admin(authorization)
    online = False
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get("http://127.0.0.1:9000/v1/health/ready")
            online = r.status_code == 200
    except Exception:
        online = False
    sysinfo = await asyncio.to_thread(_collect_system)
    gpu = (sysinfo.get("gpus") or [{}])[0]
    if gpu.get("vram_total_gb") is None:
        gpu = await _gpu_vram()
    return {
        "riva_online": online,
        "vram_total_gb": gpu.get("vram_total_gb"),
        "vram_free_gb": gpu.get("vram_free_gb"),
    }


@app.get("/v1/models")
async def list_models_proxy():
    """Proxy the served-model list from the local LLM (vLLM/NIM) so the kiosk's
    model picker shows what NVIDIA actually has loaded — not a hardcoded default."""
    try:
        async with httpx.AsyncClient(timeout=4.0) as client:
            r = await client.get(settings.llm_url.rstrip("/") + "/v1/models")
            return JSONResponse(r.json(), status_code=r.status_code)
    except Exception as exc:
        return JSONResponse({"object": "list", "data": [], "error": str(exc)})


@app.get("/admin/llm-health")
async def llm_health(authorization: str | None = Header(default=None)):
    """Is the local LLM (vLLM / NIM) up, which model is loaded, and how much VRAM
    is it using? Powers the Conversation tab's "LLM – <model>" status indicator."""
    _check_admin(authorization)
    online = False
    model = settings.llm_model
    model_root = None
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get(settings.llm_url.rstrip("/") + "/v1/models")
            if r.status_code == 200:
                online = True
                data = (r.json() or {}).get("data") or []
                if data:
                    model = data[0].get("id") or model
                    model_root = data[0].get("root")
    except Exception:
        online = False
    # VRAM used by the LLM process (best-effort, from /admin/system).
    sysinfo = await asyncio.to_thread(_collect_system)
    gpu = (sysinfo.get("gpus") or [{}])[0]
    if gpu.get("vram_total_gb") is None:
        gpu = await _gpu_vram()      # adapter has no nvidia-smi; ask the host helper
    procs = [p for p in sysinfo.get("procs", [])
             if any(k in p["name"].lower() for k in ("vllm", "python", "llm", "nim"))]
    return {
        "llm_online": online,
        "model": model,
        "model_root": model_root,
        "vram_total_gb": gpu.get("vram_total_gb"),
        "vram_free_gb": gpu.get("vram_free_gb"),
        "procs": procs,
    }


@app.post("/admin/tts-test")
async def tts_test(authorization: str | None = Header(default=None)):
    """Synthesize a short test phrase via the local Riva TTS NIM and return the
    WAV so the Audio tab can play it (a live server round-trip, not a recording)."""
    _check_admin(authorization)
    text = "Hello. This is a test. Testing. One. Two. Three."
    # multipart/form-data form fields ((None, value) = a form field, not a file).
    form = {
        "text": (None, text),
        "language": (None, "en-US"),
        "voice": (None, "Magpie-Multilingual.EN-US.Mia"),
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            r = await client.post("http://127.0.0.1:9000/v1/audio/synthesize", files=form)
        if r.status_code != 200:
            raise HTTPException(502, f"Riva TTS returned HTTP {r.status_code}")
        return Response(content=r.content, media_type="audio/wav")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(502, f"Riva TTS not reachable: {exc}")


# nv-ingest / NVIDIA RAG blueprint internal bookkeeping collections — hidden from
# the kiosk knowledge-base picker (they aren't user content) when the adapter shares
# the blueprint's Milvus.
_INTERNAL_COLLECTIONS = {"metadata_schema", "meta"}


@app.get("/admin/collections")
async def list_collections_ep(authorization: str | None = Header(default=None)):
    """List Milvus collections (kiosk knowledge-base picker), minus blueprint
    internals."""
    _check_admin(authorization)
    cols = await asyncio.to_thread(vectorstore.list_collections)
    cols = [c for c in cols if c not in _INTERNAL_COLLECTIONS]
    return {"collections": cols}


import re as _re


@app.post("/admin/collections")
async def create_collection_ep(request: Request, authorization: str | None = Header(default=None)):
    """Create a new (empty) knowledge-base collection."""
    _check_admin(authorization)
    body = await request.json()
    name = (body.get("name") or "").strip()
    # Milvus names: start with a letter/underscore, then letters/digits/underscore.
    if not _re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,254}", name):
        raise HTTPException(status_code=400, detail="invalid collection name (use letters, digits, underscore; start with a letter)")
    await asyncio.to_thread(vectorstore.ensure_collection, name)
    return {"ok": True, "collection": name}


@app.delete("/admin/collections/{name}")
async def delete_collection_ep(name: str, authorization: str | None = Header(default=None)):
    """Delete an entire collection and all its documents."""
    _check_admin(authorization)
    await asyncio.to_thread(vectorstore.drop_collection, name)
    return {"ok": True, "deleted": name}


@app.get("/admin/documents/{name}/markdown")
async def document_markdown(
    name: str,
    collection: str | None = None,
    authorization: str | None = Header(default=None),
):
    """Reconstruct a document's extracted markdown (joined chunks) for download."""
    _check_admin(authorization)
    coll = collection or settings.collection_name
    chunks = await asyncio.to_thread(vectorstore.get_doc_chunks, coll, name)
    if not chunks and settings.rag_base_url:
        # Blueprint-ingested documents live under the blueprint's schema — the direct
        # store read above finds nothing (the kiosk preview 404 bug). Fall back to the
        # RAG server: search scoped to this collection and keep only chunks belonging
        # to THIS document, joined as the preview.
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                r = await client.post(
                    f"{settings.rag_base_url.rstrip('/')}/v1/search",
                    json={"query": name, "collection_names": [coll], "top_k": 50},
                )
                if r.status_code == 200:
                    seen: set[str] = set()
                    chunks = []
                    for res in r.json().get("results", []):
                        if res.get("document_name") != name:
                            continue
                        if res.get("document_type", "text") == "text":
                            text = res.get("content") or ""
                        else:
                            # image/table elements: raw content is base64 pixels
                            # (binary soup in a preview) — show the ingest-time VLM
                            # caption instead so image-only docs still preview.
                            desc = (res.get("metadata") or {}).get("description") or ""
                            text = f"**[Image]** {desc}" if desc else ""
                        # Dedupe: the same chunk can be indexed more than once
                        # (re-ingests).
                        if text and text not in seen:
                            seen.add(text)
                            chunks.append(text)
        except Exception as exc:
            log.warning("blueprint markdown fallback failed for %s: %s", name, exc)
    if not chunks:
        raise HTTPException(status_code=404, detail="document not found")
    return {"document": name, "collection": coll, "markdown": "\n\n".join(chunks)}


@app.post("/admin/search")
async def search_documents(request: Request, authorization: str | None = Header(default=None)):
    """Preview retrieval for a query (kiosk 'test knowledge base' button)."""
    _check_admin(authorization)
    body = await request.json()
    query = (body.get("query") or "").strip()
    if not query:
        raise HTTPException(status_code=400, detail="missing 'query'")
    coll = body.get("collection") or settings.collection_name
    hits = await _retrieve(query, coll, body.get("k"))
    return {"query": query, "collection": coll, "results": hits}


# --------------------------------------------------------------------------- #
# Admin: convert an uploaded doc/pdf to clean markdown (kiosk prompt upload).
# --------------------------------------------------------------------------- #

@app.post("/admin/convert")
async def convert_document(
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
):
    _check_admin(authorization)
    content = await file.read()
    name = (file.filename or "upload").lower()
    if name.endswith((".txt", ".md", ".markdown")):
        return {"markdown": content.decode("utf-8", errors="replace"), "converted": False}
    try:
        md = await asyncio.to_thread(_to_markdown, content, file.filename or "upload")
        return {"markdown": md, "converted": True}
    except Exception as exc:
        log.exception("convert failed for %s", name)
        raise HTTPException(status_code=415, detail=f"Could not convert {file.filename}: {exc}")


# --------------------------------------------------------------------------- #
# Admin: live system metrics (kiosk Advanced panel — GPU/VRAM/CPU/RAM/disk)
# --------------------------------------------------------------------------- #

def _proc_container_id(pid: str) -> str:
    """Container id from /proc/<pid>/cgroup (world-readable). Used to group a
    container's parent tritonserver with its identified model-component stubs."""
    try:
        with open(f"/proc/{pid}/cgroup", "r") as f:
            blob = f.read()
        import re as _re2
        m = _re2.search(r"docker[-/]([0-9a-f]{12,64})", blob)
        return m.group(1) if m else ""
    except Exception:
        return ""


def _proc_cmdline(pid: str) -> str:
    """Read a process's cmdline (world-readable, no ptrace). The Triton model-repo
    path in the args reveals the model (e.g. /data/models/magpie_tts.../...)."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().decode("utf-8", errors="replace").replace("\x00", " ").lower()
    except Exception:
        return ""


def _friendly_gpu_proc(pid: str, raw: str) -> str:
    """Map known GPU processes to user-friendly names; unknown -> raw name."""
    n = raw.lower()
    if "vllm" in n or "enginecore" in n:
        return "VLLM Engine Core"
    if "renny" in n:
        return "UneeQ Digital Human (Renny)"
    if "triton" in n:
        cmd = _proc_cmdline(pid)
        if "magpie" in cmd or "tts" in cmd:
            return "NVIDIA Riva TTS"
        if "nemotron" in cmd or "parakeet" in cmd or "asr" in cmd or "conformer" in cmd:
            return "NVIDIA Riva STT"
        return raw  # unidentified Triton process
    return raw


def _collect_system() -> dict:
    import os as _os
    import shutil
    import subprocess
    out: dict = {}
    try:
        import psutil
        out["cpu_pct"] = psutil.cpu_percent(interval=0.15)
        vm = psutil.virtual_memory()
        out["ram_pct"] = round(vm.percent, 1)
        out["ram_used_gb"] = round(vm.used / 1e9, 1)
        out["ram_total_gb"] = round(vm.total / 1e9, 1)
    except Exception as exc:
        out["cpu_error"] = str(exc)
    try:
        path = "/hostfs" if _os.path.exists("/hostfs") else "/"
        du = shutil.disk_usage(path)
        out["disk_pct"] = round(du.used / du.total * 100, 1)
        out["disk_used_gb"] = round(du.used / 1e9, 1)
        out["disk_total_gb"] = round(du.total / 1e9, 1)
    except Exception as exc:
        out["disk_error"] = str(exc)
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        gpus = []
        for line in r.stdout.strip().splitlines():
            u, mu, mt = [x.strip() for x in line.split(",")]
            used_gb = round(float(mu) / 1024, 1)
            total_gb = round(float(mt) / 1024, 1)
            gpus.append({
                "util_pct": float(u),
                "vram_used_gb": used_gb,
                "vram_total_gb": total_gb,
                "vram_free_gb": round(total_gb - used_gb, 1),
                "vram_pct": round(float(mu) / float(mt) * 100, 1) if float(mt) else 0,
            })
        out["gpus"] = gpus
        # Per-process VRAM breakdown (nvidia-smi has no per-process GPU-util, so we
        # report VRAM GB + % of total — that's what answers "who's using the GPU").
        total_mib = sum(float((g["vram_total_gb"]) * 1024) for g in gpus) or 1.0
        rp = subprocess.run(
            ["nvidia-smi", "--query-compute-apps=pid,used_memory,process_name",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        procs = []
        for line in rp.stdout.strip().splitlines():
            parts = [x.strip() for x in line.split(",")]
            if len(parts) < 3:
                continue
            pid, mem_mib, name = parts[0], parts[1], ",".join(parts[2:])
            short = name.rsplit("/", 1)[-1][:28]
            try:
                gb = round(float(mem_mib) / 1024, 1)
                pct = round(float(mem_mib) / total_mib * 100, 1)
            except ValueError:
                continue
            procs.append({
                "pid": pid, "name": _friendly_gpu_proc(pid, short),
                "vram_gb": gb, "vram_pct": pct, "_raw": short, "_cid": _proc_container_id(pid),
            })
        # Group by container: a parent "tritonserver" that we couldn't name from its
        # own cmdline inherits the Riva TTS/STT label of a sibling stub in the same
        # container that WAS identified.
        cid_label = {}
        for p in procs:
            if p["_cid"] and p["name"] in ("NVIDIA Riva TTS", "NVIDIA Riva STT"):
                cid_label.setdefault(p["_cid"], p["name"])
        for p in procs:
            if p["name"] == p["_raw"] and "triton" in p["_raw"].lower() and p["_cid"] in cid_label:
                p["name"] = cid_label[p["_cid"]] + " (Triton)"
            del p["_raw"]; del p["_cid"]
        procs.sort(key=lambda p: p["vram_gb"], reverse=True)
        out["procs"] = procs[:10]
    except Exception as exc:
        out["gpu_error"] = str(exc)
    return out


@app.get("/admin/system")
async def system_stats(authorization: str | None = Header(default=None)):
    _check_admin(authorization)
    return await asyncio.to_thread(_collect_system)


# --------------------------------------------------------------------------- #
# Health
# --------------------------------------------------------------------------- #

@app.get("/health")
async def health():
    # Liveness/readiness MUST be cheap and must NEVER touch Milvus/embed. Querying the
    # vectorstore here blocked the probe when the (shared, external) Milvus was down —
    # the connection hang exceeded the 1s probe timeout, so the kubelet crash-looped
    # the pod even though the DH can still converse via the LLM without retrieval.
    # Live doc/chunk counts live on /admin/collections instead.
    rag = {"mode": settings.rag_mode}
    if settings.rag_mode == "local":
        rag["embed_url"] = settings.embed_url
        rag["llm_url"] = settings.llm_url
    else:
        rag["rag_base_url"] = settings.rag_base_url
    return {
        "status": "ok",
        "collection": settings.collection_name,
        "rag": rag,
        "session_memory": "enabled" if store.enabled else "disabled",
        "redis_ok": await store.ping(),
        "prompt_override": (await store.get_prompt_override()) is not None,
        "prompt_chars": len(await _effective_prompt()),
    }


# --------------------------------------------------------------------------- #
# Runtime "Use Knowledge Base" toggle.
# The kiosk's "Use knowledge base" checkbox only reached the /v1 path (it sends
# use_knowledge_base in the request). The Renny/DHOP /prompt path is driven by the
# platform and never carried that flag, so it fell back to the env default and RAG
# stayed ON for spoken turns. This runtime override (set by the kiosk, persisted to
# /data) is the fallback for BOTH paths, so the checkbox actually disables retrieval.
# --------------------------------------------------------------------------- #
import os as _os_kb, json as _json_kb
_USE_KB_FILE = "/data/use_kb.json"
_use_kb_override = None  # None => unset, use settings.use_knowledge_base (env)


def _load_use_kb():
    global _use_kb_override
    try:
        if _os_kb.path.exists(_USE_KB_FILE):
            _use_kb_override = bool((_json_kb.load(open(_USE_KB_FILE)) or {}).get("enabled"))
    except Exception:
        _use_kb_override = None


def _effective_use_kb() -> bool:
    return _use_kb_override if _use_kb_override is not None else settings.use_knowledge_base


_load_use_kb()


@app.get("/admin/use-kb")
async def get_use_kb():
    return {"enabled": _effective_use_kb()}


@app.post("/admin/use-kb")
async def set_use_kb(enabled: bool, authorization: str | None = Header(default=None)):
    """Kiosk's "Use knowledge base" toggle — gates retrieval for BOTH the /v1 and the
    Renny /prompt paths (persisted so it survives restarts)."""
    _check_admin(authorization)
    global _use_kb_override
    _use_kb_override = bool(enabled)
    try:
        _os_kb.makedirs("/data", exist_ok=True)
        _json_kb.dump({"enabled": bool(enabled)}, open(_USE_KB_FILE, "w"))
    except Exception:
        pass
    return {"ok": True, "enabled": bool(enabled)}
