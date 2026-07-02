"""Embedding client for the local NVIDIA embedding NIM (OpenAI-compatible).

The NIM (llama-3.2-nv-embedqa-1b-v2) is *asymmetric* — it requires an
`input_type` of "passage" when embedding documents and "query" when embedding
a user question. Getting this wrong silently degrades retrieval quality.
"""
from __future__ import annotations

import logging
from typing import List

from .config import settings
from .http_client import shared_client

log = logging.getLogger("rag-adapter.embed")


async def embed(texts: List[str], input_type: str = "passage") -> List[List[float]]:
    """Embed a batch of texts. input_type: 'passage' (docs) | 'query' (questions)."""
    if not texts:
        return []
    payload = {
        "model": settings.embed_model,
        "input": texts,
        "input_type": input_type,
        "encoding_format": "float",
    }
    url = settings.embed_url.rstrip("/") + "/v1/embeddings"
    resp = await shared_client().post(url, json=payload, timeout=120.0)
    resp.raise_for_status()
    data = resp.json().get("data", [])
    # Preserve input order (NIM returns objects with an "index").
    data = sorted(data, key=lambda d: d.get("index", 0))
    return [d["embedding"] for d in data]


async def embed_one(text: str, input_type: str = "query") -> List[float]:
    vecs = await embed([text], input_type=input_type)
    return vecs[0] if vecs else []
