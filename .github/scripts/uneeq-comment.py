#!/usr/bin/env python3
"""
Reply to an @claude mention via UneeQ's self-hosted vLLM endpoints.

Canonical copy — used by this repo's reusable CI workflows. Public repos
(e.g. miniprem) cannot call this private marketplace's reusable workflows,
so they vendor these scripts instead; keep vendored copies in sync.

Endpoint order: Dev (qwen38-flash-next) first, then Prod (qwen); the model is
discovered from /v1/models and filtered to the qwen allowlist. Exits non-zero if
every configured endpoint fails so the workflow can fall through to the Claude
step.

If the comment asks for a review or pre-mortem (keyword match, this is the
path a draft PR's author uses, since the automatic ready-state review in
inline-review.yml skips drafts), fetch the PR diff and apply the same review
policy uneeq-review.py uses instead of just chatting about the bare comment
text.

Env: UNEEQ_VLLM_DEV_ENDPOINT / UNEEQ_VLLM_DEV_KEY
     UNEEQ_VLLM_PROD_ENDPOINT / UNEEQ_VLLM_PROD_KEY
     GITHUB_COMMENT_TEXT
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request


# Model id order is arbitrary and gemma is always served — never pick data[0];
# only the qwen family is an eligible reviewer (Dev's deepseek was replaced by
# qwen38-flash-next, so the deepseek allowlist entry is gone).
MODEL_FAMILIES = ("qwen",)

POLICY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "review-policy")


def load_policy(name: str) -> str:
    """Read shared policy text. Vendored copies must ship review-policy/ too."""
    with open(os.path.join(POLICY_DIR, f"{name}.txt")) as f:
        return f.read().strip()


def cmd(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print(f"[WARN] {' '.join(args)} exited {result.returncode}", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
    return result.stdout.strip()


def discover_model(ep: str, key: str, prefer: str) -> str:
    """Pick an allowlisted model from the endpoint, preferring `prefer`'s family.

    Dev is asked for qwen38-flash-next and Prod for qwen, so the two hops of the
    failover chain don't both land on the same model. Preference is soft (Dev
    falling back to its qwen38-27b is fine); the qwen allowlist is hard. An
    endpoint offering no qwen model raises, and the caller falls through to the
    next one.
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
            "endpoint serves no qwen model "
            f"(offered: {', '.join(sorted(ids))})"
        )
    preferred = [i for i in eligible if prefer in i.lower()]
    # sorted() so a model with several served_model_name aliases resolves to the
    # same id on every run.
    return sorted(preferred or eligible)[0]


DEFAULT_SYSTEM = (
    "Helpful engineering assistant. Answer accurately and concisely. "
    "Provide code snippets when relevant. Say when uncertain."
)

# Same combined budget uneeq-review.py uses; the reviewer's request and the
# diff share it on the review path.
REVIEW_TOTAL_BUDGET = 22000
MAX_REVIEW_REQUEST = 2000


def chat(ep: str, key: str, model: str, user: str, system: str = DEFAULT_SYSTEM) -> str:
    payload = json.dumps({
        # top_p 1 is qwen3.8's documented recommendation; temperature 0.2 matches
        # the review path. max_tokens is the OUTPUT ceiling only — 4500 truncated.
        "model": model,
        "temperature": 0.2,
        "top_p": 1,
        "max_tokens": 16000,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
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
    # A reasoning model exhausting max_tokens mid-think returns content=null
    # (trail in reasoning_content) — raise so the caller fails over to the next
    # endpoint.
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
    # Input cap: prompt + max_tokens must fit max_model_len or vLLM 400s (it does
    # not slide the window), and max_tokens 16000 spends part of the same budget.
    max_input = 30000
    if len(comment) > max_input:
        comment = comment[:max_input] + "\n…(truncated)"

    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    issue_num = None
    is_pr = False
    if event_path and os.path.exists(event_path):
        with open(event_path) as f:
            ev = json.load(f)
        issue_num = (
            ev.get("issue", {}).get("number")
            or ev.get("pull_request", {}).get("number")
        )
        is_pr = bool(ev.get("issue", {}).get("pull_request")) or "pull_request" in ev

    repo = os.environ.get("GITHUB_REPOSITORY", "")

    system = DEFAULT_SYSTEM
    user = comment
    if is_pr and issue_num and re.search(load_policy("review-keywords"), comment, re.IGNORECASE):
        print(
            f"[uneeq-comment] Review/pre-mortem request on PR #{issue_num}, "
            "fetching diff.",
            flush=True,
        )
        diff = cmd("gh", "pr", "diff", str(issue_num))
        if diff:
            # The reviewer's request and the diff share the 22k review budget.
            if len(comment) > MAX_REVIEW_REQUEST:
                comment = comment[:MAX_REVIEW_REQUEST] + "\n…(truncated)"
            max_diff = REVIEW_TOTAL_BUDGET - MAX_REVIEW_REQUEST
            if len(diff) > max_diff:
                diff = (
                    f"(Truncated from {len(diff)} to {max_diff} chars.)\n"
                ) + diff[:max_diff]
            review_policy = load_policy("review-policy")
            pre_mortem_policy = load_policy("pre-mortem-policy")
            system = (
                "You are a senior engineer performing a Pull-Request code "
                f"review at a reviewer's request.\n\n{review_policy}\n\n"
                f"{pre_mortem_policy}"
            )
            user = (
                f"Pull Request #{issue_num} in {repo}\n\n"
                f"Reviewer's request: {comment}\n\nDiff:\n{diff}"
            )
        else:
            print(
                "[WARN] Could not fetch PR diff, falling back to plain chat.",
                flush=True,
            )

    endpoints = []
    # Dev first: it serves qwen38-flash-next, which is the preferred reviewer.
    # Prod is the always-on qwen fallback for when Dev is scaled to zero or down.
    for label, ep_var, key_var, prefer in (
        ("UneeQ Dev", "UNEEQ_VLLM_DEV_ENDPOINT", "UNEEQ_VLLM_DEV_KEY", "qwen38-flash-next"),
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
            content = chat(ep, key, model, user, system)
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
