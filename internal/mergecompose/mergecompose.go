// Package mergecompose ports docker/scripts/merge-compose.sh.
//
// merge-compose.sh runs under `set -euo pipefail`, but every function except
// parse_arguments/main/check_dependencies is reached through `if perform_merge ...`
// (a condition context), so errexit is DISABLED for the whole merge; only `exit`
// statements and fatal expansion errors (unbound $2) terminate the script.
package mergecompose

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// bash: lines 40-44
const (
	RED    = `\033[0;31m`
	GREEN  = `\033[0;32m`
	YELLOW = `\033[1;33m`
	BLUE   = `\033[0;34m`
	NC     = `\033[0m`
)

// bash: lines 22-37 (globals)
var (
	SCRIPT_PATH string // $0 / BASH_SOURCE[0] (from MINIPREM_SCRIPT_PATH)
	SCRIPT_DIR  string
	DOCKER_ROOT string

	DEFAULT_OFFICIAL_FILE string
	DEFAULT_CUSTOM_FILE   string
	DEFAULT_OUTPUT_FILE   string

	OFFICIAL_FILE        string
	CUSTOM_FILE          string
	OUTPUT_FILE          string
	CHECK_ONLY           bool
	PREFER_CUSTOM        bool
	RENAME_CUSTOM_PREFIX string
	VERBOSE              bool
)

func stdout(s string) { fmt.Fprintln(os.Stdout, s) }

// bash: line 50
func log(args ...string) { stdout(sh.EchoE(BLUE + "[INFO]" + NC + " " + strings.Join(args, " "))) }

// bash: line 54
func logVerbose(args ...string) { logVerboseTo(os.Stdout, args...) }

func logVerboseTo(w io.Writer, args ...string) {
	if VERBOSE {
		fmt.Fprintln(w, sh.EchoE(BLUE+"[DEBUG]"+NC+" "+strings.Join(args, " ")))
	}
}

// bash: line 60
func logSuccess(args ...string) {
	stdout(sh.EchoE(GREEN + "[SUCCESS]" + NC + " " + strings.Join(args, " ")))
}

// bash: line 64
func logWarn(args ...string) { logWarnTo(os.Stdout, args...) }

func logWarnTo(w io.Writer, args ...string) {
	fmt.Fprintln(w, sh.EchoE(YELLOW+"[WARN]"+NC+" "+strings.Join(args, " ")))
}

// bash: line 68 (stderr)
func logError(args ...string) {
	fmt.Fprintln(os.Stderr, sh.EchoE(RED+"[ERROR]"+NC+" "+strings.Join(args, " ")))
}

func baseName(p string) string { // ${0##*/}
	if i := strings.LastIndex(p, "/"); i >= 0 {
		return p[i+1:]
	}
	return p
}

// bash: line 72
func showHelp() {
	n := baseName(SCRIPT_PATH)
	fmt.Fprint(os.Stdout, "Usage: "+n+` [OPTIONS]

Intelligently merge official and custom Docker Compose files.

OPTIONS:
    --file FILE              Input custom compose file
                             (default: docker-compose.custom.yml)
    --output FILE            Output file
                             (default: docker-compose.override.yml)
    --check                  Check compatibility without writing
    --prefer-custom          Keep custom when conflicts exist (DEFAULT)
    --prefer-official        Use official when conflicts exist
    --rename-custom PREFIX   Rename conflicting custom services with PREFIX
    --verbose                Enable debug output
    -h, --help               Show this help message

EXAMPLES:
    # Basic merge with defaults
    `+n+`

    # Check for conflicts without writing
    `+n+` --check

    # Prefer official services when conflicts exist
    `+n+` --prefer-official

    # Rename conflicting custom services
    `+n+` --rename-custom "custom-"

    # Custom input and output files
    `+n+` --file my-custom.yml --output my-override.yml

EXIT CODES:
    0 - Success
    1 - Error (validation failed, missing tools, etc.)
    2 - Conflicts detected (informational, depends on strategy)

`)
}

// ---------------------------------------------------------------------------
// file helpers reproducing bash redirection failures

func strerror(err error) string {
	var en syscall.Errno
	msg := err.Error()
	if errors.As(err, &en) {
		msg = en.Error()
	}
	if msg == "" {
		return msg
	}
	return strings.ToUpper(msg[:1]) + msg[1:]
}

// redirErr prints bash's "<script>: line N: path: reason" for a failed redirection.
func redirErr(line int, path string, err error) {
	fmt.Fprintf(os.Stderr, "%s: line %d: %s: %s\n", SCRIPT_PATH, line, path, strerror(err))
}

// writeRedir emulates `printf %s content > path` / `>> path` (append=true) at a bash line.
func writeRedir(line int, path string, content string, appendMode bool) bool {
	flags := os.O_WRONLY | os.O_CREATE | os.O_TRUNC
	if appendMode {
		flags = os.O_WRONLY | os.O_CREATE | os.O_APPEND
	}
	f, err := os.OpenFile(path, flags, 0o666)
	if err != nil {
		redirErr(line, path, err)
		return false
	}
	f.WriteString(content)
	f.Close()
	return true
}

func isRegular(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// ---------------------------------------------------------------------------
// Validation

// bash: line 118
func checkDependencies() int {
	var missing []string
	if !sh.CommandExists("yq") {
		if st, err := os.Stat("/snap/bin/yq"); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			logVerbose("Found yq at /snap/bin/yq")
		} else {
			missing = append(missing, "yq")
		}
	} else {
		p, _ := exec.LookPath("yq")
		logVerbose("Found yq at " + p)
	}
	if !sh.CommandExists("docker") && !sh.CommandExists("docker-compose") {
		missing = append(missing, "docker or docker-compose")
	}
	if len(missing) > 0 {
		logError("Missing required tools: " + strings.Join(missing, " "))
		logError("Please install missing dependencies:")
		logError("  - yq: brew install yq (macOS), snap install yq (Ubuntu), or https://github.com/mikefarah/yq")
		return 1
	}
	logVerbose("All required dependencies found")
	return 0
}

// bash: line 148
func validateYAMLSyntax(file, label string) int {
	logVerbose("Validating YAML syntax for " + label + ": " + file)
	if !isRegular(file) {
		logError(label + " does not exist: " + file)
		return 1
	}
	if sh.C("yq", "eval", ".", file).Quiet().Run() != 0 {
		logError("Invalid YAML syntax in " + label + ": " + file)
		return 1
	}
	logVerbose(label + " has valid YAML syntax")
	return 0
}

// bash: line 169
func validateComposeFile(file, label string) int {
	logVerbose("Validating Docker Compose structure for " + label + ": " + file)
	var b bytes.Buffer
	c := sh.C("yq", "eval", `has("services")`, file)
	c.Stdout = &b
	rc := c.Run()
	// `yq ... | grep -q true` under pipefail: fails if yq failed or grep found nothing.
	if !(rc == 0 && strings.Contains(b.String(), "true")) {
		logError(label + " missing required 'services' key: " + file)
		return 1
	}
	logVerbose(label + " has valid Docker Compose structure")
	return 0
}

// ---------------------------------------------------------------------------
// Conflict detection

// breToRegexp converts the service name used inside grep's BRE "^NAME$" into a Go
// regexp fragment. ok=false means grep would report a regex error (-> no match).
func breToRegexp(p string) (string, bool) {
	var b strings.Builder
	for i := 0; i < len(p); i++ {
		ch := p[i]
		switch ch {
		case '.':
			b.WriteString(".")
		case '*':
			if i == 0 {
				b.WriteString(`\*`)
			} else {
				b.WriteString("*")
			}
		case '\\':
			if i+1 >= len(p) {
				return "", false
			}
			i++
			b.WriteString(regexp.QuoteMeta(string(p[i])))
		case '[':
			j := i + 1
			var cls strings.Builder
			cls.WriteString("[")
			if j < len(p) && p[j] == '^' {
				cls.WriteString("^")
				j++
			}
			if j < len(p) && p[j] == ']' {
				cls.WriteString(`\]`)
				j++
			}
			closed := false
			for j < len(p) {
				c := p[j]
				if c == ']' {
					closed = true
					break
				}
				if c == '[' && j+1 < len(p) && p[j+1] == ':' {
					if k := strings.Index(p[j:], ":]"); k >= 0 {
						cls.WriteString(p[j : j+k+2])
						j += k + 2
						continue
					}
				}
				if c == '\\' || c == '[' {
					cls.WriteString(`\`)
				}
				cls.WriteByte(c)
				j++
			}
			if !closed {
				return "", false
			}
			cls.WriteString("]")
			b.WriteString(cls.String())
			i = j
		default:
			b.WriteString(regexp.QuoteMeta(string(ch)))
		}
	}
	return b.String(), true
}

// grepLineExact emulates: echo "$text" | grep -q "^${name}$"
func grepLineExact(text, name string) bool {
	re, ok := breToRegexp(name)
	if !ok {
		return false
	}
	rx, err := regexp.Compile("^(?:" + re + ")$")
	if err != nil {
		return false
	}
	for _, l := range strings.Split(text, "\n") {
		if rx.MatchString(l) {
			return true
		}
	}
	return false
}

// findConflicts is the pure loop of detect_service_conflicts (bash: lines 204-208).
func findConflicts(officialServices, customServices string) []string {
	var conflicts []string
	for _, service := range strings.Split(customServices, "\n") {
		if grepLineExact(officialServices, service) {
			conflicts = append(conflicts, service)
		}
	}
	return conflicts
}

// yqServices emulates: $(yq eval '.services | keys | .[]' "$f" 2>/dev/null || echo "")
func yqServices(file string, in string) string {
	c := sh.C("yq", "eval", ".services | keys | .[]", file).NoErr()
	if in != "" {
		c.Stdin = strings.NewReader(in)
	}
	out, _ := c.Output()
	return out
}

// bash: line 189. w receives what bash writes to the function's stdout.
func detectServiceConflicts(officialFile, customFile string, w io.Writer) int {
	logVerboseTo(w, "Detecting service name conflicts...")
	officialServices := yqServices(officialFile, "")
	customServices := yqServices(customFile, "")
	conflicts := findConflicts(officialServices, customServices)
	if len(conflicts) > 0 {
		logWarnTo(w, fmt.Sprintf("Found %d service name conflict(s):", len(conflicts)))
		for _, s := range conflicts {
			logWarnTo(w, "  - "+s)
		}
		fmt.Fprintln(w, strings.Join(conflicts, " "))
		return 2
	}
	logVerboseTo(w, "No service name conflicts detected")
	return 0
}

// ---------------------------------------------------------------------------
// Merging

// restOf emulates what is left unread of the here-string feeding a `while read` loop.
func restOf(lines []string, i int) string {
	if i+1 >= len(lines) {
		return ""
	}
	return strings.Join(lines[i+1:], "\n") + "\n"
}

// bash: line 227
func mergeServices(officialFile, customFile, outputFile string, conflicts []string) {
	log("Merging services...")
	tmp := outputFile + ".tmp.merged"

	composeName, _ := sh.C("yq", "eval", `.name // ""`, officialFile).Output()
	if composeName != "" {
		writeRedir(242, tmp, "name: "+composeName+"\n", false)
		writeRedir(243, tmp, "services:\n", true)
	} else {
		writeRedir(245, tmp, "services:\n", false)
	}

	customServices := yqServices(customFile, "")
	lines := strings.Split(customServices, "\n")
	for i, service := range lines {
		if service == "" {
			continue
		}
		stdin := restOf(lines, i)
		isConflict := false
		for _, c := range conflicts {
			if service == c {
				isConflict = true
				break
			}
		}
		if isConflict {
			if PREFER_CUSTOM {
				logVerbose("Overwriting service '" + service + "' with custom version (prefer-custom)")
				pipeYq(stdin,
					[]string{"eval", ".services." + service, customFile},
					[]string{"eval", ".services." + service + ` = load("` + customFile + `") | .services.` + service, "--inplace", tmp})
			} else if RENAME_CUSTOM_PREFIX != "" {
				newName := RENAME_CUSTOM_PREFIX + service
				logVerbose("Renaming custom service '" + service + "' to '" + newName + "'")
				pipeYq(stdin,
					[]string{"eval", ".services." + service, customFile},
					[]string{"eval", ".services." + newName + ` = load("` + customFile + `") | .services.` + service, "--inplace", tmp})
			} else {
				logVerbose("Keeping official service '" + service + "' (prefer-official)")
			}
		} else {
			logVerbose("Adding custom service '" + service + "'")
			sh.C("yq", "eval-all", "--inplace",
				"select(fileIndex == 0).services."+service+" = select(fileIndex == 1).services."+service+" | select(fileIndex == 0)",
				tmp, customFile).In(stdin).Run()
		}
	}
}

// pipeYq runs `yq a... | yq b...` (second reads the first's stdout).
func pipeYq(loopStdin string, a, b []string) {
	var buf bytes.Buffer
	c1 := sh.C("yq", a...).In(loopStdin)
	c1.Stdout = &buf
	c1.Run()
	sh.C("yq", b...).In(buf.String()).Run()
}

// bash: line 292
func mergeVolumes(officialFile, customFile, outputFile string) {
	logVerbose("Merging volumes...")
	v, _ := sh.C("yq", "eval", ".volumes // {}", customFile).Output()
	if v != "{}" {
		sh.C("yq", "eval-all", "--inplace",
			"select(fileIndex == 0).volumes = select(fileIndex == 1).volumes | select(fileIndex == 0)",
			outputFile+".tmp.merged", customFile).Run()
	}
}

// bash: line 312
func mergeNetworks(officialFile, customFile, outputFile string) {
	logVerbose("Merging networks...")
	n, _ := sh.C("yq", "eval", ".networks // {}", customFile).Output()
	if n != "{}" {
		sh.C("yq", "eval-all", "--inplace",
			"select(fileIndex == 0).networks = select(fileIndex == 1).networks | select(fileIndex == 0)",
			outputFile+".tmp.merged", customFile).Run()
	}
}

// strategyName reproduces the $(if ...) inside the header heredoc (bash: line 348).
func strategyName() string {
	if PREFER_CUSTOM {
		return "prefer-custom"
	} else if RENAME_CUSTOM_PREFIX != "" {
		return "rename-custom (" + RENAME_CUSTOM_PREFIX + ")"
	}
	return "prefer-official"
}

// headerBase is the heredoc part of the header (bash: lines 340-349).
func headerBase(timestamp string) string {
	return "# Docker Compose Override File\n" +
		"# Generated by merge-compose.sh on " + timestamp + "\n" +
		"#\n" +
		"# This file was created by merging:\n" +
		"#   Official: " + OFFICIAL_FILE + "\n" +
		"#   Custom:   " + CUSTOM_FILE + "\n" +
		"#\n" +
		"# Merge Strategy: " + strategyName() + "\n"
}

// headerTail is what the echo >> lines append (bash: lines 351-360).
func headerTail(conflicts []string) string {
	var b strings.Builder
	if len(conflicts) > 0 {
		b.WriteString("#\n")
		b.WriteString(fmt.Sprintf("# Conflicts Resolved: %d\n", len(conflicts)))
		for _, c := range conflicts {
			b.WriteString("#   - " + c + "\n")
		}
	}
	b.WriteString("#\n\n")
	return b.String()
}

// bash: line 332
func addMetadataHeader(outputFile string, conflicts []string) {
	timestamp := sh.Now().UTC().Format("2006-01-02 15:04:05") + " UTC"
	header := outputFile + ".header"

	// A failing redirect skips only that command; each echo >> reports its own line.
	writeRedir(340, header, headerBase(timestamp), false)
	appendHeaderTail(header, conflicts)

	// cat header tmp.merged > output
	f, err := os.OpenFile(outputFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o666)
	if err != nil {
		redirErr(363, outputFile, err)
	} else {
		for _, p := range []string{header, outputFile + ".tmp.merged"} {
			data, err := os.ReadFile(p)
			if err != nil {
				fmt.Fprintf(os.Stderr, "cat: %s: %s\n", p, strerror(err))
				continue
			}
			f.Write(data)
		}
		f.Close()
	}
	os.Remove(header)
	os.Remove(outputFile + ".tmp.merged")
}

// bash: lines 351-360
func appendHeaderTail(header string, conflicts []string) {
	if len(conflicts) > 0 {
		writeRedir(352, header, "#\n", true)
		writeRedir(353, header, fmt.Sprintf("# Conflicts Resolved: %d\n", len(conflicts)), true)
		for _, c := range conflicts {
			writeRedir(355, header, "#   - "+c+"\n", true)
		}
	}
	writeRedir(359, header, "#\n", true)
	writeRedir(360, header, "\n", true)
}

// bash: line 367
func validateMergedOutput(outputFile string) int {
	log("Validating merged output...")
	if validateYAMLSyntax(outputFile, "merged output") != 0 {
		return 1
	}
	if sh.CommandExists("docker-compose") {
		logVerbose("Running docker-compose config validation...")
		// temp_dir=$(mktemp -d)
		tempDir, _ := sh.MkTempDir("")
		if data, rerr := os.ReadFile(outputFile); rerr == nil {
			os.WriteFile(filepath.Join(tempDir, "docker-compose.yml"), data, 0o666)
		}
		if sh.C("docker-compose", "config").Quiet().InDir(tempDir).Run() == 0 {
			logVerbose("docker-compose config validation passed")
			os.RemoveAll(tempDir)
			return 0
		}
		logError("docker-compose config validation failed")
		os.RemoveAll(tempDir)
		return 1
	}
	logVerbose("Merged output validation passed")
	return 0
}

// tailLast emulates `... | tail -1` on captured output.
func tailLast(s string) string {
	s = strings.TrimSuffix(s, "\n")
	if i := strings.LastIndex(s, "\n"); i >= 0 {
		return s[i+1:]
	}
	return s
}

// bash: line 404
func performMerge(officialFile, customFile, outputFile string) int {
	log("Starting merge process...")
	log("  Official: " + officialFile)
	log("  Custom:   " + customFile)
	log("  Output:   " + outputFile)

	if validateYAMLSyntax(officialFile, "official file") != 0 {
		return 1
	}
	if validateYAMLSyntax(customFile, "custom file") != 0 {
		return 1
	}
	if validateComposeFile(officialFile, "official file") != 0 {
		return 1
	}
	if validateComposeFile(customFile, "custom file") != 0 {
		return 1
	}

	var conflicts []string
	// conflicts_str=$(detect_service_conflicts ... 2>&1 >&2): `2>&1` sends fd2 into the
	// capture pipe, then `>&2` copies THAT, so all output is captured and unused here.
	if rc := detectServiceConflicts(officialFile, customFile, io.Discard); rc == 0 {
		logVerbose("No conflicts detected")
	} else if rc == 2 {
		var b bytes.Buffer
		detectServiceConflicts(officialFile, customFile, &b)
		conflicts = sh.SplitIFS(tailLast(b.String()))
		logVerbose("Detected conflicts: " + strings.Join(conflicts, " "))
		logWarn("Conflicts will be resolved using merge strategy")
	}

	if CHECK_ONLY {
		log("Check-only mode: No output file written")
		if len(conflicts) > 0 {
			logWarn("Conflicts detected (see above)")
			return 2
		}
		logSuccess("No conflicts detected")
		return 0
	}

	mergeServices(officialFile, customFile, outputFile, conflicts)
	mergeVolumes(officialFile, customFile, outputFile)
	mergeNetworks(officialFile, customFile, outputFile)

	addMetadataHeader(outputFile, conflicts)

	if validateMergedOutput(outputFile) != 0 {
		logError("Merged output validation failed")
		return 1
	}

	logSuccess("Merge completed successfully")
	logSuccess("Output written to: " + outputFile)

	if len(conflicts) > 0 {
		logWarn(fmt.Sprintf("Resolved %d conflict(s) - review output file", len(conflicts)))
		return 2
	}
	return 0
}

// unboundArg reproduces `set -u` on a missing "$2".
func unboundArg(line int) {
	fmt.Fprintf(os.Stderr, "%s: line %d: $2: unbound variable\n", SCRIPT_PATH, line)
	sh.Exit(1)
}

// bash: line 486
func parseArguments(args []string) {
	for len(args) > 0 {
		switch args[0] {
		case "--file":
			if len(args) < 2 {
				unboundArg(490)
			}
			CUSTOM_FILE = args[1]
			args = args[2:]
		case "--output":
			if len(args) < 2 {
				unboundArg(494)
			}
			OUTPUT_FILE = args[1]
			args = args[2:]
		case "--check":
			CHECK_ONLY = true
			args = args[1:]
		case "--prefer-custom":
			PREFER_CUSTOM = true
			RENAME_CUSTOM_PREFIX = ""
			args = args[1:]
		case "--prefer-official":
			PREFER_CUSTOM = false
			RENAME_CUSTOM_PREFIX = ""
			args = args[1:]
		case "--rename-custom":
			if len(args) < 2 {
				unboundArg(512)
			}
			RENAME_CUSTOM_PREFIX = args[1]
			PREFER_CUSTOM = false
			args = args[2:]
		case "--verbose":
			VERBOSE = true
			args = args[1:]
		case "-h", "--help":
			showHelp()
			sh.Exit(0)
		default:
			logError("Unknown option: " + args[0])
			stdout("")
			showHelp()
			sh.Exit(1)
		}
	}
	if !strings.HasPrefix(CUSTOM_FILE, "/") {
		CUSTOM_FILE = DOCKER_ROOT + "/" + CUSTOM_FILE
	}
	if !strings.HasPrefix(OUTPUT_FILE, "/") {
		OUTPUT_FILE = DOCKER_ROOT + "/" + OUTPUT_FILE
	}
}

// bash: lines 16-44 (top-level initialisation)
func initGlobals() {
	os.Setenv("PATH", "/snap/bin:"+os.Getenv("PATH"))
	SCRIPT_PATH = os.Getenv("MINIPREM_SCRIPT_PATH")
	if SCRIPT_PATH == "" {
		if exe, err := os.Executable(); err == nil {
			SCRIPT_PATH = filepath.Join(filepath.Dir(exe), "merge-compose.sh")
		}
	}
	// SCRIPT_DIR="$(cd "$(dirname "$SRC")" && pwd)"
	dir := filepath.Dir(SCRIPT_PATH)
	if abs, err := filepath.Abs(dir); err == nil {
		dir = abs
	}
	SCRIPT_DIR = dir
	DOCKER_ROOT = filepath.Clean(SCRIPT_DIR + "/..")
	DEFAULT_OFFICIAL_FILE = DOCKER_ROOT + "/docker-compose.yml"
	DEFAULT_CUSTOM_FILE = DOCKER_ROOT + "/docker-compose.custom.yml"
	DEFAULT_OUTPUT_FILE = DOCKER_ROOT + "/docker-compose.override.yml"
	OFFICIAL_FILE = DEFAULT_OFFICIAL_FILE
	CUSTOM_FILE = DEFAULT_CUSTOM_FILE
	OUTPUT_FILE = DEFAULT_OUTPUT_FILE
	CHECK_ONLY = false
	PREFER_CUSTOM = true
	RENAME_CUSTOM_PREFIX = ""
	VERBOSE = false
}

// Main is bash `main "$@"` (line 547).
func Main(args []string) {
	initGlobals()
	parseArguments(args)

	log("Docker Compose Merge Utility")
	log("==============================")

	if checkDependencies() != 0 {
		sh.Exit(1)
	}
	if !isRegular(CUSTOM_FILE) {
		logError("Custom file does not exist: " + CUSTOM_FILE)
		sh.Exit(1)
	}
	rc := performMerge(OFFICIAL_FILE, CUSTOM_FILE, OUTPUT_FILE)
	if rc == 0 {
		sh.Exit(0)
	}
	if rc == 2 {
		sh.Exit(2)
	}
	sh.Exit(1)
}
