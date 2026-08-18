#!/usr/bin/env python3
"""
Reply to an @claude mention via UneeQ's self-hosted vLLM endpoints.

Vendored from uneeq-digital-humans/claude-code-marketplace (private repo;
miniprem is public so it cannot call the marketplace's reusable workflows).

Endpoint order: Dev first, then Prod, model auto-discovered from /v1/models.
Exits non-zero if every configured endpoint fails so the workflow can fall
through to the Claude step.

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


def discover_model(ep: str, key: str) -> str:
    req = urllib.request.Request(
        f"{ep}/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        models = json.loads(resp.read())
    data = models.get("data", [])
    if not data:
        raise RuntimeError("no models reported by endpoint")
    return data[0]["id"]


def chat(ep: str, key: str, model: str, comment: str) -> str:
    payload = json.dumps({
        "model": model,
        "temperature": 0.3,
        "max_tokens": 4500,
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
    return result["choices"][0]["message"]["content"]


def main():
    comment = os.environ.get("GITHUB_COMMENT_TEXT", "").strip()
    comment = comment.replace("@claude", "", 1).strip()
    if not comment:
        print("[uneeq-comment] No comment text — exiting.", flush=True)
        sys.exit(1)
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
    for label, ep_var, key_var in (
        ("UneeQ Dev", "UNEEQ_VLLM_DEV_ENDPOINT", "UNEEQ_VLLM_DEV_KEY"),
        ("UneeQ Prod", "UNEEQ_VLLM_PROD_ENDPOINT", "UNEEQ_VLLM_PROD_KEY"),
    ):
        ep = os.environ.get(ep_var, "").strip().rstrip("/")
        key = os.environ.get(key_var, "").strip()
        if ep and key:
            endpoints.append((label, ep, key))

    if not endpoints:
        print("[FAIL] No UneeQ endpoints configured.", flush=True)
        sys.exit(1)

    content = None
    used_label = None
    for label, ep, key in endpoints:
        try:
            model = discover_model(ep, key)
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
