package mp

import (
	"os"
	"regexp"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/allinone.sh (no top-level code).

var allinoneInited bool

// initAllinone: allinone.sh defines functions only. Idempotent no-op for symmetry.
func initAllinone() { allinoneInited = true }

// allinoneEnvOrFile is used only as $(_allinone_env_or_file key [val]): returns the
// captured stdout (printf '%s', no trailing newline).
// bash: scripts/allinone.sh:13
func allinoneEnvOrFile(key, val string) string {
	if val != "" {
		return val
	}
	root := PROJECT_ROOT
	if root == "" {
		root = "."
	}
	envfile := root + "/docker/docker-compose.env"
	if ltIsFile(envfile) {
		// grep -E "^[[:space:]]*${key}=" file | tail -n1 || true
		line := ""
		if b, err := os.ReadFile(envfile); err == nil {
			re, rerr := regexp.Compile(`^[[:space:]]*` + key + `=`)
			if rerr == nil {
				for _, l := range ltLines(string(b)) {
					if re.MatchString(l) {
						line = l
					}
				}
			}
		}
		// ${line#*=} then sed -e 's/^["'\'']//' -e 's/["'\'']$//'
		v := line
		if i := strings.IndexByte(line, '='); i >= 0 {
			v = line[i+1:]
		}
		if len(v) > 0 && (v[0] == '"' || v[0] == '\'') {
			v = v[1:]
		}
		if len(v) > 0 && (v[len(v)-1] == '"' || v[len(v)-1] == '\'') {
			v = v[:len(v)-1]
		}
		return v
	}
	return ""
}

func ltOr(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

// maybeDeployAllinone: 0 and no-op unless ALLINONE=yes; otherwise runs
// `bash <scripts>/../kubernetes/scripts/deploy-allinone.sh` (exec seam) with the mapped
// environment and returns its status (the function's status in bash).
// bash: scripts/allinone.sh:26
func maybeDeployAllinone() int {
	if ltOr(ALLINONE, "no") != "yes" {
		return 0
	}

	scriptDir := seedLibDir()
	deploy := scriptDir + "/../kubernetes/scripts/deploy-allinone.sh"

	if syscall.Access(deploy, 1) != nil && !ltIsFile(deploy) { // [ ! -x ] && [ ! -f ]
		warning("ALLINONE=yes but orchestrator not found at " + deploy + " — skipping.")
		return 0
	}

	if NGC_API_KEY == "" {
		if seedLibSourced { // declare -f seed_record_missing
			seedRecordMissing("MINIPREM_SEED_NGC_API_KEY", "required when ALLINONE=yes")
		}
		warning("ALLINONE=yes but NGC_API_KEY is empty — skipping all-in-one deploy.")
		return 0
	}

	harborUser := allinoneEnvOrFile("HARBOR_USERNAME", ltOr(os.Getenv("HARBOR_USERNAME"), os.Getenv("MINIPREM_SEED_HARBOR_USERNAME")))
	harborPass := allinoneEnvOrFile("HARBOR_PASSWORD", ltOr(os.Getenv("HARBOR_PASSWORD"), os.Getenv("MINIPREM_SEED_HARBOR_PASSWORD")))

	info("ALLINONE=yes — launching NVIDIA all-in-one deploy via " + deploy)

	return sh.C("bash", deploy).WithEnv(
		"NGC_API_KEY="+NGC_API_KEY,
		"HARBOR_USERNAME="+harborUser,
		"HARBOR_PASSWORD="+harborPass,
		"PLATFORM_KEY="+PLATFORM_KEY,
		"TENANT_ID="+TENANT_ID,
		"GEMMA_MODEL="+ltOr(GEMMA_MODEL, "google/gemma-3-27b-it"),
		"GEMMA_BACKEND="+ltOr(GEMMA_BACKEND, "vllm"),
		"STT_PROVIDER="+ltOr(KIOSK_STT_PROVIDER, "riva"),
		"KIOSK_BRAND="+ltOr(KIOSK_BRAND, "dell"),
		"RAG_ADMIN_KEY="+RAG_ADMIN_KEY,
	).Run()
}
