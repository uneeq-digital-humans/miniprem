package mp

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of docker/scripts/install_miniprem.sh: entry, option parsing and main().
// The installer runs under `set -euo pipefail`; every unconditional call site below models
// errexit explicitly (see PORTING.md). Other areas: inst_env.go, inst_tts.go,
// inst_docker.go, inst_services.go; byte-exact text blocks: inst_text.go.

// Globals of install_miniprem.sh (bash: install_miniprem.sh:43-46 and function-less assignments).
var (
	CLEANUP_NEEDED          bool     // bash: install_miniprem.sh:43
	CONTAINERS_STARTED      []string // bash: install_miniprem.sh:44
	INSTALLATION_START_TIME int64    // bash: install_miniprem.sh:46 (date +%s)
	SCRIPT_DIR              string   // bash: install_miniprem.sh:26
	OPTIONS                 string   // bash: install_miniprem.sh:2472 (getopt output)
	COMPOSE_FILES           string   // bash: install_miniprem.sh:2581/2583

	// instSttChoice is main()'s `local stt_choice`, read by start_miniprem through bash's
	// dynamic scoping (install_miniprem.sh:1504).
	instSttChoice string

	// instLineno stands in for $LINENO in the EXIT trap (bash: install_miniprem.sh:112). It is
	// only a best effort: set at the errexit abort sites below; fatal() (exit 1 at
	// scripts/logging.sh:136) sets 136.
	instLineno int

	// instScript0 is $0 (the path the shim was invoked as).
	instScript0 string
)

// instLoopMu serialises the infinite `usage` loop (install_miniprem.sh:2697) with the
// SIGINT/SIGTERM traps so nothing is printed after the trap's output.
var instLoopMu sync.Mutex

// instAbort models a failing command at an errexit-active call site: the script exits
// with the command's status (EXIT trap runs).
func instAbort(rc, line int) {
	if rc != 0 {
		instLineno = line
		sh.Exit(rc)
	}
}

// instFatal is fatal() with the $LINENO side effect (scripts/logging.sh:136 `exit 1`).
func instFatal(args ...string) {
	instLineno = 136
	fatal(args...)
}

// instUnbound models bash's fatal "unbound variable" error under `set -u` (status 1).
func instUnbound(name string, line int) {
	fmt.Fprintf(os.Stderr, "%s: line %d: %s: unbound variable\n", instScript0, line, name)
	instLineno = line
	sh.Exit(1)
}

// instCanonicalVars are the install variables the bash script would inherit from the
// environment (they are plain globals there).
var instCanonicalVars = []string{
	"INSTALL_TYPE", "INSTALL_AS_SERVICE", "DEPLOYMENT_TARGET", "UNEEQ_REGION", "TTS_PROVIDER",
	"AZURE_REGION", "AZURE_SPEECH_KEY", "ELEVEN_LABS_API_KEY", "RIME_API_KEY", "RIME_QUAY_PASSWORD",
	"PLATFORM_ADDRESS", "PLATFORM_KEY", "TENANT_ID", "RENNY_IMAGE", "TELEMETRY_CONSENT",
	"STT_PROVIDER", "CUSTOM_SERVICES_CHOICE", "CUSTOM_SERVICES_FILE_SEED", "ALLINONE",
	"NGC_API_KEY", "GEMMA_MODEL", "GEMMA_BACKEND", "KIOSK_STT_PROVIDER", "KIOSK_BRAND", "RAG_ADMIN_KEY",
}

// cleanupOnError is the EXIT trap. bash: install_miniprem.sh:49
// ($LINENO / $BASH_COMMAND: see instLineno; `history` is empty in a non-interactive shell.)
func cleanupOnError(exitCode int) {
	if exitCode != 0 && CLEANUP_NEEDED {
		fmt.Println("")
		fmt.Println("============================================")
		fmt.Println("Installation failed! Running cleanup...")
		fmt.Printf("Exit code: %d\n", exitCode)
		fmt.Printf("Failure location: Line %d\n", instLineno)

		// `if [ -n "$BASH_COMMAND" ]`: inside the trap BASH_COMMAND is the echo itself.
		fmt.Println(`Last command: echo "Last command: $BASH_COMMAND"`)

		fmt.Println("Recent commands:")
		fmt.Println("============================================")
		fmt.Println("")

		if len(CONTAINERS_STARTED) > 0 {
			fmt.Println("Stopping partially started containers...")
			for _, container := range CONTAINERS_STARTED {
				if sh.C("docker", "ps", "-q", "-f", "name="+container).Quiet().Run() == 0 {
					fmt.Println("  Stopping " + container + "...")
					sh.C("docker", "stop", container).Quiet().Run()
				}
			}
		}

		fmt.Println("")
		fmt.Println("============================================")
		fmt.Println("Cleanup completed. System restored to pre-installation state.")
		fmt.Println("")
		fmt.Println("Troubleshooting information:")
		fmt.Printf("  - Exit code: %d\n", exitCode)
		fmt.Printf("  - Failed at line: %d\n", instLineno)
		fmt.Println("  - Check logs: docker logs <container_name>")
		fmt.Println("")
		fmt.Println("Common issues and solutions:")
		fmt.Println("  1. Docker not running: Start Docker Desktop and retry")
		fmt.Println("  2. Insufficient disk space: Free up space and retry")
		fmt.Println("  3. Port conflicts: Check if ports are in use with 'netstat -an | grep LISTEN'")
		fmt.Println("  4. Permission issues: Ensure user is in 'docker' group")
		fmt.Println("  5. Network issues: Check internet connectivity and firewall settings")
		fmt.Println("")
		fmt.Println("For detailed logs, check: docker logs <container_name>")
		fmt.Println("============================================")
	}

	// Always restore terminal state
	sh.C("stty", "sane").NoErr().Run()
}

// enableCleanup. bash: install_miniprem.sh:119
func enableCleanup() { CLEANUP_NEEDED = true }

// registerContainer. bash: install_miniprem.sh:124
func registerContainer(containerName string) {
	CONTAINERS_STARTED = append(CONTAINERS_STARTED, containerName)
}

// instUsage is usage(). bash: install_miniprem.sh:134
func instUsage() {
	os.Stdout.WriteString(instUsageString())
}

func instUsageString() string {
	return strings.Replace(instUsageText, "@BASENAME@", instBasename0(), 1)
}

// instBasename0 is `$(basename "$0")`.
func instBasename0() string {
	return filepath.Base(instScript0)
}

// printLogo. bash: install_miniprem.sh:1781
func printLogo() {
	fmt.Println("")
	instPrintEcho(instLogoLines, "")
}

// instPrintEcho prints a list of `echo`/`echo -e` statements.
func instPrintEcho(lines []instEcho, root string) {
	for _, l := range lines {
		s := strings.ReplaceAll(l.s, "@ROOT@", root)
		if l.e {
			fmt.Print(ltEchoE(s))
		} else {
			fmt.Println(s)
		}
	}
}

// instScriptPath resolves $0 as MINIPREM_SCRIPT_PATH (set by the shim).
func instScriptPath() string {
	if p := os.Getenv("MINIPREM_SCRIPT_PATH"); p != "" {
		return p
	}
	cwd, _ := os.Getwd()
	return cwd + "/docker/scripts/install_miniprem.sh"
}

// InstallMain is the whole of install_miniprem.sh (top-level code + main "$@").
// bash: docker/scripts/install_miniprem.sh:1-3, 8-47, 111-116, 2911
func InstallMain(args []string) {
	instScript0 = instScriptPath()

	// Ensure script is run from MiniPrem root directory (check BEFORE anything else).
	// bash: install_miniprem.sh:9-23
	if !ltIsFile("miniprem.sh") || !ltIsDir("docker") || !ltIsDir("kubernetes") {
		instPrintEcho(instCwdGuardTop, "")
		cwd, _ := os.Getwd()
		fmt.Println("Current location: " + cwd)
		instPrintEcho(instCwdGuardBottom, "")
		sh.Exit(1)
	}

	// bash: install_miniprem.sh:26-27 (`cd` is logical, so ".." is textual)
	scriptDir := filepath.Dir(instScript0)
	if !filepath.IsAbs(scriptDir) {
		cwd, _ := os.Getwd()
		scriptDir = filepath.Join(cwd, scriptDir)
	}
	SCRIPT_DIR = filepath.Clean(scriptDir)
	PROJECT_ROOT = filepath.Clean(SCRIPT_DIR + "/../..")

	// Variables bash would inherit from the environment.
	for _, n := range instCanonicalVars {
		if v, ok := os.LookupEnv(n); ok {
			if p := seedGlobalPtr(n); p != nil {
				*p = v
			}
		}
	}

	// source docker, logging, audio, hash, environment, seed, prompts, prerequisites, allinone
	// bash: install_miniprem.sh:29-37
	initLogging()
	initHash()
	initSeed()
	initPrerequisites()
	initAllinone()

	// bash: install_miniprem.sh:43-46
	CLEANUP_NEEDED = false
	CONTAINERS_STARTED = nil
	INSTALLATION_MARKER_CREATED = false
	INSTALLATION_START_TIME = sh.Now().Unix()

	// bash: install_miniprem.sh:112-116
	sh.OnExit(func(code int) { cleanupOnError(code) })
	sh.OnSignal(os.Interrupt, func() {
		instLoopMu.Lock()
		fmt.Println("")
		fmt.Println("Installation cancelled by user (SIGINT)")
		sh.Exit(130)
	})
	sh.OnSignal(syscall.SIGTERM, func() {
		instLoopMu.Lock()
		fmt.Println("")
		fmt.Println("Installation terminated (SIGTERM)")
		sh.Exit(143)
	})

	instMain(args)
}

// instGetoptLong is the --long list of the getopt call. bash: install_miniprem.sh:2472
const instGetoptLong = "help,platform-address:,platform-key:,tenant-id:,tts-address:,tts-key:,azure-region:,azure-speech-key:,renny-image:,deployment-target:,region:,seed:,non-interactive,interactive,force"

// instShellSplit parses a string like `eval set -- "$OPTIONS"` does (getopt output is
// single-quoted).
func instShellSplit(s string) []string {
	var out []string
	var cur strings.Builder
	have := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == ' ' || c == '\t' || c == '\n':
			if have {
				out = append(out, cur.String())
				cur.Reset()
				have = false
			}
		case c == '\'':
			have = true
			j := strings.IndexByte(s[i+1:], '\'')
			if j < 0 {
				cur.WriteString(s[i+1:])
				i = len(s)
			} else {
				cur.WriteString(s[i+1 : i+1+j])
				i = i + 1 + j
			}
		case c == '"':
			have = true
			i++
			for i < len(s) && s[i] != '"' {
				if s[i] == '\\' && i+1 < len(s) && strings.IndexByte("$`\"\\\n", s[i+1]) >= 0 {
					i++
				}
				cur.WriteByte(s[i])
				i++
			}
		case c == '\\':
			have = true
			if i+1 < len(s) {
				i++
				cur.WriteByte(s[i])
			}
		default:
			have = true
			cur.WriteByte(c)
		}
	}
	if have {
		out = append(out, cur.String())
	}
	return out
}

var instDeployTargetRe = regexp.MustCompile(`^(hardware|cloud)$`)

// instMain is main(). bash: install_miniprem.sh:2470
func instMain(args []string) {
	// Parse command line arguments using getopt (before any interactive prompts)
	gargs := append([]string{"-o", "", "--long", instGetoptLong, "--"}, args...)
	out, rc := sh.C("getopt", gargs...).Output()
	instAbort(rc, 2472) // OPTIONS=$(getopt ...) under set -e (the `if [ $? -ne 0 ]` is dead)
	OPTIONS = out

	// Handle --help early before any system checks or prompts
	if strings.Contains(OPTIONS, "--help") {
		printLogo()
		instUsage()
		sh.Exit(0)
	}

	// Early scan for seed-mode flags so they take effect before any prompts.
	earlyArgs := args
	earlySeedFile := os.Getenv("MINIPREM_SEED_FILE")
	for i := 0; i < len(earlyArgs); i++ {
		switch earlyArgs[i] {
		case "--seed":
			earlySeedFile = ""
			if i+1 < len(earlyArgs) {
				earlySeedFile = earlyArgs[i+1]
			}
		case "--non-interactive":
			INTERACTIVE_MODE = "no"
		case "--interactive":
			INTERACTIVE_MODE = "yes"
		case "--force":
			FORCE_CONFIRMATIONS = "yes"
		}
	}

	if earlySeedFile != "" {
		seedLoadFile(earlySeedFile)
		for i := 0; i < len(earlyArgs); i++ {
			if earlyArgs[i] == "--interactive" {
				INTERACTIVE_MODE = "yes"
				break
			}
		}
		seedApplyToVars()
	}

	// NVIDIA all-in-one (Kubernetes) path
	if ltOr(ALLINONE, "no") == "yes" {
		printLogo()
		info("MINIPREM_SEED_ALLINONE=yes — deploying the NVIDIA all-in-one stack (Kubernetes).")
		instAbort(maybeDeployAllinone(), 2528)
		seedCheckRequired() // surface NGC_API_KEY/etc. if the deploy recorded any
		sh.Exit(0)
	}

	printLogo()

	if seedIsNonInteractive() {
		suffix := ""
		if SEED_FILE != "" {
			suffix = " (seed: " + SEED_FILE + ")"
		}
		info("Running in non-interactive mode" + suffix)
	}

	// Install type
	promptForInstallType()

	// Optional: install as systemd service so MiniPrem auto-starts at boot
	promptForAutostart()

	checkEnvironment()

	checkDuplicateInstallations()

	// Telemetry consent dialog (BEFORE installation starts)
	promptForTelemetryConsent()

	// Validate system resources before proceeding
	validateSystemResources()

	// Ensure docker-compose.env exists
	ensureEnvFileExists()

	// Full installs run Flowise, which needs generated secrets and admin credentials
	if INSTALL_TYPE == "full" {
		ensureFlowiseEnvExists()
	}

	// If a seed provided Harbor credentials, write them into docker-compose.env
	seedApplyHarborCreds()

	// Select TTS provider before configuring
	selectTtsProvider()

	// set -u: TTS_PROVIDER is never assigned when non-interactive without a seed.
	if TTS_PROVIDER == "" && SEED_LOADED != "yes" {
		if _, ok := os.LookupEnv("TTS_PROVIDER"); !ok {
			instUnbound("TTS_PROVIDER", 2571)
		}
	}

	// Configure TTS provider based on selection
	if TTS_PROVIDER == "azure" {
		configureAzureTts()
	} else if TTS_PROVIDER == "elevenlabs" {
		configureElevenLabs()
	} else if TTS_PROVIDER == "rime" {
		setupRimeCredentials()
	}

	// In all docker compose commands, use the correct compose files
	if INSTALL_TYPE == "default" {
		COMPOSE_FILES = "-f " + PROJECT_ROOT + "/docker/docker-compose.yml"
	} else {
		COMPOSE_FILES = "-f " + PROJECT_ROOT + "/docker/docker-compose.full.yml"
	}

	// Enable protobuf API key support (required for configurable Eleven Labs TTS)
	configureProtobufTts()

	// Update docker-compose.yml based on TTS provider
	instAbort(updateDockerComposeForTts(), 2590)

	// Check if the required software prerequisites are installed so installer can run
	checkInstallerPrequisites()

	// check driver prerequisites
	checkDriverPrerequisites()

	// check software prerequisites
	checkSoftwarePrequisites()

	// check hardware prerequisites
	checkHardwarePrerequisites()

	// check docker installation
	checkDockerInstallation()

	// validate docker daemon is responsive
	instAbort(validateDockerDaemon(), 2608)

	// eval set -- "$OPTIONS"
	pos := instShellSplit(OPTIONS)

	// Initialize variables: prefer pre-set values (from --seed or CLI),
	// fall back to existing env-file values. ':=' only assigns when empty/unset.
	if PLATFORM_ADDRESS == "" {
		PLATFORM_ADDRESS = readEnvVariable("DHOP_ADDRESS")
	}
	if PLATFORM_KEY == "" {
		PLATFORM_KEY = readEnvVariable("DHOP_APIKEY")
	}
	if TENANT_ID == "" {
		TENANT_ID = readEnvVariable("DHOP_TENANTID")
	}
	if AZURE_REGION == "" {
		AZURE_REGION = readEnvVariable("AZURE_REGION")
	}

	// AZURE_SPEECH_KEY: prefer seeded value, then env file (try both legacy names).
	if AZURE_SPEECH_KEY == "" {
		AZURE_SPEECH_KEY = readEnvVariable("AZURE_SPEECH")
		if AZURE_SPEECH_KEY == "" {
			AZURE_SPEECH_KEY = readEnvVariable("AZURE_SPEECH_KEY")
		}
	}

	if RENNY_IMAGE == "" {
		RENNY_IMAGE = readDockerComposeValue("image")
	}

	// Debug output - strip quotes from values
	PLATFORM_ADDRESS = instEchoStripQuotes(PLATFORM_ADDRESS)
	PLATFORM_KEY = instEchoStripQuotes(PLATFORM_KEY)
	TENANT_ID = instEchoStripQuotes(TENANT_ID)
	AZURE_REGION = instEchoStripQuotes(AZURE_REGION)
	AZURE_SPEECH_KEY = instEchoStripQuotes(AZURE_SPEECH_KEY)
	RENNY_IMAGE = instEchoStripQuotes(RENNY_IMAGE)

	// Extract options and their arguments into variables
	for done := false; !done; {
		if len(pos) == 0 {
			instUnbound("1", 2641)
		}
		switch pos[0] {
		case "--help":
			instUsage()
			sh.Exit(0)
		case "--platform-address":
			PLATFORM_ADDRESS = instArg(pos, 1, 2647)
			pos = pos[2:]
		case "--platform-key":
			PLATFORM_KEY = instArg(pos, 1, 2651)
			pos = pos[2:]
		case "--tenant-id":
			TENANT_ID = instArg(pos, 1, 2655)
			pos = pos[2:]
		case "--azure-region":
			AZURE_REGION = instArg(pos, 1, 2659)
			pos = pos[2:]
		case "--azure-speech-key":
			AZURE_SPEECH_KEY = instArg(pos, 1, 2663)
			pos = pos[2:]
		case "--renny-image":
			RENNY_IMAGE = instArg(pos, 1, 2667)
			pos = pos[2:]
		case "--region":
			UNEEQ_REGION = instArg(pos, 1, 2671)
			pos = pos[2:]
		case "--deployment-target":
			DEPLOYMENT_TARGET = instArg(pos, 1, 2675)
			// Validate deployment target value
			if !instDeployTargetRe.MatchString(DEPLOYMENT_TARGET) {
				instFatal("Invalid --deployment-target value: " + DEPLOYMENT_TARGET + " (must be 'hardware' or 'cloud')")
			}
			info(CHECKMARK + " Deployment target specified via argument: " + DEPLOYMENT_TARGET)
			// Persist the CLI-provided value
			os.WriteFile(PROJECT_ROOT+"/.miniprem_deployment_target", []byte(DEPLOYMENT_TARGET+"\n"), 0o666)
			pos = pos[2:]
		case "--seed":
			// Already handled in the early scan; consume and continue.
			pos = instShift(pos, 2)
		case "--non-interactive", "--interactive", "--force":
			pos = instShift(pos, 1)
		case "--":
			pos = pos[1:]
			done = true
		default:
			// KNOWN UPSTREAM BUG (preserved): `*) usage` without a shift loops forever
			// (--tts-address / --tts-key are accepted by getopt but not handled).
			for {
				instLoopMu.Lock()
				os.Stdout.WriteString(instUsageString())
				instLoopMu.Unlock()
			}
		}
	}

	// Deployment target & quality configuration
	promptDeploymentTarget()
	promptForRegion()
	configureRegionEndpoints()
	PLATFORM_ADDRESS = readEnvVariable("DHOP_ADDRESS")
	configureRennyQuality()

	// Check if all required values are already provided
	if checkAllValuesProvided() == 0 {
		// All values are provided, show summary and confirm
		logSection("Configuration Summary")
		info("UneeQ platform address: " + PLATFORM_ADDRESS)
		info("UneeQ platform API key: " + instMask(PLATFORM_KEY))
		info("Tenant ID: " + TENANT_ID)
		info("Renny image name: " + RENNY_IMAGE)

		// Display TTS provider-specific information
		info("TTS Provider: " + TTS_PROVIDER)
		if TTS_PROVIDER == "azure" {
			info("Azure region: " + AZURE_REGION)
			info("Azure speech key: " + instMask(AZURE_SPEECH_KEY))
		} else if TTS_PROVIDER == "elevenlabs" {
			ELEVEN_LABS_API_KEY = readEnvVariable("ELEVEN_LABS_API_KEY")
			ELEVEN_LABS_API_KEY = instEchoStripQuotes(ELEVEN_LABS_API_KEY)
			info("Eleven Labs API key: " + instMask(ELEVEN_LABS_API_KEY))
		} else if TTS_PROVIDER == "rime" {
			RIME_API_KEY = readEnvVariable("RIME_API_KEY")
			RIME_API_KEY = instEchoStripQuotes(RIME_API_KEY)
			info("RIME API key: " + instMask(RIME_API_KEY))
		}

		if seedIsNonInteractive() {
			info("All configuration values are set; proceeding (non-interactive).")
		} else {
			for done := false; !done; {
				confirm, ok := sh.ReadLine(sh.ReadOpts{Prompt: "All configuration values are already set. Proceed with installation? (Y/n): "})
				if !ok {
					instAbort(1, 2739)
				}
				switch strings.ToLower(confirm) {
				case "y", "yes", "":
					done = true
				case "n", "no":
					info("Installation aborted by user.")
					sh.Exit(0)
				default:
					fmt.Println("Please enter 'y' or 'n'.")
				}
			}
		}
	} else {
		// PLATFORM_KEY=$(check_and_prompt_for_value ...): a status-1 return aborts under set -e.
		PLATFORM_KEY, rc = checkAndPromptForValue("Enter the UneeQ platform API key", PLATFORM_KEY, "MINIPREM_SEED_PLATFORM_KEY")
		instAbort(rc, 2755)
		TENANT_ID, rc = checkAndPromptForValue("Enter the Tenant ID", TENANT_ID, "MINIPREM_SEED_TENANT_ID")
		instAbort(rc, 2756)

		// Only prompt for Azure credentials if Azure TTS is selected
		if TTS_PROVIDER == "azure" {
			AZURE_REGION, rc = checkAndPromptForValue("Enter the Azure region", AZURE_REGION, "MINIPREM_SEED_AZURE_REGION")
			instAbort(rc, 2760)
			AZURE_SPEECH_KEY, rc = checkAndPromptForValue("Enter the Azure speech key", AZURE_SPEECH_KEY, "MINIPREM_SEED_AZURE_SPEECH_KEY")
			instAbort(rc, 2761)
		}

		RENNY_IMAGE, rc = checkAndPromptForValue("Enter the Renny image name", RENNY_IMAGE, "MINIPREM_SEED_RENNY_IMAGE")
		instAbort(rc, 2764)

		// In non-interactive mode, missing values are aggregated and reported by
		// seed_check_required below — skip the per-field fatals.
		if seedIsInteractive() {
			if PLATFORM_KEY == "" || TENANT_ID == "" || RENNY_IMAGE == "" {
				instUsage()
				instFatal("Missing required arguments. Please provide the required arguments.")
			}

			if TTS_PROVIDER == "azure" && (AZURE_REGION == "" || AZURE_SPEECH_KEY == "") {
				instUsage()
				instFatal("Azure TTS selected but Azure credentials are missing.")
			}
		}
	}

	// Final aggregation point: any non-interactive run that accumulated missing
	// required keys fails here with the full list, before any destructive work.
	seedCheckRequired()

	// Update the environment file with collected values
	updateEnvFile()

	// Make sure PLATFORM_ADDRESS has a default value if it's empty
	if PLATFORM_ADDRESS == "" {
		PLATFORM_ADDRESS = "wss://" + getDhopAPIHostname() + "/signalling-service/v1/ws/renderer"
		// Also update it in the env file
		envFile := PROJECT_ROOT + "/docker/docker-compose.env"
		if instFileHasLinePrefix(envFile, "DHOP_ADDRESS=") {
			escaped := instSedEscape(PLATFORM_ADDRESS)
			instAbort(instSedSetVar(envFile, "DHOP_ADDRESS", escaped), 2796)
		}
	}

	// Validate network connectivity before proceeding
	validateNetworkConnectivity(getDhopAPIHostname(), 10)

	// check to make sure the cloud services are reachable
	checkCloudServices(PLATFORM_ADDRESS, PLATFORM_ADDRESS)

	if INSTALL_TYPE == "full" {
		// Honor STT_PROVIDER from --seed/CLI: whisper -> 1, fastwhisper -> 2, none -> 3
		instSttChoice = ""
		if STT_PROVIDER != "" {
			seedValidateChoice("STT_PROVIDER", "whisper|fastwhisper|none")
			switch STT_PROVIDER {
			case "whisper":
				instSttChoice = "1"
			case "fastwhisper":
				instSttChoice = "2"
			case "none":
				instSttChoice = "3"
			}
			info("Using STT provider: " + STT_PROVIDER)
		} else if seedIsNonInteractive() {
			seedRecordMissing("MINIPREM_SEED_STT_PROVIDER", "whisper|fastwhisper|none (full install only)")
			seedCheckRequired() // exits if missing
		} else {
			fmt.Print(ltEchoE(`\nChoose your speech-to-text backend (only one will be enabled):`))
			fmt.Println("1) Whisper (OpenAI, onerahmet/openai-whisper-asr-webservice)")
			fmt.Println("2) FastWhisper (GPU-optimized, locally built)")
			fmt.Println("3) Do not use local STT (UneeQ default STT will be used)")
			instSttChoice = readOrDie("Enter choice [1-3]: ")
		}

		if instSttChoice == "1" || instSttChoice == "2" || instSttChoice == "3" {
			// Update docker-compose.yml for the selected STT backend
			instAbort(updateDockerComposeForStt(instSttChoice), 2832)

			// If FastWhisper is selected, build the image
			if instSttChoice == "2" {
				buildFastWhisperImage()
			}
		} else {
			fmt.Println("Invalid STT choice, exiting.")
			sh.Exit(1)
		}
	}

	// pull the images down with TTS provider information
	pullDockerWithTtsProvider()

	// Start the Miniprem system
	startMiniprem()

	// Setup Flowise chatflow
	if INSTALL_TYPE == "full" {
		instAbort(setupFlowiseChatflow(), 2852)
	}

	// Optional: enable auto-start at boot (gated by prompt_for_autostart)
	if ltOr(INSTALL_AS_SERVICE, "no") == "yes" {
		instAbort(enableSystemdAutostart(), 2857)
	}

	// Create desktop shortcut for easy launching (Ubuntu Desktop only)
	createDesktopShortcut()

	success(CHECKMARK + " Installation and configuration complete.")
	info("Miniprem is now running. You can access:")
	info("- MiniPrem Monitor at http://localhost:3001 (container/Kubernetes monitoring)")
	if INSTALL_TYPE == "full" {
		info("- Flowise at http://localhost:3000 (workflow automation)")
		info("  Log in with the admin account in docker/flowise.env (FLOWISE_ADMIN_EMAIL / FLOWISE_ADMIN_PASSWORD).")
		info("  If no account exists yet, the first visit prompts you to create one.")
		info("- Grafana at http://localhost:3002 (metrics dashboard)")
	}
	info("- Renny service health at http://localhost:8081/health")
	info("")
	info("To stop the services, use: " + PROJECT_ROOT + "/miniprem.sh stop")
	if ltOr(INSTALL_AS_SERVICE, "no") == "yes" {
		info("MiniPrem will auto-start at boot (managed by systemd: miniprem.service).")
	}

	// Prompt for custom Docker services setup
	promptCustomServices()

	instPrintEcho(instFinalBanner, PROJECT_ROOT)
}

// instArg returns pos[i] (the option argument; getopt guarantees it exists).
func instArg(pos []string, i, line int) string {
	if i >= len(pos) {
		instUnbound("2", line)
	}
	return pos[i]
}

// instShift is `shift n` (a no-op failure when n exceeds the count leaves the list alone).
func instShift(pos []string, n int) []string {
	if n > len(pos) {
		return pos
	}
	return pos[n:]
}

// instMask is "${v:0:8}****${v: -8}": a value shorter than 8 characters has an empty
// tail (the negative offset falls before the start).
func instMask(v string) string {
	r := []rune(v)
	head := r
	if len(head) > 8 {
		head = head[:8]
	}
	tail := ""
	if len(r) >= 8 {
		tail = string(r[len(r)-8:])
	}
	return string(head) + "****" + tail
}
