package mp

import (
	"fmt"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/hash.sh.

var hashInited bool

// initHash runs hash.sh's top-level `log_script_hash`. Idempotent.
// bash: scripts/hash.sh:36
func initHash() {
	if hashInited {
		return
	}
	hashInited = true
	logScriptHash()
}

// computeHash is used only as $(compute_hash file): sha256sum "$file" | awk '{ print $1 }'
// bash: scripts/hash.sh:7
func computeHash(file string) string {
	out, _ := sh.Output("sha256sum", file)
	return ltAwkFieldLines(ltLines(out), 1)
}

// bash: scripts/hash.sh:13
func logScriptHash() {
	scriptPath := PROJECT_ROOT + "/docker/scripts/install_miniprem.sh"
	scriptHash := computeHash(scriptPath)
	otherFiles := []string{
		PROJECT_ROOT + "/scripts/audio.sh", PROJECT_ROOT + "/scripts/docker.sh", PROJECT_ROOT + "/scripts/logging.sh",
		PROJECT_ROOT + "/scripts/hash.sh", PROJECT_ROOT + "/scripts/environment.sh", PROJECT_ROOT + "/scripts/prerequisites.sh",
	}
	combined := scriptHash

	for _, file := range otherFiles {
		if ltIsFile(file) {
			// `local file_hash=$(...)` masks the status, so `$? -eq 0` is always true
			combined = combined + " " + computeHash(file)
		} else {
			fmt.Println("File " + file + " does not exist. Cannot compute hash.")
		}
	}

	out, _ := sh.C("sha256sum").In(combined).Output() // echo -n | sha256sum
	finalHash := ltAwkFieldLines(ltLines(out), 1)
	info("Combined script hash: " + finalHash)
}
