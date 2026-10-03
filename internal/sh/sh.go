// Package sh is the small runtime that lets the Go port reproduce the observable
// behaviour of the original bash scripts: external commands are always resolved via
// PATH (so the harness stubs and the customer's real tools behave identically), stdin
// is read unbuffered like bash `read`, and `exit` anywhere unwinds to Main and runs
// the EXIT traps.
package sh

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// DefaultIFS is bash's default field separator.
const DefaultIFS = " \t\n"

// IFS is the current field separator. install_miniprem.sh sets IFS=$'\n\t' globally,
// which changes `read` trimming and unquoted word splitting for it and every lib it
// sources; miniprem.sh and merge-compose.sh keep the default.
var IFS = DefaultIFS

type exitSignal struct{ code int }

var exitHooks []func(code int)

// Exit emulates bash `exit N` from any depth: it unwinds to Main, which runs the
// EXIT traps and returns the code. Do NOT call it from code that emulates a $(...)
// subshell; there `exit` only ends the subshell — return a status instead.
func Exit(code int) { panic(exitSignal{code}) }

// OnExit registers an EXIT trap. Like `trap '...' EXIT`, a later registration
// replaces the earlier one.
func OnExit(fn func(code int)) { exitHooks = []func(int){fn} }

// ClearExitTrap emulates `trap - EXIT`.
func ClearExitTrap() { exitHooks = nil }

// Main runs body with the given IFS, converts Exit panics into a status code, runs
// the EXIT trap, and returns the final status. Other panics are re-raised.
func Main(ifs string, body func()) (code int) {
	IFS = ifs
	code = run(body)
	if len(exitHooks) > 0 {
		hooks := exitHooks
		exitHooks = nil // a trap that calls exit must not re-run itself
		for _, h := range hooks {
			if c, exited := runHook(h, code); exited {
				code = c
			}
		}
	}
	return code
}

func run(body func()) (code int) {
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(exitSignal); ok {
				code = e.code
				return
			}
			panic(r)
		}
	}()
	body()
	return 0
}

func runHook(h func(int), code int) (c int, exited bool) {
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(exitSignal); ok {
				c, exited = e.code, true
				return
			}
			panic(r)
		}
	}()
	h(code)
	return 0, false
}

// Now returns the current time, or MINIPREM_FAKE_EPOCH (seconds, UTC) when set; the
// test harness sets it so log timestamps match the stubbed `date`.
func Now() time.Time {
	if v := os.Getenv("MINIPREM_FAKE_EPOCH"); v != "" {
		if s, err := strconv.ParseInt(v, 10, 64); err == nil {
			return time.Unix(s, 0).UTC()
		}
	}
	return time.Now()
}

// ---------------------------------------------------------------------------
// External commands

// Cmd describes one external command invocation. The zero values mean "inherit"
// (stdin/stdout/stderr) exactly as a plain bash command line would.
type Cmd struct {
	Name   string
	Args   []string
	Stdin  io.Reader // nil = inherit os.Stdin (e.g. `cmd <<< "$x"` -> strings.NewReader(x+"\n"))
	Stdout io.Writer // nil = inherit; use io.Discard for >/dev/null
	Stderr io.Writer // nil = inherit; use io.Discard for 2>/dev/null
	Dir    string
	Env    []string // extra VAR=value entries appended to the environment
}

// C builds a Cmd.
func C(name string, args ...string) *Cmd { return &Cmd{Name: name, Args: args} }

func (c *Cmd) In(s string) *Cmd          { c.Stdin = strings.NewReader(s); return c }
func (c *Cmd) Out(w io.Writer) *Cmd      { c.Stdout = w; return c }
func (c *Cmd) Err(w io.Writer) *Cmd      { c.Stderr = w; return c }
func (c *Cmd) Quiet() *Cmd               { c.Stdout, c.Stderr = io.Discard, io.Discard; return c } // &>/dev/null
func (c *Cmd) NoErr() *Cmd               { c.Stderr = io.Discard; return c }                       // 2>/dev/null
func (c *Cmd) InDir(d string) *Cmd       { c.Dir = d; return c }
func (c *Cmd) WithEnv(kv ...string) *Cmd { c.Env = append(c.Env, kv...); return c }

// Run executes the command and returns its exit status. A command that cannot be
// found returns 127 and prints bash's message ("<name>: command not found") to
// stderr, like bash does (minus bash's "script: line N:" prefix).
func (c *Cmd) Run() int {
	path, err := exec.LookPath(c.Name)
	if err != nil {
		w := c.Stderr
		if w == nil {
			w = os.Stderr
		}
		fmt.Fprintf(w, "%s: command not found\n", c.Name)
		return 127
	}
	cmd := exec.Command(path, c.Args...)
	cmd.Args[0] = c.Name
	cmd.Stdin = c.Stdin
	if cmd.Stdin == nil {
		cmd.Stdin = os.Stdin
	}
	cmd.Stdout = c.Stdout
	if cmd.Stdout == nil {
		cmd.Stdout = os.Stdout
	}
	cmd.Stderr = c.Stderr
	if cmd.Stderr == nil {
		cmd.Stderr = os.Stderr
	}
	cmd.Dir = c.Dir
	if len(c.Env) > 0 {
		cmd.Env = append(os.Environ(), c.Env...)
	}
	err = cmd.Run()
	if err == nil {
		return 0
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal())
		}
		return ee.ExitCode()
	}
	return 126
}

// Output emulates $(cmd): captures stdout with trailing newlines removed, returns
// the status. Stderr is inherited unless set.
func (c *Cmd) Output() (string, int) {
	var b bytes.Buffer
	c.Stdout = &b
	rc := c.Run()
	return strings.TrimRight(b.String(), "\n"), rc
}

// Combined emulates $(cmd 2>&1).
func (c *Cmd) Combined() (string, int) {
	var b bytes.Buffer
	c.Stdout, c.Stderr = &b, &b
	rc := c.Run()
	return strings.TrimRight(b.String(), "\n"), rc
}

// Run is shorthand for C(name, args...).Run().
func Run(name string, args ...string) int { return C(name, args...).Run() }

// Output is shorthand for C(name, args...).Output().
func Output(name string, args ...string) (string, int) { return C(name, args...).Output() }

// CommandExists emulates `command -v name >/dev/null` for external commands only.
// Callers must check bash builtins/functions themselves if the script relied on that.
func CommandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// ---------------------------------------------------------------------------
// Output helpers

// EchoE returns s with bash `echo -e` escapes interpreted (\n \t \\ \a \b \e \E \f
// \r \v \0nnn \033-style octal, \xHH). Text after \c is dropped.
func EchoE(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if ch != '\\' || i+1 >= len(s) {
			b.WriteByte(ch)
			continue
		}
		i++
		switch s[i] {
		case 'n':
			b.WriteByte('\n')
		case 't':
			b.WriteByte('\t')
		case '\\':
			b.WriteByte('\\')
		case 'a':
			b.WriteByte('\a')
		case 'b':
			b.WriteByte('\b')
		case 'e', 'E':
			b.WriteByte(0x1b)
		case 'f':
			b.WriteByte('\f')
		case 'r':
			b.WriteByte('\r')
		case 'v':
			b.WriteByte('\v')
		case 'c':
			return b.String()
		case '0': // \0nnn: up to 3 octal digits after the 0
			v, n := 0, 0
			for n < 3 && i+1 < len(s) && s[i+1] >= '0' && s[i+1] <= '7' {
				i++
				v = v*8 + int(s[i]-'0')
				n++
			}
			b.WriteByte(byte(v))
		case '1', '2', '3', '4', '5', '6', '7': // bash also accepts \nnn without the leading 0
			v, n := int(s[i]-'0'), 1
			for n < 3 && i+1 < len(s) && s[i+1] >= '0' && s[i+1] <= '7' {
				i++
				v = v*8 + int(s[i]-'0')
				n++
			}
			b.WriteByte(byte(v))
		case 'x':
			v, n := 0, 0
			for n < 2 && i+1 < len(s) && isHex(s[i+1]) {
				i++
				v = v*16 + hexVal(s[i])
				n++
			}
			if n == 0 {
				b.WriteString(`\x`)
			} else {
				b.WriteByte(byte(v))
			}
		default:
			b.WriteByte('\\')
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}
func hexVal(c byte) int {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0')
	case c >= 'a' && c <= 'f':
		return int(c-'a') + 10
	default:
		return int(c-'A') + 10
	}
}

// ---------------------------------------------------------------------------
// Input (bash `read`)

// IsTTY reports whether fd is a terminal (bash only prints `read -p` prompts then).
func IsTTY(fd uintptr) bool {
	var t syscall.Termios
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&t)))
	return e == 0
}

// ReadOpts mirrors the bash `read` flags the scripts use.
type ReadOpts struct {
	Prompt string // -p: written to stderr, only when stdin is a TTY
	Raw    bool   // -r: backslashes are literal
	Silent bool   // -s: no echo (only meaningful on a TTY)
}

// readByte reads exactly one byte from stdin so that child processes inherit the
// unread remainder, as with bash.
func readByte() (byte, error) {
	var b [1]byte
	for {
		n, err := os.Stdin.Read(b[:])
		if n == 1 {
			return b[0], nil
		}
		if err != nil {
			return 0, err
		}
	}
}

// ReadLine emulates `read [-r] [-s] [-p prompt] VAR` into ONE variable: reads up to
// newline, handles backslash escapes unless Raw, and trims leading/trailing IFS
// whitespace (only the whitespace characters present in the current IFS). ok is
// false when EOF was hit before a newline (bash returns status 1 but still assigns
// the partial line, which is returned).
func ReadLine(o ReadOpts) (line string, ok bool) {
	raw, ok := readRaw(o)
	return trimIFS(raw), ok
}

// ReadFields emulates `read [-r] -a ARR` / `read A B C`: the line split on IFS.
// For `read A B` with fewer names than fields, join the tail yourself with the
// original separators (rare in these scripts; check the call site).
func ReadFields(o ReadOpts) (fields []string, ok bool) {
	raw, ok := readRaw(o)
	return SplitIFS(raw), ok
}

func readRaw(o ReadOpts) (string, bool) {
	tty := IsTTY(0)
	if o.Prompt != "" && tty {
		fmt.Fprint(os.Stderr, o.Prompt)
	}
	var restore func()
	if o.Silent && tty {
		restore = noEcho()
	}
	var b []byte
	ok := true
	for {
		c, err := readByte()
		if err != nil {
			ok = false
			break
		}
		if c == '\n' {
			break
		}
		if c == '\\' && !o.Raw {
			n, err := readByte()
			if err != nil {
				ok = false
				break
			}
			if n == '\n' { // line continuation
				continue
			}
			b = append(b, n)
			continue
		}
		b = append(b, c)
	}
	if restore != nil {
		restore() // bash -s does not echo the newline either; scripts print their own
	}
	return string(b), ok
}

func noEcho() func() {
	var t syscall.Termios
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&t))); e != 0 {
		return func() {}
	}
	old := t
	t.Lflag &^= syscall.ECHO
	syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&t)))
	return func() {
		syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&old)))
	}
}

func ifsWhite() string {
	var w strings.Builder
	for _, c := range IFS {
		if c == ' ' || c == '\t' || c == '\n' {
			w.WriteRune(c)
		}
	}
	return w.String()
}

func trimIFS(s string) string { return strings.Trim(s, ifsWhite()) }

// SplitIFS emulates unquoted word splitting of a value with the current IFS
// (whitespace IFS chars collapse; empty fields from them are dropped). Non-whitespace
// IFS characters are not used by these scripts.
func SplitIFS(s string) []string {
	w := ifsWhite()
	return strings.FieldsFunc(s, func(r rune) bool { return strings.ContainsRune(w, r) })
}
