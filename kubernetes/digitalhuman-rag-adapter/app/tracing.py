"""OpenInference / OpenTelemetry tracing for the kiosk conversation path.

The kiosk SPA owns its conversation (Direct-Speak pattern) and calls the LLM via
the *same-origin* ``/v1/chat/completions`` endpoint. When that endpoint is the
instrumented proxy in :mod:`app.main`, this module records each call as an
OpenInference **LLM** span — the full input messages, the generated answer, and
token usage — and exports them over OTLP/gRPC to the on-box Arize Phoenix
(default ``127.0.0.1:4317``) under a dedicated project.

Why this exists: vLLM already exports its own OTLP spans to Phoenix
(``--otlp-traces-endpoint``), but those ``llm_request`` spans carry only token
counts / latency / sampling params — **no prompt or response text** — and use
the raw ``gen_ai.*`` conventions, so Phoenix can't render them as readable
conversations. The spans produced here use the OpenInference conventions
(prompt + completion text, ``openinference.span.kind == "LLM"``) so they show up
in Phoenix as proper, sortable LLM conversation cards.

Everything here is best-effort: if the OTel deps are missing, tracing is
disabled, or the exporter fails to start, the helpers degrade to no-ops so the
conversation proxy keeps working regardless.
"""
from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional

log = logging.getLogger("rag-adapter.tracing")

# --- OpenInference semantic-convention attribute keys ----------------------- #
# Hardcoded (rather than importing openinference-semantic-conventions) to keep
# the dependency surface minimal and the box rebuild robust. These strings are
# the stable OpenInference spec keys that Phoenix renders.
_SPAN_KIND = "openinference.span.kind"
_INPUT_VALUE = "input.value"
_INPUT_MIME = "input.mime_type"
_OUTPUT_VALUE = "output.value"
_OUTPUT_MIME = "output.mime_type"
_LLM_MODEL = "llm.model_name"
_LLM_PROVIDER = "llm.provider"
_LLM_SYSTEM = "llm.system"
_LLM_INVOCATION_PARAMS = "llm.invocation_parameters"
_LLM_INPUT_MESSAGES = "llm.input_messages"
_LLM_OUTPUT_MESSAGES = "llm.output_messages"
_MSG_ROLE = "message.role"
_MSG_CONTENT = "message.content"
_TOK_PROMPT = "llm.token_count.prompt"
_TOK_COMPLETION = "llm.token_count.completion"
_TOK_TOTAL = "llm.token_count.total"

_ENABLED = os.getenv("PHOENIX_TRACING_ENABLED", "true").strip().lower() in {
    "1", "true", "yes", "on",
}
# Phoenix OTLP/HTTP traces collector (Phoenix serves this on its UI port :6006).
# HTTP, not gRPC: avoids a grpcio version clash with pymilvus 2.4.9.
_ENDPOINT = os.getenv("PHOENIX_OTLP_ENDPOINT", "http://127.0.0.1:6006/v1/traces")
# Phoenix routes spans to a project via this resource attribute. A dedicated
# project keeps readable conversations out of vLLM's noisy "default" project.
_PROJECT = os.getenv("PHOENIX_PROJECT", "Digital Human Kiosk")
# Static metadata stamped on every span so a Phoenix viewer can tell at a glance
# which box/deployment a conversation came from. Identical on Docker & kubeadm —
# only PHOENIX_OTLP_ENDPOINT differs between them. Seed-driven for the Dell ISO.
_DEPLOYMENT_KIND = os.getenv("DEPLOYMENT_KIND", "")   # e.g. "kubeadm" | "docker"
_SITE_ALIAS = os.getenv("SITE_ALIAS", "")             # e.g. "dell-lobby-kiosk"
# Machine identifier. EMPTY on a single local install -> project stays the clean
# base name ("kiosk-conversations"). Set it (seed-driven "machine number", e.g.
# "dell-001" or the node name) on multi-machine fleets so the Phoenix project
# becomes "<machine>-kiosk-conversations" and every span carries machine.id —
# this is what keeps the LLM / Riva-STT / Renny traces separable when someone is
# looking at more than one box (or one aggregated Phoenix).
_MACHINE_ID = os.getenv("MACHINE_ID", "").strip()


def _effective_project() -> str:
    return f"{_MACHINE_ID} · {_PROJECT}" if _MACHINE_ID else _PROJECT

_tracer = None  # type: ignore[var-annotated]
_status_error = None  # OTel StatusCode.ERROR, captured lazily


def init() -> None:
    """Initialise the OTLP exporter + tracer. Safe to call once at startup."""
    global _tracer, _status_error
    if not _ENABLED:
        log.info("Phoenix tracing disabled (PHOENIX_TRACING_ENABLED=false)")
        return
    if _tracer is not None:
        return
    try:
        from opentelemetry import trace
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.trace import StatusCode

        _status_error = StatusCode.ERROR
        project = _effective_project()
        resource = Resource.create(
            {
                "service.name": "kiosk-rag-adapter",
                # Phoenix project routing (recognised by the Phoenix collector).
                # Machine-prefixed when MACHINE_ID is set (multi-box fleets).
                "openinference.project.name": project,
            }
        )
        provider = TracerProvider(resource=resource)
        exporter = OTLPSpanExporter(endpoint=_ENDPOINT)
        provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(provider)
        _tracer = trace.get_tracer("rag-adapter.kiosk-conversations")
        log.info(
            "Phoenix tracing on: project=%r -> OTLP %s", project, _ENDPOINT
        )
    except Exception:  # pragma: no cover - never break the app over telemetry
        log.exception("Phoenix tracing init failed; conversations untraced")
        _tracer = None


def _flatten_content(content: Any) -> str:
    """OpenAI content may be a string or a list of typed parts; join the text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, dict):
                parts.append(p.get("text") or p.get("content") or "")
            else:
                parts.append(str(p))
        return " ".join(x for x in parts if x)
    return "" if content is None else str(content)


def _set_messages(span, prefix: str, messages: List[Dict[str, Any]]) -> None:
    for i, m in enumerate(messages):
        if not isinstance(m, dict):
            continue
        span.set_attribute(f"{prefix}.{i}.{_MSG_ROLE}", str(m.get("role", "")))
        span.set_attribute(
            f"{prefix}.{i}.{_MSG_CONTENT}", _flatten_content(m.get("content"))
        )


def start_llm_span(
    model: str,
    messages: List[Dict[str, Any]],
    params: Dict[str, Any],
    *,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None,
    span_name: Optional[str] = None,
):
    """Begin an OpenInference LLM span. Returns the span, or None if disabled.

    session_id groups all turns of one conversation into a single Phoenix session
    (and is the shared thread that lets the kiosk's own STT/speak spans join this
    LLM span into one end-to-end trace). metadata (persona, language, …) + the
    static deployment/site tags make conversations searchable and easy to read.
    """
    if _tracer is None:
        return None
    try:
        span = _tracer.start_span(span_name or "llm.chat")
        span.set_attribute(_SPAN_KIND, "LLM")
        span.set_attribute(_LLM_MODEL, str(model or ""))
        span.set_attribute(_LLM_PROVIDER, "vllm")
        span.set_attribute(_LLM_SYSTEM, "openai")
        if params:
            span.set_attribute(_LLM_INVOCATION_PARAMS, json.dumps(params))
        _set_messages(span, _LLM_INPUT_MESSAGES, messages)
        # input.value: the raw request for the "Input" panel in Phoenix.
        span.set_attribute(
            _INPUT_VALUE, json.dumps({"model": model, "messages": messages})
        )
        span.set_attribute(_INPUT_MIME, "application/json")
        # Session grouping + identity (OpenInference conventions Phoenix renders).
        if session_id:
            span.set_attribute("session.id", str(session_id))
        if user_id:
            span.set_attribute("user.id", str(user_id))
        # Merge static (deployment/site) + per-request (persona/language/model) metadata.
        md: Dict[str, Any] = {}
        if _MACHINE_ID:
            md["machine"] = _MACHINE_ID
        if _DEPLOYMENT_KIND:
            md["deployment"] = _DEPLOYMENT_KIND
        if _SITE_ALIAS:
            md["site"] = _SITE_ALIAS
        if model:
            md["model"] = model
        if metadata:
            md.update({k: v for k, v in metadata.items() if v})
        if md:
            span.set_attribute("metadata", json.dumps(md))
        return span
    except Exception:  # pragma: no cover
        log.exception("start_llm_span failed")
        return None


def end_llm_span(
    span,
    output_text: str,
    usage: Optional[Dict[str, Any]] = None,
) -> None:
    """Record the generated answer + token usage and close the span."""
    if span is None:
        return
    try:
        span.set_attribute(_OUTPUT_VALUE, output_text or "")
        span.set_attribute(_OUTPUT_MIME, "text/plain")
        span.set_attribute(f"{_LLM_OUTPUT_MESSAGES}.0.{_MSG_ROLE}", "assistant")
        span.set_attribute(
            f"{_LLM_OUTPUT_MESSAGES}.0.{_MSG_CONTENT}", output_text or ""
        )
        if usage:
            pt = usage.get("prompt_tokens")
            ct = usage.get("completion_tokens")
            tt = usage.get("total_tokens")
            if isinstance(pt, int):
                span.set_attribute(_TOK_PROMPT, pt)
            if isinstance(ct, int):
                span.set_attribute(_TOK_COMPLETION, ct)
            if isinstance(tt, int):
                span.set_attribute(_TOK_TOTAL, tt)
            elif isinstance(pt, int) and isinstance(ct, int):
                span.set_attribute(_TOK_TOTAL, pt + ct)
    except Exception:  # pragma: no cover
        log.exception("end_llm_span set-attributes failed")
    finally:
        try:
            span.end()
        except Exception:  # pragma: no cover
            pass


def fail_llm_span(span, exc: BaseException) -> None:
    """Mark the span errored (upstream failure) and close it."""
    if span is None:
        return
    try:
        if _status_error is not None:
            span.set_status(_status_error)
        span.record_exception(exc)
    except Exception:  # pragma: no cover
        pass
    finally:
        try:
            span.end()
        except Exception:  # pragma: no cover
            pass
