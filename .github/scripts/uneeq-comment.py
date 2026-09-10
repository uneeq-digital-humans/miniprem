#!/usr/bin/env python3
"""
Reply to an @claude mention via UneeQ's self-hosted vLLM endpoints.

Vendored from uneeq-digital-humans/claude-code-marketplace (private repo;
miniprem is public so it cannot call the marketplace's reusable workflows).

Endpoint order: Dev (deepseek) first, then Prod (qwen); the model is discovered
from /v1/models and filtered to the deepseek/qwen allowlist. Exits non-zero if
every configured endpoint fails so the workflow can fall through to the Claude
step.

Env: UNEEQ_VLLM_DEV_ENDPOINT / UNEEQ_VLLM_DEV_KEY
     UNEEQ_VLLM_PROD_ENDPOINT / UNEEQ_VLLM_PROD_KEY
     GITHUB_COMMENT_TEXT
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request


# Only these two families are eligible. Both endpoints also serve gemma and (on
# Dev) the whole eval matrix, and /v1/models order is arbitrary — every
# comma-separated served_model_name alias registers as its own id — so the old
# data[0] pick could silently review a PR with gemma-e4b.
MODEL_FAMILIES = ("deepseek", "qwen")


def discover_model(ep: str, key: str, prefer: str) -> str:
    """Pick an allowlisted model from the endpoint, preferring `prefer`'s family.

    Dev is asked for deepseek and Prod for qwen, so the two hops of the failover
    chain don't both land on the same model. Preference is soft (Prod serving
    deepseek is fine); the deepseek/qwen allowlist is hard. An endpoint offering
    neither raises, and the caller falls through to the next one.
    """
    req = urllib.request.Request(
        f"{ep}/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        models = json.loads(resp.read())
    ids = [m["id"] for m in models.get("data", []) if m.get("id")]
    if not ids:
        raise RuntimeError("no models reported by endpoint")

    eligible = [i for i in ids if any(f in i.lower() for f in MODEL_FAMILIES)]
    if not eligible:
        raise RuntimeError(
            "endpoint serves no deepseek/qwen model "
            f"(offered: {', '.join(sorted(ids))})"
        )
    preferred = [i for i in eligible if prefer in i.lower()]
    # sorted() so a model with several served_model_name aliases resolves to the
    # same id on every run.
    return sorted(preferred or eligible)[0]


def chat(ep: str, key: str, model: str, comment: str) -> str:
    payload = json.dumps({
        # top_p 1 is qwen3.8's documented sampling recommendation; temperature drops
        # 0.3 -> 0.2 to match the review path. max_tokens is the OUTPUT ceiling only
        # — 4500 was truncating longer answers.
        "model": model,
        "temperature": 0.2,
        "top_p": 1,
        "max_tokens": 16000,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Helpful engineering assistant. Answer accurately and concisely. "
                    "Provide code snippets when relevant. Say when uncertain."
                ),
            },
            {"role": "user", "content": comment},
        ],
    }).encode()
    req = urllib.request.Request(
        f"{ep}/v1/chat/completions",
        data=payload,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
    choice = result["choices"][0]
    content = choice["message"].get("content")
    # Reasoning models (deepseek) that exhaust max_tokens mid-think return a
    # 200 with content=null and the partial chain-of-thought in
    # reasoning_content. Raise instead of returning it so the caller's loop
    # fails over to the next endpoint rather than posting nothing.
    if not (content and content.strip()):
        reasoning = choice["message"].get("reasoning_content") or ""
        raise RuntimeError(
            "empty completion content "
            f"(finish_reason={choice.get('finish_reason')}, "
            f"{len(reasoning)} chars of reasoning_content)"
        )
    return content


def main():
    comment = os.environ.get("GITHUB_COMMENT_TEXT", "").strip()
    comment = comment.replace("@claude", "", 1).strip()
    if not comment:
        print("[uneeq-comment] No comment text — exiting.", flush=True)
        sys.exit(1)
    # Input cap, and it is load-bearing: prompt + max_tokens must fit inside the
    # engine's max_model_len or vLLM rejects the request with a 400 — it does not
    # compact or slide the window. Raising max_tokens to 16000 spends part of that
    # same budget, so this stays.
    max_input = 30000
    if len(comment) > max_input:
        comment = comment[:max_input] + "\n…(truncated)"

    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    issue_num = None
    if event_path and os.path.exists(event_path):
        with open(event_path) as f:
            ev = json.load(f)
        issue_num = (
            ev.get("issue", {}).get("number")
            or ev.get("pull_request", {}).get("number")
        )

    repo = os.environ.get("GITHUB_REPOSITORY", "")

    endpoints = []
    # Dev first: it serves deepseek, which is the preferred reviewer. Prod is the
    # always-on qwen fallback for when Dev is scaled to zero or down.
    for label, ep_var, key_var, prefer in (
        ("UneeQ Dev", "UNEEQ_VLLM_DEV_ENDPOINT", "UNEEQ_VLLM_DEV_KEY", "deepseek"),
        ("UneeQ Prod", "UNEEQ_VLLM_PROD_ENDPOINT", "UNEEQ_VLLM_PROD_KEY", "qwen"),
    ):
        ep = os.environ.get(ep_var, "").strip().rstrip("/")
        key = os.environ.get(key_var, "").strip()
        if ep and key:
            endpoints.append((label, ep, key, prefer))

    if not endpoints:
        print("[FAIL] No UneeQ endpoints configured.", flush=True)
        sys.exit(1)

    content = None
    used_label = None
    for label, ep, key, prefer in endpoints:
        try:
            model = discover_model(ep, key, prefer)
            print(f"[uneeq-comment] Asking {label} ({model})...", flush=True)
            content = chat(ep, key, model, comment)
            used_label = label
            break
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            print(f"[WARN] {label} HTTP {exc.code}: {body[:500]}", flush=True)
        except Exception as exc:
            print(f"[WARN] {label} unavailable: {exc}", flush=True)

    if content is None:
        print("[FAIL] All UneeQ endpoints failed.", flush=True)
        sys.exit(1)

    if issue_num and repo:
        body = json.dumps({
            "body": f"_🤖 Via {used_label}_\n\n{content}"
        }).encode()
        subprocess.run(
            ["gh", "api", f"repos/{repo}/issues/{issue_num}/comments", "--input", "-"],
            input=body,
            check=True,
        )
        print(f"[uneeq-comment] Replied to #{issue_num}.", flush=True)
    else:
        print(content)


if __name__ == "__main__":
    main()
