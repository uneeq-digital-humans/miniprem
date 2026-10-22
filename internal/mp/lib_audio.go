package mp

import (
	"fmt"
	"os"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/audio.sh. All functions are used as $(...) only, so they return the
// captured stdout (trailing newlines stripped).

// getDefaultSink: pactl info | grep 'Default Sink' | cut -d ' ' -f 3
// bash: scripts/audio.sh:6
func getDefaultSink() string {
	out, _ := sh.Output("pactl", "info")
	return strings.Join(ltCutLines(ltGrepSub(ltLines(out), "Default Sink"), " ", 3), "\n")
}

// ltPactlDescription: pactl list <what> | grep -A 20 "Name: $name" | grep 'Description'
// | cut -d ':' -f 2 | xargs
func ltPactlDescription(what, name string) string {
	out, _ := sh.Output("pactl", "list", what)
	g := ltGrepA(ltLines(out), ltBRE("Name: "+name), 20)
	g = ltGrepSub(g, "Description")
	res, _ := ltXargs(strings.Join(ltCutLines(g, ":", 2), "\n"))
	return res
}

// getSinkDescription. `$1` is referenced under set -u: with an empty (word-split away)
// argument bash aborts the substitution with "unbound variable".
// bash: scripts/audio.sh:11
func getSinkDescription(sink string) string {
	if sink == "" {
		fmt.Fprintf(os.Stderr, "scripts/audio.sh: $1: unbound variable\n")
		return ""
	}
	return ltPactlDescription("sinks", sink)
}

// bash: scripts/audio.sh:17
func getDefaultSource() string {
	out, _ := sh.Output("pactl", "info")
	return strings.Join(ltCutLines(ltGrepSub(ltLines(out), "Default Source"), " ", 3), "\n")
}

// bash: scripts/audio.sh:22
func getSourceDescription(source string) string {
	if source == "" {
		fmt.Fprintf(os.Stderr, "scripts/audio.sh: $1: unbound variable\n")
		return ""
	}
	return ltPactlDescription("sources", source)
}

// bash: scripts/audio.sh:28
func getAudioPlaybackDevice() string {
	sink := getDefaultSink()
	return getSinkDescription(sink)
}

// bash: scripts/audio.sh:33
func getAudioRecordingDevice() string {
	source := getDefaultSource()
	return getSourceDescription(source)
}
