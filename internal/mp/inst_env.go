package mp

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of the docker-compose.env / value handling parts of install_miniprem.sh.

// instEchoStripQuotes is `$(echo "$v" | sed 's/^"//;s/"$//')`.
func instEchoStripQuotes(v string) string {
	lines := strings.Split(v, "\n")
	for i, l := range lines {
		l = strings.TrimPrefix(l, `"`)
		l = strings.TrimSuffix(l, `"`)
		lines[i] = l
	}
	return strings.TrimRight(strings.Join(lines, "\n"), "\n")
}

// instSedEscape is `$(printf '%s\n' "$v" | sed -e 's/[\/&]/\\&/g')`.
func instSedEscape(v string) string {
	lines := strings.Split(v, "\n")
	for i, l := range lines {
		l = strings.ReplaceAll(l, `/`, `\/`)
		l = strings.ReplaceAll(l, `&`, `\&`)
		lines[i] = l
	}
	return strings.TrimRight(strings.Join(lines, "\n"), "\n")
}

// instFileHasLinePrefix is `grep -q "^<prefix>" file` for a literal prefix.
func instFileHasLinePrefix(path, prefix string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	for _, l := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(l, prefix) {
			return true
		}
	}
	return false
}

// instSedSetVar is `sed -i "s|^VAR=.*|VAR=<escaped>|" file`; returns sed's status.
func instSedSetVar(file, varName, escaped string) int {
	rhs := varName + "=" + escaped
	data, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sed: can't read %s: No such file or directory\n", file)
		return 2
	}
	// An unescaped '|' in the value terminates the s command early: GNU sed fails.
	if idx := unescapedPipe(rhs); idx >= 0 {
		pos := len("s|^"+varName+"=.*|") + idx + 2
		fmt.Fprintf(os.Stderr, "sed: -e expression #1, char %d: unknown option to `s'\n", pos)
		return 1
	}
	lines := strings.Split(string(data), "\n")
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
	if err := os.WriteFile(file, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
		return 4
	}
	return 0
}

// instSedReplaceAll is `sed -i 's|<bre>|<repl>|g' file` (the BRE used here only has
// literal text and `.`, which RE2 reads the same way).
func instSedReplaceAll(file, pattern, repl string) int {
	data, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sed: can't read %s: No such file or directory\n", file)
		return 2
	}
	re := regexp.MustCompile(pattern)
	out := re.ReplaceAllLiteralString(string(data), repl)
	if err := os.WriteFile(file, []byte(out), 0o644); err != nil {
		return 4
	}
	return 0
}

// instMv is `mv src dst` (rename, or copy+unlink across filesystems, keeping the mode).
func instMv(src, dst string) bool {
	if err := os.Rename(src, dst); err == nil {
		return true
	}
	st, err := os.Stat(src)
	if err != nil {
		return false
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return false
	}
	os.Remove(dst)
	if err := os.WriteFile(dst, data, st.Mode().Perm()); err != nil {
		return false
	}
	os.Remove(src)
	return true
}

// instCopyFile is `cp src dst` for regular files (mode of the source, masked by umask).
func instCopyFile(src, dst string) bool {
	st, err := os.Stat(src)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cp: cannot stat '%s': No such file or directory\n", src)
		return false
	}
	data, err := os.ReadFile(src)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cp: cannot open '%s' for reading: %s\n", src, ltErrText(err))
		return false
	}
	if err := os.WriteFile(dst, data, st.Mode().Perm()); err != nil {
		fmt.Fprintf(os.Stderr, "cp: cannot create regular file '%s': %s\n", dst, ltErrText(err))
		return false
	}
	return true
}

// instGrepQ is `echo "$text" | grep -q "<bre>"`.
func instGrepQ(text, bre string) bool {
	re := ltBRE(bre)
	for _, l := range strings.Split(text, "\n") {
		if re.MatchString(l) {
			return true
		}
	}
	return false
}

// checkAndPromptForValue is used only as $(check_and_prompt_for_value ...): it returns the
// captured stdout and the function status. The subshell runs with errexit cleared, and
// its seed_record_missing side effect on MINIPREM_SEED_MISSING is lost.
// bash: install_miniprem.sh:569
func checkAndPromptForValue(promptMessage, currentValue, seedKey string) (string, int) {
	inputValue := currentValue

	if currentValue == "" {
		if seedIsNonInteractive() {
			if seedKey != "" {
				saved := append([]string(nil), MINIPREM_SEED_MISSING...)
				seedRecordMissing(seedKey, promptMessage)
				MINIPREM_SEED_MISSING = saved
			}
			return "", 1
		}
		inputValue, _ = sh.ReadLine(sh.ReadOpts{Prompt: promptMessage + ": "})
		if inputValue == "" {
			return "", 1 // Return failure if no value provided
		}
	}

	return strings.TrimRight(inputValue, "\n"), 0
}

// instEREMatch is `[[ s =~ re ]]` (a regex that does not compile does not match).
func instEREMatch(s, re string) bool {
	r, err := regexp.Compile(re)
	if err != nil {
		return false
	}
	return r.MatchString(s)
}

// formatDhopAddress is used as $(format_dhop_address addr suffix) (never called).
// bash: install_miniprem.sh:594
func formatDhopAddress(address, suffix string) string {
	if !instEREMatch(address, `^(ws://|wss://)`) {
		address = "wss://" + address
	}
	if !instEREMatch(address, suffix+"$") {
		address = address + suffix
	}
	return address
}

var instPortInAddrRe = regexp.MustCompile(`:([0-9]+)`)

// formatUrlAddress is used as $(format_url_address addr suffix) (never called).
// bash: install_miniprem.sh:613
func formatUrlAddress(address, suffix string) string {
	if address == "" {
		return ""
	}

	if m := instPortInAddrRe.FindStringSubmatch(address); m != nil {
		port, _ := ltArithInt(m[1])
		if port == 443 {
			if !instEREMatch(address, `^https://`) {
				address = "https://" + address
			}
		} else {
			if !instEREMatch(address, `^http://`) && !instEREMatch(address, `^https://`) {
				address = "http://" + address
			}
		}
	} else {
		if !instEREMatch(address, `^http://`) && !instEREMatch(address, `^https://`) {
			address = "http://" + address
		}
	}

	if !instEREMatch(address, suffix+"$") {
		address = address + suffix
	}

	return address
}

var (
	instUrlProtoRe = regexp.MustCompile(`^(.*://).*$`)
	instUrlAddrRe  = regexp.MustCompile(`^.*://([^:/]*).*$`)
	instUrlPortRe  = regexp.MustCompile(`^.*://[^:/]*:([0-9]*).*$`)
	instUrlPathRe  = regexp.MustCompile(`^.*://[^/]*/(.*)$`)
)

// extractUrlComponents prints protocol/address/port/path, one per line (never called).
// bash: install_miniprem.sh:252
func extractUrlComponents(url string) {
	protocol := ""
	if m := instUrlProtoRe.FindStringSubmatch(url); m != nil {
		protocol = m[1]
	}
	address := ""
	if m := instUrlAddrRe.FindStringSubmatch(url); m != nil {
		address = m[1]
	}
	port := ""
	if m := instUrlPortRe.FindStringSubmatch(url); m != nil {
		port = m[1]
	}
	path := ""
	if m := instUrlPathRe.FindStringSubmatch(url); m != nil {
		path = "/" + m[1]
	}

	// If port is not found, set default based on protocol
	if port == "" {
		if protocol == "wss://" || protocol == "https://" {
			port = "443"
		} else {
			port = "80"
		}
	}

	fmt.Println(protocol)
	fmt.Println(address)
	fmt.Println(port)
	fmt.Println(path)
}

// instGrepFileE is `grep -E <re> file`; a missing file prints grep's error.
func instGrepFileE(file string, re *regexp.Regexp) []string {
	b, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "grep: %s: No such file or directory\n", file)
		return nil
	}
	var out []string
	for _, l := range ltLines(string(b)) {
		if re.MatchString(l) {
			out = append(out, l)
		}
	}
	return out
}

var (
	instReAzureVars   = regexp.MustCompile(`^(AZURE_REGION|AZURE_SPEECH|AZURE_SPEECH_KEY)=$`)
	instReElevenVar   = regexp.MustCompile(`^ELEVEN_LABS_API_KEY=$`)
	instReRimeVar     = regexp.MustCompile(`^RIME_API_KEY=$`)
	instReEmptyVars   = regexp.MustCompile(`^[A-Z0-9_]+=$`)
	instReTTSPrefixes = regexp.MustCompile(`^(AZURE_|ELEVEN_LABS_|RIME_)`)
	instReCommonVars  = regexp.MustCompile(`^(DHOP_APIKEY|DHOP_TENANTID)=$`)
)

// getRequiredEnvVarsFromExample is used only as `( $(get_required_env_vars_from_example) )`:
// it returns the IFS-split words of the sorted, de-duplicated list.
// bash: install_miniprem.sh:931
func getRequiredEnvVarsFromExample() []string {
	exampleFile := PROJECT_ROOT + "/docker/docker-compose.env.example"
	var allVars []string

	// Get variables based on the selected TTS provider
	switch TTS_PROVIDER {
	case "azure":
		allVars = ltCutLines(instGrepFileE(exampleFile, instReAzureVars), "=", 1)
	case "elevenlabs":
		allVars = ltCutLines(instGrepFileE(exampleFile, instReElevenVar), "=", 1)
	case "rime":
		allVars = ltCutLines(instGrepFileE(exampleFile, instReRimeVar), "=", 1)
	default:
		// Get common variables (not related to TTS)
		var keep []string
		for _, l := range instGrepFileE(exampleFile, instReEmptyVars) {
			if !instReTTSPrefixes.MatchString(l) {
				keep = append(keep, l)
			}
		}
		allVars = ltCutLines(keep, "=", 1)
	}

	// Add common required variables
	commonVars := ltCutLines(instGrepFileE(exampleFile, instReCommonVars), "=", 1)

	// echo "$all_vars"$'\n'"$common_vars" | sort | uniq
	text := strings.Join(allVars, "\n") + "\n" + strings.Join(commonVars, "\n")
	lines := strings.Split(text, "\n")
	sort.Strings(lines)
	var out []string
	for i, l := range lines {
		if i > 0 && lines[i-1] == l {
			continue
		}
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

// checkAndPromptRequiredEnvVars (never called: only the first, overridden
// configure_eleven_labs used it). bash: install_miniprem.sh:958
func checkAndPromptRequiredEnvVars() {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	requiredVars := getRequiredEnvVarsFromExample()

	for _, v := range requiredVars {
		value := readEnvVariable(v)
		if value == "" {
			warning(v + " is missing or empty in " + envFile + ".")
			value = readOrDie("Enter value for " + v + ": ")
			if value == "" {
				instFatal(v + " is required. Exiting.")
			}
			// Store the value in a variable instead of writing directly
			switch v {
			case "DHOP_APIKEY":
				PLATFORM_KEY = value
			case "DHOP_TENANTID":
				TENANT_ID = value
			case "AZURE_REGION":
				AZURE_REGION = value
			case "AZURE_SPEECH_KEY", "AZURE_SPEECH":
				AZURE_SPEECH_KEY = value
			case "ELEVEN_LABS_API_KEY":
				ELEVEN_LABS_API_KEY = value
			case "RIME_API_KEY":
				RIME_API_KEY = value
			default:
				instAbort(updateEnvVariable(v, value), 979) // Only use for non-main vars
			}
		}
	}

	// Update all main variables at once using update_env_file
	updateEnvFile()
}

// atomicFileUpdate (never called). bash: install_miniprem.sh:988
func atomicFileUpdate(targetFile, content string) {
	tempFile, _ := sh.MkTemp(targetFile + ".tmp.XXXXXX")

	if err := os.WriteFile(tempFile, []byte(content+"\n"), 0o666); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %s\n", tempFile, ltErrText(err))
		instAbort(1, 993)
	}
	if !instMv(tempFile, targetFile) {
		os.Remove(tempFile)
		instFatal("Failed to update " + targetFile + " atomically")
	}
}

// envValueNeedsUpdate is true (status 0) when the env file value differs from newValue.
// bash: install_miniprem.sh:1002
func envValueNeedsUpdate(varName, newValue string) bool {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"

	var vals []string
	if b, err := os.ReadFile(envFile); err == nil {
		for _, l := range ltLines(string(b)) {
			if strings.HasPrefix(l, varName+"=") {
				vals = append(vals, ltCutField2Plus(l))
			}
		}
	}
	current := strings.Join(vals, "\n")
	// Remove surrounding quotes if any
	current = instEchoStripQuotes(current)
	// Unescape $$ back to $ for comparison
	current = strings.ReplaceAll(current, "$$", "$")

	return current != newValue
}

// updateEnvFile batches PLATFORM_KEY/TENANT_ID/TTS values into docker-compose.env via a
// 0600 mktemp file that is mv'd over the original (so the env file ends up 0600).
// bash: install_miniprem.sh:1018
func updateEnvFile() {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	tempFile, _ := sh.MkTemp("")
	updatesMade := false

	// Copy original file to temp
	data, err := os.ReadFile(envFile)
	if err == nil {
		err = os.WriteFile(tempFile, data, 0o600)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "cp: cannot stat '%s': No such file or directory\n", envFile)
		os.Remove(tempFile)
		instFatal("Failed to create temporary file for environment updates")
	}

	// set applies one batched variable update; it aborts the script if sed fails (errexit).
	set := func(name, value string) {
		if instFileHasLinePrefix(tempFile, name+"=") && envValueNeedsUpdate(name, value) {
			escaped := instSedEscape(value)
			instAbort(instSedSetVar(tempFile, name, escaped), 1033)
			updatesMade = true
			info("Updating " + name)
		}
	}

	// Batch update all variables at once - only if value changed
	if PLATFORM_KEY != "" {
		set("DHOP_APIKEY", PLATFORM_KEY)
	}

	if TENANT_ID != "" {
		set("DHOP_TENANTID", TENANT_ID)
	}

	// TTS-specific batch updates
	if TTS_PROVIDER == "azure" {
		if AZURE_REGION != "" {
			set("AZURE_REGION", AZURE_REGION)
		}

		if AZURE_SPEECH_KEY != "" {
			set("AZURE_SPEECH_KEY", AZURE_SPEECH_KEY)
			set("AZURE_SPEECH", AZURE_SPEECH_KEY)
		}
	} else if TTS_PROVIDER == "elevenlabs" {
		if ELEVEN_LABS_API_KEY != "" {
			set("ELEVEN_LABS_API_KEY", ELEVEN_LABS_API_KEY)
		}
	} else if TTS_PROVIDER == "rime" {
		if RIME_API_KEY != "" {
			set("RIME_API_KEY", RIME_API_KEY)
		}
	}

	// Apply atomic update if changes were made
	if updatesMade {
		if !instMv(tempFile, envFile) {
			os.Remove(tempFile)
			instFatal("Failed to apply environment file updates atomically")
		}
		success(CHECKMARK + " Environment file updated with batch operations")
	} else {
		os.Remove(tempFile)
		info("No environment variable updates needed (values unchanged)")
	}
}

// configureRegionEndpoints (the installer's own copy; the scripts/environment.sh copy is
// shadowed by it). bash: install_miniprem.sh:1108
func configureRegionEndpoints() {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	region := ltOr(UNEEQ_REGION, "us")

	// Check current endpoint to see if update is needed
	var vals []string
	if b, err := os.ReadFile(envFile); err == nil {
		for _, l := range ltLines(string(b)) {
			if strings.HasPrefix(l, "DHOP_ADDRESS=") {
				vals = append(vals, ltCutField2Plus(l))
			}
		}
	}
	currentEndpoint := strings.Join(vals, "\n")

	if region == "eu" {
		// Check if already configured for EU
		if instGrepQ(currentEndpoint, "api-eu.enterprise.uneeq.io") {
			info("Endpoints already configured for region: eu (no change needed)")
			return
		}
		info("Configuring endpoints for region: eu")
		instAbort(instSedReplaceAll(envFile, `api.enterprise.uneeq.io`, "api-eu.enterprise.uneeq.io"), 1122)
	} else {
		// Check if already configured for US
		if instGrepQ(currentEndpoint, "api.enterprise.uneeq.io") && !instGrepQ(currentEndpoint, "api-eu") {
			info("Endpoints already configured for region: us (no change needed)")
			return
		}
		// Change EU back to US if needed
		if instGrepQ(currentEndpoint, "api-eu.enterprise.uneeq.io") {
			info("Configuring endpoints for region: us")
			instAbort(instSedReplaceAll(envFile, `api-eu.enterprise.uneeq.io`, "api.enterprise.uneeq.io"), 1132)
		} else {
			info("Endpoints already configured for region: us (default)")
		}
	}
}

// promptForRegion (the installer's own copy). bash: install_miniprem.sh:1140
func promptForRegion() {
	if UNEEQ_REGION != "" {
		seedValidateChoice("UNEEQ_REGION", "us|eu")
		info("Using region: " + UNEEQ_REGION)
		return
	}
	if seedIsNonInteractive() {
		// Region has a sensible default ("us"); apply it instead of failing.
		UNEEQ_REGION = "us"
		info("Region defaulted to 'us' (set MINIPREM_SEED_REGION=eu for EU)")
		return
	}
	fmt.Println("")
	fmt.Println("Select UneeQ region:")
	fmt.Println("1) US (default)")
	fmt.Println("2) EU")
	regionChoice := readOrDie("Enter choice [1-2, default 1]: ")
	switch regionChoice {
	case "2":
		UNEEQ_REGION = "eu"
	default:
		UNEEQ_REGION = "us"
	}
	info("Region selected: " + UNEEQ_REGION)
}

// ensureEnvFileExists. bash: install_miniprem.sh:1165
func ensureEnvFileExists() {
	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	exampleFile := PROJECT_ROOT + "/docker/docker-compose.env.example"

	// Use stat for more reliable file existence checking
	if sh.C("stat", envFile).Quiet().Run() != 0 {
		// Example file must exist
		if ltIsFile(exampleFile) {
			info("Environment file not found, creating from example.")

			// Attempt to copy with error handling
			if !instCopyFile(exampleFile, envFile) {
				logError("Failed to copy " + exampleFile + " to " + envFile)
				instFatal("Check disk space and permissions in " + PROJECT_ROOT + "/docker/")
			}

			// Verify the copied file is readable and non-empty
			st, serr := os.Stat(envFile)
			if syscall.Access(envFile, 4) != nil || serr != nil || st.Size() == 0 {
				logError("Created " + envFile + " is not readable or empty")
				os.Remove(envFile) // Clean up invalid file
				instFatal("File creation verification failed. Check permissions and disk space.")
			}

			success(CHECKMARK + " Created " + envFile + " from " + exampleFile)
		} else {
			instFatal("Example environment file " + exampleFile + " not found.")
		}
	} else {
		info("Environment file already exists at " + envFile)
	}
}

// ensureFlowiseEnvExists generates docker/flowise.env with random secrets.
// bash: install_miniprem.sh:1201
func ensureFlowiseEnvExists() {
	envFile := PROJECT_ROOT + "/docker/flowise.env"

	if sh.C("stat", envFile).Quiet().Run() == 0 {
		info("Flowise environment file already exists at " + envFile)
		return
	}

	info("Generating Flowise secrets and admin credentials...")

	// Password must satisfy Flowise complexity rules: lower, upper, digit, special
	hex8, _ := sh.C("openssl", "rand", "-hex", "8").Output()
	adminPassword := "Mp1!" + hex8

	// The heredoc expands its $(...) in textual order: date, then the five secrets.
	content := strings.Replace(instFlowiseEnv, "@DATE@", sh.Now().Format("2006-01-02 15:04:05"), 1)
	for strings.Contains(content, "@HEX32@") {
		h, _ := sh.C("openssl", "rand", "-hex", "32").Output()
		content = strings.Replace(content, "@HEX32@", h, 1)
	}
	content = strings.Replace(content, "@PW@", adminPassword, 1)

	if err := os.WriteFile(envFile, []byte(content), 0o666); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %s\n", envFile, ltErrText(err))
		instAbort(1, 1214)
	}
	if err := os.Chmod(envFile, 0o600); err != nil {
		instAbort(1, 1233)
	}

	if st, err := os.Stat(envFile); err != nil || st.Size() == 0 {
		instFatal("Failed to create " + envFile + ". Check disk space and permissions.")
	}
	success(CHECKMARK + " Created " + envFile + " with generated secrets")
	info("Flowise admin login is stored in " + envFile + " (FLOWISE_ADMIN_EMAIL / FLOWISE_ADMIN_PASSWORD)")
}

// checkAllValuesProvided returns 0 when everything is present, else 1. It is only called
// from an `if`, so errexit is off.
// bash: install_miniprem.sh:1338
func checkAllValuesProvided() int {
	missing := 0

	// Debug information
	info("Checking configuration values...")
	info("PLATFORM_ADDRESS: " + instDefault(PLATFORM_ADDRESS, "'Not set'"))
	info("PLATFORM_KEY: " + instAlt(PLATFORM_KEY, "'Set (value hidden)'"))
	info("TENANT_ID: " + instDefault(TENANT_ID, "'Not set'"))
	info("RENNY_IMAGE: " + instDefault(RENNY_IMAGE, "'Not set'"))

	// Check TTS-specific variables based on provider
	if TTS_PROVIDER == "azure" {
		info("AZURE_REGION: " + instDefault(AZURE_REGION, "'Not set'"))
		info("AZURE_SPEECH_KEY: " + instAlt(AZURE_SPEECH_KEY, "'Set (value hidden)'"))
	} else if TTS_PROVIDER == "elevenlabs" {
		ELEVEN_LABS_API_KEY = readEnvVariable("ELEVEN_LABS_API_KEY")
		info("ELEVEN_LABS_API_KEY: " + instAlt(ELEVEN_LABS_API_KEY, "'Set (value hidden)'"))
	} else if TTS_PROVIDER == "rime" {
		RIME_API_KEY = readEnvVariable("RIME_API_KEY")
		info("RIME_API_KEY: " + instAlt(RIME_API_KEY, "'Set (value hidden)'"))
	}

	if PLATFORM_KEY == "" {
		warning("UneeQ platform API key is missing")
		missing = 1
	}

	if TENANT_ID == "" {
		warning("Tenant ID is missing")
		missing = 1
	}

	// Check TTS-specific requirements
	if TTS_PROVIDER == "azure" {
		if AZURE_REGION == "" {
			warning("Azure region is missing")
			missing = 1
		}

		if AZURE_SPEECH_KEY == "" {
			warning("Azure speech key is missing")
			missing = 1
		}
	} else if TTS_PROVIDER == "elevenlabs" {
		ELEVEN_LABS_API_KEY = readEnvVariable("ELEVEN_LABS_API_KEY")
		if ELEVEN_LABS_API_KEY == "" {
			warning("Eleven Labs API key is missing")
			missing = 1
		}
	} else if TTS_PROVIDER == "rime" {
		RIME_API_KEY = readEnvVariable("RIME_API_KEY")
		if RIME_API_KEY == "" {
			warning("RIME API key is missing")
			missing = 1
		}
	}

	if RENNY_IMAGE == "" {
		warning("Renny image name is missing")
		missing = 1
	}

	if missing == 0 {
		return 0 // All values are present
	}
	return 1 // Some values are missing
}

// instDefault is "${v:-def}"; instAlt is "${v:+alt}" (single quotes inside double quotes
// are literal in bash).
func instDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

func instAlt(v, alt string) string {
	if v == "" {
		return ""
	}
	return alt
}
