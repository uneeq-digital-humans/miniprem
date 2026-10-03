package mp

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/prerequisites.sh. All check_* functions are plain top-level statements
// of the installer, i.e. run under `set -euo pipefail`: unchecked failing commands /
// pipelines abort with their status (sh.Exit(rc)); `fatal` exits 1.

// Requirement thresholds. bash: scripts/prerequisites.sh:22-49
var (
	MIN_GPU_MEMORY                  = 6000
	MIN_NVIDIA_DRIVER_VERSION       = 580
	SUPPORTED_NVIDIA_DRIVER_VERSION = "580.82.09"
	MIN_CUDA_VERSION                = "12.0"
	MIN_CPU_CORES                   = 8
	MIN_RAM                         = 6000
	MIN_FREE_SSD_SPACE              = 64
	MIN_UBUNTU_VERSION              = "24.04"
	MIN_KERNEL_VERSION              = "5.15"
	MIN_CHROME_MAJOR_VERSION        = "124"
)

// Globals that bash functions leave behind (assigned without `local`).
var (
	driver_version string // check_driver_prerequisites
	cuda_version   string
)

var prerequisitesInited bool

// initPrerequisites: prerequisites.sh has no executable top-level code beyond the
// variable assignments above. Idempotent no-op kept for symmetry.
func initPrerequisites() { prerequisitesInited = true }

// validateDockerDaemon: always returns 0 (fatal exits on failure).
// bash: scripts/prerequisites.sh:8
func validateDockerDaemon() int {
	logSection("Docker Daemon Validation")

	if sh.C("timeout", "5", "sudo", "docker", "info").Quiet().Run() != 0 {
		fatal(CROSS + " Docker daemon is not running or unreachable (timeout after 5 seconds)")
		fatal("Try starting Docker: sudo service docker start")
		return 1
	}

	success(CHECKMARK + " Docker daemon is running and responsive")
	return 0
}

var cudaVersionRe = regexp.MustCompile(`CUDA Version: ([0-9.]+)`)
var leadDigitsRe = regexp.MustCompile(`([0-9]+).*`)

// logWarn: `log_warn` is not defined anywhere in the scripts, so bash prints
// "log_warn: command not found" (status 127) and, under errexit, aborts. Reproduced by
// invoking the (nonexistent) command.
func logWarn(msg string) {
	if rc := sh.C("log_warn", msg).Run(); rc != 0 {
		sh.Exit(rc)
	}
}

// checkDriverPrerequisites. bash: scripts/prerequisites.sh:51
func checkDriverPrerequisites() {
	logSection("Nvidia Driver Prerequisites")

	if !commandExists("nvidia-smi") {
		fatal("Nvidia drivers are not installed. Please install Nvidia drivers and try again.")
	} else {
		out, rc := sh.C("timeout", "5", "nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader,nounits").NoErr().Output()
		driver_version = out
		if rc != 0 {
			logWarn("Could not query NVIDIA driver (GPU may be unavailable)")
			return
		}
		// cuda_version=$(timeout 5 nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9.]+' || echo "")
		smi, _ := sh.C("timeout", "5", "nvidia-smi").NoErr().Output()
		var found []string
		for _, l := range ltLines(smi) {
			for _, m := range cudaVersionRe.FindAllStringSubmatch(l, -1) {
				found = append(found, m[1])
			}
		}
		cuda_version = strings.Join(found, "\n")

		if driver_version == "" {
			logWarn("Could not determine NVIDIA driver version")
			return
		}

		// major_version=$(echo "$driver_version" | sed -E 's/([0-9]+).*/\1/')
		var mv []string
		for _, l := range strings.Split(driver_version, "\n") {
			mv = append(mv, leadDigitsRe.ReplaceAllString(l, "$1"))
		}
		majorVersion := strings.Join(mv, "\n")

		if !regexp.MustCompile(`^[0-9]+$`).MatchString(majorVersion) {
			logWarn("Could not parse NVIDIA driver version: " + driver_version)
			return
		}

		major, _ := strconv.Atoi(majorVersion)
		if major < MIN_NVIDIA_DRIVER_VERSION {
			fatal(fmt.Sprintf("%s Nvidia driver version is less than %d. Please install Nvidia driver version %d or higher.", CROSS, MIN_NVIDIA_DRIVER_VERSION, MIN_NVIDIA_DRIVER_VERSION))
		} else {
			success(CHECKMARK + " Nvidia driver version " + driver_version + " is sufficient.")
		}

		if driver_version != SUPPORTED_NVIDIA_DRIVER_VERSION {
			warning("Nvidia driver " + driver_version + " detected. MiniPrem only supports " + SUPPORTED_NVIDIA_DRIVER_VERSION + ".")
		}

		if ltBcTrue(cuda_version + " < " + MIN_CUDA_VERSION) {
			fatal(CROSS + " CUDA version is less than " + MIN_CUDA_VERSION + ". Please install CUDA version " + MIN_CUDA_VERSION + " or higher.")
		} else {
			success(CHECKMARK + " CUDA version " + cuda_version + " is sufficient.")
		}
	}
}

// commandExistsAndWorks: status 0 when `cmd --version` succeeds. bash: scripts/prerequisites.sh:104
func commandExistsAndWorks(cmd string) int {
	if commandExists(cmd) {
		return sh.C(cmd, "--version").Quiet().Run()
	}
	return 1
}

// aptInstallBlock is the `{ sudo apt-get update >/dev/null 2>&1; sudo apt-get install -y X
// >/dev/null 2>&1; } &` + show_spinner pattern.
func aptInstallBlock(pkg string) {
	bg := bgPID()
	st := bgRunE(
		func() int { return sh.C("sudo", "apt-get", "update").Quiet().Run() },
		func() int { return sh.C("sudo", "apt-get", "install", "-y", pkg).Quiet().Run() },
	)
	showSpinner(bg, st)
}

// checkInstallerPrequisites (sic). bash: scripts/prerequisites.sh:115
func checkInstallerPrequisites() {
	logSection("Software Prerequisites")

	if !commandExists("jq") {
		info("jq is not installed. Installing jq...")
		sudoV()
		aptInstallBlock("jq")
		success(CHECKMARK + " jq installed successfully.")
	}

	if !commandExists("snap") {
		info("snap is not installed. Installing snap...")
		sudoV()
		bg := bgPID()
		st := bgRunE(
			func() int { return sh.Run("sudo", "apt", "update") },
			func() int { return sh.Run("sudo", "apt", "install", "-y", "snapd") },
			func() int { return sh.Run("sudo", "systemctl", "enable", "--now", "snapd") },
		)
		showSpinner(bg, st)
		success(CHECKMARK + " snap installed successfully.")
	}

	ensureYqBinary()
	yqv, _ := sh.C("yq", "--version").Combined()
	success(CHECKMARK + " yq ready: " + yqv)

	success(CHECKMARK + " installer software prerequisites are met.")
}

// ensureYqBinary. bash: scripts/prerequisites.sh:171
func ensureYqBinary() {
	if commandExists("yq") {
		p, _ := lookPath("yq")
		resolved, rc := sh.C("readlink", "-f", p).NoErr().Output()
		if rc != 0 {
			resolved = ""
		}
		switch {
		case strings.HasPrefix(resolved, "/snap/"):
			warning("yq is currently snap-installed (" + resolved + ").")
			warning("Snap confinement under sudo blocks /home access — installing static binary to shadow it.")
		case resolved == "":
			info("yq present but path could not be resolved; reinstalling as static binary.")
		default:
			return
		}
	}

	var arch string
	m, _ := sh.Output("uname", "-m")
	switch m {
	case "x86_64":
		arch = "amd64"
	case "aarch64", "arm64":
		arch = "arm64"
	default:
		m2, _ := sh.Output("uname", "-m")
		fatal("Unsupported architecture for yq install: " + m2)
	}

	url := "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_" + arch
	target := "/usr/local/bin/yq"
	info("Installing yq (static binary) from " + url + " to " + target + "...")

	sudoV()
	bg := bgPID()
	st := bgRunE(func() int {
		if rc := sh.Run("sudo", "curl", "-fsSL", url, "-o", target); rc != 0 {
			return rc
		}
		return sh.Run("sudo", "chmod", "+x", target)
	})
	showSpinner(bg, st)

	if syscall.Access(target, 1) != nil { // [ ! -x "$target" ]
		fatal("Failed to install yq from " + url)
	}

	success(CHECKMARK + " yq installed at " + target)
}

// checkSoftwarePrequisites (sic). bash: scripts/prerequisites.sh:220
func checkSoftwarePrequisites() {
	logSection("Software Prerequisites")

	osVersion, rc := sh.Output("lsb_release", "-rs")
	if rc != 0 {
		sh.Exit(rc)
	}
	notUbuntu := func() bool { o, _ := sh.Output("lsb_release", "-is"); return o != "Ubuntu" }
	if notUbuntu() || ltBcTrue(osVersion+" < "+MIN_UBUNTU_VERSION) {
		fatal(CROSS + " OS is not Ubuntu or version is less than " + MIN_UBUNTU_VERSION + ". Please use Ubuntu version " + MIN_UBUNTU_VERSION + " or higher.")
	} else {
		success(CHECKMARK + " OS is Ubuntu and version " + osVersion + " is sufficient.")
	}

	// kernel_version=$(uname -r | cut -d '-' -f 1 | awk -F. '{print $1"."$2}')
	kr, rc := sh.Output("uname", "-r")
	if rc != 0 {
		sh.Exit(rc)
	}
	var kv []string
	for _, l := range ltLines(kr) {
		f := strings.Split(ltCutField(l, "-", 1), ".")
		a, b := "", ""
		a = f[0]
		if len(f) > 1 {
			b = f[1]
		}
		kv = append(kv, a+"."+b)
	}
	kernelVersion := strings.Join(kv, "\n")
	if ltBcTrue(kernelVersion + " < " + MIN_KERNEL_VERSION) {
		fatal(CROSS + " Kernel version is less than " + MIN_KERNEL_VERSION + ". Please use kernel version " + MIN_KERNEL_VERSION + " or higher.")
	} else {
		success(CHECKMARK + " Kernel version " + kernelVersion + " is sufficient.")
	}

	if !commandExists("google-chrome") {
		fatal(CROSS + " Google Chrome is not installed. Please install Google Chrome and try again.")
	} else {
		cv, rc := sh.Output("google-chrome", "--version")
		if rc != 0 {
			sh.Exit(rc)
		}
		chromeVersion := strings.Join(ltCutLines(ltCutLines(ltLines(cv), " ", 3), ".", 1), "\n")
		// (( $chrome_version < $MIN_CHROME_MAJOR_VERSION )): empty -> syntax error -> false
		less := false
		if n, ok := ltArithInt(chromeVersion); ok && strings.TrimSpace(chromeVersion) != "" {
			min, _ := strconv.Atoi(MIN_CHROME_MAJOR_VERSION)
			less = n < min
		}
		if less {
			fatal(CROSS + " Google Chrome version is less than " + MIN_CHROME_MAJOR_VERSION + ". Please install Google Chrome version " + MIN_CHROME_MAJOR_VERSION + " or higher.")
		} else {
			success(CHECKMARK + " Google Chrome version " + chromeVersion + " is sufficient.")
		}
	}

	if !commandExists("pactl") {
		info("pactl is not installed. This is required for audio checks. Installing pulseaudio-utils...")
		sudoV()
		aptInstallBlock("pulseaudio-utils")
		success(CHECKMARK + " pactl installed successfully.")
	}

	if !commandExists("curl") {
		info("curl is not installed. Installing curl...")
		sudoV()
		aptInstallBlock("curl")
		success(CHECKMARK + " curl installed successfully.")
	}

	if !commandExists("socat") {
		info("socat is not installed. Installing socat...")
		sudoV()
		aptInstallBlock("socat")
		success(CHECKMARK + " socat installed successfully.")
	}
}

// ltArithOperand evaluates a variable used in `$(( ))`; a syntax error aborts the script.
func ltArithOperand(s string) int {
	n, ok := ltArithInt(s)
	if !ok {
		fmt.Fprintf(os.Stderr, "%s: syntax error: operand expected (error token is \"%s\")\n", s, s)
		sh.Exit(1)
	}
	return n
}

// checkHardwarePrerequisites. bash: scripts/prerequisites.sh:302
func checkHardwarePrerequisites() {
	logSection("Hardware Prerequisites")

	if !commandExists("nvidia-smi") {
		fatal(CROSS + " Nvidia GPU is not available. Please install Nvidia GPU and try again")
	} else {
		// gpu_count=$(nvidia-smi ... | head -1)
		gc, rc := sh.Output("nvidia-smi", "--query-gpu=count", "--format=csv,noheader,nounits")
		if rc != 0 {
			sh.Exit(rc)
		}
		gpuCount := strings.Join(ltHead(ltLines(gc), 1), "\n")
		info(`\tDetected ` + gpuCount + ` GPU(s)`)

		gpuModels, rc := sh.Output("nvidia-smi", "--query-gpu=name", "--format=csv,noheader,nounits")
		if rc != 0 {
			sh.Exit(rc)
		}
		gpuMemoryInfo, rc := sh.Output("nvidia-smi", "--query-gpu=memory.total,memory.used", "--format=csv,noheader,nounits")
		if rc != 0 {
			sh.Exit(rc)
		}

		gpuIndex := 0
		sufficientGPUFound := false

		// while read memory_line && read model_line <&3 ... <<< "$gpu_memory_info" 3<<< "$gpu_models"
		// (a here-string of "" still yields one empty line)
		memLines := strings.Split(gpuMemoryInfo, "\n")
		modelLines := strings.Split(gpuModels, "\n")
		for i := 0; i < len(memLines) && i < len(modelLines); i++ {
			memoryLine, modelLine := memLines[i], modelLines[i]
			gpuIndex++

			totalS, _ := ltXargs(ltCutField(memoryLine, ",", 1))
			usedS, _ := ltXargs(ltCutField(memoryLine, ",", 2))
			totalMemory, usedMemory := ltArithOperand(totalS), ltArithOperand(usedS)
			freeMemory := totalMemory - usedMemory

			info(fmt.Sprintf(`\tGPU %d: %s`, gpuIndex, modelLine))
			info(fmt.Sprintf(`\t  Total: %s MB, Used: %s MB, Free: %d MB`, totalS, usedS, freeMemory))

			if freeMemory >= MIN_GPU_MEMORY {
				success(fmt.Sprintf("%s GPU %d has sufficient free memory (%d MB >= %d MB)", CHECKMARK, gpuIndex, freeMemory, MIN_GPU_MEMORY))
				sufficientGPUFound = true
			} else {
				warning(fmt.Sprintf("GPU %d does not have sufficient free memory (%d MB < %d MB)", gpuIndex, freeMemory, MIN_GPU_MEMORY))
			}
		}

		if !sufficientGPUFound {
			fatal(fmt.Sprintf("%s No GPU found with at least %d MB of free memory. Please free up GPU memory or use a system with more GPU resources.", CROSS, MIN_GPU_MEMORY))
		}
	}

	numCoresS, rc := sh.Output("nproc")
	if rc != 0 {
		sh.Exit(rc)
	}
	// cpu_model=$(lscpu | grep 'Model name' | cut -d ':' -f 2 | xargs)   (pipefail)
	lscpu, rcL := sh.Output("lscpu")
	g := ltGrepSub(ltLines(lscpu), "Model name")
	rcG := 1
	if len(g) > 0 {
		rcG = 0
	}
	cpuModel, rcX := ltXargs(strings.Join(ltCutLines(g, ":", 2), "\n"))
	if p := pipeStatus(rcL, rcG, 0, rcX); p != 0 {
		sh.Exit(p)
	}
	info(`\tCPU Model: ` + cpuModel)
	// [ $num_cores -lt $MIN_CPU_CORES ]: a non-integer operand makes `[` fail (status 2) -> else branch
	if n, err := strconv.Atoi(numCoresS); err == nil && n < MIN_CPU_CORES {
		fatal(fmt.Sprintf("%s Number of CPU cores is less than %d. Please use a system with at least %d CPU cores.", CROSS, MIN_CPU_CORES, MIN_CPU_CORES))
	} else {
		success(fmt.Sprintf("%s Number of CPU cores is sufficient. Total cores: %s", CHECKMARK, numCoresS))
	}

	// total_ram=$(free -m | grep Mem | awk '{print $2}')   (pipefail)
	fr, rcF := sh.Output("free", "-m")
	gm := ltGrepSub(ltLines(fr), "Mem")
	rcGM := 1
	if len(gm) > 0 {
		rcGM = 0
	}
	if p := pipeStatus(rcF, rcGM, 0); p != 0 {
		sh.Exit(p)
	}
	totalRAM := ltAwkFieldLines(gm, 2)
	if n, err := strconv.Atoi(totalRAM); err == nil && n < MIN_RAM {
		fatal(fmt.Sprintf("%s Total RAM is less than %d MB. Please use a system with at least %d MB of RAM.", CROSS, MIN_RAM, MIN_RAM))
	} else {
		success(fmt.Sprintf("%s Total RAM is sufficient. Total RAM: %s MB", CHECKMARK, totalRAM))
	}

	// free_space=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')   (pipefail)
	df, rcD := sh.Output("df", "-BG", "/")
	if rcD != 0 {
		sh.Exit(rcD)
	}
	dl := ltLines(df)
	last := []string{}
	if len(dl) > 0 {
		last = dl[len(dl)-1:]
	}
	freeSpace := strings.Replace(ltAwkFieldLines(last, 4), "G", "", 1)
	if n, err := strconv.Atoi(freeSpace); err == nil && n < MIN_FREE_SSD_SPACE {
		fatal(fmt.Sprintf("%s Free SSD space is less than %d GB. Please ensure at least %d GB of free SSD space.", CROSS, MIN_FREE_SSD_SPACE, MIN_FREE_SSD_SPACE))
	} else {
		success(fmt.Sprintf("%s Free SSD space is sufficient. Free space: %s GB", CHECKMARK, freeSpace))
	}

	playbackDevice := getAudioPlaybackDevice()
	recordingDevice := getAudioRecordingDevice()

	info(`\tDefault Speaker: ` + playbackDevice)
	info(`\tDefault Microphone: ` + recordingDevice)
}
