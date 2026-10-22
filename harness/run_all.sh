#!/bin/bash
# Usage: harness/run_all.sh <bash|go> [label]   -- every scenario, strictly serial.
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPL="${1:?impl}"; LABEL="${2:-$IMPL}"
for d in "$H"/scenarios/*/; do
    s="$(basename "$d")"
    case "$s" in _*) continue ;; esac
    "$H/run.sh" "$IMPL" "$s" "$LABEL" || echo "RUNNER-ERROR $s"
done
