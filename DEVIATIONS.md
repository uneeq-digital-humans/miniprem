# Known differences between the Go port and the bash scripts

Policy: the Go port reproduces the bash behaviour, bugs included. Everything below is a place where
it does not, or cannot, with the reason. Items marked **harness** are visible in the harness and are
handled by a documented normalization rule or allowlist entry; everything else is outside the
scenarios the harness exercises.

## Handled in the harness

**D1 — `Terminated` job-status line (allowlist: `harness/allowlist/install_tts_address_loop.sed`).**
When the `--tts-address` infinite loop is killed with SIGTERM, bash additionally prints
`Terminated`. bash prints that itself, about a child process inside `usage()` that was killed by the
process-group signal; the script never prints it. The Go loop has no child process. The script's own
trap output ("Installation terminated (SIGTERM)", exit 143) is compared and matches.

**D2 — bash diagnostic prefix `<script>.sh: line N: ` (normalization N4).** bash prefixes its own
errors (unbound variable, command not found) with the script path and line number. The Go port
prints the same message without the prefix; the message text is still compared.

**D3 — spinner frames and the combined script hash (normalizations N2, N3).** Spinner frame counts
depend on timing (the Go port prints none, the final status line matches). The "Combined script hash"
hashes the files on disk, which are shims in Go mode.

## Not exercised by the harness

**D4 — `$LINENO` in the installer's EXIT trap.** The failure report ("Failure location: Line N",
"Failed at line: N") uses a best-effort line number tracked at each errexit abort site in
`start_miniprem` and at the logging `fatal` exit. It matches in the covered failure scenarios but may
differ for failure paths that the harness does not cover.

**D5 — `eval docker login -p=…` for the RIME registry (install_miniprem.sh, setup_rime_credentials).**
The Go port passes the password as a single argument instead of running it through `eval`. Results
are identical for passwords without shell metacharacters. With metacharacters, bash would re-parse
(and potentially execute) parts of the password; Go does not. This is the one place where we chose
not to reproduce bash, because reproducing it means a shell-injection path.

**D6 — merge-compose.sh:205.** A service name that makes `grep "^NAME$"` fail (unbalanced `[`,
trailing `\`) prints a grep error in bash; Go treats it as "no match" without the message.

**D7 — miniprem.sh edge inputs.**
- A CNS pod-number argument with a leading zero and an 8 or 9 (e.g. `08`): bash aborts with an arithmetic error; Go reports "Invalid".
- `custom add` with a service name containing `/` (line 845): bash's `sed` fails and an empty template is appended; Go does not model it.
- `basename $0` is unquoted in bash (line 229); a script path containing spaces would split there. Go does not split.

**D8 — exact text of secondary tool errors.** `sed -i` failures in `update_env_variable` with `|` or
`\1` in the value (environment.sh:50), `[ ]` integer-expression errors on empty operands, some
`cp`/`awk` diagnostics, and marker-file write failures (prompts.sh:12, :31) print approximate rather
than byte-identical messages. Exit statuses match.

**D9 — dead code.** These bash functions are never called; they are ported for completeness but are
not exercised: `pull_images_parallel`, `pull_required_images`, `validate_cloud_service`,
`format_dhop_address`, `format_url_address`, `retry_network_operation`, `check_gpu_usage`,
`show_progress_spinner`, `atomic_file_update`, `check_and_prompt_required_env_vars`,
`get_required_env_vars_from_example` (its `sort` uses byte order = C locale). The lib copies of
`configure_region_endpoints` / `prompt_for_region` and the first `configure_eleven_labs` are shadowed
in bash and are not ported.

**D10 — TTY mode.** All scenarios run without a TTY. On a TTY, `read -p` prompts and `read -s` echo
suppression are implemented in `internal/sh` but not differentially tested.
