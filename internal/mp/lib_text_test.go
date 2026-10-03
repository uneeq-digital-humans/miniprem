package mp

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestLtXargs(t *testing.T) {
	cases := map[string]string{
		"  Built-in Audio   Analog Stereo ": "Built-in Audio Analog Stereo",
		"a 'b c' \"d e\" f\\ g":             "a b c d e f g",
		"":                                  "",
	}
	for in, want := range cases {
		got, rc := ltXargs(in)
		if rc != 0 || got != want {
			t.Errorf("ltXargs(%q) = %q,%d want %q", in, got, rc, want)
		}
	}
	if _, rc := ltXargs("it's"); rc != 1 {
		t.Errorf("unmatched quote should fail")
	}
}

func TestLtCutAwk(t *testing.T) {
	if g := ltCutField("Default Sink: alsa_out", " ", 3); g != "alsa_out" {
		t.Error(g)
	}
	if g := ltCutField("nodelim", ",", 2); g != "nodelim" {
		t.Error(g)
	}
	if g := ltCutField("a,b", ",", 3); g != "" {
		t.Error(g)
	}
	if g := ltAwkField("  Mem:  128000   5 ", 2); g != "128000" {
		t.Error(g)
	}
}

func TestLtGrepA(t *testing.T) {
	lines := strings.Split("x\nName: a\n1\n2\nName: b\n3", "\n")
	got := ltGrepA(lines, ltBRE("Name: a"), 2)
	if strings.Join(got, ",") != "Name: a,1,2" {
		t.Error(got)
	}
}

func TestLtTail(t *testing.T) {
	if g := ltTail("a\nb\nc\n", 2); g != "b\nc\n" {
		t.Errorf("%q", g)
	}
	if g := ltTail("a\nb", 5); g != "a\nb" {
		t.Errorf("%q", g)
	}
}

// bashHas reports whether bash is usable for the differential tests below.
func bashHas(t *testing.T) string {
	p, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	return p
}

func scriptsDir(t *testing.T) string {
	d, _ := filepath.Abs("../../scripts")
	if _, err := os.Stat(d + "/environment.sh"); err != nil {
		t.Skip("scripts dir not found")
	}
	return d
}

// Differential check of update_env_variable / read_env_variable against the real bash.
func TestEnvVariableAgainstBash(t *testing.T) {
	bash := bashHas(t)
	sd := scriptsDir(t)
	initials := []string{"", "A=1", "A=1\n", "A=1\nB=\"two\"\n", "A=1\nB=2", "X=\"v\"\nX=\"w\"\n"}
	sets := [][2]string{{"B", "new"}, {"B", "robot$cust"}, {"B", "a&b"}, {"B", `back\slash`}, {"C", "x$$y"}, {"A", "\"q\""}, {"B", `a\&b`}}
	for _, init := range initials {
		for _, kv := range sets {
			root := t.TempDir()
			os.MkdirAll(root+"/docker", 0o755)
			bf := root + "/docker/docker-compose.env"
			os.WriteFile(bf, []byte(init), 0o644)
			cmd := exec.Command(bash, "-c", `PROJECT_ROOT="$1"; source "$2/environment.sh"; update_env_variable "$3" "$4"`, "x", root, sd, kv[0], kv[1])
			cmd.Run()
			want, _ := os.ReadFile(bf)

			root2 := t.TempDir()
			os.MkdirAll(root2+"/docker", 0o755)
			gf := root2 + "/docker/docker-compose.env"
			os.WriteFile(gf, []byte(init), 0o644)
			PROJECT_ROOT = root2
			updateEnvVariable(kv[0], kv[1])
			got, _ := os.ReadFile(gf)
			if string(got) != string(want) {
				t.Errorf("init=%q set=%q: got %q want %q", init, kv, got, want)
			}

			// read_env_variable
			out, _ := exec.Command(bash, "-c", `PROJECT_ROOT="$1"; source "$2/environment.sh"; read_env_variable "$3"`, "x", root, sd, kv[0]).Output()
			if g := readEnvVariable(kv[0]); g != strings.TrimRight(string(out), "\n") {
				t.Errorf("read %q: got %q want %q", kv[0], g, out)
			}
		}
	}
}

var tsRe = regexp.MustCompile(`[0-9]{4}-[0-9]{2}-[0-9]{2}[ _][0-9]{2}[-:][0-9]{2}[-:][0-9]{2}`)

// Differential check of the console and file output of the logging functions.
func TestLoggingAgainstBash(t *testing.T) {
	bash := bashHas(t)
	sd := scriptsDir(t)
	script := `source "$1/logging.sh"
info "plain msg"
info "" "sym" "two" "words"
success "ok done"
warning "tab\\there" "x"
logfn() { error "e1"; }; logfn
log_section "Docker Prerequisites"
log_section "Ünïcode ✓"
(fatal "boom") || true
`
	run := func(dir string) (string, string) {
		cmd := exec.Command(bash, "-c", script, "x", sd)
		cmd.Dir = dir
		var se strings.Builder
		cmd.Stderr = &se
		cmd.Run()
		b, _ := os.ReadFile(dir + "/install_miniprem.log")
		return se.String(), string(b)
	}
	bdir := t.TempDir()
	wantErr, wantLog := run(bdir)

	gdir := t.TempDir()
	old, _ := os.Getwd()
	os.Chdir(gdir)
	defer os.Chdir(old)
	r, w, _ := os.Pipe()
	oe := os.Stderr
	os.Stderr = w
	loggingInited = false
	initLogging()
	info("plain msg")
	info("", "sym", "two", "words")
	success("ok done")
	warning(`tab\there`, "x")
	logError("e1")
	logSection("Docker Prerequisites")
	logSection("Ünïcode ✓")
	fatalSub("boom")
	w.Close()
	os.Stderr = oe
	var sb strings.Builder
	buf := make([]byte, 4096)
	for {
		n, err := r.Read(buf)
		sb.Write(buf[:n])
		if err != nil {
			break
		}
	}
	gotLog, _ := os.ReadFile(gdir + "/install_miniprem.log")
	if sb.String() != wantErr {
		t.Errorf("stderr mismatch:\n got %q\nwant %q", sb.String(), wantErr)
	}
	if tsRe.ReplaceAllString(string(gotLog), "TS") != tsRe.ReplaceAllString(wantLog, "TS") {
		t.Errorf("logfile mismatch:\n got %q\nwant %q", gotLog, wantLog)
	}
}
