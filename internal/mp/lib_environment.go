package mp

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/environment.sh (no top-level code).
//
// NOTE: configure_region_endpoints (environment.sh:~190) is NOT ported here: the
// installer defines its own copy at install_miniprem.sh:1108 which is the one bash
// uses (later definition wins); the lib copy is never called by miniprem.sh.

// readEnvVariable is used only as $(read_env_variable name).
// grep "^name=" file | cut -d '=' -f 2- | sed 's/^"//;s/"$//' then "$$" -> "$".
// bash: scripts/environment.sh:6
func readEnvVariable(varName string) string {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	value := ""
	if ltIsFile(envFile) {
		b, _ := os.ReadFile(envFile)
		var vals []string
		re := ltBRE("^" + varName + "=")
		for _, l := range ltLines(string(b)) {
			if re.MatchString(l) {
				vals = append(vals, ltCutField2Plus(l))
			}
		}
		// echo "$value" | sed 's/^"//;s/"$//'  (per line)
		for i, v := range vals {
			v = strings.TrimPrefix(v, `"`)
			v = strings.TrimSuffix(v, `"`)
			vals[i] = v
		}
		value = strings.Join(vals, "\n")
		value = strings.ReplaceAll(value, "$$", "$")
	}
	return strings.TrimRight(value, "\n")
}

// ltCutField2Plus emulates `cut -d '=' -f 2-` on one line (whole line if no '=').
func ltCutField2Plus(l string) string {
	if i := strings.IndexByte(l, '='); i >= 0 {
		return l[i+1:]
	}
	return l
}

// sedReplacement expands a sed RHS for a match: & = whole match, \& literal &, \\ ->
// \, \n newline; unsupported backrefs error like GNU sed.
func sedReplacement(rhs, match string) (string, bool) {
	var b strings.Builder
	for i := 0; i < len(rhs); i++ {
		c := rhs[i]
		switch {
		case c == '&':
			b.WriteString(match)
		case c == '\\' && i+1 < len(rhs):
			i++
			switch rhs[i] {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				return "", false
			default:
				b.WriteByte(rhs[i])
			}
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), true
}

// updateEnvVariable: set (or append) VAR=value in docker/docker-compose.env, escaping $
// as $$. Returns bash's status (1 when the env file is missing; sed failures return
// sed's status, which bash would also surface as the function status). Preserves the
// bash quirk that a non-empty file ending in a newline gets an extra blank line.
// bash: scripts/environment.sh:25
func updateEnvVariable(varName, newValue string) int {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	escapedValue := strings.ReplaceAll(newValue, "$", "$$")

	if !ltIsFile(envFile) {
		fmt.Println("")
		fmt.Println("ERROR: " + envFile + " not found.")
		fmt.Println("")
		fmt.Println("Run the Docker install script first:")
		fmt.Println("  ./docker/scripts/install_miniprem.sh")
		fmt.Println("")
		return 1
	}

	// [[ ! -s f ]] || [[ $(tail -c 1 f | wc -l) -eq 0 ]]  -> nothing; else append "\n"
	content, _ := os.ReadFile(envFile)
	if len(content) > 0 && content[len(content)-1] == '\n' {
		if f, err := os.OpenFile(envFile, os.O_WRONLY|os.O_APPEND, 0); err == nil {
			f.WriteString("\n")
			f.Close()
			content = append(content, '\n')
		}
	}

	re := ltBRE("^" + varName + "=")
	has := false
	for _, l := range strings.Split(string(content), "\n") {
		if re.MatchString(l) {
			has = true
			break
		}
	}
	if has {
		// sed -i "s|^VAR=.*|VAR=value|" file
		rhs := varName + "=" + escapedValue
		// An unescaped '|' in the value terminates the s command early: GNU sed fails.
		if idx := unescapedPipe(rhs); idx >= 0 {
			pos := len("s|^"+varName+"=.*|") + idx + 2 // 1-based index of the char after the 3rd delimiter
			fmt.Fprintf(os.Stderr, "sed: -e expression #1, char %d: unknown option to `s'\n", pos)
			return 1
		}
		lines := strings.Split(string(content), "\n")
		reLine := regexp.MustCompile(`^` + regexp.QuoteMeta(varName) + `=.*`)
		for i, l := range lines {
			if m := reLine.FindString(l); m != "" {
				exp, ok := sedReplacement(rhs, m)
				if !ok {
					fmt.Fprintf(os.Stderr, "sed: -e expression #1, char %d: invalid reference \\1 on `s' command's RHS\n", len("s|^"+varName+"=.*|"+rhs+"|"))
					return 1
				}
				lines[i] = exp + l[len(m):]
			}
		}
		if err := os.WriteFile(envFile, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
			return 4
		}
		return 0
	}
	if f, err := os.OpenFile(envFile, os.O_WRONLY|os.O_APPEND, 0); err == nil {
		f.WriteString(varName + "=" + escapedValue + "\n")
		f.Close()
		return 0
	}
	return 1
}

// unescapedPipe returns the index of the first '|' in rhs not preceded by a backslash.
func unescapedPipe(rhs string) int {
	for i := 0; i < len(rhs); i++ {
		if rhs[i] == '\\' {
			i++
			continue
		}
		if rhs[i] == '|' {
			return i
		}
	}
	return -1
}

// configureRennyQuality. fatal exits. bash: scripts/environment.sh:62
func configureRennyQuality() {
	if DEPLOYMENT_TARGET == "" {
		fatal("DEPLOYMENT_TARGET not set. prompt_deployment_target() must be called first.")
	}

	qualityLevel := ""
	switch DEPLOYMENT_TARGET {
	case "hardware":
		qualityLevel = "miniprem"
	case "cloud":
		qualityLevel = "web"
	default:
		fatal("Invalid deployment target: " + DEPLOYMENT_TARGET)
	}

	currentQuality := readEnvVariable("RENNY_QUALITY_LEVEL")
	if currentQuality == qualityLevel {
		info("Renny quality level already set to: " + qualityLevel + " (no change needed)")
		return
	}

	if updateEnvVariable("RENNY_QUALITY_LEVEL", qualityLevel) == 0 {
		success(CHECKMARK + " Renny quality level configured: RENNY_QUALITY_LEVEL=" + qualityLevel)
		info("You can change this later by editing docker/docker-compose.env and restarting Renny")
	} else {
		warning("Failed to update RENNY_QUALITY_LEVEL, but continuing...")
	}
}

// checkHarborCredentials: 0 when creds exist and are not the placeholder, else 1.
// bash: scripts/environment.sh:100
func checkHarborCredentials() int {
	username := readEnvVariable("HARBOR_USERNAME")
	password := readEnvVariable("HARBOR_PASSWORD")
	if username == "" || password == "" {
		return 1
	}
	if username == "robot$your-customer-name" {
		return 1
	}
	return 0
}

// seedFnAvailable models `declare -f`/command lookup of the seed.sh functions: miniprem.sh
// never sources seed.sh, so there `seed_is_non_interactive` is "command not found"
// (status 127 -> `if` false) and `seed_record_missing` is never reached.
func seedFnAvailable(name string) bool {
	if seedLibSourced {
		return true
	}
	fmt.Fprintf(os.Stderr, "%s: command not found\n", name)
	return false
}

// promptHarborCredentials: 0 on success, 1 when non-interactive. Called in `if !`
// context, so errexit is off: an EOF on `read` is NOT fatal here.
// bash: scripts/environment.sh:118
func promptHarborCredentials() int {
	if seedFnAvailable("seed_is_non_interactive") && seedIsNonInteractive() {
		warning("Harbor credentials are not available in docker-compose.env.")
		seedRecordMissing("MINIPREM_SEED_HARBOR_USERNAME", "Harbor robot username")
		seedRecordMissing("MINIPREM_SEED_HARBOR_PASSWORD", "Harbor robot password")
		return 1
	}

	info("Harbor registry credentials required for cr.uneeq.io")
	info("If you don't have Harbor credentials:")
	info("  - Contact: help@uneeq.com")
	info("  - Or ask your UneeQ representative")
	fmt.Println()

	harborUser, _ := sh.ReadLine(sh.ReadOpts{Prompt: "Enter Harbor robot username (e.g., robot$customer-name): "})
	harborPass, _ := sh.ReadLine(sh.ReadOpts{Prompt: "Enter Harbor robot password: ", Silent: true})
	fmt.Println()

	updateEnvVariable("HARBOR_USERNAME", harborUser)
	updateEnvVariable("HARBOR_PASSWORD", harborPass)
	success(CHECKMARK + " Harbor credentials saved to docker/docker-compose.env")
	return 0
}

// loginHarborRegistry: echo "$password" | eval "$DOCKER_CMD" login https://cr.uneeq.io
// -u \'"$username"\' --password-stdin. Returns docker's status.
// bash: scripts/environment.sh:145
func loginHarborRegistry() int {
	username := readEnvVariable("HARBOR_USERNAME")
	password := readEnvVariable("HARBOR_PASSWORD")
	DOCKER_CMD = getDockerCommand()

	a := append(dockerFields(DOCKER_CMD), "login", "https://cr.uneeq.io", "-u", username, "--password-stdin")
	return sh.C(a[0], a[1:]...).In(password + "\n").Run()
}

// ensureHarborCredentials returns 0 on a successful login, 1 otherwise. (Always used in
// condition context by the callers, so errexit is off inside.)
// bash: scripts/environment.sh:154
func ensureHarborCredentials() int {
	if checkHarborCredentials() == 0 {
		info("Found Harbor credentials in docker/docker-compose.env, logging in...")
		if loginHarborRegistry() == 0 {
			success(CHECKMARK + " Harbor login successful")
			return 0
		}
		warning("Saved Harbor credentials failed - may be expired or invalid")
	}

	if promptHarborCredentials() != 0 {
		return 1
	}
	if loginHarborRegistry() == 0 {
		success(CHECKMARK + " Harbor login successful")
		return 0
	}
	logError("Harbor login failed with provided credentials")
	return 1
}

// getDhopAPIHostname is used only as $(get_dhop_api_hostname).
// bash: scripts/environment.sh:182
func getDhopAPIHostname() string {
	region := UNEEQ_REGION
	if region == "" {
		region = "us"
	}
	switch region {
	case "eu":
		return "api-eu.enterprise.uneeq.io"
	}
	return "api.enterprise.uneeq.io"
}

// getCdnHostname is used only as $(get_cdn_hostname). bash: scripts/environment.sh:190
func getCdnHostname() string {
	region := UNEEQ_REGION
	if region == "" {
		region = "us"
	}
	switch region {
	case "eu":
		return "cdn-eu.enterprise.uneeq.io"
	}
	return "cdn.enterprise.uneeq.io"
}
