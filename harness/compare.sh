#!/bin/bash
# Usage: harness/compare.sh <scenario|all> [dirA dirB]
# Defaults: dirA=harness/out/bash  dirB=harness/out/go.  Prints PASS/FAIL per scenario
# (+ unified diff on failure); exit 1 if any FAIL.
#
# Compared artifacts (each normalized by harness/normalize): stdout stderr rc stdin_pos
# files.diff, files/** (contents of added/changed files) and trace.jsonl with the commands
# listed in harness/trace_ignore dropped.
# Allowlist: harness/allowlist/_all.sed and harness/allowlist/<scenario>.sed are sed scripts
# applied to BOTH sides (after normalization) of every compared text artifact.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHICH="${1:?scenario|all}"; A="${2:-$H/out/bash}"; B="${3:-$H/out/go}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

prep() {  # $1 dir  $2 scenario  $3 dest
    local src="$1/$2" dst="$3" f kind rel
    mkdir -p "$dst"
    local allow=()
    [ -f "$H/allowlist/_all.sed" ] && allow+=(-f "$H/allowlist/_all.sed")
    [ -f "$H/allowlist/$2.sed" ] && allow+=(-f "$H/allowlist/$2.sed")
    post() { if [ ${#allow[@]} -gt 0 ]; then sed "${allow[@]}"; else cat; fi; }
    for f in stdout stderr rc stdin_pos; do
        [ -f "$src/$f" ] && "$H/normalize" text < "$src/$f" | post > "$dst/$f"
    done
    # files.diff: for files whose text copy is compared separately under files/, drop the raw
    # sha (it would differ only by normalized content, e.g. the "Combined script hash" line).
    if [ -f "$src/files.diff" ]; then
        awk -v d="$src/files" '{ p=$2; if ($1 != "removed" && $0 ~ /type=f$/ && (getline _x < (d p)) >= 0) { sub(/sha=[0-9a-f]+/, "sha=<see files/>") } close(d p); print }' "$src/files.diff" \
            | "$H/normalize" text | post > "$dst/files.diff"
    fi
    if [ -f "$src/trace.jsonl" ]; then
        local pat; pat="$(sed -e '/^$/d' -e 's/.*/"cmd":"&"/' "$H/trace_ignore" | paste -sd'|')"
        { if [ -n "$pat" ]; then grep -vE "^\{($pat)," "$src/trace.jsonl"; else cat "$src/trace.jsonl"; fi; } \
            | "$H/normalize" trace | post > "$dst/trace.jsonl"
    fi
    if [ -d "$src/files" ]; then
        (cd "$src/files" && find . -type f -print0) | while IFS= read -r -d '' rel; do
            mkdir -p "$dst/files/$(dirname "$rel")"
            "$H/normalize" text < "$src/files/$rel" | post > "$dst/files/$rel"
        done
    fi
}

if [ "$WHICH" = all ]; then
    scen=(); for d in "$A"/*/; do scen+=("$(basename "$d")"); done
else scen=("$WHICH"); fi

fail=0
for s in "${scen[@]}"; do
    if [ ! -d "$A/$s" ] || [ ! -d "$B/$s" ]; then echo "FAIL $s (missing output dir: $A/$s or $B/$s)"; fail=1; continue; fi
    rm -rf "$TMP/a" "$TMP/b"
    prep "$A" "$s" "$TMP/a"; prep "$B" "$s" "$TMP/b"
    if d="$(cd "$TMP" && diff -ruN a b)"; then echo "PASS $s"
    else echo "FAIL $s"; printf '%s\n' "$d" | head -n "${DIFF_LINES:-200}"; fail=1; fi
done
exit $fail
