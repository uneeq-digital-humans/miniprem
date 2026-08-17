#!/usr/bin/env python3
"""
Post a PR review via UneeQ's self-hosted vLLM endpoints.

Vendored from uneeq-digital-humans/claude-code-marketplace (the marketplace
repo is private, and miniprem is public, so the reusable-workflow pin cannot
be used here — see GitHub's reusable-workflow access rules).

Endpoint order: Dev first, then Prod. The model is discovered from each
endpoint's /v1/models (Dev and Prod serve different models), so nothing is
hardcoded. Exits non-zero only if every configured endpoint fails, which
lets the workflow fall through to the Claude step.

Env: UNEEQ_VLLM_DEV_ENDPOINT / UNEEQ_VLLM_DEV_KEY
     UNEEQ_VLLM_PROD_ENDPOINT / UNEEQ_VLLM_PROD_KEY
     PR_NUMBER
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request


def cmd(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print(f"[WARN] {' '.join(args)} exited {result.returncode}", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
    return result.stdout.strip()


def discover_model(ep: str, key: str) -> str:
    req = urllib.request.Request(
        f"{ep}/v1/models",
        headers={"Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        models = json.loads(resp.read())
    return models["data"][0]["id"]


def chat(ep: str, key: str, model: str, system: str, user: str) -> str:
    payload = json.dumps({
        "model": model,
        "temperature": 0.2,
        "top_p": 0.93,
        "max_tokens": 8096,
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
    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.loads(resp.read())
    return result["choices"][0]["message"]["content"]


def main():
    pr_number = os.environ["PR_NUMBER"]
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

    print("[uneeq-review] Gathering PR diff...", flush=True)
    diff = cmd("gh", "pr", "diff", pr_number)
    if not diff:
        print("[FAIL] Could not retrieve PR diff — aborting.", flush=True)
        sys.exit(1)
    max_diff = 22000
    if len(diff) > max_diff:
        diff = (
            f"(Truncated from {len(diff)} to {max_diff} chars.)\n"
        ) + diff[:max_diff]

    system = (
        "You are a senior engineer performing a Pull-Request code review. "
        "Flag only REAL problems:\n"
        "- Correctness bugs (logic errors, off-by-one, concurrency hazards)\n"
        "- Security vulnerabilities (credential leaks, injection flaws)\n"
        "- Broken error-handling (silenced exceptions, unchecked returns)\n"
        "- Contradictions with surrounding code patterns\n\n"
        "Ignore cosmetics a linter catches.\n\n"
        "Prefix each finding with SEVERITY: HIGH / MEDIUM / LOW.\n\n"
        "End with exactly:\n"
        "OVERALL VERDICT: APPROVE\n"
        "OVERALL VERDICT: REQUEST_CHANGES\n"
        "OVERALL VERDICT: COMMENT"
    )

    user = f"Pull Request #{pr_number} in {repo}\n\nDiff:\n{diff}"

    content = None
    used_label = None
    used_model = None
    for label, ep, key in endpoints:
        try:
            model = discover_model(ep, key)
            print(f"[uneeq-review] Trying {label} ({model})...", flush=True)
            content = chat(ep, key, model, system, user)
            used_label, used_model = label, model
            break
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            print(f"[WARN] {label} HTTP {exc.code}: {body[:500]}", flush=True)
        except Exception as exc:  # URLError, timeout, bad JSON — try next endpoint
            print(f"[WARN] {label} unavailable: {exc}", flush=True)

    if content is None:
        print("[FAIL] All UneeQ endpoints failed.", flush=True)
        sys.exit(1)

    verdict = re.search(
        r"OVERALL VERDICT:\s*(APPROVE|REQUEST_CHANGES|COMMENT)", content, re.IGNORECASE
    )
    event = verdict.group(1).upper() if verdict else "COMMENT"

    print(f"[uneeq-review] Verdict: {event}", flush=True)

    review_payload = json.dumps({
        "event": event,
        "body": f"_🧑‍💻 Reviewed via {used_label} ({used_model})_\n\n{content[:44000]}",
    }).encode()

    subprocess.run(
        ["gh", "api", f"repos/{repo}/pulls/{pr_number}/reviews", "--input", "-"],
        input=review_payload,
        check=True,
    )
    print("[uneeq-review] Posted.", flush=True)


if __name__ == "__main__":
    main()
