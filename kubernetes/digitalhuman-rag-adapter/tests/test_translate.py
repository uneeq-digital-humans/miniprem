"""Unit tests for the UneeQ <-> NVIDIA RAG translation layer.

The headline guarantee: UneeQ inline tags (gestures/emotions) survive the full
round-trip through translation and Flowise SSE re-emission. The Riva-TTS gesture
bug is downstream of this service; these tests prove the adapter itself is clean.
"""
import json
import os

os.environ.setdefault("PROMPT_FILE", "/nonexistent")  # use fallback prompt

from app.translate import (  # noqa: E402
    build_rag_payload,
    extract_token,
    flowise_final_json,
    parse_request,
    sse_flowise,
)

# A real captured UneeQ Direct-Speak payload's prompt text, with a gesture tag.
GESTURE_TEXT = "hey <uneeq:action_wavehello />  hi test again"


def test_parse_flowise_request():
    body = {
        "question": "hey Sophie how are you",
        "streaming": True,
        "overrideConfig": {"sessionId": "test-session-123"},
        "history": [
            {"type": "human", "message": "my name is Doug"},
            {"type": "apiMessage", "message": "Nice to meet you, Doug!"},
        ],
    }
    q, hist, sid, streaming, override = parse_request(body)
    assert q == "hey Sophie how are you"
    assert sid == "test-session-123"
    assert streaming is True
    assert hist == [
        {"role": "user", "content": "my name is Doug"},
        {"role": "assistant", "content": "Nice to meet you, Doug!"},
    ]


def test_build_payload_injects_system_prompt_and_order():
    remembered = [{"role": "user", "content": "my name is Doug"}]
    payload = build_rag_payload(
        "what is my name?", remembered, [], streaming=True, override={}
    )
    roles = [m["role"] for m in payload["messages"]]
    assert roles[0] == "system"          # persona prompt injected first
    assert payload["messages"][1] == remembered[0]  # memory before new turn
    assert payload["messages"][-1] == {"role": "user", "content": "what is my name?"}
    assert payload["use_knowledge_base"] is True
    assert payload["stream"] is True


def test_system_prompt_override_is_honored():
    # A kiosk-edited persona prompt must be the injected system message.
    custom = "You are Sophie, the Acme Corp host. <uneeq:action_wavehello />"
    payload = build_rag_payload(
        "hi", [], [], streaming=False, override={}, system_prompt=custom
    )
    assert payload["messages"][0] == {"role": "system", "content": custom}


def test_override_config_controls_retrieval():
    payload = build_rag_payload(
        "hi", [], [], streaming=False,
        override={"useKnowledgeBase": False, "collectionName": "acme_docs"},
    )
    assert payload["use_knowledge_base"] is False
    assert payload["collection_name"] == "acme_docs"
    assert payload["stream"] is False


def test_extract_token_from_openai_delta():
    chunk = {"choices": [{"delta": {"content": GESTURE_TEXT}}]}
    assert extract_token(chunk) == GESTURE_TEXT


def test_extract_token_from_full_message():
    chunk = {"choices": [{"message": {"content": "done"}}]}
    assert extract_token(chunk) == "done"


def test_gesture_tags_survive_sse_roundtrip():
    # Re-emit the gesture text as Flowise SSE token frames and read it back.
    frame = sse_flowise("token", GESTURE_TEXT).decode("utf-8")
    assert frame.startswith("data:")
    assert frame.endswith("\n\n")
    payload = json.loads(frame[len("data:"):].strip())
    assert payload == {"event": "token", "data": GESTURE_TEXT}
    assert "<uneeq:action_wavehello />" in payload["data"]  # tag intact


def test_final_json_preserves_tags_and_appends_history():
    out = flowise_final_json(GESTURE_TEXT, "say hi and wave", [])
    assert out["text"] == GESTURE_TEXT
    assert out["result"] == GESTURE_TEXT
    assert "<uneeq:action_wavehello />" in out["text"]
    assert out["history"][-1] == {"type": "apiMessage", "message": GESTURE_TEXT}
