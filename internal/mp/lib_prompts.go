package mp

import (
	"crypto/rand"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of scripts/prompts.sh (no top-level code).
//
// NOTE: prompt_for_region (prompts.sh:159) is NOT ported here: the installer defines its
// own copy (install_miniprem.sh:1140), which is the one bash uses (later definition
// wins); the lib copy is never called by miniprem.sh.
//
// errexit: all functions here are called as plain top-level statements of the installer,
// so a bare `read` that hits EOF (status 1) aborts the script -> readOrDie.

// INSTALLATION_ID: bash scripts/prompts.sh:257 (global, assigned inside the function).
var INSTALLATION_ID string

// readOrDie is a bare `read -p PROMPT var` under `set -e`.
func readOrDie(prompt string) string {
	line, ok := sh.ReadLine(sh.ReadOpts{Prompt: prompt})
	if !ok {
		sh.Exit(1)
	}
	return line
}

// ltEchoToFile emulates `echo "$s" > path` (reports false on failure).
func ltEchoToFile(path, s string) bool {
	if err := os.WriteFile(path, []byte(s+"\n"), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %s\n", path, ltErrText(err))
		return false
	}
	return true
}

func ltErrText(err error) string {
	if pe, ok := err.(*os.PathError); ok {
		err = pe.Err
	}
	s := err.Error()
	if s != "" {
		s = strings.ToUpper(s[:1]) + s[1:]
	}
	return s
}

// promptForInstallType. bash: scripts/prompts.sh:8
func promptForInstallType() {
	if INSTALL_TYPE != "" {
		seedValidateChoice("INSTALL_TYPE", "default|full")
		if !ltEchoToFile(PROJECT_ROOT+"/.miniprem_install_type", INSTALL_TYPE) {
			warning("Failed to write installation type marker, but continuing...")
		}
		markInstallationMarkerCreated()
		info("Using installation type: " + INSTALL_TYPE)
		return
	}

	if seedIsNonInteractive() {
		seedRecordMissing("MINIPREM_SEED_INSTALL_TYPE", "default|full")
		return
	}

	INSTALL_TYPE = ""
	fmt.Println("Select installation type:")
	fmt.Println("1) Default Install (Renny with internal speech processing only)")
	fmt.Println("2) Full Install (All services: Renny with internal speech, Flowise, vLLM, Grafana, Prometheus, RIME, Whisper etc.)")
	installChoice := readOrDie("Enter choice [1-2]: ")
	if installChoice == "1" {
		INSTALL_TYPE = "default"
		if !ltEchoToFile(PROJECT_ROOT+"/.miniprem_install_type", "default") {
			warning("Failed to write installation type marker, but continuing...")
		}
		markInstallationMarkerCreated()
	} else if installChoice == "2" {
		INSTALL_TYPE = "full"
		if !ltEchoToFile(PROJECT_ROOT+"/.miniprem_install_type", "full") {
			warning("Failed to write installation type marker, but continuing...")
		}
		markInstallationMarkerCreated()
	} else {
		fmt.Println("Invalid choice, exiting.")
		sh.Exit(1)
	}

	if INSTALL_TYPE == "" {
		fatal("Failed to set installation type")
	}
}

// promptForAutostart. bash: scripts/prompts.sh:55
func promptForAutostart() {
	if INSTALL_AS_SERVICE != "" {
		seedValidateChoice("INSTALL_AS_SERVICE", "yes|no")
		info("Using install-as-service: " + INSTALL_AS_SERVICE)
		return
	}
	if seedIsNonInteractive() {
		INSTALL_AS_SERVICE = "no"
		info("Install-as-service defaulted to 'no' (set MINIPREM_SEED_INSTALL_AS_SERVICE=yes to enable)")
		return
	}

	INSTALL_AS_SERVICE = "no"
	fmt.Println("")
	fmt.Println("Install MiniPrem as a systemd service?")
	fmt.Println("  - Auto-starts at boot, even before any user logs in")
	fmt.Println("  - Requires root (this installer is already running with sudo)")
	fmt.Println("  - Disable later with: sudo systemctl disable miniprem.service")
	autostartChoice := readOrDie("Install as service? [y/N] ")
	switch autostartChoice {
	case "y", "Y", "yes", "YES", "Yes":
		INSTALL_AS_SERVICE = "yes"
	default:
		INSTALL_AS_SERVICE = "no"
	}
}

// promptDeploymentTarget. bash: scripts/prompts.sh:87
func promptDeploymentTarget() {
	if DEPLOYMENT_TARGET != "" {
		seedValidateChoice("DEPLOYMENT_TARGET", "hardware|cloud")
		info(CHECKMARK + " Using deployment target: " + DEPLOYMENT_TARGET)
		os.WriteFile(PROJECT_ROOT+"/.miniprem_deployment_target", []byte(DEPLOYMENT_TARGET+"\n"), 0o644)
		return
	}

	if ltIsFile(PROJECT_ROOT + "/.miniprem_deployment_target") {
		b, err := os.ReadFile(PROJECT_ROOT + "/.miniprem_deployment_target")
		if err != nil {
			sh.Exit(1) // `cat | tr` fails under pipefail+errexit
		}
		DEPLOYMENT_TARGET = ltRemoveSpace(string(b))
		if DEPLOYMENT_TARGET != "" {
			info(CHECKMARK + " Using previously configured deployment target: " + DEPLOYMENT_TARGET)
			return
		}
	}

	if seedIsNonInteractive() {
		seedRecordMissing("MINIPREM_SEED_DEPLOYMENT_TARGET", "hardware|cloud")
		return
	}

	logSection("Deployment Target Selection")

	DEPLOYMENT_TARGET = ""
	maxRetries := 3
	attempts := 0

	for attempts < maxRetries {
		fmt.Println("")
		fmt.Println("Select deployment target:")
		fmt.Println("1) Dedicated Hardware (PC/Server) - Optimized for local/on-premise installations")
		fmt.Println("2) Cloud Platform (AWS/Azure/GCP) - Optimized for cloud infrastructure")
		deploymentChoice := readOrDie("Enter choice [1-2]: ")

		switch deploymentChoice {
		case "1":
			DEPLOYMENT_TARGET = "hardware"
			info(CHECKMARK + " Selected: Dedicated Hardware deployment")
		case "2":
			DEPLOYMENT_TARGET = "cloud"
			info(CHECKMARK + " Selected: Cloud Platform deployment")
		default:
			attempts++
			if attempts < maxRetries {
				warning(fmt.Sprintf("Invalid choice. Please enter 1 or 2. (Attempt %d/%d)", attempts, maxRetries))
				continue
			} else {
				fatal(fmt.Sprintf("Invalid choice after %d attempts. Exiting.", maxRetries))
			}
		}

		if os.WriteFile(PROJECT_ROOT+"/.miniprem_deployment_target", []byte(DEPLOYMENT_TARGET+"\n"), 0o644) == nil {
			success(CHECKMARK + " Deployment target saved for future installations")
		} else {
			warning("Failed to save deployment target, but continuing...")
		}
		break
	}

	if DEPLOYMENT_TARGET == "" {
		fatal("Failed to set deployment target")
	}
}

const telemetryNoticeBox = `┌─────────────────────────────────────────────────────────────────┐
│                    MiniPrem Telemetry Notice                    │
├─────────────────────────────────────────────────────────────────┤
│ This installation sends anonymous usage data to UneeQ:          │
│                                                                 │
│ ✓ Installation notification (one-time)                          │
│ ✓ Heartbeat every 15 minutes to monitor uptime                  │
│                                                                 │
│ Data collected (NO personally identifiable information):        │
│   • Anonymous installation ID (generated locally)               │
│   • GPU hardware identifier (one-way SHA-256 hash)              │
│   • MiniPrem version and deployment type                        │
│   • System uptime and health status                             │
│                                                                 │
│ We DO NOT collect:                                              │
│   ✗ IP addresses, hostnames, or network identifiers             │
│   ✗ UneeQ credentials, API keys, or tokens                      │
│   ✗ Conversation data or chat history                           │
│   ✗ Any content processed by Renny                              │
│   ✗ Customer information                                        │
│                                                                 │
│ Privacy: See docs/TELEMETRY.md for full details                 │
└─────────────────────────────────────────────────────────────────┘
`

// promptForTelemetryConsent. bash: scripts/prompts.sh:199
func promptForTelemetryConsent() {
	logSection("MiniPrem Telemetry Notice")

	fmt.Print(telemetryNoticeBox)

	fmt.Println("")
	var telemetryConsent string
	if TELEMETRY_CONSENT != "" {
		seedValidateChoice("TELEMETRY_CONSENT", "yes|no")
		if TELEMETRY_CONSENT == "yes" {
			telemetryConsent = "y"
		} else {
			telemetryConsent = "n"
		}
		info("Using telemetry consent from seed/CLI: " + TELEMETRY_CONSENT)
	} else if seedIsNonInteractive() {
		seedRecordMissing("MINIPREM_SEED_TELEMETRY_CONSENT", "yes|no")
		fmt.Println("")
		return
	} else {
		telemetryConsent = readOrDie("Do you consent to anonymous telemetry? [Y/n] ")
		if telemetryConsent == "" {
			telemetryConsent = "y"
		}
	}

	if telemetryConsent == "y" || telemetryConsent == "Y" {
		INSTALLATION_ID = ""

		dataDir := "/var/lib/miniprem"
		idFile := dataDir + "/installation_id"

		if !ltIsDir(dataDir) {
			if sh.C("sudo", "mkdir", "-p", dataDir).NoErr().Run() != 0 {
				if err := os.MkdirAll(dataDir, 0o777); err != nil {
					fmt.Fprintf(os.Stderr, "mkdir: cannot create directory '%s': %s\n", dataDir, ltErrText(err))
					sh.Exit(1)
				}
			}
			if sh.C("sudo", "chmod", "755", dataDir).NoErr().Run() != 0 {
				if err := os.Chmod(dataDir, 0o755); err != nil {
					sh.Exit(1)
				}
			}
		}

		if st, err := os.Stat(idFile); err == nil && st.Mode().IsRegular() && st.Size() > 0 {
			b, rerr := os.ReadFile(idFile)
			if rerr != nil {
				sh.Exit(1) // cat | tr under pipefail+errexit
			}
			INSTALLATION_ID = ltRemoveSpace(string(b))
			if INSTALLATION_ID != "" {
				success(CHECKMARK + " Reusing existing installation ID: " + ltFirst8(INSTALLATION_ID) + "...")
			} else {
				INSTALLATION_ID = ""
			}
		}

		if INSTALLATION_ID == "" {
			if ltIsDir(idFile) {
				if sh.C("sudo", "rm", "-rf", idFile).NoErr().Run() != 0 {
					os.RemoveAll(idFile)
				}
			}

			if commandExists("uuidgen") {
				out, rc := sh.Output("uuidgen")
				if rc != 0 {
					sh.Exit(rc)
				}
				INSTALLATION_ID = strings.ToLower(out)
			} else {
				id := ltRandHex(32)
				INSTALLATION_ID = id[0:8] + "-" + id[8:12] + "-" + id[12:16] + "-" + id[16:20] + "-" + id[20:32]
			}

			// echo "$INSTALLATION_ID" | sudo tee "$FILE" > /dev/null
			if rc := sh.C("sudo", "tee", idFile).In(INSTALLATION_ID + "\n").Out(io.Discard).Run(); rc != 0 {
				sh.Exit(rc)
			}
			if rc := sh.Run("sudo", "chmod", "644", idFile); rc != 0 {
				sh.Exit(rc)
			}

			success(CHECKMARK + " Installation ID generated: " + ltFirst8(INSTALLATION_ID) + "...")
		}

		info("Sending installation notification...")

		ts := sh.Now().UTC().Format("2006-01-02T15:04:05Z")
		osOut, _ := sh.Output("uname", "-s")
		archOut, _ := sh.Output("uname", "-m")
		payload := "{\n" +
			"  \"installation_id\": \"" + INSTALLATION_ID + "\",\n" +
			"  \"event_type\": \"installation\",\n" +
			"  \"timestamp\": \"" + ts + "\",\n" +
			"  \"version\": \"2.1.0\",\n" +
			"  \"platform\": \"docker\",\n" +
			"  \"os\": \"" + strings.ToLower(osOut) + "\",\n" +
			"  \"platform_arch\": \"" + archOut + "\",\n" +
			"  \"status\": \"installing\"\n" +
			"}"

		if sh.C("curl", "-X", "POST", "-H", "Content-Type: application/json",
			"-d", payload,
			"--max-time", "5",
			"--silent",
			"--show-error",
			"--fail",
			"https://renny.services.uneeq.io/telemetry").Quiet().Run() == 0 {
			success(CHECKMARK + " Installation notification sent")
		} else {
			info("Installation notification will be sent when container starts")
		}

	} else {
		warning("Telemetry disabled - you can re-enable later by removing MINIPREM_TELEMETRY_DISABLED from docker/docker-compose.env")

		if rc := updateEnvVariable("MINIPREM_TELEMETRY_DISABLED", "1"); rc != 0 {
			sh.Exit(rc) // bare statement under errexit
		}

		if sh.C("sudo", "rm", "-f", "/var/lib/miniprem/installation_id").NoErr().Run() != 0 {
			os.Remove("/var/lib/miniprem/installation_id")
		}

		info("Telemetry disabled - continuing with installation")
	}

	fmt.Println("")
}

func ltFirst8(s string) string {
	if len(s) > 8 {
		return s[:8]
	}
	return s
}

// ltRandHex emulates `tr -dc 'a-f0-9' < /dev/urandom | fold -w n | head -n 1`.
func ltRandHex(n int) string {
	const alpha = "abcdef0123456789"
	out := make([]byte, 0, n)
	buf := make([]byte, 64)
	for len(out) < n {
		rand.Read(buf)
		for _, b := range buf {
			if b < 240 { // 240 = 16*15, avoids modulo bias
				out = append(out, alpha[int(b)%16])
				if len(out) == n {
					break
				}
			}
		}
	}
	return string(out)
}
