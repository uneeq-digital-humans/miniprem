#!/bin/bash
# Usage: harness/run.sh <bash|go> <scenario> [label]
# Runs ONE scenario in a throw-away container; writes harness/out/<label|impl>/<scenario>/.
set -eu
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$H/.." && pwd)"
IMPL="${1:?impl (bash|go)}"; SCENARIO="${2:?scenario}"; LABEL="${3:-$IMPL}"
case "$IMPL" in bash|go) ;; *) echo "impl must be bash or go" >&2; exit 2 ;; esac
[ -d "$H/scenarios/$SCENARIO" ] || { echo "no such scenario: $SCENARIO" >&2; exit 2; }
if [ "$IMPL" = go ] && [ ! -x "$H/bin/miniprem" ]; then
    echo "IMPL=go needs an executable $H/bin/miniprem (linux binary, CGO_ENABLED=0)" >&2; exit 2
fi
docker image inspect miniprem-harness:latest >/dev/null 2>&1 || docker build -q -t miniprem-harness:latest "$H"

OUT="$H/out/$LABEL/$SCENARIO"
rm -rf "$OUT"; mkdir -p "$OUT"

# One container at a time, no network, no docker.sock, capped memory/CPU/pids.
docker run --rm --network none --memory 1g --memory-swap 1g --cpus 2 --pids-limit 1024 \
    -v "$REPO":/src:ro -v "$H":/h:ro -v "$OUT":/out \
    -e SCENARIO="$SCENARIO" -e IMPL="$IMPL" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -e MINIPREM_FAKE_EPOCH=1767225600 -e MINIPREM_MKTEMP_COUNTER_FILE=/tmp/.mktemp_counter -e LC_ALL=C -e TZ=UTC \
    miniprem-harness:latest bash /h/inner.sh
echo "$IMPL/$SCENARIO rc=$(cat "$OUT/rc" 2>/dev/null || echo '?')"
