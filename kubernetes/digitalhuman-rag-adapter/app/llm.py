"""Local LLM client (Gemma vLLM, OpenAI-compatible) for the local RAG path."""
from __future__ import annotations

import json
import logging
from typing import Any, AsyncIterator, Dict, List

from .config import settings
from .http_client import shared_client

log = logging.getLogger("rag-adapter.llm")

Message = Dict[str, str]


def _url() -> str:
    return settings.llm_url.rstrip("/") + "/v1/chat/completions"


def _body(messages: List[Message], stream: bool) -> Dict[str, Any]:
    return {
        "model": settings.llm_model,
        "messages": messages,
        "temperature": settings.temperature,
        "top_p": settings.top_p,
        "max_tokens": settings.max_tokens,
        "stream": stream,
    }


async def generate(messages: List[Message]) -> str:
    resp = await shared_client().post(_url(), json=_body(messages, False))
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"] or ""


async def stream(messages: List[Message]) -> AsyncIterator[str]:
    """Yield content token deltas from the local LLM."""
    client = shared_client()
    async with client.stream("POST", _url(), json=_body(messages, True)) as resp:
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
                chunk = json.loads(line)
                delta = (chunk.get("choices") or [{}])[0].get("delta", {})
                tok = delta.get("content")
                if tok:
                    yield tok
            except json.JSONDecodeError:
                continue
