#!/bin/bash
# Determinism acceptance test: every scenario run TWICE with IMPL=bash, outputs compared
# with the normal compare logic.  Usage: harness/selfcheck.sh [scenario ...]
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ $# -gt 0 ]; then scen=("$@"); else
    scen=(); for d in "$H"/scenarios/*/; do s="$(basename "$d")"; case "$s" in _*) ;; *) scen+=("$s") ;; esac; done
fi
pass=0; fail=0; failed=()
for s in "${scen[@]}"; do
    "$H/run.sh" bash "$s" run1 >/dev/null || echo "RUNNER-ERROR $s run1"
    "$H/run.sh" bash "$s" run2 >/dev/null || echo "RUNNER-ERROR $s run2"
    if out="$("$H/compare.sh" "$s" "$H/out/run1" "$H/out/run2")"; then
        pass=$((pass+1)); echo "PASS $s (rc=$(cat "$H/out/run1/$s/rc"))"
    else fail=$((fail+1)); failed+=("$s"); echo "$out"; fi
done
echo "selfcheck: $pass passed, $fail failed (of ${#scen[@]})"
[ $fail -eq 0 ]
