# Porting rules (bash -> Go)

Goal: the Go binary must be **observably identical** to the bash scripts under the
differential harness (`harness/`): same ordered external-command argv (except
`date`/`sleep`/`mktemp`), same files written (byte-identical), same stdout/stderr
bytes, same exit code, same stdin consumption. Readability is secondary to fidelity.
Preserve bugs (see GO_PORT.md and DEVIATIONS.md); never "fix" anything silently. If you
believe a fix is unavoidable, stop and report it instead.

## Layout
- `cmd/miniprem/main.go` — entry dispatch: `miniprem` | `install` | `merge-compose`.
- `internal/sh` — runtime (commands, exit/traps, `read`, `echo -e`). Use it; extend it
  only if something is genuinely missing, and say so in your report.
- `internal/mp` — ONE package mirroring bash's single global namespace:
  - `lib_<name>.go` for each `scripts/<name>.sh` (logging, docker, audio, hash,
    environment, seed, prompts, prerequisites, allinone).
  - `inst_*.go` for `docker/scripts/install_miniprem.sh`.
  - `cli_*.go` for `miniprem.sh`.
- `internal/mergecompose` — `docker/scripts/merge-compose.sh` (separate process in bash,
  separate package here).
- Stdlib only. No third-party modules. Go 1.22.

## Naming
- Bash function `foo_bar_baz` -> Go `fooBarBaz` (unexported), same package, so every
  porter can call functions they did not write by deriving the name mechanically.
- Collisions: `usage` in miniprem.sh -> `cliUsage`; in the installer -> `instUsage`.
  `configure_eleven_labs` is defined twice in the installer; bash uses the LAST
  definition (line 770) — port only that one. `configure_region_endpoints` and
  `prompt_for_region` exist in scripts/environment.sh / scripts/prompts.sh AND in the
  installer; the lib copies are never called by miniprem.sh, so port only the
  installer versions (in `inst_*.go`) and skip the lib copies (note it in a comment).
- Bash globals -> package-level Go vars with the SAME UPPER_CASE name (e.g.
  `var INSTALL_TYPE string`). Declare each global in the file that ports the script that
  first assigns it at top level (lib file before installer); shared installer globals
  live in `globals_libs.go`. Arrays -> `[]string`.
- Unset vs empty matters under `set -u` — if the script relies on `${X:-}` vs `$X`,
  model "unset" explicitly (e.g. a `map[string]bool` or pointer) only where behaviour
  differs.

## Semantics checklist (the usual sources of divergence)
- **External commands**: every command the script runs that is not a bash builtin
  and not a pure text tool MUST be run via `sh.C(...)`/`sh.Run` with the identical argv
  (the harness compares argv). This includes `docker`, `sudo`, `curl`, `nvidia-smi`,
  `free`, `df`, `nproc`, `uname`, `lsb_release`, `systemctl`, `apt-get`, `openssl`,
  `uuidgen`, `bc`, `pactl`, `tee` when used with sudo, `getent`, `id` ... Do NOT replace
  them with Go stdlib equivalents (os.Hostname, runtime.NumCPU, syscall.Statfs): the
  harness stubs them and the customer's box behaves through them.
  Exceptions (not traced): `date` -> `sh.Now()` (honours MINIPREM_FAKE_EPOCH);
  `sleep N` -> `sh.Sleep(N*time.Second)` (no-op under the harness); `mktemp [tmpl]` ->
  `sh.MkTemp(tmpl)` ALWAYS (never os.CreateTemp directly: the name reaches traced
  argv, e.g. installer:2189 `install -m 0644 "$tmp_unit" ...`).
- **Pure text tools** (`grep sed awk cut tr head tail sort uniq wc cat basename dirname
  xargs printf echo test [`): reimplement in Go; they are not traced. Match their exact
  semantics on the inputs the script feeds them (regex flavours: grep -E/BRE, sed BRE).
  `cp mv rm mkdir chmod ln touch` on files: use os.* — the result is checked through
  "files written", not argv. But if run under `sudo`, the argv IS traced: run them via
  `sh.C("sudo", "cp", ...)`.
- **Pipelines**: `a | b` where a is traced and b is a text tool -> run a via
  `sh.C(...).Output()` and do b in Go. `pipefail` is on in the installer: the pipeline
  status is the last non-zero status.
- **`set -e`**: the installer and merge-compose use `set -euo pipefail`; miniprem.sh does
  NOT. Under -e, an unchecked failing command aborts the script (EXIT trap runs, status
  = that command's status). Not in conditions (`if`, `while`, `&&`, `||`, `!`), not in
  the non-final part of `&&`/`||` lists, and NOT inside functions called from a
  condition context (bash disables -e there). Model each call site deliberately:
  `if rc := ...; rc != 0 { sh.Exit(rc) }` where bash would abort.
  `local x=$(cmd)` masks the status (local returns 0); `x=$(cmd)` does not.
  `((n++))` with n==0 returns status 1 and aborts under -e (a known upstream bug class).
- **`exit`** -> `sh.Exit(code)` (unwinds, runs the EXIT trap). Inside `$(func)` command
  substitution bash runs the function in a SUBSHELL: `exit` there only ends the
  subshell, and variable assignments made there are lost. Port such call sites as a
  function returning (stdout string, status) without touching globals.
- **Traps**: `trap 'cleanup_on_error $LINENO' EXIT` -> `sh.OnExit(...)`; `trap '...' INT`
  / `TERM` -> `sh.OnSignal(os.Interrupt|syscall.SIGTERM, fn)` (the harness kills the
  infinite-loop scenario with SIGTERM, so the TERM trap output is compared). `$LINENO` has no
  Go equivalent; if it is printed, report the call site (allowlist candidate).
- **IFS**: the installer sets `IFS=$'\n\t'` at the top, so in the installer and every
  lib it sources, `read` does not trim spaces and unquoted `$var` splits only on
  newline/tab. `sh.Main` sets `sh.IFS` per entry; use `sh.ReadLine`/`sh.SplitIFS`.
  Unquoted expansions in miniprem.sh (e.g. `docker compose $COMPOSE_FILE up`) split on
  spaces — reproduce the split exactly.
- **read**: always via `sh.ReadLine(sh.ReadOpts{Prompt, Raw, Silent})` — it reads stdin
  one byte at a time so child processes see the rest, prints `-p` prompts only on a TTY,
  handles backslashes without `-r`. At EOF `read` returns non-zero: under set -e at a
  bare `read` call site that ABORTS the script — reproduce.
- **echo**: `echo -e "$s"` -> `fmt.Fprintln(w, sh.EchoE(s))`; plain `echo` does NOT
  interpret escapes. Colour vars are stored as literal `\033[...` strings in bash
  (logging.sh) — store them the same way and pass through EchoE where bash used -e.
  `echo -e $WHITE` with an UNSET var prints an empty line. `printf` -> fmt with bash
  printf semantics (format reuse when more args than verbs!).
- **stderr vs stdout**: logging.sh writes console logs to STDERR. Keep every stream
  exactly as bash had it.
- **Heredocs**: copy text byte-for-byte; `<<EOF` expands `$vars` and `` `cmd` ``;
  `<<'EOF'` does not.
- **cwd**: miniprem.sh does `cd "$(dirname "$0")"`; the installer requires cwd = repo
  root. The shim runs the binary with the caller's cwd and `$0` lost: derive the repo
  root the same way bash would (miniprem.sh: directory of the shim =
  `MINIPREM_SCRIPT_PATH` env set by the shim, else the binary's ../). `basename $0`
  output -> the shim name (`miniprem.sh`, `install_miniprem.sh`).
- **Exec seam**: every `bash <path> [args]` / `./script` call into another repo script
  (`docker/scripts/merge-compose.sh` from miniprem.sh:380,574,854 and installer:2279,
  `kubernetes/scripts/deploy-allinone.sh`, `setup_multiple_rennys.sh`, kubernetes
  scripts) stays an external call: `sh.Run("bash", path, args...)` with the same argv.
  NEVER call `mergecompose.Main` in-process.
- **getopt**: run the real `getopt` via `sh.C(...).Output()` with identical args; do not
  reimplement (its quoting and error messages must match GNU exactly).
- **Background jobs**: `{ ...; } &` + `show_spinner $!` (docker.sh, prerequisites.sh) is
  sequential in effect: run the block, then the spinner's output (frames are normalized
  by the harness, but keep the final line). `pull_images_parallel` (installer:316) is
  truly parallel: goroutines + wait, preserving per-job exit statuses and the
  per-job temp-file output ordering the script prints after `wait`.
- **Known bugs to preserve explicitly**: `--tts-address/--tts-key` loop forever in the
  installer's option parsing (`*) usage` with no shift) — keep the infinite loop.
- **Sourcing side effects**: sourcing logging.sh runs `mkdir -p logs` and
  `rotate_logs` at load time; miniprem.sh sources logging/docker/environment, the
  installer sources all nine libs in the order docker, logging, audio, hash,
  environment, seed, prompts, prerequisites, allinone. Port top-level lib code as
  `init<Lib>()` functions called by the entry in that same order.

## Checks
- `gofmt`, `go vet ./...`, `CGO_ENABLED=0 go build ./...` must pass.
- Each ported function carries a `// bash: <file>:<line>` comment so it can be reviewed side by side.
- Any behaviour that cannot be reproduced exactly goes in DEVIATIONS.md; `harness/compare.sh all` must stay green.
