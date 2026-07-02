"""Thin async client for the NVIDIA RAG OpenAI-compatible chat endpoint."""
from __future__ import annotations

import json
import logging
from typing import Any, AsyncIterator, Dict

from .config import settings
from .http_client import shared_client

log = logging.getLogger("rag-adapter.rag")


def _headers() -> Dict[str, str]:
    h = {"Content-Type": "application/json", "Accept": "text/event-stream"}
    if settings.rag_api_key:
        h["Authorization"] = f"Bearer {settings.rag_api_key}"
    return h


def _url() -> str:
    return settings.rag_base_url.rstrip("/") + settings.rag_chat_path


async def stream_chat(payload: Dict[str, Any]) -> AsyncIterator[Dict[str, Any]]:
    """Yield parsed OpenAI/NVIDIA streaming chunks (dicts) until [DONE]."""
    client = shared_client()
    async with client.stream(
        "POST", _url(), json=payload, headers=_headers()
    ) as resp:
        resp.raise_for_status()
        async for line in resp.aiter_lines():
            if not line:
                continue
            line = line.strip()
            if line.startswith("data:"):
                line = line[len("data:"):].strip()
            if not line or line == "[DONE]":
                if line == "[DONE]":
                    return
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                log.debug("Skipping non-JSON SSE line: %r", line[:120])
                continue


async def complete_chat(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Non-streaming completion. Returns the full OpenAI-style response."""
    body = dict(payload)
    body["stream"] = False
    resp = await shared_client().post(_url(), json=body, headers=_headers())
    resp.raise_for_status()
    return resp.json()
