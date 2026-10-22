package mp

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of miniprem.sh (the day-2 management CLI). Every helper/global that is local
// to this entry is prefixed `cli` so it cannot collide with inst_*.go.

// cliScript0 is bash's $0 for miniprem.sh (the shim sets MINIPREM_SCRIPT_PATH).
var cliScript0 string

// cliComposeFile is COMPOSE_FILE (miniprem.sh:220/222); expanded unquoted -> split on
// blanks by dockerFields at every use.
var cliComposeFile string

// cliConfigFilesToPreserve is CONFIG_FILES_TO_PRESERVE. bash: miniprem.sh:401
var cliConfigFilesToPreserve = []string{
	"docker/configuration.dat",
	".env",
	"docker/.env",
	"docker/docker-compose.custom.yml",
	".miniprem_install_type",
	"kubernetes/scripts/cns/.cns_config",
	"kubernetes/values/renny-values-cns.yaml",
	"kubernetes/terraform/eks/terraform.tfvars",
	"kubernetes/terraform/aks/terraform.tfvars",
	"kubernetes/terraform/gke/terraform.tfvars",
}

// cliExec emulates bash `exec cmd args...` (replaces the process; no EXIT trap, no
// return on success). A failure exits like a non-interactive bash (126/127).
func cliExec(name string, args ...string) {
	path, err := exec.LookPath(name)
	if err != nil {
		if strings.Contains(name, "/") {
			if _, serr := os.Stat(name); serr == nil {
				fmt.Fprintf(os.Stderr, "exec: %s: cannot execute: Permission denied\n", name)
				sh.Exit(126)
			}
		}
		fmt.Fprintf(os.Stderr, "exec: %s: not found\n", name)
		sh.Exit(127)
	}
	argv := append([]string{name}, args...)
	err = syscall.Exec(path, argv, os.Environ())
	fmt.Fprintf(os.Stderr, "exec: %s: cannot execute: %v\n", name, err)
	sh.Exit(126)
}

// cliArith emulates bash arithmetic on a [0-9]+ string (leading 0 = octal).
func cliArith(s string) (int, bool) {
	v, err := strconv.ParseInt(s, 0, 64)
	if err != nil {
		return 0, false
	}
	return int(v), true
}

func cliEcho(s string) { fmt.Fprintln(os.Stdout, s) }

// cliEchoE is `echo -e "$s"`.
func cliEchoE(s string) { fmt.Fprint(os.Stdout, ltEchoE(s)) }

// cliChdirScriptDir emulates `cd "$(dirname "$0")"; PROJECT_ROOT=$(pwd)` with bash's
// logical (lexical) pwd. bash: miniprem.sh:4-7
func cliChdirScriptDir() bool {
	cliScript0 = os.Getenv("MINIPREM_SCRIPT_PATH")
	if cliScript0 == "" {
		exe, err := os.Executable()
		if err != nil {
			exe = os.Args[0]
		}
		// shim fallback: the binary lives in <repo>/bin or similar; use ../ of it.
		cliScript0 = filepath.Join(filepath.Dir(filepath.Dir(exe)), "miniprem.sh")
	}
	dir := filepath.Dir(cliScript0)
	target := dir
	if !filepath.IsAbs(dir) {
		base := os.Getenv("PWD")
		if base == "" || !filepath.IsAbs(base) {
			base, _ = os.Getwd()
		}
		target = filepath.Join(base, dir)
	}
	target = filepath.Clean(target)
	if err := os.Chdir(target); err != nil {
		return false
	}
	PROJECT_ROOT = target
	os.Setenv("PWD", target)
	return true
}

// cliCatTrim emulates $(cat file) (trailing newlines stripped).
func cliCatTrim(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(b), "\n")
}

// MiniPremMain is miniprem.sh. bash: miniprem.sh:1-961
func MiniPremMain(args []string) {
	arg := func(i int) string { // $1.. (unset == empty; nothing relies on the difference)
		if i-1 < len(args) {
			return args[i-1]
		}
		return ""
	}

	// bash: miniprem.sh:4
	if !cliChdirScriptDir() {
		cliEcho("Failed to change directory to script location")
		sh.Exit(1)
	}

	cliCNSDetectAndRoute(args)

	// Docker mode. bash: miniprem.sh:207-209 (source logging, docker, environment)
	initLogging()

	// bash: miniprem.sh:212-223
	if ltIsFile(".miniprem_install_type") {
		INSTALL_TYPE = cliCatTrim(".miniprem_install_type")
	} else {
		INSTALL_TYPE = "default"
	}
	if INSTALL_TYPE == "default" {
		cliComposeFile = "-f " + PROJECT_ROOT + "/docker/docker-compose.yml"
	} else {
		cliComposeFile = "-f " + PROJECT_ROOT + "/docker/docker-compose.full.yml"
	}

	// bash: miniprem.sh:864-866
	if arg(1) == "" {
		cliUsage()
	}

	rc := 0
	switch arg(1) {
	case "start":
		rc = cliStartServices()
	case "stop":
		rc = cliStopServices()
	case "restart":
		rc = cliRestartServices()
	case "status":
		rc = cliCheckStatus()
	case "logs":
		rc = cliViewLogs()
	case "setup":
		rc = cliSetupFlowise()
	case "upgrade", "update":
		rc = cliUpgradeServices()
	case "pull":
		rc = cliPullUpdates(arg(2))
	case "validate":
		rc = cliValidateCustomServices()
	case "config":
		rc = cliShowConfig(arg(2))
	case "custom":
		switch arg(2) {
		case "list":
			rc = cliListCustomServices()
		case "add":
			rc = cliAddCustomService(arg(3))
		default:
			logError("Unknown custom command: " + arg(2))
			cliEcho("")
			cliEcho("Usage: " + cliScript0 + " custom [list|add]")
			cliEcho("")
			cliEcho("  list       - List all custom services")
			cliEcho("  add [name] - Add a new custom service")
			sh.Exit(1)
		}
	case "deploy":
		rc = cliDeploy()
	case "-h", "--help":
		cliUsage()
	default:
		logError("Unknown command: " + arg(1))
		cliEcho("")
		cliUsage()
	}
	// The script's exit status is the status of the last command executed.
	if rc != 0 {
		sh.Exit(rc)
	}
}

// cliCNSDetectAndRoute is miniprem.sh:12-200 (CNS detection + routing; exec seams).
func cliCNSDetectAndRoute(args []string) {
	arg := func(i int) string {
		if i-1 < len(args) {
			return args[i-1]
		}
		return ""
	}
	rest := func() []string {
		if len(args) > 1 {
			return args[1:]
		}
		return nil
	}

	cnsConfigFile := PROJECT_ROOT + "/kubernetes/scripts/cns/.cns_config"
	cnsInstalled := false
	if ltIsFile(cnsConfigFile) {
		cnsInstalled = true
	}
	hasMicrok8s := sh.CommandExists("microk8s")
	if hasMicrok8s {
		if sh.C("microk8s", "kubectl", "get", "deployment", "renny", "-n", "uneeq").Quiet().Run() == 0 {
			cnsInstalled = true
		}
	}
	if !cnsInstalled {
		return
	}

	if hasMicrok8s {
		if sh.C("microk8s", "status").Quiet().Run() != 0 {
			cliEcho("")
			cliEcho("⚠️  MicroK8s permission denied.")
			cliEcho("")
			cliEcho("You need to run this command with sudo OR be in the microk8s group:")
			cliEcho("")
			cliEcho("  Option 1: Run with sudo")
			cliEcho("    sudo ./miniprem.sh " + arg(1))
			cliEcho("")
			cliEcho("  Option 2: Add yourself to microk8s group (recommended)")
			cliEcho("    sudo usermod -a -G microk8s $USER")
			cliEcho("    newgrp microk8s  # Or logout and login again")
			cliEcho("")
			sh.Exit(1)
		}
	}
	cnsDir := PROJECT_ROOT + "/kubernetes/scripts/cns"

	switch arg(1) {
	case "start":
		cliExec(cnsDir+"/restart.sh", rest()...)
	case "stop":
		cliExec(cnsDir+"/stop.sh", rest()...)
	case "restart":
		sh.Run(cnsDir + "/stop.sh")
		cliExec(cnsDir+"/restart.sh", rest()...)
	case "status":
		cliExec(cnsDir+"/status.sh", rest()...)
	case "scale":
		cliExec(cnsDir+"/sizer.sh", "--apply")
	case "scale-quick":
		cliExec(cnsDir+"/scale.sh", rest()...)
	case "sizer":
		cliExec(cnsDir+"/sizer.sh", rest()...)
	case "logs":
		cliCNSLogs(arg(2))
	case "deploy":
		cliExec(cnsDir+"/deploy-local.sh", rest()...)
	case "upgrade", "update":
		cliExec(cnsDir+"/upgrade.sh", rest()...)
	case "destroy":
		cliExec(cnsDir+"/destroy.sh", rest()...)
	case "-h", "--help", "help":
		for _, l := range []string{
			"",
			"MiniPrem CNS (Kubernetes) Management",
			"",
			"CNS installation detected. Available commands:",
			"",
			"  start       - Start the CNS deployment (scale up Renny pods)",
			"  stop        - Stop the CNS deployment (scale down to 0)",
			"  restart     - Restart the CNS deployment",
			"  status      - Check CNS deployment status",
			"  logs [N|all]- View Renny pod logs (select pod or 'all')",
			"",
			"Configuration & Scaling:",
			"  upgrade             - Interactive upgrade menu",
			"  upgrade --full      - Full upgrade (git + helm + new Renny)",
			"  upgrade --config-only - Just apply values file changes",
			"  upgrade --restart   - Just restart pods",
			"  scale             - Interactive scaling with GPU config",
			"  scale-quick N     - Quick scale to N replicas",
			"  sizer             - GPU capacity calculator",
			"",
			"Deployment:",
			"  deploy      - Run full CNS deployment (interactive)",
			"  destroy     - Destroy CNS deployment",
			"",
			"Examples:",
			"  ./miniprem.sh upgrade             # Apply renny-values-cns.yaml changes",
			"  ./miniprem.sh upgrade --replicas 3 # Change replica count",
			"  ./miniprem.sh upgrade --clear-secrets # Clear TTS/LLM secrets",
			"  ./miniprem.sh scale               # Interactive GPU-aware scaling",
			"",
			"CNS Configuration: " + cnsConfigFile,
			"",
		} {
			cliEcho(l)
		}
		sh.Exit(0)
	default:
		for _, l := range []string{
			"MiniPrem CNS installation detected.",
			"Run './miniprem.sh --help' for available commands.",
			"",
			"Quick commands:",
			"  ./miniprem.sh status   - Check deployment status",
			"  ./miniprem.sh upgrade  - Full upgrade (git + helm + image)",
			"  ./miniprem.sh scale    - Scale Renny (with GPU config)",
			"  ./miniprem.sh logs     - View Renny logs",
		} {
			cliEcho(l)
		}
		sh.Exit(0)
	}
}

// cliCNSLogs is the `logs)` branch of the CNS router. bash: miniprem.sh:78-143
func cliCNSLogs(podArg string) {
	var kubectl []string
	if sh.CommandExists("microk8s") {
		kubectl = []string{"microk8s", "kubectl"}
	} else {
		kubectl = []string{"kubectl"}
	}
	kc := func(extra ...string) *sh.Cmd {
		a := append(append([]string{}, kubectl[1:]...), extra...)
		return sh.C(kubectl[0], a...)
	}
	kexec := func(extra ...string) {
		a := append(append([]string{}, kubectl[1:]...), extra...)
		cliExec(kubectl[0], a...)
	}

	out, _ := kc("get", "pods", "-n", "uneeq", "-l", "app=renny", "-o", "jsonpath={.items[*].metadata.name}").NoErr().Output()
	pods := sh.SplitIFS(out)

	if len(pods) == 0 {
		cliEcho("No Renny pods found in uneeq namespace")
		sh.Exit(1)
	}

	if podArg == "all" {
		maxReq := strconv.Itoa(len(pods) * 3)
		cliEcho(fmt.Sprintf("Following logs from ALL %d Renny pods (Ctrl+C to stop)...", len(pods)))
		kexec("logs", "-f", "-l", "app=renny", "-n", "uneeq", "--all-containers=true", "--max-log-requests="+maxReq)
	}

	if podArg != "" {
		if cliAllDigits(podArg) {
			n, _ := cliArith(podArg)
			idx := n - 1
			if idx >= 0 && idx < len(pods) {
				kexec("logs", "-f", pods[idx], "-n", "uneeq", "--all-containers=true")
			} else {
				cliEcho(fmt.Sprintf("Invalid pod number: %s (have %d pods)", podArg, len(pods)))
				sh.Exit(1)
			}
		} else {
			kexec("logs", "-f", podArg, "-n", "uneeq", "--all-containers=true")
		}
	}

	cliEcho("")
	cliEcho("Select a Renny pod to view logs:")
	cliEcho("")
	for i, p := range pods {
		status, _ := kc("get", "pod", p, "-n", "uneeq", "-o", "jsonpath={.status.phase}").NoErr().Output()
		fmt.Printf("  %d) %s (%s)\n", i+1, p, status)
	}
	cliEcho("")
	cliEcho("  all) Follow ALL pods")
	cliEcho("")
	selection, _ := sh.ReadLine(sh.ReadOpts{Prompt: fmt.Sprintf("Enter selection [1-%d or 'all']: ", len(pods))})

	if selection == "all" {
		maxReq := strconv.Itoa(len(pods) * 3)
		kexec("logs", "-f", "-l", "app=renny", "-n", "uneeq", "--all-containers=true", "--max-log-requests="+maxReq)
	} else if n, ok := cliArith(selection); cliAllDigits(selection) && ok && n >= 1 && n <= len(pods) {
		kexec("logs", "-f", pods[n-1], "-n", "uneeq", "--all-containers=true")
	} else {
		cliEcho("Invalid selection")
		sh.Exit(1)
	}
}

var cliDigitsRe = regexp.MustCompile(`^[0-9]+$`)

func cliAllDigits(s string) bool { return cliDigitsRe.MatchString(s) }

// cliUsage is usage(). Never returns (exit 1). bash: miniprem.sh:226
func cliUsage() {
	cliEcho("") // echo -e $WHITE  (WHITE is never defined)
	fmt.Print("" + cliBasename(cliScript0) + ` [start|stop|status|restart|logs|upgrade|deploy|setup|pull|validate|config|custom]
Control the MiniPrem services

Commands:
    start:              Start the MiniPrem services
    stop:               Stop the MiniPrem services
    status:             Check the status of the MiniPrem services
    restart:            Restart the MiniPrem services
    logs:               View the logs of the MiniPrem services
    upgrade:            Full upgrade (git pull + renny-latest pull + rebuild)
    deploy:             Install MiniPrem (choose Docker or NVIDIA CNS)
    setup:              Run the Flowise chatflow setup (Docker only)
    pull [--regenerate]: Pull latest code from git only (no docker pull)
    validate:           Validate custom services configuration
    config [--custom]:  Show final merged Docker Compose config
    custom list:        List all custom services
    custom add [name]:  Add a new custom service interactively

Upgrade:
    The 'upgrade' command performs a complete MiniPrem update:
    1. Backs up your config files (credentials, terraform vars, etc.)
    2. Pulls latest code from git
    3. Restores your config files
    4. Pulls latest Renny image from Harbor
    5. Rebuilds MiniPrem Monitor locally

    After upgrade, run './miniprem.sh restart' to apply changes.

Options:
    -h, --help: Show this usage information
`)
	cliEchoE(NC)
	sh.Exit(1)
}

// cliBasename is `basename`: strips trailing slashes, then the directory part.
func cliBasename(p string) string {
	p = strings.TrimRight(p, "/")
	if p == "" {
		return "/"
	}
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}
