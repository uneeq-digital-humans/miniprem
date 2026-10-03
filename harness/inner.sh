#!/bin/bash
# Container-side driver. Run by harness/run.sh inside the sandbox container
# (as root, --network none).  Mounts: /src (repo, ro), /h (harness, ro), /out (rw).
# env in: SCENARIO IMPL HOST_UID HOST_GID MINIPREM_FAKE_EPOCH
set -u
export LC_ALL=C TZ=UTC
export MINIPREM_FAKE_EPOCH="${MINIPREM_FAKE_EPOCH:-1767225600}"
SCEN_DIR=/h/scenarios/$SCENARIO
export SCENARIO_DIR=$SCEN_DIR TRACE_FILE=/out/trace.jsonl
export PATH=/h/stub:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export MINIPREM_MKTEMP_COUNTER_FILE=/tmp/.mktemp_counter

mkdir -p /run/stub /out/files /run/systemd/system /work
: > "$TRACE_FILE"

# ---- working copy of the repo (never touches /src) ---------------------------
# tar instead of `cp -a /src /work` so the harness dir (and its out/) is not copied
# recursively; the Go sources / notes are excluded so /work looks like a customer
# checkout.
tar -C /src --exclude=./.git --exclude=./harness --exclude=./cmd --exclude=./internal \
    --exclude=./go.mod --exclude=./go.sum --exclude=./port-notes --exclude=./PORT_STATUS.md \
    -cf - . | tar -C /work -xf - --no-same-owner

cd /work || exit 99

# ---- seams that are replaced by recorders in BOTH impls -----------------------
# (not ported: Go keeps exec'ing them, so their internals are out of scope)
recorder() {  # $1 = path relative to /work
    printf '#!/bin/sh\nSTUB_CMD="recorder:%s" exec /h/stub/stub "$@"\n' "$1" > "/work/$1"
    chmod 755 "/work/$1"
}
recorder kubernetes/scripts/deploy-allinone.sh
recorder setup-chatflow-post-deployment.sh
recorder deploy-chatflow.sh
for f in kubernetes/scripts/cns/*.sh; do recorder "$f"; done

# ---- Go mode: the three subjects become shims ----------------------------------
if [ "$IMPL" = "go" ]; then
    printf '#!/bin/sh\nMINIPREM_SCRIPT_PATH="$0" exec /h/bin/miniprem miniprem "$@"\n'      > /work/miniprem.sh
    printf '#!/bin/sh\nMINIPREM_SCRIPT_PATH="$0" exec /h/bin/miniprem install "$@"\n'       > /work/docker/scripts/install_miniprem.sh
    printf '#!/bin/sh\nMINIPREM_SCRIPT_PATH="$0" exec /h/bin/miniprem merge-compose "$@"\n' > /work/docker/scripts/merge-compose.sh
    chmod 755 /work/miniprem.sh /work/docker/scripts/install_miniprem.sh /work/docker/scripts/merge-compose.sh
fi

# ---- scenario setup (pre.sh) and env ------------------------------------------
if [ -f "$SCEN_DIR/pre.sh" ]; then ( cd /work && . "$SCEN_DIR/pre.sh" ) || echo "pre.sh failed" >&2; fi
set -a
CWD=/work
TIMEOUT=60
[ -f "$SCEN_DIR/env" ] && . "$SCEN_DIR/env"
set +a

# ---- baseline manifest (AFTER shims/recorders/pre.sh) ---------------------------
DIRS=(/work /var/lib /etc/systemd/system /usr/local/bin /root /tmp)
manifest() {  # $1 = output file; lines: path TAB type TAB mode TAB sha
    local tmp=/run/stub/manifest.$$
    find "${DIRS[@]}" -xdev -path /tmp/.mktemp_counter -prune -o -type f -exec sha256sum {} + 2>/dev/null \
        | awk '{ sha=$1; p=substr($0,67); print p "\t" sha }' | sort -t$'\t' -k1,1 > "$tmp.sha"
    find "${DIRS[@]}" -xdev -path /tmp/.mktemp_counter -prune -o \( -type f -o -type d -o -type l \) -printf '%p\t%y\t%m\n' 2>/dev/null \
        | sort -t$'\t' -k1,1 > "$tmp.mode"
    awk -F'\t' 'NR==FNR { sha[$1]=$2; next } { s = ($1 in sha) ? sha[$1] : "-"; print $1 "\t" $2 "\t" $3 "\t" s }' \
        "$tmp.sha" "$tmp.mode" > "$1"
    rm -f "$tmp.sha" "$tmp.mode"
}
manifest /run/stub/before.tsv

# ---- run the subject -------------------------------------------------------------
set -- $(:)  # clear
eval "set -- $(cat "$SCEN_DIR/args")"
kind="$1"; shift
case "$kind" in
    miniprem)      rel=miniprem.sh ;;
    install)       rel=docker/scripts/install_miniprem.sh ;;
    merge-compose) rel=docker/scripts/merge-compose.sh ;;
    *) echo "bad subject kind: $kind" >&2; exit 98 ;;
esac
if [ "$CWD" = /work ]; then subject="./$rel"; else subject="/work/$rel"; fi

STDIN_FILE=/dev/null
[ -f "$SCEN_DIR/stdin" ] && STDIN_FILE="$SCEN_DIR/stdin"
exec 3< "$STDIN_FILE"
cd "$CWD" || exit 97
timeout --preserve-status "$TIMEOUT" "$subject" "$@" <&3 > /out/stdout 2> /out/stderr
rc=$?
echo "$rc" > /out/rc
cd /work
# bytes of stdin the subject consumed (fd 3 shares the open file description)
awk '/^pos:/{print $2}' /proc/$$/fdinfo/3 > /out/stdin_pos
exec 3<&-

[ -f "$SCEN_DIR/post.sh" ] && ( cd /out && . "$SCEN_DIR/post.sh" )
# cap runaway output (the --tts-address infinite loop): the prefix is periodic
# and therefore deterministic
for f in stdout stderr; do
    if [ "$(stat -c %s /out/$f)" -gt 262144 ]; then
        head -c 262144 /out/$f > /out/$f.cut && mv /out/$f.cut /out/$f
        printf '\n[harness: output truncated at 256KiB]\n' >> /out/$f
    fi
done

# ---- after manifest + diff ----------------------------------------------------------
manifest /run/stub/after.tsv
awk -F'\t' '
    NR==FNR { b[$1] = $2 "\t" $3 "\t" $4; next }
    { a[$1] = $2 "\t" $3 "\t" $4 }
    END {
        for (p in a) {
            split(a[p], x, "\t")
            if (!(p in b)) print "added\t" p "\t" x[3] "\t" x[2] "\t" x[1]
            else if (a[p] != b[p]) print "changed\t" p "\t" x[3] "\t" x[2] "\t" x[1]
        }
        for (p in b) if (!(p in a)) { split(b[p], y, "\t"); print "removed\t" p "\t" y[3] "\t" y[2] "\t" y[1] }
    }' /run/stub/before.tsv /run/stub/after.tsv \
    | LC_ALL=C sort -t$'\t' -k2,2 -k1,1 \
    | awk -F'\t' '{ printf "%s %s sha=%s mode=%s type=%s\n", $1, $2, $3, $4, $5 }' > /out/files.diff

# copies of added/changed regular text files (<=1MiB) so diffs are inspectable
awk '$1 != "removed" && $0 ~ /type=f$/ { print $2 }' /out/files.diff | while IFS= read -r p; do
    [ -f "$p" ] || continue
    [ "$(stat -c %s "$p")" -le 1048576 ] || continue
    grep -Iq . "$p" 2>/dev/null || [ ! -s "$p" ] || continue
    mkdir -p "/out/files$(dirname "$p")"
    cp "$p" "/out/files$p"
done

{
    echo "impl=$IMPL"
    echo "scenario=$SCENARIO"
    echo "subject=$kind $*"
    echo "cwd=$CWD"
    echo "timeout=$TIMEOUT"
} > /out/meta
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /out
exit 0
