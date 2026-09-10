#!/usr/bin/env python3
"""
Post a PR review via UneeQ's self-hosted vLLM endpoints.

Canonical copy — used by this repo's reusable CI workflows. Public repos
(e.g. miniprem) cannot call this private marketplace's reusable workflows,
so they vendor these scripts instead; keep vendored copies in sync.

Endpoint order: Dev (qwen38-flash-next) first, then Prod (qwen). The model is
discovered from each endpoint's /v1/models and filtered to the qwen allowlist —
both endpoints also serve gemma, which must never review a PR. Exits non-zero
only if every configured endpoint fails, which lets the workflow fall through
to the Claude step.

Every posted review body is prefixed with REVIEW_MARKER. On each run we grep
past reviews on the PR for that marker (from either this script or the Claude
fallback) to tell a first review from a recheck of one already in progress.

Env: UNEEQ_VLLM_DEV_ENDPOINT / UNEEQ_VLLM_DEV_KEY
     UNEEQ_VLLM_PROD_ENDPOINT / UNEEQ_VLLM_PROD_KEY
     UNEEQ_HOUSE_RULES (optional — the calling repo's own documented
       conventions, gathered by the review-policy action; empty if none)
     PR_NUMBER
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

REVIEW_MARKER = "<!-- uneeq-review:v1 -->"

# Generated/lockfile artifacts: reviewing them wastes the tight diff budget and
# starves the hand-written code the model actually needs to see.
GENERATED_PATTERNS = re.compile(
    r"(^|/)(docs/(docs\.go|swagger\.json|swagger\.yaml)"
    r"|[^/]*\.sql\.go"
    r"|[^/]*\.pb\.go"
    r"|mocks?/[^/]+"
    r"|[^/]*_mock\.go"
    r"|package-lock\.json"
    r"|yarn\.lock"
    r"|go\.sum)$"
)


def strip_generated(diff: str) -> str:
    """Drop generated-file hunks from a unified diff, noting what was removed."""
    kept, dropped = [], []
    for chunk in re.split(r"(?m)^(?=diff --git )", diff):
        if not chunk:
            continue
        m = re.match(r"diff --git a/(\S+) b/(\S+)", chunk)
        path = m.group(2) if m else ""
        if path and GENERATED_PATTERNS.search(path):
            dropped.append(f"{path} ({len(chunk)} chars)")
        else:
            kept.append(chunk)
    if dropped:
        kept.append(
            "\n(Generated files omitted from this diff to preserve review "
            "budget: " + ", ".join(dropped) + ")\n"
        )
    return "".join(kept)

POLICY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "review-policy")


def load_policy(name: str) -> str:
    """Read shared policy text. Vendored copies must ship review-policy/ too."""
    with open(os.path.join(POLICY_DIR, f"{name}.txt")) as f:
        return f.read().strip()


def load_house_rules() -> str:
    """Return the calling repo's own documented conventions, or ''.

    This script ships with the action, so it cannot know which convention files
    a repo keeps; the caller-side review-policy step discovers them from the
    checkout it already made and passes the concatenation through. Empty is the
    normal case for a repo that documents nothing, and is not an error.
    """
    return os.environ.get("UNEEQ_HOUSE_RULES", "").strip()


def cmd(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print(f"[WARN] {' '.join(args)} exited {result.returncode}", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
    return result.stdout.strip()


# Model id order is arbitrary and gemma is always served — never pick data[0];
# only the qwen family is an eligible reviewer (Dev's deepseek was replaced by
# qwen38-flash-next, so the deepseek allowlist entry is gone).
MODEL_FAMILIES = ("qwen",)


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


def chat(ep: str, key: str, model: str, system: str, user: str) -> str:
    payload = json.dumps({
        # top_p 1 is qwen3.8's documented recommendation; temperature stays 0.2
        # for reproducibility. max_tokens is the OUTPUT ceiling — 8096 truncated.
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
    with urllib.request.urlopen(req, timeout=180) as resp:
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


def find_previous_review(pr_number: str) -> str:
    """Return the most recent past review body carrying REVIEW_MARKER, or ''.

    Its presence means this PR already went through an automated review
    (vLLM or Claude) and this run is a recheck, not a first pass.
    """
    raw = cmd(
        "gh", "pr", "view", pr_number,
        "--json", "reviews",
        "--jq", ".reviews",
    )
    if not raw:
        return ""
    try:
        reviews = json.loads(raw)
    except json.JSONDecodeError:
        return ""
    marked = [r for r in reviews if REVIEW_MARKER in (r.get("body") or "")]
    return marked[-1]["body"] if marked else ""


def main():
    pr_number = os.environ.get("PR_NUMBER", "")
    if not pr_number:
        print("[FAIL] PR_NUMBER not set.", flush=True)
        sys.exit(1)
    repo = os.environ.get("GITHUB_REPOSITORY", "")

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

    previous_review = find_previous_review(pr_number)
    recheck = bool(previous_review)

    print("[uneeq-review] Gathering PR diff...", flush=True)
    diff = cmd("gh", "pr", "diff", pr_number)
    if not diff:
        print("[FAIL] Could not retrieve PR diff — aborting.", flush=True)
        sys.exit(1)
    diff = strip_generated(diff)
    # Input cap: prompt + max_tokens must fit max_model_len or vLLM 400s (it does
    # not slide; an over-budget 400 fails over to the Claude step, so the worst
    # case is a fallback review, not a lost one). A recheck spends budget on the
    # prior review, shrinking the diff.
    total_budget = 500000
    max_prev = 6000 if recheck else 0
    if recheck and len(previous_review) > max_prev:
        previous_review = (
            f"(Truncated from {len(previous_review)} to {max_prev} chars.)\n"
        ) + previous_review[:max_prev]
    max_diff = total_budget - max_prev
    if len(diff) > max_diff:
        diff = (
            f"(Truncated from {len(diff)} to {max_diff} chars.)\n"
        ) + diff[:max_diff]

    print(f"[uneeq-review] Mode: {'recheck' if recheck else 'first review'}", flush=True)

    review_policy = load_policy("review-policy")
    pre_mortem_policy = load_policy("pre-mortem-policy")
    house_rules = load_house_rules()

    system = (
        "You are a senior engineer performing a Pull-Request code review.\n\n"
        + review_policy
        + "\n\n"
        + pre_mortem_policy
        + "\n\n"
    )
    # This is the section the policy's house-rules exception refers to. Only
    # present when the calling repo actually documents conventions.
    if house_rules:
        system += (
            "HOUSE RULES — the documented conventions of this repository. The "
            "house-rules exception in the policy above applies to this PR:\n\n"
            + house_rules
            + "\n\n"
        )
    if recheck:
        system += (
            "This PR already has a prior automated review (below). The author "
            "has since pushed changes. Add a section titled RECHECK: for each "
            "HIGH or MEDIUM item the prior review raised, state RESOLVED or "
            "STILL OPEN with a one-line reason, judged against the current "
            "diff, not the old one. Then list any new findings using the same "
            "severity rules.\n\n"
        )
    system += (
        "End with exactly one of:\n"
        "OVERALL VERDICT: APPROVE\n"
        "OVERALL VERDICT: REQUEST_CHANGES\n"
        "OVERALL VERDICT: COMMENT\n"
        "REQUEST_CHANGES requires at least one confirmed HIGH or MEDIUM finding: "
        "one whose mechanism you read the code for and named, per the grounding "
        "rules. If every finding you have is a HYPOTHESIS — a concern whose "
        "mechanism lives in code outside the diff — or you have no findings, the "
        "verdict is COMMENT. Do not let a hypothesis carry a blocking verdict."
    )

    user = f"Pull Request #{pr_number} in {repo}\n\nDiff:\n{diff}"
    if recheck:
        user += f"\n\nPrior automated review:\n{previous_review}"

    content = None
    used_label = None
    used_model = None
    for label, ep, key, prefer in endpoints:
        try:
            model = discover_model(ep, key, prefer)
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

    body = (
        f"{REVIEW_MARKER}\n"
        f"_🧑‍💻 Reviewed via {used_label} ({used_model})_\n\n{content[:44000]}"
    )

    def post(ev: str, text: str) -> bool:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/pulls/{pr_number}/reviews", "--input", "-"],
            input=json.dumps({"event": ev, "body": text}).encode(),
            capture_output=True,
        )
        if result.returncode == 0:
            return True
        print(
            f"[WARN] posting {ev} failed: "
            f"{result.stderr.decode(errors='replace')[:500]}",
            flush=True,
        )
        return False

    if post(event, body):
        print(f"[uneeq-review] Posted ({event}).", flush=True)
    elif event == "APPROVE":
        # GITHUB_TOKEN cannot approve PRs — the API 422s with "GitHub Actions is
        # not permitted to approve pull requests". Without this branch a finished
        # review is discarded on an unhandled CalledProcessError and the workflow
        # burns a Claude fallback run, which is why the vLLM path looked broken
        # whenever the model was happy with the diff. Downgrade to COMMENT, the
        # same escape hatch the Claude step's prompt already uses.
        if post("COMMENT", f"Passed review.\n\n{body}"):
            print(
                "[uneeq-review] Posted (COMMENT — APPROVE is not permitted for "
                "GitHub Actions).",
                flush=True,
            )
        else:
            sys.exit(1)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
