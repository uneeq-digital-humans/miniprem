package mp

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/logging.sh.

// bash: scripts/logging.sh:6-16 (colours stay literal backslash strings; print them
// through sh.EchoE where bash used `echo -e`).
var (
	LOG_FILE  = "install_miniprem.log"
	LOG_DIR   = "logs"
	LIGHTGRAY = `\033[0;37m`
	GREEN     = `\033[0;32m`
	ORANGE    = `\033[0;33m`
	RED       = `\033[0;31m`
	BLUE      = `\033[0;34m`
	BOLD      = `\033[1m`
	NC        = `\033[0m`
	// bash: scripts/logging.sh:19-20
	CHECKMARK = "✓"
	CROSS     = "✗"
)

var loggingInited bool

// initLogging runs logging.sh's top-level code in source order: mkdir -p "$LOG_DIR",
// rotate_logs, initialize_log. Idempotent. bash: scripts/logging.sh:23,60,106
func initLogging() {
	if loggingInited {
		return
	}
	loggingInited = true
	_ = os.MkdirAll(LOG_DIR, 0o777)
	rotateLogs()
	initializeLog()
}

var tsInLogRe = regexp.MustCompile(`[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}`)

// rotateLogs moves an existing log file to logs/install_miniprem_<ts>.log.
// bash: scripts/logging.sh:26
func rotateLogs() {
	if !ltIsFile(LOG_FILE) {
		return
	}
	var first string
	if b, err := os.ReadFile(LOG_FILE); err == nil {
		first = string(b)
		if i := strings.IndexByte(first, '\n'); i >= 0 {
			first = first[:i]
		}
	}
	timestamp := strings.Join(tsInLogRe.FindAllString(first, -1), "\n")
	if timestamp == "" {
		timestamp = sh.Now().Format("2006-01-02_15-04-05")
	}
	target := LOG_DIR + "/install_miniprem_" + timestamp + ".log"
	if err := os.Rename(LOG_FILE, target); err != nil {
		// mv falls back to copy+delete across filesystems
		b, rerr := os.ReadFile(LOG_FILE)
		if rerr == nil && os.WriteFile(target, b, 0o644) == nil {
			os.Remove(LOG_FILE)
			return
		}
		fmt.Fprintf(os.Stderr, "ERROR: Failed to rotate log file from %s to %s\n", LOG_FILE, target)
		fmt.Fprintf(os.Stderr, "  - Check disk space: df -h\n")
		fmt.Fprintf(os.Stderr, "  - Check permissions: ls -la %s\n", LOG_DIR)
	}
}

// initializeLog truncates LOG_FILE and writes the start line.
// bash: scripts/logging.sh:100
func initializeLog() {
	timestamp := sh.Now().Format("2006-01-02_15-04-05")
	_ = os.WriteFile(LOG_FILE, []byte("Log start time: "+timestamp+"\n"), 0o644)
}

// ltAppendLog emulates `... >> "$LOG_FILE"`.
func ltAppendLog(s string) {
	f, err := os.OpenFile(LOG_FILE, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return
	}
	f.WriteString(s)
	f.Close()
}

// logMessage: console line to STDERR, plain line appended to LOG_FILE. `message="$@"`
// joins the remaining args with a space. bash: scripts/logging.sh:63
func logMessage(level, color, symbol string, msg ...string) {
	message := strings.Join(msg, " ")
	timestamp := sh.Now().Format("2006-01-02 15:04:05")
	fmt.Fprint(os.Stderr, ltEchoE(color+level+": "+symbol+" "+message+NC))
	ltAppendLog(ltEchoE(timestamp + " " + level + ": " + symbol + " " + message))
}

// ltPadBytes emulates printf %-Ns (bash pads by BYTES, not characters).
func ltPadBytes(s string, n int) string {
	if len(s) >= n {
		return s
	}
	return s + strings.Repeat(" ", n-len(s))
}

// logSection prints the boxed section header (stderr) and logs it (file).
// bash: scripts/logging.sh:79
func logSection(sectionName string) {
	timestamp := sh.Now().Format("2006-01-02 15:04:05")
	const boxWidth = 63
	border := strings.Repeat("=", boxWidth+2)

	fmt.Fprint(os.Stderr, ltEchoE(`\n`+BLUE+BOLD+"+"+border+"+"+NC))
	// printf interprets the \033 escapes inside its format string.
	fmt.Fprint(os.Stderr, sh.EchoE(BLUE+BOLD)+"| "+ltPadBytes(sectionName, boxWidth)+" |"+sh.EchoE(NC)+"\n")
	fmt.Fprint(os.Stderr, ltEchoE(BLUE+BOLD+"+"+border+"+"+NC+`\n`))

	ltAppendLog(ltEchoE(`\n` + timestamp + " +" + border + "+"))
	ltAppendLog(timestamp + " | " + ltPadBytes(sectionName, boxWidth) + " |\n")
	ltAppendLog(ltEchoE(timestamp + " +" + border + "+" + `\n`))
}

// logSym implements the shared `local symbol=${1:-DEFAULT}; shift` prologue of
// info/success/warning/error/fatal: the FIRST argument is the symbol (so callers that
// pass a single string get it printed as the "symbol" with an empty message, exactly
// like bash). An empty first arg selects the default symbol.
func logSym(def string, args []string) (string, []string) {
	sym := ""
	if len(args) > 0 {
		sym = args[0]
		args = args[1:]
	}
	if sym == "" {
		sym = def
	}
	return sym, args
}

// info/success/warning/logError take bash's argument list verbatim: (symbol, msg...).
// NOTE: `error` is renamed logError because Go's predeclared `error` type would be
// shadowed package-wide. bash: scripts/logging.sh:108
func info(args ...string) {
	s, rest := logSym("", args)
	logMessage("INFO", LIGHTGRAY, s, rest...)
}

// bash: scripts/logging.sh:114
func success(args ...string) {
	s, rest := logSym(CHECKMARK, args)
	logMessage("SUCCESS", GREEN, s, rest...)
}

// bash: scripts/logging.sh:120
func warning(args ...string) {
	s, rest := logSym("", args)
	logMessage("WARNING", ORANGE, s, rest...)
}

// logError is bash `error`. bash: scripts/logging.sh:126
func logError(args ...string) {
	s, rest := logSym(CROSS, args)
	logMessage("ERROR", RED, s, rest...)
}

// fatal logs and exits 1 (sh.Exit unwinds and runs the EXIT trap). Do not use it where
// bash ran fatal inside $(...) (a subshell): use fatalSub there.
// bash: scripts/logging.sh:132
func fatal(args ...string) {
	fatalSub(args...)
	sh.Exit(1)
}

// fatalSub logs the FATAL line but does not exit (for emulating fatal inside a
// command-substitution subshell, where `exit 1` only ends the subshell).
// bash: scripts/logging.sh:132-136
func fatalSub(args ...string) {
	s, rest := logSym(CROSS, args)
	logMessage("FATAL", RED, s, rest...)
}

var bgPIDCounter int

// bgPID returns a stand-in for `$!` (the pid of the background job whose body the
// port ran synchronously). Only used in show_spinner's failure message.
func bgPID() int {
	bgPIDCounter++
	return os.Getpid() + bgPIDCounter
}

// showSpinner emulates `{ ...; } & show_spinner $!` where the background block has
// ALREADY been run synchronously by the caller and returned `status`. No frames are
// printed (their count is timing dependent and normalized by the harness); the final
// erase sequence and the failure path are reproduced. On failure it exits 1 like bash.
// Returns normally (bash status 0) on success.
// bash: scripts/logging.sh:140
func showSpinner(pid int, status int) {
	if status != 0 {
		fmt.Print(sh.EchoE(`    \b\b\b\b`)) // printf "    \b\b\b\b"
		logError(fmt.Sprintf("Background process (PID: %d) failed with exit code: %d", pid, status))
		logError("Check the log file for details: " + LOG_FILE)
		sh.Exit(1)
	}
	fmt.Print(sh.EchoE(`    \b\b\b\b`))
}
