# Differential-testing harness (bash -> Go port)

Runs the ORIGINAL bash subjects (`./miniprem.sh`, `docker/scripts/install_miniprem.sh`,
`docker/scripts/merge-compose.sh`) or, later, the Go binary behind shims, in a throw-away
container with every system/network/hardware/time/random command stubbed, and records
(a) ordered argv of every stubbed command, (b) files written, (c) stdout/stderr/exit code,
(d) bytes of stdin consumed. `compare.sh` diffs the normalized artifacts of two runs.

Nothing under the repo is modified: the repo is mounted read-only at `/src`, copied to `/work`
inside the container (tar, excluding `.git harness cmd internal go.mod port-notes PORT_STATUS.md`
so it looks like a customer checkout and `harness/out` is not copied recursively).

## Running
```
docker build -t miniprem-harness:latest harness/     # once (run.sh builds it if missing; build needs network)
harness/run.sh bash <scenario> [label]      # -> harness/out/<label|impl>/<scenario>/
harness/run_all.sh bash                     # every scenario, strictly serial (~2.5 min)
harness/compare.sh <scenario|all> [dirA dirB]   # default out/bash vs out/go; PASS/FAIL + unified diff; exit 1 on FAIL
harness/selfcheck.sh [scenario...]          # every scenario twice with IMPL=bash, compare run1 vs run2 (acceptance test, ~5 min)
```
`IMPL=go` needs `harness/bin/miniprem` (static linux binary). In that mode inner.sh overwrites the three
subjects inside the container's /work with `#!/bin/sh` + `MINIPREM_SCRIPT_PATH="$0" exec /h/bin/miniprem <miniprem|install|merge-compose> "$@"`,
and the "files written" baseline is taken AFTER the shims (and recorders, and pre.sh) are in place.

Container: `docker run --rm --network none --memory 1g --memory-swap 1g --cpus 2 --pids-limit 1024`, `/src` ro, `/h` (harness) ro,
`/out` rw, root inside, never docker.sock. One container at a time. Env in both impls: `LC_ALL=C TZ=UTC
MINIPREM_FAKE_EPOCH=1767225600 MINIPREM_MKTEMP_COUNTER_FILE=/tmp/.mktemp_counter`. Subject runs under
`timeout --preserve-status ${TIMEOUT:-60}` (so rc is the subject's own status, e.g. 143 from the SIGTERM trap), stdin from
`scenarios/<name>/stdin` (else /dev/null), NOT a TTY (so `read -p` prompts are not echoed; Go must check isatty).
Image `miniprem-harness:latest` = ubuntu:24.04 + real `bc jq` + real mikefarah `yq v4.44.3` (pure local tools; yq is therefore NOT stubbed/traced).

## Artifacts per run (`out/<impl>/<scenario>/`)
`trace.jsonl` (one JSON line per stub call: `{"cmd","argv":[...],"stdin_sha"?}`; recorders also carry `"env"`), `files.diff`
(manifest of /work /var/lib /etc/systemd/system /usr/local/bin /root /tmp before vs after, lines
`added|removed|changed <path> sha=<sha256|-> mode=<octal> type=<f|d|l>`, sorted by path; `/tmp/.mktemp_counter` excluded),
`files/` (copies of added/changed text files <=1MiB), `stdout`, `stderr`, `rc`, `stdin_pos` (bytes of stdin consumed), `meta`.

## Stubs
`stub/stub` is one dispatcher; each stubbed command is a symlink to it: sleep date sudo docker curl wget nvidia-smi nvidia-ctk free df
nproc lscpu lsb_release uname google-chrome pactl aplay arecord openssl uuidgen lsof ss apt-get apt dpkg dpkg-query systemctl service snap
socat nc hostname ip ping git kubectl mktemp gsettings usermod groupadd gpg editor.
Deliberately ABSENT (so `command -v` is false): docker-compose (v1), microk8s (only the `mp_cns_microk8s_*` scenarios add it), xdg-open, gio, code/nano/vim/vi.
Deliberately REAL: all pure text/file tools (sed awk grep cut tr sort head tail wc cat cp mv rm mkdir chmod ln find stat cmp tee install timeout xargs stty ps getopt perl),
bc, jq, yq, sha256sum. `tee`/`install`/`sudo mkdir|chmod|rm` therefore really write (inside the container; visible in files.diff); `sudo` itself is recorded
(`{"cmd":"sudo","argv":["tee",...]}`) and execs the rest via `env "$@"` (so `sudo -v` is a recorded no-op and `sudo VAR=x apt-get ...` works).
`/run/systemd/system` is pre-created so `enable_systemd_autostart` takes its real path. Built-ins: `sleep` no-op; `date` = `/usr/bin/date -d @$MINIPREM_FAKE_EPOCH "$@"`
(2026-01-01T00:00:00Z, identical across runs and in C locale so timestamps are NOT normalized);
`mktemp` (files, and `-d` directories - only merge-compose.sh:382 uses `-d`, unreachable without docker-compose v1): no template => `${TMPDIR:-/tmp}/tmp.XXXXXXXXXX`; counter read/incremented/written
as `<n>\n` under flock in `$MINIPREM_MKTEMP_COUNTER_FILE`; the trailing X-run is replaced by the zero-padded counter; created O_EXCL mode 0600 (dirs 0700); path printed.
Every trace line is appended under flock. `docker login ... --password-stdin` also records `stdin_sha` (the only stub that reads stdin, so answer files are never stolen).

### Rules files
`scenarios/<name>/rules` (first) then `scenarios/_common.rules`; lines `cmd<TAB>argv-regex<TAB>exit<TAB>stdout[<TAB>stderr[<TAB>max-uses]]`, `#` comments, first match wins, default exit 0 / empty.
`cmd` may be `*`. argv-regex is a bash ERE tested against the space-joined argv (`^$` = no args). stdout/stderr: `@file` (scenario dir, then `harness/fixtures/`) or a literal
interpreted by `printf %b`. `max-uses N` makes a rule stateful (fires its first N matches), used for "lsof sees redis once, then it is stopped".
`_common.rules` holds the happy-path world: RTX 6000 Ada 48GB driver 580.82.09 CUDA 13.0, Ubuntu 24.04 / kernel 6.8, 24 cores, 64GB, 800GB free, Chrome 130, pulse sinks,
Docker 27.3.1 + compose v2.29.7, toolkit installed, health `healthy`, curl 101 for WebSocket probes, vLLM chat completion JSON, git clean.

### Replaced scripts (identical in BOTH impls, because Go keeps exec'ing them and their internals are out of scope)
`kubernetes/scripts/deploy-allinone.sh`, `setup-chatflow-post-deployment.sh`, `deploy-chatflow.sh`, `kubernetes/scripts/cns/*.sh` become recorders
(`{"cmd":"recorder:<relpath>","argv":[..],"env":{NGC_API_KEY,HARBOR_*,PLATFORM_KEY,TENANT_ID,GEMMA_*,STT_PROVIDER,KIOSK_BRAND,RAG_ADMIN_KEY - only those set}}`).
`scripts/lint-seed.sh` is left REAL (bash/grep only); a Go reimplementation is therefore compared by outcome, not by trace.

### Scenario files
`args` (first word = subject: `miniprem|install|merge-compose`, rest = its args, shell-quoted), `stdin`, `rules`, `env` (sourced as shell, e.g. `CWD=/tmp`, `TIMEOUT=10`, `export EDITOR=editor`),
`pre.sh` (runs in /work BEFORE the baseline; helpers in `scenarios/_pre.sh`), `post.sh` (runs in /out after the run; only `install_tts_address_loop`). Shared seeds: `scenarios/_seeds/`.

## Normalization (`harness/normalize`, applied to stdout/stderr/rc/files.diff/trace/file contents) - deliberately minimal
- N1 strip ANSI CSI escapes: colours are cosmetic and Go may emit them differently only if it should not; it keeps comparison readable.
- N2 delete `show_spinner` frames (` [x]  ` + 6 backspaces): frame count depends on wall-clock timing inside bash itself; a Go port cannot/should not reproduce it. NOT observed in any of 125 runs (jobs finish before the first poll) - defensive.
- N3 `Combined script hash: <64 hex>` -> `<HASH>`: it hashes the (shimmed) script files. Also, in files.diff the raw `sha=` of any file whose text copy is compared under `files/` is dropped (the content is compared there, after N1-N3).
- Trace: commands listed in `harness/trace_ignore` (`date sleep mktemp`) are dropped before diffing (still stubbed so bash stays deterministic; Go uses native time/temp files).
- Allowlist: `harness/allowlist/_all.sed` and `allowlist/<scenario>.sed` are sed scripts applied to BOTH sides of every text artifact after normalization (deliberate deviations; currently none).
- NOT normalized: timestamps (fixed epoch), PIDs (none are printed), temp names (counter scheme), trace ordering. The old "parallel docker pull" sort was removed: `pull_images_parallel` (install:316) is dead code (only caller `pull_required_images` is never called) and the live
  pulls (docker.sh:213-222) run sequentially inside ONE background block, so trace order is deterministic and order bugs must stay visible.
- Raw (un-normalized) run1 vs run2 are byte-identical for all 125 scenarios.

## Scenarios (125; rc = bash rc; all exercised by selfcheck)
Fields: name | args | bash rc | where it ends.

| scenario | args | rc | ends |
|---|---|---|---|
| install_badflag | `install --bogus` | 1 | getopt error (stderr) under set -e, no usage |
| install_cli_args | `install --platform-key pk_cli_0123456789abcdefghij --tenant-id tenant-cli --azure-region westus --azure-speech-key azcli0123456789abcdef --renny-image cr.uneeq.io/uneeq/renny-renderer:cli --region eu --deployment-target cloud` | 0 | full flow, CLI flags parsed AFTER Azure prompts; completes |
| install_cli_bad_target | `install --deployment-target mars` | 1 | fatal "Invalid --deployment-target" (after prompts+prereqs) |
| install_eof_stdin | `install` | 1 | first read hits EOF -> silent rc 1 |
| install_help | `install --help` | 0 | logo + usage, exit 0 before any checks |
| install_int_default_azure | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_default_elevenlabs | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_default_extras | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_default_rime | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_default_rime_nocache | `install` | 1 | crash: RIME_QUAY_PASSWORD unbound (install:854) |
| install_int_full_stt1 | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_full_stt2 | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_full_stt3 | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| install_int_full_stt_invalid | `install` | 1 | Invalid STT choice, exiting. |
| install_int_telemetry_no | `install` | 1 | DEFECT: declining telemetry fails (env file not yet created) rc 1 |
| install_invalid_choice | `install` | 1 | Invalid choice, exiting. |
| install_tts_address_loop | `install --tts-address X` | 143 | infinite usage loop; killed by TERM, trap prints, rc 143 (preserve-status) |
| install_wrong_cwd | `install` | 1 | ║  ERROR: Installation script must be run from MiniPrem     ║ |
| merge_bad_option | `merge-compose --bogus` | 1 | 1 - Error (validation failed, missing tools, etc.) |
| merge_check_conflict | `merge-compose --check` | 2 | (see stdout) |
| merge_check_verbose | `merge-compose --check --verbose` | 0 | (see stdout) |
| merge_clean_override_exists | `merge-compose --output docker-compose.override.yml` | 0 | [SUCCESS] Merge completed successfully |
| merge_conflict | `merge-compose --verbose` | 2 | [SUCCESS] Merge completed successfully |
| merge_default | `merge-compose` | 0 | [SUCCESS] Merge completed successfully |
| merge_help | `merge-compose --help` | 0 | 1 - Error (validation failed, missing tools, etc.) |
| merge_invalid_yaml | `merge-compose --check` | 1 | [ERROR] Invalid YAML syntax in custom file: /work/docker/docker-compose.custom.yml |
| merge_no_custom | `merge-compose` | 1 | [ERROR] Custom file does not exist: /work/docker/docker-compose.custom.yml |
| merge_no_yq | `merge-compose --check` | 1 | [ERROR]   - yq: brew install yq (macOS), snap install yq (Ubuntu), or https://github.com/m |
| merge_prefer_official | `merge-compose --prefer-official --output out.yml` | 2 | [SUCCESS] Merge completed successfully |
| merge_rename | `merge-compose --rename-custom x- --file docker-compose.custom.yml` | 2 | [SUCCESS] Merge completed successfully |
| mp_cns_deploy | `miniprem deploy` | 0 | routed to cns recorder / CNS help text |
| mp_cns_destroy | `miniprem destroy` | 0 | routed to cns recorder / CNS help text |
| mp_cns_frobnicate | `miniprem frobnicate` | 0 | routed to cns recorder / CNS help text |
| mp_cns_help | `miniprem --help` | 0 | routed to cns recorder / CNS help text |
| mp_cns_logs_2 | `miniprem logs 2` | 0 | routed to cns recorder / CNS help text |
| mp_cns_logs_all | `miniprem logs all` | 0 | routed to cns recorder / CNS help text |
| mp_cns_logs_badnum | `miniprem logs 9` | 1 | Invalid pod number: 9 (have 2 pods) |
| mp_cns_logs_menu | `miniprem logs ` | 0 | routed to cns recorder / CNS help text |
| mp_cns_logs_nopods | `miniprem logs` | 1 | (see stdout) |
| mp_cns_logs_renny-1 | `miniprem logs renny-1` | 0 | routed to cns recorder / CNS help text |
| mp_cns_microk8s_noperm | `miniprem status` | 1 | "MicroK8s permission denied" message, rc 1 |
| mp_cns_microk8s_status | `miniprem status` | 0 | routed to cns recorder / CNS help text |
| mp_cns_noargs | `miniprem` | 0 | routed to cns recorder / CNS help text |
| mp_cns_restart | `miniprem restart` | 0 | routed to cns recorder / CNS help text |
| mp_cns_scale | `miniprem scale` | 0 | routed to cns recorder / CNS help text |
| mp_cns_scalequick | `miniprem scale-quick` | 0 | routed to cns recorder / CNS help text |
| mp_cns_sizer | `miniprem sizer` | 0 | routed to cns recorder / CNS help text |
| mp_cns_start | `miniprem start` | 0 | routed to cns recorder / CNS help text |
| mp_cns_start_args | `miniprem start --replicas 3` | 0 | routed to cns recorder / CNS help text |
| mp_cns_status | `miniprem status` | 0 | routed to cns recorder / CNS help text |
| mp_cns_stop | `miniprem stop` | 0 | routed to cns recorder / CNS help text |
| mp_cns_update | `miniprem update` | 0 | routed to cns recorder / CNS help text |
| mp_cns_upgrade | `miniprem upgrade` | 0 | routed to cns recorder / CNS help text |
| mp_config | `miniprem config` | 0 | (see stdout) |
| mp_config_custom | `miniprem config --custom` | 0 | restart: unless-stopped |
| mp_config_custom_none | `miniprem config --custom` | 0 | (see stdout) |
| mp_config_override | `miniprem config` | 0 | (see stdout) |
| mp_custom_add_byname | `miniprem custom add foo` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_cancel | `miniprem custom add` | 0 | INFO: Cancelled. |
| mp_custom_add_custom | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_empty_name | `miniprem custom add` | 1 | FATAL: Service name cannot be empty. |
| mp_custom_add_exists | `miniprem custom add postgres` | 1 | FATAL: Service 'postgres' already exists in docker-compose.custom.yml |
| mp_custom_add_mongodb | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_mysql | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_nginx | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_postgres | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_redis | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_add_renamed | `miniprem custom add` | 0 | [SUCCESS] Merge completed successfully |
| mp_custom_list | `miniprem custom list` | 0 | Status: stopped |
| mp_custom_list_empty | `miniprem custom list` | 0 | (see stdout) |
| mp_custom_list_none | `miniprem custom list` | 0 | (see stdout) |
| mp_custom_unknown | `miniprem custom bogus` | 1 | Usage: ./miniprem.sh custom [list/add] |
| mp_deploy_1 | `miniprem deploy` | 0 | full flow completes (final quality/multi-renny banner) |
| mp_deploy_2 | `miniprem deploy` | 0 | (see stdout) |
| mp_deploy_bad | `miniprem deploy` | 1 | Invalid selection |
| mp_help | `miniprem --help` | 1 | -h, --help: Show this usage information |
| mp_logs | `miniprem logs` | 0 | (see stdout) |
| mp_noargs | `miniprem` | 1 | -h, --help: Show this usage information |
| mp_pull | `miniprem pull` | 0 | (see stdout) |
| mp_pull_custom | `miniprem pull` | 0 | (see stdout) |
| mp_pull_dirty | `miniprem pull` | 1 | FATAL: Aborting pull to avoid conflicts. |
| mp_pull_regenerate | `miniprem pull --regenerate` | 0 | [SUCCESS] Merge completed successfully |
| mp_restart | `miniprem restart` | 0 | SUCCESS: ✓ Docker Compose services started successfully. |
| mp_restart_full | `miniprem restart` | 0 | SUCCESS: ✓ Docker Compose services started successfully. |
| mp_setup | `miniprem setup` | 0 | (see stdout) |
| mp_setup_flowise_down | `miniprem setup` | 0 | SUCCESS: ✓ Docker Compose services started successfully. |
| mp_start | `miniprem start` | 0 | SUCCESS: ✓ Docker Compose services started successfully. |
| mp_start_loginfail | `miniprem start` | 1 | FATAL: Cannot start services without valid Harbor credentials |
| mp_start_noenv | `miniprem start` | 1 | ERROR: Environment file not found: /work/docker/docker-compose.env |
| mp_start_noharbor | `miniprem start` | 0 | SUCCESS: ✓ Docker Compose services started successfully. |
| mp_status | `miniprem status` | 0 | (see stdout) |
| mp_stop | `miniprem stop` | 0 | SUCCESS: ✓ Docker Compose services stopped successfully. |
| mp_unknown | `miniprem frobnicate` | 1 | -h, --help: Show this usage information |
| mp_update_alias | `miniprem update` | 0 | SUCCESS:   Upgrade Complete! |
| mp_upgrade | `miniprem upgrade` | 0 | SUCCESS:   Upgrade Complete! |
| mp_upgrade_dirty | `miniprem upgrade` | 0 | SUCCESS:   Upgrade Complete! |
| mp_upgrade_notgit | `miniprem upgrade` | 1 | FATAL: Not a git repository. Cannot upgrade. |
| mp_upgrade_pullfail | `miniprem upgrade` | 1 | FATAL: ✗ Failed to pull updates from git. |
| mp_validate | `miniprem validate` | 0 | (see stdout) |
| mp_validate_conflict | `miniprem validate` | 2 | WARNING: Validation completed with warnings. Conflicts detected but can be resolved. |
| mp_validate_invalid | `miniprem validate` | 1 | ERROR: ✗ Validation failed. Please fix errors in docker-compose.custom.yml |
| mp_validate_nocustom | `miniprem validate` | 0 | (see stdout) |
| seed_allinone | `install --seed allinone.env` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_allinone_nokey | `install --seed allinone_nokey.env` | 1 | FATAL: Aborting due to incomplete seed configuration. |
| seed_bad_lint | `install --seed badlint.env` | 1 | FATAL: Refusing to load a seed that failed validation: /h/scenarios/_seeds/badlint.env |
| seed_docker_down | `install --seed happy.env` | 1 | fatal docker daemon unreachable |
| seed_existing_env | `install --seed happy.env` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_fewcores | `install --seed happy.env` | 1 | fatal <8 CPU cores |
| seed_force_gates | `install --seed full_rime.env --force` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_full | `install --seed full.env` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_full_rime | `install --seed full_rime.env` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_gate_dup_noforce | `install --seed happy.env` | 1 | FATAL: Installation aborted due to multiple MiniPrem installations detected. |
| seed_gate_redis_noforce | `install --seed full_rime.env` | 1 | redis conflict box, exit 1 (confirm -> no) |
| seed_happy | `install --seed happy.env` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_harbor_login_fail | `install --seed happy.env` | 1 | fatal Harbor auth failed (non-interactive) |
| seed_interactive | `install --seed mixed.env --interactive` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_low_gpu_mem | `install --seed happy.env` | 1 | fatal no GPU with 6000MB free |
| seed_missing_keys | `install --seed missing.env` | 1 | fatal DEPLOYMENT_TARGET not set (environment.sh:65) - aggregated report NEVER reached |
| seed_network_down | `install --seed happy.env` | 1 | fatal cannot reach api host |
| seed_nonint_noseed | `install --non-interactive` | 1 | crash: TTS_PROVIDER unbound (install:2571) |
| seed_not_found | `install --seed nope.env` | 1 | FATAL: Seed file not found: /h/scenarios/_seeds/nope.env |
| seed_old_driver | `install --seed happy.env` | 1 | fatal driver <580 |
| seed_telemetry_no | `install --seed telemetry_no.env` | 1 | DEFECT: same telemetry-decline failure via seed |
| seed_via_env | `install` | 0 | full flow completes (final quality/multi-renny banner) |
| seed_wss_unreachable | `install --seed happy.env` | 0 | full flow completes (final quality/multi-renny banner) |

Notes on early endings (all deliberate, they pin real bash behaviour): see "surprises" below. `seed_*` scenarios use `_seeds/*.env`.
`seed_force_gates` = full seed + `--force` + a duplicate-install dir + redis on :6379 (stopped on the 2nd lsof) -> proceeds through every gate.

## Surprising bash behaviour found (replicate, do not fix)
1. Declining telemetry on a fresh install aborts the installer: prompts.sh (decline branch) calls `update_env_variable`, but docker-compose.env is only created later (install:2556 vs 2550) -> rc 1 (`install_int_telemetry_no`, `seed_telemetry_no`).
2. Interactive RIME with no cached images: `while [ -z "$RIME_QUAY_PASSWORD" ]` (install:854) is an unbound variable under `set -u` -> rc 1 (`install_int_default_rime_nocache`).
3. `--non-interactive` without a seed: `TTS_PROVIDER: unbound variable` at install:2571. A seed missing DEPLOYMENT_TARGET dies in `configure_renny_quality` (environment.sh:65) before the aggregated missing-keys report (`seed_missing_keys`).
4. `miniprem.sh start` with no Harbor creds: environment.sh:127 calls `seed_is_non_interactive`, which miniprem.sh never sources ("command not found" on stderr) and then falls through to the interactive prompt (`mp_start_noharbor`).
5. `--tts-address X` -> infinite `usage` loop (install:2697). Output is huge, so `post.sh` collapses identical consecutive usage blocks to one block + `[harness: usage block repeated]`; the SIGTERM trap line and rc 143 are kept.
6. Any `install` run calls `miniprem.sh stop` (install:1824) first, which re-sources logging.sh (rotates `install_miniprem.log` into `logs/`), (its own log lines are written to the same files; not separately verified).
7. Boxed output (`log_section`, duplicate/port-conflict boxes) uses `printf %-Ns` with multi-byte glyphs; under `LC_ALL=C` printf pads by BYTES (multi-byte glyphs shrink the visible padding). A Go port must pad by bytes to match; real users (UTF-8) differ.

## Known caveats
- Non-TTY only (TTY variant via `script -qfc` not done). stdout and stderr are captured separately (cross-stream interleaving is not compared).
- Go mode is implemented but untested (no binary exists yet); yq/jq/bc are real and untraced.
- Busy loops (`sleep` is a no-op) make `wait_for_service`/spinners spin; harmless but CPU-heavy for a few ms.
- `/work` comes from a tar copy rather than `cp -a /src /work` (excludes listed above).
- Scenarios with fabricated test credentials only; `.miniprem_install_type/.miniprem_tts_provider/.miniprem_installation_marker` are tracked files so they show up as `changed` in files.diff.

### N4 — bash diagnostic line prefix
`^<path>.sh: line N: ` prefix stripped from text artifacts. bash prefixes its own diagnostics (unbound variable,
command not found, arithmetic errors) with the script path and line number; the Go port cannot reproduce bash
line numbers. Only the prefix is removed; the diagnostic text itself is still compared. Applies to lines
starting with a path ending in `.sh`, so ordinary output is unaffected.
