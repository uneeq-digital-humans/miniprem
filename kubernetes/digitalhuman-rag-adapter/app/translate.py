"""Translation between the UneeQ/Flowise contract and NVIDIA RAG.

Inbound  (UneeQ -> us):  Flowise prediction shape
    { "question": str,
      "history": [ {"type": "human"|"apiMessage", "message": str}, ... ],
      "streaming": bool,
      "overrideConfig": { "sessionId": str, ... } }

Outbound (us -> NVIDIA RAG): OpenAI chat-completions shape
    { "messages": [ {"role": "system"|"user"|"assistant", "content": str} ],
      "use_knowledge_base": bool, "collection_name": str,
      "model": str, "temperature": float, "top_p": float,
      "max_tokens": int, "stream": bool }

The model's reply may contain UneeQ inline tags (e.g. <uneeq:action_wavehello />).
We pass them through verbatim — Renny converts/animates them. Nothing here
strips or rewrites tags.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Tuple

from .config import settings
from .prompt import prompt_store

Message = Dict[str, str]


def parse_request(body: Dict[str, Any]) -> Tuple[str, List[Message], Optional[str], bool, Dict[str, Any]]:
    """Return (question, inline_history, session_id, streaming, overrides)."""
    question = (body.get("question") or body.get("prompt") or "").strip()

    override = body.get("overrideConfig") or {}
    session_id = override.get("sessionId") or body.get("sessionId")

    # streaming can arrive as "streaming" (Flowise) or "stream" (OpenAI-ish)
    streaming = bool(body.get("streaming", body.get("stream", True)))

    inline_history: List[Message] = []
    for turn in body.get("history") or []:
        ttype = (turn.get("type") or turn.get("role") or "").lower()
        text = turn.get("message") or turn.get("content") or ""
        if not text:
            continue
        if ttype in {"human", "user", "userMessage".lower()}:
            inline_history.append({"role": "user", "content": text})
        else:  # apiMessage / ai / assistant
            inline_history.append({"role": "assistant", "content": text})

    return question, inline_history, session_id, streaming, override


def build_rag_payload(
    question: str,
    remembered: List[Message],
    inline_history: List[Message],
    streaming: bool,
    override: Dict[str, Any],
    system_prompt: str | None = None,
    use_kb_default: bool | None = None,
) -> Dict[str, Any]:
    """Assemble the OpenAI-style payload for the NVIDIA RAG server.

    `system_prompt` is the effective persona prompt (a kiosk-edited override if
    present, else the ConfigMap default). Falls back to the file-backed prompt.

    `use_kb_default` is the EFFECTIVE knowledge-base toggle (the kiosk's persisted
    /admin/use-kb override when set, else the env default). The caller supplies it
    so the runtime switch drives /prompt traffic too; falling back to the static
    env setting here would silently ignore the kiosk toggle for voice turns.
    """
    messages: List[Message] = [
        {"role": "system", "content": system_prompt or prompt_store.text}
    ]
    # Redis-remembered turns first, then any history the caller passed inline.
    messages.extend(remembered)
    messages.extend(inline_history)
    messages.append({"role": "user", "content": question})

    payload: Dict[str, Any] = {
        "messages": messages,
        "model": override.get("model", settings.rag_model),
        "temperature": override.get("temperature", settings.temperature),
        "top_p": override.get("topP", override.get("top_p", settings.top_p)),
        "max_tokens": override.get("maxTokens", settings.max_tokens),
        "stream": streaming,
        # NVIDIA RAG extensions
        "use_knowledge_base": override.get(
            "useKnowledgeBase",
            use_kb_default if use_kb_default is not None
            else settings.use_knowledge_base,
        ),
        "collection_name": override.get(
            "collectionName", settings.collection_name
        ),
    }
    return payload


# --- Response token extraction (NVIDIA / OpenAI SSE) ------------------------

def extract_token(openai_chunk: Dict[str, Any]) -> str:
    """Pull the text delta out of one OpenAI/NVIDIA streaming chunk."""
    try:
        choices = openai_chunk.get("choices") or []
        if not choices:
            return ""
        delta = choices[0].get("delta") or {}
        if "content" in delta and delta["content"]:
            return delta["content"]
        # Some servers send full message instead of delta on non-stream replies.
        msg = choices[0].get("message") or {}
        return msg.get("content", "") or ""
    except Exception:
        return ""


# --- Outbound SSE in the shape Renny/Flowise expects ------------------------

def sse_flowise(event: str, data: Any) -> bytes:
    """One Flowise-style SSE frame: `data:{"event":..,"data":..}\\n\\n`."""
    return f"data:{json.dumps({'event': event, 'data': data})}\n\n".encode("utf-8")


def flowise_final_json(answer: str, question: str, history: List[Message]) -> Dict[str, Any]:
    """Non-streaming Flowise prediction response body."""
    new_history = list(history) + [
        {"type": "human", "message": question},
        {"type": "apiMessage", "message": answer},
    ]
    return {"text": answer, "result": answer, "question": question, "history": new_history}
