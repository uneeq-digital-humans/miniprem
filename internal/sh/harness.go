package sh

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Sleep emulates `sleep`. Under the test harness (MINIPREM_FAKE_EPOCH set) it is a
// no-op, matching the stubbed sleep.
func Sleep(d time.Duration) {
	if os.Getenv("MINIPREM_FAKE_EPOCH") != "" {
		return
	}
	time.Sleep(d)
}

// MkTemp emulates `mktemp [template]` (files only) and returns the path.
// Without a template it creates $TMPDIR/tmp.XXXXXXXXXX like GNU mktemp. When
// MINIPREM_MKTEMP_COUNTER_FILE is set (test harness), the trailing X run is replaced
// by a zero-padded counter shared with the mktemp stub, so names are deterministic
// and identical across the bash and Go runs.
func MkTemp(template string) (string, error) { return mkTemp(template, false) }

// MkTempDir emulates `mktemp -d [template]` (mode 0700) with the same naming rules.
func MkTempDir(template string) (string, error) { return mkTemp(template, true) }

func mkTemp(template string, dir bool) (string, error) {
	if template == "" {
		dir := os.Getenv("TMPDIR")
		if dir == "" {
			dir = "/tmp"
		}
		template = filepath.Join(dir, "tmp.XXXXXXXXXX")
	}
	n := len(template) - len(strings.TrimRight(template, "X"))
	if n < 3 {
		return "", fmt.Errorf("mktemp: too few X's in template '%s'", template)
	}
	prefix := template[:len(template)-n]
	if cf := os.Getenv("MINIPREM_MKTEMP_COUNTER_FILE"); cf != "" {
		c := 0
		if b, err := os.ReadFile(cf); err == nil {
			c, _ = strconv.Atoi(strings.TrimSpace(string(b)))
		}
		c++
		if err := os.WriteFile(cf, []byte(strconv.Itoa(c)+"\n"), 0o644); err != nil {
			return "", err
		}
		p := fmt.Sprintf("%s%0*d", prefix, n, c)
		if dir {
			return p, os.Mkdir(p, 0o700)
		}
		f, err := os.OpenFile(p, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			return "", err
		}
		f.Close()
		return p, nil
	}
	if dir {
		return os.MkdirTemp(filepath.Dir(prefix), filepath.Base(prefix)+"*")
	}
	f, err := os.CreateTemp(filepath.Dir(prefix), filepath.Base(prefix)+"*")
	if err != nil {
		return "", err
	}
	f.Close()
	return f.Name(), nil
}

// OnSignal emulates `trap '<body>' INT|TERM`. When sig arrives, fn runs (it typically
// prints and calls Exit(130/143)); then the EXIT trap runs and the process exits with
// the code fn passed to Exit (0 if it returned normally; these scripts always exit in
// their signal traps).
func OnSignal(sig os.Signal, fn func()) {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, sig)
	go func() {
		<-ch
		code := run(fn)
		hooks := exitHooks
		exitHooks = nil
		for _, h := range hooks {
			if c, exited := runHook(h, code); exited {
				code = c
			}
		}
		os.Exit(code)
	}()
}
