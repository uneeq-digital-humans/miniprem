#!/usr/bin/env python3
"""
Post a PR review via UneeQ's self-hosted vLLM endpoints.

Vendored from uneeq-digital-humans/claude-code-marketplace (the marketplace
repo is private, and miniprem is public, so the reusable-workflow pin cannot
be used here — see GitHub's reusable-workflow access rules).

Endpoint order: Dev (deepseek) first, then Prod (qwen). The model is discovered
from each endpoint's /v1/models and filtered to the deepseek/qwen allowlist —
both endpoints also serve gemma, which must never review a PR. Exits non-zero
only if every configured endpoint fails, which lets the workflow fall through
to the Claude step.

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


def chat(ep: str, key: str, model: str, system: str, user: str) -> str:
    payload = json.dumps({
        # top_p 1 is qwen3.8's documented sampling recommendation (0.93 clipped the
        # tail for no measured benefit); temperature stays low because review output
        # should be reproducible. max_tokens is the OUTPUT ceiling only — 8096 was
        # cutting long reviews off mid-finding.
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
    pr_number = os.environ.get("PR_NUMBER", "")
    if not pr_number:
        print("[FAIL] PR_NUMBER not set.", flush=True)
        sys.exit(1)
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

    print("[uneeq-review] Gathering PR diff...", flush=True)
    diff = cmd("gh", "pr", "diff", pr_number)
    if not diff:
        print("[FAIL] Could not retrieve PR diff — aborting.", flush=True)
        sys.exit(1)
    # Input cap, and it is load-bearing: prompt + max_tokens must fit inside the
    # engine's max_model_len or vLLM rejects the request with a 400 — it does not
    # compact or slide the window. Raising max_tokens to 16000 spends part of that
    # same budget, so this stays.
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
        "Respond with ONLY a JSON object (no markdown fences, no prose "
        "around it) in exactly this shape:\n"
        '{"summary": "2-4 sentence overall assessment",\n'
        ' "verdict": "APPROVE" | "REQUEST_CHANGES" | "COMMENT",\n'
        ' "findings": [{"path": "file path exactly as in the diff",\n'
        '               "line": 123,\n'
        '               "severity": "HIGH" | "MEDIUM" | "LOW",\n'
        '               "comment": "one actionable finding"}]}\n\n'
        '"findings" may be empty. "line" is the line number in the NEW '
        "version of the file and MUST be a line visible in the diff (count "
        "from each hunk header, @@ -old +new,count @@). If a finding cannot "
        "be tied to one diff line, set line to null.\n"
        "Verdict rules: REQUEST_CHANGES if any finding should block merging; "
        "APPROVE otherwise; COMMENT only for non-blocking observations."
    )

    user = f"Pull Request #{pr_number} in {repo}\n\nDiff:\n{diff}"

    content = None
    parsed = None
    used_label = None
    used_model = None
    for idx, (label, ep, key, prefer) in enumerate(endpoints):
        final_vllm = idx == len(endpoints) - 1
        try:
            model = discover_model(ep, key, prefer)
            print(f"[uneeq-review] Trying {label} ({model})...", flush=True)
            text = chat(ep, key, model, system, user)
            candidate = None
            try:
                candidate = json.loads(text[text.index("{"):text.rindex("}") + 1])
            except ValueError:
                candidate = None
            if isinstance(candidate, dict) and "verdict" in candidate:
                parsed = candidate
            elif not final_vllm:
                # Format is part of the quality bar: a model that can't emit
                # the findings JSON hands off to the next FREE endpoint. Only
                # the last vLLM attempt may post prose — its alternative is
                # paying Claude to reformat a review we already have.
                raise RuntimeError("response is not findings JSON")
            else:
                print(
                    f"[WARN] {label} response is not findings JSON; "
                    "posting as one comment.",
                    flush=True,
                )
            content = text
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

    header = f"_🧑‍💻 Reviewed via {used_label} ({used_model})_"

    if parsed is None:
        # Last vLLM endpoint ignored the JSON contract: post its raw text as
        # one review body, exactly like the pre-findings versions did.
        match = re.search(
            r"OVERALL VERDICT:\s*(APPROVE|REQUEST_CHANGES|COMMENT)", content, re.IGNORECASE
        )
        event = match.group(1).upper() if match else "COMMENT"
        summary = content[:44000]
        findings = []
    else:
        event = str(parsed.get("verdict", "COMMENT")).upper()
        if event not in ("APPROVE", "REQUEST_CHANGES", "COMMENT"):
            event = "COMMENT"
        summary = str(parsed.get("summary", "")).strip()[:44000]
        findings = [f for f in parsed.get("findings") or [] if isinstance(f, dict)][:30]

    print(f"[uneeq-review] Verdict: {event} ({len(findings)} findings)", flush=True)

    inline, unanchored = [], []
    for f in findings:
        note = f"**{str(f.get('severity', 'NOTE')).upper()}**: {str(f.get('comment', '')).strip()}"
        path, line = f.get("path"), f.get("line")
        if path and isinstance(line, int) and line > 0:
            inline.append({"path": str(path), "line": line, "side": "RIGHT", "body": note})
        else:
            unanchored.append(f"- {'`' + str(path) + '`: ' if path else ''}{note}")

    body = header + (f"\n\n{summary}" if summary else "")
    if unanchored:
        body += "\n\n" + "\n".join(unanchored)
    folded = body
    if inline:
        folded += "\n\n" + "\n".join(f"- `{c['path']}:{c['line']}` {c['body']}" for c in inline)

    def post(ev: str, text: str, comments: list) -> bool:
        payload = {"event": ev, "body": text}
        if comments:
            payload["comments"] = comments
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/pulls/{pr_number}/reviews", "--input", "-"],
            input=json.dumps(payload).encode(),
            capture_output=True,
        )
        if result.returncode == 0:
            print(f"[uneeq-review] Posted ({ev}, {len(comments)} inline).", flush=True)
            return True
        print(
            f"[WARN] posting {ev} with {len(comments)} inline comments failed: "
            f"{result.stderr.decode(errors='replace')[:500]}",
            flush=True,
        )
        return False

    # Posting ladder, because two distinct 422s exist: GITHUB_TOKEN cannot
    # APPROVE ("GitHub Actions is not permitted to approve pull requests"),
    # and any inline comment citing a line outside the diff rejects the whole
    # review. Downgrade APPROVE to COMMENT first, then fold the inline
    # findings into the body, before giving up.
    if event == "APPROVE":
        attempts = [
            ("APPROVE", body, inline),
            ("COMMENT", f"Passed review.\n\n{body}", inline),
            ("COMMENT", f"Passed review.\n\n{folded}", []),
        ]
    else:
        attempts = [(event, body, inline), (event, folded, [])]

    seen = set()
    for ev, text, comments in attempts:
        key = (ev, text, len(comments))
        if key in seen:
            continue
        seen.add(key)
        if post(ev, text, comments):
            break
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
