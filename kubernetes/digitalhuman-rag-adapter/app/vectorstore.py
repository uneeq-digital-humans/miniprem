"""Embedded Milvus Lite vector store.

Single-file local vector DB (no etcd/minio/standalone). One collection per RAG
"collection_name"; each row is a document chunk with its embedding. Sync
pymilvus calls are wrapped in run_in_executor by callers via asyncio.to_thread.
"""
from __future__ import annotations

import logging
import threading
from collections import Counter
from typing import Any, Dict, List

from pymilvus import DataType, MilvusClient

from .config import settings

log = logging.getLogger("rag-adapter.vec")

_client: MilvusClient | None = None
_lock = threading.Lock()


def client() -> MilvusClient:
    global _client
    if _client is None:
        with _lock:
            if _client is None:
                # milvus_uri is either a Milvus-Lite file path (/data/milvus.db) OR a
                # remote server URI (http://milvus.advanced-rag:19530) when sharing the
                # NVIDIA RAG blueprint's standalone Milvus so blueprint-created
                # collections show up here too.
                log.info("opening Milvus at %s", settings.milvus_uri)
                _client = MilvusClient(settings.milvus_uri)
    return _client


def list_collections() -> List[str]:
    try:
        return list(client().list_collections())
    except Exception:
        return []


def drop_collection(name: str) -> None:
    c = client()
    if name in c.list_collections():
        c.drop_collection(name)


def ensure_collection(name: str) -> None:
    c = client()
    if c.has_collection(name):
        return
    schema = c.create_schema(auto_id=True, enable_dynamic_field=False)
    schema.add_field("id", DataType.INT64, is_primary=True)
    schema.add_field("vector", DataType.FLOAT_VECTOR, dim=settings.embed_dim)
    schema.add_field("doc_name", DataType.VARCHAR, max_length=512)
    schema.add_field("text", DataType.VARCHAR, max_length=65535)
    index = c.prepare_index_params()
    index.add_index(field_name="vector", metric_type="COSINE", index_type="AUTOINDEX")
    c.create_collection(name, schema=schema, index_params=index)
    log.info("created collection %s (dim=%d)", name, settings.embed_dim)


def ingest(name: str, doc_name: str, chunks: List[str], vectors: List[List[float]]) -> int:
    ensure_collection(name)
    rows = [
        {"vector": v, "doc_name": doc_name, "text": t}
        for t, v in zip(chunks, vectors)
    ]
    if not rows:
        return 0
    client().insert(name, rows)
    return len(rows)


def list_docs(name: str) -> List[Dict[str, Any]]:
    c = client()
    if not c.has_collection(name):
        return []
    # A collection created by the NVIDIA RAG blueprint (nv-ingest) has a different
    # schema (no `doc_name`/`id` fields), so this query can raise. Degrade to "no
    # documents listed" rather than 500-ing the kiosk panel — the collection still
    # shows and the kiosk's own collections list normally.
    try:
        rows = c.query(name, filter="id >= 0", output_fields=["doc_name"], limit=16384)
    except Exception as exc:
        log.warning("list_docs(%s) failed (foreign schema?): %s", name, exc)
        return []
    counts = Counter(r.get("doc_name", "") for r in rows)
    return [{"name": k, "chunks": v} for k, v in sorted(counts.items()) if k]


def get_doc_chunks(name: str, doc_name: str) -> List[str]:
    """Return a document's chunk texts (insertion order) for download/preview."""
    c = client()
    if not c.has_collection(name):
        return []
    safe = doc_name.replace('"', '\\"')
    try:
        rows = c.query(name, filter=f'doc_name == "{safe}"', output_fields=["text", "id"], limit=16384)
    except Exception as exc:
        log.warning("get_doc_chunks(%s) failed (foreign schema?): %s", name, exc)
        return []
    rows.sort(key=lambda r: r.get("id", 0))
    return [r.get("text", "") for r in rows]


def delete_doc(name: str, doc_name: str) -> int:
    c = client()
    if not c.has_collection(name):
        return 0
    safe = doc_name.replace('"', '\\"')
    res = c.delete(name, filter=f'doc_name == "{safe}"')
    # pymilvus returns a dict-ish with delete_count on recent versions.
    try:
        return int(res["delete_count"])  # type: ignore[index]
    except Exception:
        return 0


def search(name: str, query_vector: List[float], k: int | None = None) -> List[Dict[str, Any]]:
    c = client()
    if not c.has_collection(name) or not query_vector:
        return []
    k = k or settings.top_k
    try:
        res = c.search(
            name,
            data=[query_vector],
            anns_field="vector",
            limit=k,
            search_params={"metric_type": "COSINE"},
            output_fields=["text", "doc_name"],
        )
    except Exception as exc:
        # Foreign-schema collection (e.g. blueprint nv-ingest) or metric mismatch —
        # don't break the conversation; fall back to no retrieved context.
        log.warning("search(%s) failed (foreign schema/metric?): %s", name, exc)
        return []
    hits = res[0] if res else []
    out = []
    for h in hits:
        ent = h.get("entity", h)
        out.append(
            {
                "text": ent.get("text", ""),
                "doc_name": ent.get("doc_name", ""),
                "score": h.get("distance", 0.0),
            }
        )
    return out
