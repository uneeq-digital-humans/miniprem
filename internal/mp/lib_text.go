package mp

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Shared helpers for the lib_*.go files (emulations of pure text tools and of tiny
// bash idioms). Names are prefixed lt to avoid clashing with other porters' helpers.

// ltEchoE returns the full output of bash `echo -e s` (newline included, unless the
// string contains an unescaped \c, which suppresses everything after it AND the
// trailing newline).
func ltEchoE(s string) string {
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			if s[i+1] == 'c' {
				return sh.EchoE(s)
			}
			i++
		}
	}
	return sh.EchoE(s) + "\n"
}

// ltLines splits command output into lines (no trailing newline expected); "" -> nil.
func ltLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(s, "\n"), "\n")
}

// ltCutField emulates `cut -d <delim> -f n` on one line: a line without the
// delimiter is printed whole.
func ltCutField(line string, delim string, n int) string {
	if !strings.Contains(line, delim) {
		return line
	}
	f := strings.Split(line, delim)
	if n-1 < len(f) {
		return f[n-1]
	}
	return ""
}

// ltCutLines applies ltCutField to every line of s and re-joins with newline.
func ltCutLines(lines []string, delim string, n int) []string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		out = append(out, ltCutField(l, delim, n))
	}
	return out
}

// ltAwkField emulates awk '{print $n}' (default FS) on one line.
func ltAwkField(line string, n int) string {
	f := strings.FieldsFunc(line, func(r rune) bool { return r == ' ' || r == '\t' })
	if n-1 < len(f) && n >= 1 {
		return f[n-1]
	}
	return ""
}

// ltAwkFieldLines applies ltAwkField to each line and joins with "\n" (awk prints an
// (empty) line for every input line).
func ltAwkFieldLines(lines []string, n int) string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		out = append(out, ltAwkField(l, n))
	}
	return strings.Join(out, "\n")
}

// ltXargs emulates `xargs` with no command (== echo of the whitespace/quote-split
// tokens). rc is 1 on unmatched quotes (message on stderr, no output).
func ltXargs(s string) (string, int) {
	var toks []string
	var cur strings.Builder
	have := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == ' ' || c == '\t' || c == '\n':
			if have {
				toks = append(toks, cur.String())
				cur.Reset()
				have = false
			}
		case c == '\\':
			have = true
			if i+1 < len(s) {
				i++
				cur.WriteByte(s[i])
			}
		case c == '\'' || c == '"':
			have = true
			q := c
			j := i + 1
			for j < len(s) && s[j] != q && s[j] != '\n' {
				cur.WriteByte(s[j])
				j++
			}
			if j >= len(s) || s[j] != q {
				kind := "single"
				if q == '"' {
					kind = "double"
				}
				fmt.Fprintf(os.Stderr, "xargs: unmatched %s quote; by default quotes are special to xargs unless you use the -0 option\n", kind)
				return "", 1
			}
			i = j
		default:
			have = true
			cur.WriteByte(c)
		}
	}
	if have {
		toks = append(toks, cur.String())
	}
	return strings.Join(toks, " "), 0
}

// ltBRE compiles a (simple) POSIX BRE as used by the scripts' grep calls: `.` any,
// `*` star, `[..]` bracket, ^/$ anchors; everything else literal.
func ltBRE(p string) *regexp.Regexp {
	var b strings.Builder
	for i := 0; i < len(p); i++ {
		c := p[i]
		switch {
		case c == '[':
			j := i + 1
			if j < len(p) && p[j] == '^' {
				j++
			}
			if j < len(p) && p[j] == ']' {
				j++
			}
			for j < len(p) && p[j] != ']' {
				j++
			}
			if j >= len(p) {
				b.WriteString(regexp.QuoteMeta(string(c)))
			} else {
				b.WriteString(p[i : j+1])
				i = j
			}
		case c == '.' || (c == '*' && i > 0):
			b.WriteByte(c)
		case c == '^' && i == 0:
			b.WriteByte(c)
		case c == '$' && i == len(p)-1:
			b.WriteByte(c)
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	re, err := regexp.Compile(b.String())
	if err != nil {
		return regexp.MustCompile(regexp.QuoteMeta(p))
	}
	return re
}

// ltGrepA emulates `grep -A n re` (context separators omitted; callers pipe on to a
// second grep that never matches them).
func ltGrepA(lines []string, re *regexp.Regexp, after int) []string {
	var out []string
	remain := 0
	for _, l := range lines {
		if re.MatchString(l) {
			remain = after
			out = append(out, l)
		} else if remain > 0 {
			remain--
			out = append(out, l)
		}
	}
	return out
}

func ltGrepSub(lines []string, sub string) []string {
	var out []string
	for _, l := range lines {
		if strings.Contains(l, sub) {
			out = append(out, l)
		}
	}
	return out
}

// ltHead emulates `head -n n` over lines.
func ltHead(lines []string, n int) []string {
	if len(lines) > n {
		return lines[:n]
	}
	return lines
}

// ltRemoveSpace emulates tr -d '[:space:]'.
func ltRemoveSpace(s string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\n', '\v', '\f', '\r':
			return -1
		}
		return r
	}, s)
}

// ltArithInt evaluates the simple operands the scripts feed to $(( )) / (( )):
// decimal integers; an identifier counts as an unset variable (0); empty is 0.
// ok is false for a syntax error.
func ltArithInt(s string) (n int, ok bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, true
	}
	if v, err := strconv.Atoi(s); err == nil {
		return v, true
	}
	if regexp.MustCompile(`^[A-Za-z_][A-Za-z_0-9]*$`).MatchString(s) {
		return 0, true
	}
	return 0, false
}

// ltBcTrue emulates `(( $(echo "<expr>" | bc -l) ))`: runs bc (traced) and treats its
// stdout as an arithmetic truth value. Empty/non-numeric output is false.
func ltBcTrue(expr string) bool {
	out, _ := sh.C("bc", "-l").In(expr + "\n").Output()
	n, ok := ltArithInt(out)
	return ok && n != 0
}

// ltTail emulates `tail -n n` of text.
func ltTail(text string, n int) string {
	if text == "" {
		return ""
	}
	endsNL := strings.HasSuffix(text, "\n")
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	r := strings.Join(lines, "\n")
	if endsNL {
		r += "\n"
	}
	return r
}

func ltIsFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

func ltIsDir(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// lookPath returns the PATH-resolved path of a command (`command -v name`).
func lookPath(name string) (string, bool) {
	p, err := exec.LookPath(name)
	return p, err == nil
}
