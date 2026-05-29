#!/bin/bash
# lint-seed.sh
#
# Lint a MiniPrem unattended-install seed file for the "silent" configuration
# pitfalls that pass a naive read but corrupt the install: unquoted $ in
# values (shell expansion), CRLF line endings, a UTF-8 BOM, trailing
# whitespace in credentials, and duplicate keys.
#
# This is a STANDALONE validator with no dependency on the rest of the
# installer — it is the single source of truth for seed validation. The
# installer calls it from scripts/seed.sh before sourcing a --seed file, and
# the ISO-builder project can run it at build time on the same file.
#
# Usage:
#   bash scripts/lint-seed.sh <seed-file> [--strict] [--quiet]
#
# Options:
#   --strict   Treat warnings as errors (recommended for build-time gating).
#   --quiet    Suppress the per-issue WARN/OK chatter; still prints errors and
#              the final summary line.
#
# Exit codes:
#   0   no errors (warnings allowed unless --strict)
#   1   one or more errors found — do not load this seed
#   2   usage error (missing/unreadable file, bad flag)
#
# Only lines of the form MINIPREM_SEED_*=... are value-checked. Comments and
# blank lines are ignored. Single-quoted values are treated as literal (their
# $ does not expand); double-quoted and bare values are NOT exempt.

set -uo pipefail

STRICT="no"
QUIET="no"
SEED_FILE=""

if [ -t 2 ]; then
    C_RED=$'\033[0;31m'; C_YEL=$'\033[0;33m'; C_GRN=$'\033[0;32m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_YEL=""; C_GRN=""; C_OFF=""
fi

ERRORS=0
WARNINGS=0

err()  { echo "${C_RED}ERROR:${C_OFF} $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { [ "$QUIET" = "yes" ] || echo "${C_YEL}WARN:${C_OFF}  $*" >&2; WARNINGS=$((WARNINGS + 1)); }
note() { [ "$QUIET" = "yes" ] || echo "$*"; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT="yes"; shift ;;
        --quiet)  QUIET="yes"; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown argument: $1" >&2; usage 2 ;;
        *)  if [ -z "$SEED_FILE" ]; then SEED_FILE="$1"; else echo "Unexpected argument: $1" >&2; usage 2; fi; shift ;;
    esac
done

if [ -z "$SEED_FILE" ]; then
    echo "ERROR: no seed file given." >&2
    usage 2
fi
if [ ! -f "$SEED_FILE" ]; then
    echo "${C_RED}ERROR:${C_OFF} Seed file not found: $SEED_FILE" >&2
    exit 2
fi
if [ ! -r "$SEED_FILE" ]; then
    echo "${C_RED}ERROR:${C_OFF} Seed file not readable: $SEED_FILE" >&2
    exit 2
fi

note "Linting seed file: $SEED_FILE"

# ---------------------------------------------------------------------------
# File-level checks (whole-file, not per-line)
# ---------------------------------------------------------------------------

# UTF-8 BOM (EF BB BF) at the very start corrupts the first key name.
if [ "$(head -c 3 "$SEED_FILE" | od -An -t x1 | tr -d ' \n')" = "efbbbf" ]; then
    err "File begins with a UTF-8 BOM — it corrupts the first key. Re-save as UTF-8 without BOM."
fi

# CRLF line endings (Windows). A trailing \r ends up appended to every value
# and breaks both sourcing and the $-expansion scan below.
if grep -qU $'\r' "$SEED_FILE" 2>/dev/null; then
    err "File has CRLF (Windows) line endings — convert to LF (e.g. 'sed -i \$'s/\\\\r\$//' $SEED_FILE' or dos2unix)."
fi

# Duplicate keys: when the file is sourced, the later definition silently wins.
# Done at file level with grep|sort|uniq so the linter stays portable to bash
# 3.x (no associative arrays needed).
dup_keys="$(grep -oE '^[[:space:]]*MINIPREM_SEED_[A-Za-z0-9_]+[[:space:]]*=' "$SEED_FILE" \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*=$//' \
    | sort | uniq -d)"
if [ -n "$dup_keys" ]; then
    while IFS= read -r dk; do
        [ -z "$dk" ] && continue
        err "duplicate key '$dk' — defined more than once; the later value silently wins."
    done <<< "$dup_keys"
fi

# ---------------------------------------------------------------------------
# Per-line value checks
# ---------------------------------------------------------------------------
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # Normalise away a trailing CR so per-line checks below are accurate even
    # when the file-level CRLF error has already been recorded.
    line="${line%$'\r'}"

    # Skip blank lines and comments (leading-whitespace comments included).
    case "$line" in
        ''|\#*|[[:space:]]*\#*) continue ;;
    esac

    # Only consider MINIPREM_SEED_* assignments.
    case "$line" in
        MINIPREM_SEED_*=*) ;;
        [[:space:]]*MINIPREM_SEED_*=*)
            warn "line $lineno: leading whitespace before key — keep assignments flush-left."
            line="${line#"${line%%[![:space:]]*}"}"
            ;;
        *) continue ;;
    esac

    key="${line%%=*}"
    raw_value="${line#*=}"

    # Tab around the assignment is almost always an accident.
    case "$line" in
        *$'\t'*) warn "line $lineno: '$key' line contains a TAB character." ;;
    esac

    # Strip a best-effort trailing inline comment (a # preceded by whitespace).
    value="${raw_value%%[[:space:]]#*}"

    # Single-quoted values are literal: $ is safe, and surrounding quotes are
    # intentional. Strip the quotes for the trailing-whitespace check but skip
    # the $-expansion check.
    single_quoted="no"
    case "$value" in
        \'*\') single_quoted="yes" ;;
    esac

    if [ "$single_quoted" = "no" ]; then
        # Unquoted (or double-quoted) $ followed by an identifier char, digit,
        # or { — the shell would expand it on source, corrupting the value.
        if [[ "$value" =~ \$[A-Za-z_0-9{] ]]; then
            err "line $lineno: '$key' has an unquoted \$ that the shell will expand. Wrap the value in SINGLE quotes, e.g. ${key}='robot\$customer-name'."
        fi
    fi

    # Trailing whitespace inside the value (after stripping surrounding single
    # quotes if present). Silent killer for credentials.
    check_val="$value"
    if [ "$single_quoted" = "yes" ]; then
        check_val="${value#\'}"; check_val="${check_val%\'}"
    fi
    case "$check_val" in
        *[[:space:]])
            if [[ "$key" =~ (PASSWORD|KEY|TOKEN|SECRET) ]]; then
                err "line $lineno: '$key' value has trailing whitespace — this silently breaks credential auth. Remove it."
            else
                warn "line $lineno: '$key' value has trailing whitespace."
            fi
            ;;
    esac
done < "$SEED_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [ "$STRICT" = "yes" ] && [ "$WARNINGS" -gt 0 ]; then
    err "--strict: promoting $WARNINGS warning(s) to errors."
fi

echo
if [ "$ERRORS" -eq 0 ]; then
    note "${C_GRN}SEED OK${C_OFF}: $SEED_FILE (${WARNINGS} warning(s))"
    exit 0
fi
echo "${C_RED}SEED INVALID${C_OFF}: $SEED_FILE — ${ERRORS} error(s), ${WARNINGS} warning(s)." >&2
exit 1
