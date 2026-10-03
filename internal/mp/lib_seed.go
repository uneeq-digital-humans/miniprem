package mp

import (
	"bytes"
	"fmt"
	"os"
	"regexp"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/seed.sh.
//
// Seed files are SOURCED as bash (set -a). There is no Go equivalent, so
// seedLoadFile runs the real `bash` once: it sources the file (stdout/stderr/stdin
// pass through exactly as when sourced in-process) and then dumps `env -0`. Every
// variable that is new or changed relative to this process's environment is applied
// with os.Setenv (== exported by `set -a`, visible to children and to os.Getenv), and
// known installer globals are updated through seedGlobalPtr (so a seed that assigns
// INSTALL_TYPE=... directly behaves like bash). A seed file that calls `exit N` ends the
// real shell in bash; here the wrapper ends without a dump and we sh.Exit(N).

// bash: scripts/seed.sh:22-26
var (
	INTERACTIVE_MODE    = "yes"
	FORCE_CONFIRMATIONS = "no"
	SEED_FILE           = ""
	SEED_LOADED         = "no"
)

// MINIPREM_SEED_MISSING: bash scripts/seed.sh:29
var MINIPREM_SEED_MISSING []string

// MINIPREM_SEED_KNOWN_KEYS: bash scripts/seed.sh:33-61
var MINIPREM_SEED_KNOWN_KEYS = []string{
	"MINIPREM_SEED_INSTALL_TYPE",
	"MINIPREM_SEED_INSTALL_AS_SERVICE",
	"MINIPREM_SEED_TELEMETRY_CONSENT",
	"MINIPREM_SEED_DEPLOYMENT_TARGET",
	"MINIPREM_SEED_REGION",
	"MINIPREM_SEED_TTS_PROVIDER",
	"MINIPREM_SEED_AZURE_REGION",
	"MINIPREM_SEED_AZURE_SPEECH_KEY",
	"MINIPREM_SEED_ELEVEN_LABS_API_KEY",
	"MINIPREM_SEED_RIME_API_KEY",
	"MINIPREM_SEED_RIME_QUAY_PASSWORD",
	"MINIPREM_SEED_PLATFORM_ADDRESS",
	"MINIPREM_SEED_PLATFORM_KEY",
	"MINIPREM_SEED_TENANT_ID",
	"MINIPREM_SEED_RENNY_IMAGE",
	"MINIPREM_SEED_HARBOR_USERNAME",
	"MINIPREM_SEED_HARBOR_PASSWORD",
	"MINIPREM_SEED_STT_PROVIDER",
	"MINIPREM_SEED_CUSTOM_SERVICES",
	"MINIPREM_SEED_CUSTOM_SERVICES_FILE",
	"MINIPREM_SEED_FORCE",
	"MINIPREM_SEED_ALLINONE",
	"MINIPREM_SEED_NGC_API_KEY",
	"MINIPREM_SEED_GEMMA_MODEL",
	"MINIPREM_SEED_GEMMA_BACKEND",
	"MINIPREM_SEED_KIOSK_STT_PROVIDER",
	"MINIPREM_SEED_KIOSK_BRAND",
	"MINIPREM_SEED_RAG_ADMIN_KEY",
}

// seedLibSourced is true once initSeed ran (== seed.sh sourced). miniprem.sh never
// sources seed.sh, so the seed_* functions do not exist there (see seedFnAvailable).
var seedLibSourced bool

// initSeed runs seed.sh's top-level assignments (`X="${X:-default}"` take an inherited
// environment value). Idempotent. bash: scripts/seed.sh:22-29
func initSeed() {
	if seedLibSourced {
		return
	}
	seedLibSourced = true
	INTERACTIVE_MODE = envOr("INTERACTIVE_MODE", "yes")
	FORCE_CONFIRMATIONS = envOr("FORCE_CONFIRMATIONS", "no")
	SEED_FILE = envOr("SEED_FILE", "")
	SEED_LOADED = "no"
	MINIPREM_SEED_MISSING = nil
}

// envOr emulates ${NAME:-def} for an inherited environment variable.
func envOr(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

// seedGlobalPtr maps a bash global name to its Go variable (for `${!var_name}` and for
// seed files that assign installer variables directly). nil when unknown.
func seedGlobalPtr(name string) *string {
	switch name {
	case "INTERACTIVE_MODE":
		return &INTERACTIVE_MODE
	case "FORCE_CONFIRMATIONS":
		return &FORCE_CONFIRMATIONS
	case "SEED_FILE":
		return &SEED_FILE
	case "SEED_LOADED":
		return &SEED_LOADED
	case "INSTALL_TYPE":
		return &INSTALL_TYPE
	case "INSTALL_AS_SERVICE":
		return &INSTALL_AS_SERVICE
	case "DEPLOYMENT_TARGET":
		return &DEPLOYMENT_TARGET
	case "UNEEQ_REGION":
		return &UNEEQ_REGION
	case "TTS_PROVIDER":
		return &TTS_PROVIDER
	case "AZURE_REGION":
		return &AZURE_REGION
	case "AZURE_SPEECH_KEY":
		return &AZURE_SPEECH_KEY
	case "ELEVEN_LABS_API_KEY":
		return &ELEVEN_LABS_API_KEY
	case "RIME_API_KEY":
		return &RIME_API_KEY
	case "RIME_QUAY_PASSWORD":
		return &RIME_QUAY_PASSWORD
	case "PLATFORM_ADDRESS":
		return &PLATFORM_ADDRESS
	case "PLATFORM_KEY":
		return &PLATFORM_KEY
	case "TENANT_ID":
		return &TENANT_ID
	case "RENNY_IMAGE":
		return &RENNY_IMAGE
	case "TELEMETRY_CONSENT":
		return &TELEMETRY_CONSENT
	case "STT_PROVIDER":
		return &STT_PROVIDER
	case "CUSTOM_SERVICES_CHOICE":
		return &CUSTOM_SERVICES_CHOICE
	case "CUSTOM_SERVICES_FILE_SEED":
		return &CUSTOM_SERVICES_FILE_SEED
	case "ALLINONE":
		return &ALLINONE
	case "NGC_API_KEY":
		return &NGC_API_KEY
	case "GEMMA_MODEL":
		return &GEMMA_MODEL
	case "GEMMA_BACKEND":
		return &GEMMA_BACKEND
	case "KIOSK_STT_PROVIDER":
		return &KIOSK_STT_PROVIDER
	case "KIOSK_BRAND":
		return &KIOSK_BRAND
	case "RAG_ADMIN_KEY":
		return &RAG_ADMIN_KEY
	case "PROJECT_ROOT":
		return &PROJECT_ROOT
	}
	return nil
}

// ltIndirect is `${!name:-}`.
func ltIndirect(name string) string {
	if p := seedGlobalPtr(name); p != nil {
		return *p
	}
	return os.Getenv(name)
}

// seedLibDir is `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` for a lib sourced as
// "$PROJECT_ROOT/scripts/<x>.sh".
func seedLibDir() string { return PROJECT_ROOT + "/scripts" }

// seedLintFile. bash: scripts/seed.sh:72
func seedLintFile(file string) {
	linter := seedLibDir() + "/lint-seed.sh"

	if !ltIsFile(linter) {
		fatal("Seed validator not found: " + linter + " (cannot safely load a seed without validation).")
	}

	if sh.Run("bash", linter, file) != 0 {
		fatal("Refusing to load a seed that failed validation: " + file)
	}
}

const seedDumpMarker = "\x00__MP_SEED_DUMP__\x00"

const seedSourceScript = `set -a
set +u
set +e
. "$1"
__mp_rc=$?
printf '\0__MP_SEED_DUMP__\0%s\0' "$__mp_rc"
env -0
`

var seedSeenKeyRe = regexp.MustCompile(`^[[:space:]]*(MINIPREM_SEED_[A-Z_]+)`)

// seedLoadFile sources a seed file; implies non-interactive. bash: scripts/seed.sh:96
func seedLoadFile(file string) {
	if file == "" {
		return
	}
	if !ltIsFile(file) {
		fatal("Seed file not found: " + file)
	}
	if syscall.Access(file, 4) != nil { // [ ! -r ]
		fatal("Seed file not readable: " + file)
	}

	info("Loading seed file: " + file)

	seedLintFile(file)

	// . "$file" under set -a; set +u; set +e   (see package comment)
	var out bytes.Buffer
	script0 := os.Getenv("MINIPREM_SCRIPT_PATH")
	if script0 == "" {
		script0 = "install_miniprem.sh"
	}
	c := sh.C("bash", "-c", seedSourceScript, script0, file)
	c.Stdout = &out
	runRC := c.Run()

	data := out.Bytes()
	idx := bytes.LastIndex(data, []byte(seedDumpMarker))
	if idx < 0 {
		// The seed file itself called `exit N`: in bash that ends the installer.
		os.Stdout.Write(data)
		sh.Exit(runRC)
	}
	os.Stdout.Write(data[:idx])
	rest := data[idx+len(seedDumpMarker):]
	parts := bytes.Split(rest, []byte{0})
	srcRC := string(parts[0])
	for _, kv := range parts[1:] {
		eq := bytes.IndexByte(kv, '=')
		if eq <= 0 {
			continue
		}
		k, v := string(kv[:eq]), string(kv[eq+1:])
		switch k {
		case "_", "SHLVL", "PWD", "OLDPWD", "__mp_rc":
			continue
		}
		if strings.HasPrefix(k, "BASH_FUNC_") {
			continue
		}
		if cur, ok := os.LookupEnv(k); ok && cur == v {
			continue
		}
		os.Setenv(k, v)
		if p := seedGlobalPtr(k); p != nil {
			*p = v
		}
	}
	if srcRC != "0" {
		fatal(fmt.Sprintf("Failed to source seed file: %s (exit %s)", file, srcRC))
	}

	SEED_FILE = file
	SEED_LOADED = "yes"
	INTERACTIVE_MODE = "no"

	// Typo guard: grep -oE '^[[:space:]]*MINIPREM_SEED_[A-Z_]+' | sed | sort -u
	var keys []string
	if b, err := os.ReadFile(file); err == nil {
		for _, l := range ltLines(string(b)) {
			if m := seedSeenKeyRe.FindStringSubmatch(l); m != nil {
				keys = append(keys, m[1])
			}
		}
	}
	sorted, _ := sh.C("sort", "-u").In(strings.Join(keys, "\n") + "\n").Output()
	if len(keys) == 0 {
		sorted = ""
	}
	for _, seen := range ltLines(sorted) {
		known := false
		for _, k := range MINIPREM_SEED_KNOWN_KEYS {
			if seen == k {
				known = true
				break
			}
		}
		if !known {
			warning("Seed file contains unknown key: " + seen + " (ignored)")
		}
	}

	if envOr("MINIPREM_SEED_FORCE", "no") == "yes" {
		FORCE_CONFIRMATIONS = "yes"
	}
}

// seedDefault emulates `: "${VAR:=${MINIPREM_SEED_X:-}}"`.
func seedDefault(dst *string, seedKey string) {
	if *dst == "" {
		*dst = os.Getenv(seedKey)
	}
}

// seedApplyToVars. bash: scripts/seed.sh:150
func seedApplyToVars() {
	if SEED_LOADED != "yes" {
		return
	}
	seedDefault(&INSTALL_TYPE, "MINIPREM_SEED_INSTALL_TYPE")
	seedDefault(&INSTALL_AS_SERVICE, "MINIPREM_SEED_INSTALL_AS_SERVICE")
	seedDefault(&DEPLOYMENT_TARGET, "MINIPREM_SEED_DEPLOYMENT_TARGET")
	seedDefault(&UNEEQ_REGION, "MINIPREM_SEED_REGION")
	seedDefault(&TTS_PROVIDER, "MINIPREM_SEED_TTS_PROVIDER")
	seedDefault(&AZURE_REGION, "MINIPREM_SEED_AZURE_REGION")
	seedDefault(&AZURE_SPEECH_KEY, "MINIPREM_SEED_AZURE_SPEECH_KEY")
	seedDefault(&ELEVEN_LABS_API_KEY, "MINIPREM_SEED_ELEVEN_LABS_API_KEY")
	seedDefault(&RIME_API_KEY, "MINIPREM_SEED_RIME_API_KEY")
	seedDefault(&RIME_QUAY_PASSWORD, "MINIPREM_SEED_RIME_QUAY_PASSWORD")
	seedDefault(&PLATFORM_ADDRESS, "MINIPREM_SEED_PLATFORM_ADDRESS")
	seedDefault(&PLATFORM_KEY, "MINIPREM_SEED_PLATFORM_KEY")
	seedDefault(&TENANT_ID, "MINIPREM_SEED_TENANT_ID")
	seedDefault(&RENNY_IMAGE, "MINIPREM_SEED_RENNY_IMAGE")
	seedDefault(&TELEMETRY_CONSENT, "MINIPREM_SEED_TELEMETRY_CONSENT")
	seedDefault(&STT_PROVIDER, "MINIPREM_SEED_STT_PROVIDER")
	seedDefault(&CUSTOM_SERVICES_CHOICE, "MINIPREM_SEED_CUSTOM_SERVICES")
	seedDefault(&CUSTOM_SERVICES_FILE_SEED, "MINIPREM_SEED_CUSTOM_SERVICES_FILE")

	seedDefault(&ALLINONE, "MINIPREM_SEED_ALLINONE")
	seedDefault(&NGC_API_KEY, "MINIPREM_SEED_NGC_API_KEY")
	seedDefault(&GEMMA_MODEL, "MINIPREM_SEED_GEMMA_MODEL")
	seedDefault(&GEMMA_BACKEND, "MINIPREM_SEED_GEMMA_BACKEND")
	seedDefault(&KIOSK_STT_PROVIDER, "MINIPREM_SEED_KIOSK_STT_PROVIDER")
	seedDefault(&KIOSK_BRAND, "MINIPREM_SEED_KIOSK_BRAND")
	seedDefault(&RAG_ADMIN_KEY, "MINIPREM_SEED_RAG_ADMIN_KEY")
}

// seedApplyHarborCreds. bash: scripts/seed.sh:183
func seedApplyHarborCreds() {
	if SEED_LOADED != "yes" {
		return
	}
	if v := os.Getenv("MINIPREM_SEED_HARBOR_USERNAME"); v != "" {
		updateEnvVariable("HARBOR_USERNAME", v)
		info("Applied seeded HARBOR_USERNAME")
	}
	if v := os.Getenv("MINIPREM_SEED_HARBOR_PASSWORD"); v != "" {
		updateEnvVariable("HARBOR_PASSWORD", v)
		info("Applied seeded HARBOR_PASSWORD")
	}
}

// Mode predicates (used in conditions only -> bool). bash: scripts/seed.sh:197-207
func seedIsInteractive() bool    { return INTERACTIVE_MODE == "yes" }
func seedIsNonInteractive() bool { return INTERACTIVE_MODE != "yes" }
func seedIsForced() bool         { return FORCE_CONFIRMATIONS == "yes" }

// seedRecordMissing. bash: scripts/seed.sh:213
func seedRecordMissing(key string, hint ...string) {
	entry := key
	if len(hint) > 0 && hint[0] != "" {
		entry = key + "  (" + hint[0] + ")"
	}
	MINIPREM_SEED_MISSING = append(MINIPREM_SEED_MISSING, entry)
}

// seedCheckRequired exits 1 listing every missing key (via fatal), else returns.
// bash: scripts/seed.sh:228
func seedCheckRequired() {
	if len(MINIPREM_SEED_MISSING) == 0 {
		return
	}
	logError("Non-interactive install is missing required seed values:")
	for _, entry := range MINIPREM_SEED_MISSING {
		fmt.Fprintln(os.Stderr, "  - "+entry)
	}
	logError("Add the missing keys to your seed file, or run interactively.")
	fatal("Aborting due to incomplete seed configuration.")
}

// seedConfirm: true == bash status 0. Used only in `if`/`if !` (errexit off).
// def is the optional second argument ("yes"/"no", default "no").
// bash: scripts/seed.sh:253
func seedConfirm(message string, def ...string) bool {
	d := "no"
	if len(def) > 0 && def[0] != "" {
		d = def[0]
	}

	if seedIsNonInteractive() {
		if seedIsForced() {
			info("[non-interactive --force] " + message + " -> yes")
			return true
		}
		info("[non-interactive] " + message + " -> no (use --force to override)")
		return false
	}

	prompt := "[y/N]"
	if d == "yes" {
		prompt = "[Y/n]"
	}
	reply, _ := sh.ReadLine(sh.ReadOpts{Prompt: message + " " + prompt + ": "})
	if reply == "" {
		reply = d
	}
	switch strings.ToLower(reply) {
	case "y", "yes":
		return true
	}
	return false
}

// seedValidateChoice: varName is the bash variable NAME (its value is looked up);
// allowed is the pipe-separated set. No-op for an empty value; fatal on mismatch.
// bash: scripts/seed.sh:291
func seedValidateChoice(varName, allowed string) {
	value := ltIndirect(varName)
	if value == "" {
		return
	}
	if strings.Contains("|"+allowed+"|", "|"+value+"|") {
		return
	}
	fatal("Invalid value for " + varName + ": '" + value + "' (allowed: " + allowed + ")")
}
