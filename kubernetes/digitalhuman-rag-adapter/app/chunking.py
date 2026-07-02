"""Paragraph-aware text chunker for markdown → retrievable chunks."""
from __future__ import annotations

from typing import List

from .config import settings


def chunk_text(md: str, size: int | None = None, overlap: int | None = None) -> List[str]:
    """Split markdown into ~`size`-char chunks on paragraph boundaries.

    Paragraphs are accumulated until they'd exceed `size`; an oversized single
    paragraph is hard-split with `overlap` so no chunk is lost.
    """
    size = size or settings.chunk_size
    overlap = overlap or settings.chunk_overlap
    paras = [p.strip() for p in md.replace("\r\n", "\n").split("\n\n") if p.strip()]
    chunks: List[str] = []
    cur = ""
    for p in paras:
        if len(p) > size:
            if cur:
                chunks.append(cur)
                cur = ""
            step = max(1, size - overlap)
            for i in range(0, len(p), step):
                chunks.append(p[i : i + size])
            continue
        if len(cur) + len(p) + 2 <= size:
            cur = (cur + "\n\n" + p).strip() if cur else p
        else:
            if cur:
                chunks.append(cur)
            cur = p
    if cur:
        chunks.append(cur)
    return chunks
