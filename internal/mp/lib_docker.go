package mp

import (
	"bytes"
	"fmt"
	"os"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/docker.sh (no top-level code).
//
// Background blocks `{ ...; } &` + show_spinner are run synchronously (PORTING.md).
// The block is a subshell that inherits `set -e` (the installer), so the first failing
// command ends the block with that command's status; blocks therefore stop at the
// first non-zero status (bgRunE).

// DOCKER_CMD / DOCKER_COMPOSE_CMD are first assigned inside docker.sh functions
// (docker.sh:122, 40-44).
var (
	DOCKER_CMD         string
	DOCKER_COMPOSE_CMD string
)

// bgRunE runs the steps of a `{ a; b; c; } &` block in order with errexit semantics
// and returns the block's exit status.
func bgRunE(steps ...func() int) int {
	rc := 0
	for _, st := range steps {
		if rc = st(); rc != 0 {
			return rc
		}
	}
	return rc
}

// sudoV is a bare `sudo -v` statement under `set -e`: a failure aborts the script.
func sudoV() {
	if rc := sh.Run("sudo", "-v"); rc != 0 {
		sh.Exit(rc)
	}
}

// commandExists is `command_exists` (install_miniprem.sh:160); defined here because the
// libs need it before the installer file exists. Dedupe at integration.
func commandExists(name string) bool { return sh.CommandExists(name) }

// dockerFields splits a command string like `eval $DOCKER_CMD ...` does (eval re-parses
// the joined words): on blanks.
func dockerFields(s string) []string { return strings.Fields(s) }

// getDockerCommand is used ONLY as $(get_docker_command): returns the captured stdout
// (stdout of `sudo -v`, which is normally empty, followed by "sudo docker"; trailing
// newlines stripped). The subshell has errexit off, so a failing `sudo -v` is ignored.
// bash: scripts/docker.sh:6
func getDockerCommand() string {
	var b bytes.Buffer
	sh.C("sudo", "-v").Out(&b).Run()
	b.WriteString("sudo docker\n")
	return strings.TrimRight(b.String(), "\n")
}

// pipeStatus: with pipefail the pipeline status is the last non-zero stage status.
func pipeStatus(rcs ...int) int {
	r := 0
	for _, c := range rcs {
		if c != 0 {
			r = c
		}
	}
	return r
}

// checkDockerInstalled. bash: scripts/docker.sh:13
func checkDockerInstalled() {
	if !commandExists("docker") {
		warning("Docker is not installed. Installing Docker...")
		sudoV()
		bg := bgPID()
		st := bgRunE(func() int {
			// curl https://get.docker.com | sh && sudo systemctl --now enable docker
			var b bytes.Buffer
			rc1 := sh.C("curl", "https://get.docker.com").Out(&b).Run()
			rc2 := sh.C("sh").Out(os.Stdout).In(b.String()).Run()
			if p := pipeStatus(rc1, rc2); p != 0 {
				return p
			}
			return sh.Run("sudo", "systemctl", "--now", "enable", "docker")
		})
		showSpinner(bg, st)
		success(CHECKMARK + " Docker & compose installed successfully.")
	}

	// docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
	out, rc := sh.Output("docker", "--version")
	if rc != 0 {
		sh.Exit(rc)
	}
	dockerVersion := ltSedFirstComma(ltAwkFieldLines(ltLines(out), 3))
	success(CHECKMARK + " Docker version: " + dockerVersion)

	if !commandExists("docker-compose") && sh.C("docker", "compose", "version").Quiet().Run() != 0 {
		fatal("docker-compose is not installed. Please install Docker Compose.")
		fatal("Visit https://docs.docker.com/compose/install/ for installation instructions.")
	}

	if commandExists("docker-compose") {
		DOCKER_COMPOSE_CMD = "docker-compose"
		out, rc := sh.Output("docker-compose", "--version")
		if rc != 0 {
			sh.Exit(rc)
		}
		composeVersion := ltSedFirstComma(ltAwkFieldLines(ltLines(out), 3))
		success(CHECKMARK + " Docker Compose (v1) version: " + composeVersion)
	} else {
		DOCKER_COMPOSE_CMD = "docker compose"
		out, rc := sh.Output("docker", "compose", "version")
		if rc != 0 {
			sh.Exit(rc)
		}
		composeVersion := ltAwkFieldLines(ltLines(out), 4)
		success(CHECKMARK + " Docker Compose (v2) version: " + composeVersion)
	}

	os.Setenv("DOCKER_COMPOSE_CMD", DOCKER_COMPOSE_CMD) // export DOCKER_COMPOSE_CMD
}

// ltSedFirstComma emulates sed 's/,//' per line.
func ltSedFirstComma(s string) string {
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		lines[i] = strings.Replace(l, ",", "", 1)
	}
	return strings.Join(lines, "\n")
}

// checkNvidiaToolkit. bash: scripts/docker.sh:53
func checkNvidiaToolkit() {
	st, _ := sh.C("dpkg-query", "-W", "-f=${Status}", "nvidia-container-toolkit").NoErr().Output()
	if !strings.Contains(st, "ok installed") {
		info("Nvidia Container Toolkit is not installed. Installing Nvidia Container Toolkit...")

		sudoV()

		aptEnv := []string{"DEBIAN_FRONTEND=noninteractive", "NEEDRESTART_MODE=a", "NEEDRESTART_SUSPEND=1"}

		// _nvtk_run: bash scripts/docker.sh:75
		nvtkRun := func(desc string, argv ...string) {
			info("  " + desc)
			f, err := os.OpenFile(LOG_FILE, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
			var rc int
			if err != nil {
				fmt.Fprintf(os.Stderr, "%s: Permission denied\n", LOG_FILE)
				rc = 1
			} else {
				rc = sh.C(argv[0], argv[1:]...).Out(f).Err(f).Run()
				f.Close()
			}
			if rc != 0 {
				logError("Step failed: " + desc)
				logError("Last 30 lines of " + LOG_FILE + ":")
				if b, e := os.ReadFile(LOG_FILE); e == nil {
					os.Stderr.WriteString(ltTail(string(b), 30))
				}
				fatal(CROSS + " Nvidia Container Toolkit install failed at: " + desc)
			}
		}

		if ltIsFile("/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg") {
			sh.Run("sudo", "rm", "-f", "/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg")
		}

		nvtkRun("Fetching NVIDIA Container Toolkit GPG key",
			"bash", "-c", "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \\\n                | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg")

		nvtkRun("Adding NVIDIA Container Toolkit apt source",
			"bash", "-c", "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \\\n                | sed \"s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g\" \\\n                | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list")

		nvtkRun("Running apt-get update",
			append(append([]string{"sudo"}, aptEnv...), "apt-get", "update")...)

		nvtkRun("Installing nvidia-container-toolkit (may take a minute)",
			append(append([]string{"sudo"}, aptEnv...), "apt-get", "install", "-y", "nvidia-container-toolkit")...)

		nvtkRun("Configuring Docker for NVIDIA runtime",
			"sudo", "nvidia-ctk", "runtime", "configure", "--runtime=docker")

		nvtkRun("Restarting Docker",
			"sudo", "systemctl", "restart", "docker")

		success(CHECKMARK + " Nvidia Docker runtime installed successfully.")
	}

	ver, rc := sh.Output("dpkg-query", "-W", "-f=${Version}", "nvidia-container-toolkit")
	if rc != 0 {
		sh.Exit(rc)
	}
	success(CHECKMARK + " Nvidia Container Toolkit version: " + ver)
}

// performNvidiaRuntimeTest. bash: scripts/docker.sh:119
func performNvidiaRuntimeTest() {
	info("Performing test to ensure Nvidia docker runtime is operational...")

	DOCKER_CMD = getDockerCommand()

	info("Pulling NVIDIA CUDA test image (if not already cached)...")

	// set +e ... set -e around the pull
	pullArgs := append(dockerFields(DOCKER_CMD), "pull", "nvidia/cuda:11.6.2-base-ubuntu20.04")
	pullOutput, pullExit := sh.C(pullArgs[0], pullArgs[1:]...).Combined()

	if pullExit != 0 {
		warning(fmt.Sprintf("Failed to pull NVIDIA CUDA test image (exit code: %d)", pullExit))
		info("Will attempt to use cached version. Pull output:")
		fmt.Println(strings.Join(ltHead(strings.Split(pullOutput, "\n"), 5), "\n")) // echo | head -5
	} else {
		success(CHECKMARK + " NVIDIA CUDA test image ready")
	}

	tempOutput, _ := sh.MkTemp("")

	bg := bgPID()
	st := bgRunE(func() int {
		// nvidia_smi_output=$(eval $DOCKER_CMD run ... 2>&1)  -- errexit: a failing
		// substitution assignment ends the subshell here with its status, so the
		// "exit_code -ne 0" branch of the bash source is unreachable (and tempOutput
		// stays behind, empty).
		runArgs := append(dockerFields(DOCKER_CMD), "run", "--rm", "--privileged", "--gpus", "all", "nvidia/cuda:11.6.2-base-ubuntu20.04", "nvidia-smi")
		out, rc := sh.C(runArgs[0], runArgs[1:]...).Combined()
		if rc != 0 {
			return rc
		}
		if !strings.Contains(out, "NVIDIA-SMI") {
			os.WriteFile(tempOutput, []byte("ERROR: nvidia-smi output does not contain expected 'NVIDIA-SMI' string\n"+"Output: "+out+"\n"), 0o644)
			return 1
		}
		os.Remove(tempOutput)
		return 0
	})
	showSpinner(bg, st)
	// spinner_exit is always 0 here: show_spinner exits the script on failure.

	os.Remove(tempOutput)
	success(CHECKMARK + " Nvidia runtime is working correctly.")
}

// checkDockerInstallation. bash: scripts/docker.sh:184
func checkDockerInstallation() {
	logSection("Docker Prerequisites")
	checkDockerInstalled()
	checkNvidiaToolkit()
	performNvidiaRuntimeTest()
}

// pullDockerImages: `$1` is only consulted when INSTALL_TYPE is empty (and unset $1
// under set -u aborts, like bash). bash: scripts/docker.sh:194
func pullDockerImages(args ...string) {
	logSection("Pulling Docker Images")

	currentDir, _ := os.Getwd()

	installType := INSTALL_TYPE
	if installType == "" {
		if len(args) == 0 {
			fmt.Fprintln(os.Stderr, "pull_docker_images: $1: unbound variable")
			sh.Exit(1)
		}
		installType = args[0]
	}
	var composeFile string
	if installType == "full" {
		composeFile = "-f " + currentDir + "/docker/docker-compose.full.yml"
	} else {
		composeFile = "-f " + currentDir + "/docker/docker-compose.yml"
	}

	DOCKER_CMD = getDockerCommand()

	if installType == "full" {
		info("Pulling public images (Grafana, Prometheus, Redis)...")
		bg := bgPID()
		pull := func(img string) func() int {
			return func() int {
				a := append(dockerFields(DOCKER_CMD), "pull", img)
				return sh.Run(a[0], a[1:]...)
			}
		}
		st := bgRunE(pull("grafana/grafana:latest"), pull("prom/prometheus:latest"), pull("redis:latest"))
		showSpinner(bg, st)
		success(CHECKMARK + " Public Docker images pulled successfully.")

		if TTS_PROVIDER == "rime" {
			info("Pulling RIME-specific images...")
		}
	} else {
		if TTS_PROVIDER == "rime" {
			info("Pulling RIME-specific images for default installation...")
		}
	}

	info("Testing connectivity to cr.uneeq.io...")
	if sh.C("curl", "--max-time", "10", "--silent", "--fail", "--output", "/dev/null", "https://cr.uneeq.io").NoErr().Run() != 0 {
		warning("Cannot reach cr.uneeq.io")
		warning("Please ensure:")
		warning("  1. You have internet connectivity")
		warning("  2. Your firewall allows HTTPS to cr.uneeq.io (port 443)")
		warning("  3. Corporate networks: cr.uneeq.io is whitelisted")
		fatal("Network connectivity test failed")
	}
	success(CHECKMARK + " Network connectivity to Harbor verified")

	if ensureHarborCredentials() != 0 {
		fmt.Println("")
		logError("ERROR: Harbor Registry Authentication Failed")
		fmt.Println("")
		logError("Unable to authenticate with cr.uneeq.io using the provided credentials.")
		fmt.Println("")
		logError("Common causes:")
		logError("  • Invalid robot account username or password")
		logError("  • Robot account has been disabled or expired")
		logError("  • Robot account lacks required permissions")
		fmt.Println("")
		fatal("Please contact UneeQ Support for further assistance.")
	}

	info("Pulling Docker images for selected install type...")
	bg := bgPID()
	st := bgRunE(func() int {
		// cd $current_dir; eval $DOCKER_CMD compose $compose_file pull  (cd is local to the subshell)
		a := append(dockerFields(DOCKER_CMD), "compose")
		a = append(a, dockerFields(composeFile)...)
		a = append(a, "pull")
		return sh.C(a[0], a[1:]...).InDir(currentDir).Run()
	})
	showSpinner(bg, st)
	success(CHECKMARK + " Docker images pulled successfully for selected install type.")
}

// startDockerCompose: composeFile "" selects the default (`${1:-"-f docker/docker-compose.yml"}`).
// bash: scripts/docker.sh:281
func startDockerCompose(composeFile string) {
	logSection("Starting Docker Compose Services")
	DOCKER_CMD = getDockerCommand()
	if composeFile == "" {
		composeFile = "-f docker/docker-compose.yml"
	}
	info("Starting Docker Compose services...")
	a := append(dockerFields(DOCKER_CMD), "compose")
	a = append(a, dockerFields(composeFile)...)
	a = append(a, "up", "-d")
	if sh.Run(a[0], a[1:]...) != 0 {
		fatal(CROSS + " Failed to start Docker Compose services.")
	}
	success(CHECKMARK + " Docker Compose services started successfully.")
}

// stopDockerCompose. bash: scripts/docker.sh:293
func stopDockerCompose(composeFile string) {
	logSection("Stopping Docker Compose Services")
	DOCKER_CMD = getDockerCommand()
	if composeFile == "" {
		composeFile = "-f docker/docker-compose.yml"
	}
	info("Stopping Docker Compose services...")
	a := append(dockerFields(DOCKER_CMD), "compose")
	a = append(a, dockerFields(composeFile)...)
	a = append(a, "down")
	if sh.Run(a[0], a[1:]...) != 0 {
		fatal(CROSS + " Failed to stop Docker Compose services.")
	}
	success(CHECKMARK + " Docker Compose services stopped successfully.")
}

// ltInstallTypeFromMarker: install_type=$(cat "$PROJECT_ROOT/.miniprem_install_type" 2>/dev/null || echo "default")
func ltInstallTypeFromMarker() string {
	b, err := os.ReadFile(PROJECT_ROOT + "/.miniprem_install_type")
	if err != nil {
		return "default"
	}
	return strings.TrimRight(string(b), "\n")
}

// updateDockerComposeImage (no callers in the two entry scripts). fatal exits.
// bash: scripts/docker.sh:305
func updateDockerComposeImage(imageName string) {
	installType := ltInstallTypeFromMarker()
	composeFile := "docker/docker-compose.yml"
	if installType == "full" {
		composeFile = "docker/docker-compose.full.yml"
	}
	if ltIsFile(composeFile) {
		if sh.Run("yq", "eval", ".services.renny.image = \""+imageName+"\"", "-i", composeFile) == 0 {
			success(CHECKMARK + " Updated Docker image in " + composeFile + " to " + imageName)
		} else {
			fatal(CROSS + " Failed to update Docker image in " + composeFile)
		}
	} else {
		fatal(CROSS + " Docker compose file " + composeFile + " not found.")
	}
}

// readDockerComposeValue is used ONLY as $(read_docker_compose_value key): returns the
// captured stdout. `fatal` inside the substitution ends only the subshell, so it logs
// (fatalSub) and yields "". bash: scripts/docker.sh:326
func readDockerComposeValue(key string) string {
	installType := ltInstallTypeFromMarker()
	composeFile := PROJECT_ROOT + "/docker/docker-compose.yml"
	if installType == "full" {
		composeFile = PROJECT_ROOT + "/docker/docker-compose.full.yml"
	}
	if ltIsFile(composeFile) {
		out, _ := sh.Output("yq", "eval", ".services.renny."+key, composeFile)
		return out
	}
	warning("Docker compose file " + composeFile + " not found. Trying fallback options.")
	composeFile = PROJECT_ROOT + "/docker/docker-compose.miniprem.services.yml"
	if ltIsFile(composeFile) {
		out, _ := sh.Output("yq", "eval", ".services.renny."+key, composeFile)
		return out
	}
	fatalSub(CROSS + " No valid Docker compose file found.")
	return ""
}
