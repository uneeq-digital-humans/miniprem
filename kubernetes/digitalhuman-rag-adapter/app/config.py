"""Configuration for the UneeQ <-> NVIDIA RAG adapter.

All settings are environment-driven so the same image works from local docker,
the MiniPrem Helm chart, and the autoinstall ISO seed without rebuilds.
"""
from __future__ import annotations

import os
from dataclasses import dataclass


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    # ---- NVIDIA RAG backend -------------------------------------------------
    # Base URL of the NVIDIA RAG rag-server (OpenAI-compatible).
    rag_base_url: str = os.getenv(
        "RAG_BASE_URL", "http://rag-server.advanced-rag.svc.cluster.local:8081"
    )
    # Chat endpoint. NVIDIA exposes /v1/chat/completions and the alias /v1/generate.
    rag_chat_path: str = os.getenv("RAG_CHAT_PATH", "/v1/chat/completions")
    rag_model: str = os.getenv("RAG_MODEL", "google/gemma-4-26B-A4B-it")
    rag_api_key: str = os.getenv("RAG_API_KEY", "")  # optional bearer for the RAG server

    # Retrieval / knowledge base
    use_knowledge_base: bool = _bool("USE_KNOWLEDGE_BASE", True)
    collection_name: str = os.getenv("COLLECTION_NAME", "multimodal_data")

    # Generation params (overridable per request via overrideConfig)
    temperature: float = _float("RAG_TEMPERATURE", 0.2)
    top_p: float = _float("RAG_TOP_P", 0.7)
    max_tokens: int = _int("RAG_MAX_TOKENS", 1024)
    request_timeout_s: float = _float("RAG_TIMEOUT_S", 120.0)

    # ---- Persona prompt -----------------------------------------------------
    # File the digital-human system prompt is read from. Mounted from a ConfigMap
    # so the kiosk settings panel can edit it and trigger a reload.
    prompt_file: str = os.getenv(
        "PROMPT_FILE", "/etc/rag-adapter/digital-human-system-prompt.md"
    )

    # ---- Sessions / Redis ---------------------------------------------------
    redis_url: str = os.getenv("REDIS_URL", "")  # empty => session memory disabled
    session_ttl_s: int = _int("SESSION_TTL_S", 1800)  # 30 min idle expiry
    max_history_turns: int = _int("MAX_HISTORY_TURNS", 12)  # user+assistant pairs kept
    # Share the Redis session window with /v1/chat/completions too (keyed by the
    # x-session-id header / OpenAI `user` field), so the kiosk's typed chat and the
    # Renny voice path (/prompt) see ONE conversation. false => /v1 stays a pure
    # stateless proxy.
    v1_session_memory: bool = os.getenv("V1_SESSION_MEMORY", "true").strip().lower() in {"1", "true", "yes", "on"}

    # ---- Admin / kiosk management ------------------------------------------
    # nv-ingest ingestion server, for the kiosk's document manager (upload/list).
    nv_ingest_url: str = os.getenv(
        "NV_INGEST_URL", "http://nv-ingest.advanced-rag.svc.cluster.local:7670"
    )
    # NVIDIA RAG blueprint INGESTION server (the /v1/documents API). When set, kiosk
    # uploads are routed through it so they REGISTER as blueprint documents (visible
    # in rag-frontend) AND embed into the shared Milvus — instead of the adapter's
    # direct markitdown→embed path, which only writes vectors (collection shows
    # entries but rag-frontend lists "no documents"). Empty => direct path (fallback).
    ingestor_url: str = os.getenv("INGESTOR_URL", "")
    # STT readiness probe target for the kiosk Audio-tab badge. The ASR NIM + WS proxy
    # run in a SEPARATE pod, so the adapter must hit the asr SERVICE, not its own
    # localhost. The riva-ws-proxy answers /health (200) once the pod is Ready.
    stt_health_url: str = os.getenv(
        "STT_HEALTH_URL", "http://digitalhuman-asr.uneeq.svc.cluster.local:8000/health"
    )
    # Optional shared secret protecting the /admin/* endpoints. Empty => open
    # (fine for an on-box kiosk that only the local UI can reach).
    admin_api_key: str = os.getenv("ADMIN_API_KEY", "")

    # ---- Lightweight on-box RAG (Milvus Lite + nim-embed + Gemma) ----------
    # When rag_mode == "local", the adapter owns retrieval itself: documents are
    # chunked + embedded via the local embedding NIM and stored in an embedded
    # Milvus Lite file; the conversation path retrieves top-k chunks and asks the
    # local LLM. No nv-ingest / rag-server / milvus-standalone needed. Set to
    # "blueprint" to instead proxy to a full NVIDIA RAG server at rag_base_url.
    rag_mode: str = os.getenv("RAG_MODE", "local")
    embed_url: str = os.getenv("EMBED_URL", "http://127.0.0.1:8002")
    embed_model: str = os.getenv("EMBED_MODEL", "nvidia/llama-3.2-nv-embedqa-1b-v2")
    embed_dim: int = _int("EMBED_DIM", 2048)
    llm_url: str = os.getenv("LLM_URL", "http://127.0.0.1:11438")
    # Default LLM = the turnkey Dell-kiosk model (matches the nim-gemma chart + Tyler's
    # NIMService spec). Override LLM_MODEL to the exact id the served NIM reports.
    llm_model: str = os.getenv("LLM_MODEL", "google/gemma-4-26B-A4B-it")
    # NOTE: do NOT name this env MILVUS_URI — pymilvus reads that at import and
    # validates it as an http(s) server URI, crashing on a local file path.
    milvus_uri: str = os.getenv("MILVUS_DB_PATH", "/data/milvus.db")
    chunk_size: int = _int("CHUNK_SIZE", 1200)
    chunk_overlap: int = _int("CHUNK_OVERLAP", 150)
    top_k: int = _int("RAG_TOP_K", 4)

    # ---- Output shape -------------------------------------------------------
    # "flowise" emits Flowise-style SSE (what Renny currently consumes).
    # "openai" passes through OpenAI-style chunks unchanged.
    stream_format: str = os.getenv("STREAM_FORMAT", "flowise")

    # ---- Service ------------------------------------------------------------
    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = _int("PORT", 8085)
    log_level: str = os.getenv("LOG_LEVEL", "info")


settings = Settings()
