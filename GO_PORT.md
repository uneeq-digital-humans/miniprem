# Go port of the MiniPrem Docker installer and CLI

This branch adds a Go (stdlib-only, Go 1.22) port of the Docker-path bash tooling, plus the
differential test harness used to prove it behaves the same as the bash it replaces.
**The bash scripts are unchanged and are still what customers run.** Cutover is a separate,
deliberate step (see "Cutover" below).

## Scope

Ported:

| bash | Go |
|---|---|
| `miniprem.sh` (all Docker-mode subcommands + CNS routing) | `internal/mp/cli_*.go` |
| `docker/scripts/install_miniprem.sh` | `internal/mp/inst_*.go` |
| `scripts/{logging,docker,audio,hash,environment,seed,prompts,prerequisites,allinone}.sh` | `internal/mp/lib_*.go` |
| `docker/scripts/merge-compose.sh` | `internal/mergecompose` |

Not ported — the Go binary calls these exactly as the bash did (`bash <script> ...`):
`kubernetes/scripts/**` (cloud/CNS/all-in-one deploys), Ansible, Terraform,
`docker/scripts/setup_multiple_rennys.sh` (not called by anything),
`docker/scripts/upgrade_nvidia_driver.sh` (not called), `setup-chatflow-post-deployment.sh`,
`deploy-chatflow.sh`, `scripts/lint-seed.sh`. Cloud provisioning has no honest local oracle, so it
stays in bash.

`internal/sh` is a small runtime that reproduces the bash behaviours that matter for fidelity:
external commands resolved via `PATH` with identical argv, unbuffered `read` (so child processes see
the rest of stdin), `read -p` prompts only on a TTY, `echo -e` escapes, `exit` from any depth
running the EXIT trap, INT/TERM traps, per-entry `IFS` (the installer runs with `IFS=$'\n\t'`).

## Layout

```
cmd/miniprem/          entry: miniprem {miniprem|install|merge-compose} [args...]
internal/sh/           bash-semantics runtime
internal/mp/           miniprem.sh + installer + sourced libs (one package = bash's one namespace)
internal/mergecompose/ merge-compose.sh
harness/               differential test harness (see harness/README.md)
PORTING.md             rules the port follows (fidelity over idiom)
DEVIATIONS.md          every known difference from bash, with justification
```

## Build

```
CGO_ENABLED=0 go build -o bin/miniprem ./cmd/miniprem                        # host arch
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/miniprem ./cmd/miniprem   # customer boxes
```

## Verification

Behavioural equivalence is checked by `harness/`, not by reading code. Each scenario runs the
ORIGINAL bash and then the Go binary (behind shims at the original script paths) in a throw-away
`ubuntu:24.04` container with no network, every system/hardware/network/time command stubbed, and
compares:

1. the ordered argv of every stubbed external command (docker, sudo, systemctl, curl, nvidia-smi, apt-get, …)
2. every file written (paths, modes, contents) under the repo, `/var/lib`, `/etc/systemd/system`, `/usr/local/bin`, `/root`, `/tmp`
3. stdout, stderr and exit code
4. how many bytes of stdin were consumed (i.e. which prompts were answered)

125 scenarios cover the installer (interactive default/full installs for each TTS/STT choice, seed
files incl. missing keys / bad lint / forced gates / all-in-one, failure gates: docker down, old
driver, low GPU memory, network down, Harbor login failure, wrong cwd, bad flags, the
`--tts-address` loop), every `miniprem.sh` subcommand in Docker and CNS mode, and `merge-compose.sh`
(clean merge, conflicts, prefer/rename, invalid YAML, missing yq).

Current result: **125/125 PASS**. `selfcheck.sh` (bash vs bash, twice) is also 125/125 with
byte-identical raw output, so the harness itself is deterministic. `compare.sh` was mutation-tested
(a one-line stdout edit and a truncated trace are both detected). Normalization is limited to four
documented rules (harness/README.md) and one single-line allowlist entry (DEVIATIONS.md D1).

```
docker build -t miniprem-harness:latest harness/
CGO_ENABLED=0 go build -o harness/bin/miniprem ./cmd/miniprem
harness/run_all.sh bash && harness/run_all.sh go && harness/compare.sh all
```

Not covered by the harness: TTY-mode prompts (all scenarios are non-TTY), functions that are dead
code in the bash (ported anyway, listed in DEVIATIONS.md), and real hardware.

## Upstream bash defects (preserved on purpose; fix separately)

The port reproduces these so that equivalence is provable; each should be fixed in BOTH
implementations (or in Go after cutover) as its own change:

- Declining telemetry on a fresh install exits 1: `update_env_variable` runs before `docker-compose.env` exists (install_miniprem.sh:2550 vs 2556).
- Interactive RIME without cached images: `RIME_QUAY_PASSWORD: unbound variable` (install_miniprem.sh:854).
- `--non-interactive` without a seed: `TTS_PROVIDER: unbound variable` (install_miniprem.sh:2571).
- A seed without `DEPLOYMENT_TARGET` dies at environment.sh:65 before the aggregated missing-keys report.
- `--tts-address` / `--tts-key` loop forever printing usage (`*) usage` without `shift`).
- `miniprem.sh start` without Harbor credentials calls `seed_is_non_interactive`, which miniprem.sh never sources ("command not found"), then falls back to an interactive prompt.
- `miniprem.sh` treats `merge-compose.sh` exit 2 as failure (`[ $? -eq 0 ] || [ $? -eq 2 ]`, lines 381, 855).
- `miniprem.sh start|stop` pass a single `-f`, so custom services from the override file never start.
- `miniprem.sh upgrade` step 5 builds `miniprem-monitor`, which has no `build:` section.
- The compose toggle `sed`s in `update_docker_compose_for_tts/stt` never match (markers are indented), so they are no-ops.
- `pull_images_parallel` and several other installer functions are dead code.
- `.miniprem_install_type`, `.miniprem_tts_provider`, `.miniprem_installation_marker` are tracked in git, so a fresh clone looks installed.

## Cutover (not done in this branch)

1. Decide distribution: customers do not have Go. Either ship a prebuilt `bin/miniprem` (linux/amd64)
   per release, or build it in CI and attach it to releases.
2. Replace the three entry scripts with shims (docs, systemd unit and desktop shortcut keep working):
   ```sh
   #!/bin/sh
   MINIPREM_SCRIPT_PATH="$0" exec "$(dirname "$0")/<relative path to>/bin/miniprem" <miniprem|install|merge-compose> "$@"
   ```
3. Acceptance on a disposable Ubuntu 24.04 GPU machine: the installer stops the compose stack, may
   restart docker, installs apt packages and a systemd unit, and logs into Harbor.

The binary has two env-gated test hooks used only by the harness, inert unless set:
`MINIPREM_FAKE_EPOCH` (fixed clock, no-op sleep) and `MINIPREM_MKTEMP_COUNTER_FILE`
(deterministic temp-file names shared with the harness's `mktemp` stub).
