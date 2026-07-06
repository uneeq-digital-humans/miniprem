"""Shared httpx.AsyncClient for the conversation hot paths.

Every turn used to construct (and tear down) a fresh AsyncClient per call —
a new TCP handshake ahead of the first token, plus socket/FD churn under
sustained kiosk use. One pooled client keeps connections alive across turns.
Per-request timeouts are passed at call time; the pool default matches the
old per-call construction.
"""
from __future__ import annotations

import httpx

from .config import settings

_client: httpx.AsyncClient | None = None


def shared_client() -> httpx.AsyncClient:
    """The process-wide pooled client (created lazily, reused across requests)."""
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(
            timeout=settings.request_timeout_s,
            limits=httpx.Limits(max_connections=64, max_keepalive_connections=20),
        )
    return _client


async def close_shared_client() -> None:
    """Close the pool on app shutdown."""
    global _client
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None
