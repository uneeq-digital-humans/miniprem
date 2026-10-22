package mp

import (
	"fmt"
	"os"
	"strings"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of the TTS / STT provider parts of install_miniprem.sh.
// NOTE: configure_eleven_labs is defined twice in bash (line 276 and line 770); the later
// definition wins, so only that one is ported (configureElevenLabs below).

// instUpdEnv is a bare `update_env_variable NAME VALUE` under errexit.
func instUpdEnv(name, value string, line int) {
	instAbort(updateEnvVariable(name, value), line)
}

// instEchoToFile is a bare `echo "$s" > path` under errexit.
func instEchoToFile(path, s string, line int) {
	if !ltEchoToFile(path, s) {
		instAbort(1, line)
	}
}

// configureProtobufTts. bash: install_miniprem.sh:666
func configureProtobufTts() {
	instUpdEnv("RENNY_TTS_USE_PROTO_API_KEY", "1", 667)
	success(CHECKMARK + " Protobuf TTS API support enabled")
}

// selectTtsProvider. bash: install_miniprem.sh:672
func selectTtsProvider() {
	logSection("Text-to-Speech Provider Selection")

	// Honor a pre-set value (from --seed or CLI)
	if TTS_PROVIDER != "" {
		seedValidateChoice("TTS_PROVIDER", "azure|elevenlabs|rime")
		instEchoToFile(PROJECT_ROOT+"/.miniprem_tts_provider", TTS_PROVIDER, 678)
		info("Using TTS provider: " + TTS_PROVIDER)
		return
	}

	if seedIsNonInteractive() {
		seedRecordMissing("MINIPREM_SEED_TTS_PROVIDER", "azure|elevenlabs|rime")
		return
	}

	fmt.Println("Select your preferred text-to-speech provider:")
	fmt.Println("1) Azure (Microsoft TTS)")
	fmt.Println("2) Eleven Labs")
	fmt.Println("3) RIME")
	ttsChoice := readOrDie("Enter choice [1-3]: ")

	switch ttsChoice {
	case "1":
		TTS_PROVIDER = "azure"
		instEchoToFile(PROJECT_ROOT+"/.miniprem_tts_provider", "azure", 697)
		info("Azure TTS selected")
	case "2":
		TTS_PROVIDER = "elevenlabs"
		instEchoToFile(PROJECT_ROOT+"/.miniprem_tts_provider", "elevenlabs", 702)
		info("Eleven Labs TTS selected")
	case "3":
		TTS_PROVIDER = "rime"
		instEchoToFile(PROJECT_ROOT+"/.miniprem_tts_provider", "rime", 707)
		info("RIME TTS selected")
	default:
		warning("Invalid choice, defaulting to Azure TTS")
		TTS_PROVIDER = "azure"
		instEchoToFile(PROJECT_ROOT+"/.miniprem_tts_provider", "azure", 713)
	}
}

// configureAzureTts. bash: install_miniprem.sh:719
func configureAzureTts() {
	if TTS_PROVIDER != "azure" {
		// Clear Azure environment variables if not using Azure
		instUpdEnv("AZURE_REGION", `""`, 722)
		instUpdEnv("AZURE_SPEECH", `""`, 723)
		instUpdEnv("AZURE_SPEECH_KEY", `""`, 724)
		return
	}

	logSection("Configure Azure TTS")

	// Resolve precedence: existing global (from seed/CLI) > env file > prompt
	if AZURE_REGION == "" {
		AZURE_REGION = readEnvVariable("AZURE_REGION")
	}
	if AZURE_REGION == "" {
		if seedIsNonInteractive() {
			seedRecordMissing("MINIPREM_SEED_AZURE_REGION", "Azure region (when TTS=azure)")
		} else {
			AZURE_REGION = readOrDie("Enter your Azure region (e.g., eastus): ")
			if AZURE_REGION == "" {
				warning("No Azure region provided. Azure TTS may not function correctly.")
			}
		}
	}
	if AZURE_REGION != "" {
		instUpdEnv("AZURE_REGION", `"`+AZURE_REGION+`"`, 745)
		success(CHECKMARK + " Azure region configured")
	}

	if AZURE_SPEECH_KEY == "" {
		AZURE_SPEECH_KEY = readEnvVariable("AZURE_SPEECH_KEY")
	}
	if AZURE_SPEECH_KEY == "" {
		if seedIsNonInteractive() {
			seedRecordMissing("MINIPREM_SEED_AZURE_SPEECH_KEY", "Azure speech key (when TTS=azure)")
		} else {
			AZURE_SPEECH_KEY = readOrDie("Enter your Azure speech key: ")
			if AZURE_SPEECH_KEY == "" {
				warning("No Azure speech key provided. Azure TTS may not function correctly.")
			}
		}
	}
	if AZURE_SPEECH_KEY != "" {
		instUpdEnv("AZURE_SPEECH_KEY", `"`+AZURE_SPEECH_KEY+`"`, 763)
		instUpdEnv("AZURE_SPEECH", `"`+AZURE_SPEECH_KEY+`"`, 764)
		success(CHECKMARK + " Azure speech key configured")
	}
}

// configureElevenLabs is the LAST (live) definition. bash: install_miniprem.sh:770
func configureElevenLabs() {
	if TTS_PROVIDER != "elevenlabs" {
		// Clear Eleven Labs environment variables if not using Eleven Labs
		instUpdEnv("ELEVEN_LABS_API_KEY", `""`, 773)
		instUpdEnv("ELEVEN_LABS_MODEL_ID", `""`, 774)
		instUpdEnv("ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL", `""`, 775)
		instUpdEnv("ELEVEN_LABS_SIMILARITY_BOOST", `""`, 776)
		instUpdEnv("ELEVEN_LABS_STABILITY", `""`, 777)
		return
	}

	logSection("Configure Eleven Labs TTS")

	// Resolve precedence: existing global (from seed/CLI) > env file > prompt
	if ELEVEN_LABS_API_KEY == "" {
		ELEVEN_LABS_API_KEY = readEnvVariable("ELEVEN_LABS_API_KEY")
	}
	if ELEVEN_LABS_API_KEY == "" {
		if seedIsNonInteractive() {
			seedRecordMissing("MINIPREM_SEED_ELEVEN_LABS_API_KEY", "Eleven Labs API key (when TTS=elevenlabs)")
		} else {
			ELEVEN_LABS_API_KEY = readOrDie("Enter your Eleven Labs API key: ")
			if ELEVEN_LABS_API_KEY == "" {
				warning("No Eleven Labs API key provided. Eleven Labs services may not function correctly.")
			}
		}
	}
	if ELEVEN_LABS_API_KEY != "" {
		instUpdEnv("ELEVEN_LABS_API_KEY", `"`+ELEVEN_LABS_API_KEY+`"`, 798)
		// Set default values for other Eleven Labs parameters
		instUpdEnv("ELEVEN_LABS_MODEL_ID", `"eleven_flash_v2_5"`, 800)
		instUpdEnv("ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL", "1", 801)
		instUpdEnv("ELEVEN_LABS_SIMILARITY_BOOST", "0.5", 802)
		instUpdEnv("ELEVEN_LABS_STABILITY", "0.5", 803)
		success(CHECKMARK + " Eleven Labs API key configured")
	}
}

// instDockerImagesGrep is `eval $DOCKER_CMD images | grep -q "<bre>"` in a condition.
func instDockerImagesGrep(bre string) bool {
	f := dockerFields(DOCKER_CMD)
	out, drc := sh.C(f[0], append(f[1:], "images")...).Output()
	grc := 1
	if instGrepQ(out, bre) {
		grc = 0
	}
	return pipeStatus(drc, grc) == 0
}

// instRimeQuayUnset reports whether RIME_QUAY_PASSWORD is an UNSET variable in bash terms
// (never assigned: no seed applied it, not inherited from the environment).
func instRimeQuayUnset() bool {
	if RIME_QUAY_PASSWORD != "" || SEED_LOADED == "yes" {
		return false
	}
	_, ok := os.LookupEnv("RIME_QUAY_PASSWORD")
	return !ok
}

// setupRimeCredentials. bash: install_miniprem.sh:809
func setupRimeCredentials() {
	DOCKER_CMD = "sudo docker"

	if TTS_PROVIDER != "rime" {
		// Clear RIME environment variables if not using RIME
		instUpdEnv("RIME_API_KEY", `""`, 815)
		return
	}

	logSection("Setting up RIME credentials")

	// Resolve precedence: existing global (from seed/CLI) > env file > prompt
	if RIME_API_KEY == "" {
		RIME_API_KEY = readEnvVariable("RIME_API_KEY")
	}
	if RIME_API_KEY == "" {
		if seedIsNonInteractive() {
			seedRecordMissing("MINIPREM_SEED_RIME_API_KEY", "RIME API key (when TTS=rime)")
		} else {
			RIME_API_KEY = readOrDie("Enter your RIME API key: ")
			if RIME_API_KEY == "" {
				warning("No RIME API key provided. RIME services may not function correctly.")
			}
		}
	}
	if RIME_API_KEY != "" {
		instUpdEnv("RIME_API_KEY", `"`+RIME_API_KEY+`"`, 836)
		success(CHECKMARK + " RIME API key configured")
	}

	// Only pull RIME images if we're using RIME
	if TTS_PROVIDER == "rime" {
		// Check if we've already authenticated with quay.io
		if instDockerImagesGrep("quay.io/rimelabs/api") && instDockerImagesGrep("quay.io/rimelabs/mistv2") {
			success(CHECKMARK + " Already have RIME Docker images, skipping quay.io login")
			return
		}

		// Resolve quay.io RIME password (seed/CLI > prompt)
		if RIME_QUAY_PASSWORD == "" {
			if seedIsNonInteractive() {
				seedRecordMissing("MINIPREM_SEED_RIME_QUAY_PASSWORD", "quay.io RIME password (when TTS=rime, no cached images)")
				return
			}
			// set -u: `[ -z "$RIME_QUAY_PASSWORD" ]` on a never-assigned variable aborts (known upstream defect).
			unset := instRimeQuayUnset()
			for {
				if unset {
					instUnbound("RIME_QUAY_PASSWORD", 854)
				}
				if RIME_QUAY_PASSWORD != "" {
					break
				}
				pw, ok := sh.ReadLine(sh.ReadOpts{Prompt: "Enter the quay.io password for RIME (rimelabs+uneeq): ", Silent: true})
				RIME_QUAY_PASSWORD = pw
				unset = false
				if !ok {
					instAbort(1, 855)
				}
				fmt.Println()
				if RIME_QUAY_PASSWORD == "" {
					warning("No password entered. Please provide the quay.io password for RIME.")
				}
			}
		}

		// Login to quay.io for RIME images
		info("Logging in to quay.io for RIME images...")
		f := dockerFields(DOCKER_CMD)
		instAbort(sh.Run(f[0], append(f[1:], "login", "-u=rimelabs+uneeq", "-p="+RIME_QUAY_PASSWORD, "quay.io")...), 865)
		instAbort(sh.Run(f[0], append(f[1:], "pull", "quay.io/rimelabs/api:v0.0.2-20250407")...), 866)
		instAbort(sh.Run(f[0], append(f[1:], "pull", "quay.io/rimelabs/mistv2:v0.0.1-20250403")...), 867)

		info("RIME credential setup complete")
	}
}

// instSedRange is `sed -i '/^<begin>/,/^<end>/s/^<from>/<to>/' file` (literal prefixes;
// the end address is only tested on lines after the start line).
func instSedRange(file, begin, end, from, to string) int {
	data, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sed: can't read %s: No such file or directory\n", file)
		return 2
	}
	lines := strings.Split(string(data), "\n")
	inRange := false
	for i, l := range lines {
		if !inRange {
			if !strings.HasPrefix(l, begin) {
				continue
			}
			inRange = true
		} else if strings.HasPrefix(l, end) {
			inRange = false
		}
		// (a range end also takes the substitution on its own line)
		if strings.HasPrefix(l, from) {
			lines[i] = to + l[len(from):]
		}
	}
	out := strings.Join(lines, "\n")
	if out != string(data) {
		if err := os.WriteFile(file, []byte(out), 0o644); err != nil {
			return 4
		}
	}
	return 0
}

// updateDockerComposeForTts: returns the function status (1 = compose file missing; the
// caller is a bare statement so that aborts the script). The seds are no-ops on the real
// files (markers are indented, seds anchor at column 0): replicated, not fixed.
// bash: install_miniprem.sh:874
func updateDockerComposeForTts() int {
	composeFile := PROJECT_ROOT + "/docker/docker-compose.yml"

	// Only proceed if docker-compose.yml exists
	if !ltIsFile(composeFile) {
		warning("docker-compose.yml not found, skipping TTS configuration")
		return 1
	}

	// Make a backup of the original file
	if !instCopyFile(composeFile, composeFile+".bak") {
		instAbort(1, 884)
	}

	info("Updating docker-compose.yml for selected TTS provider: " + TTS_PROVIDER)

	// Handle RIME services based on selection
	if TTS_PROVIDER == "rime" {
		// Uncomment RIME services if RIME is selected
		instAbort(instSedRange(composeFile, "### RIME BEGIN ###", "### RIME END ###", "  # ", "  "), 891)
	} else {
		// Comment out RIME services if not selected
		instAbort(instSedRange(composeFile, "### RIME BEGIN ###", "### RIME END ###", "  ", "  # "), 894)
	}

	success(CHECKMARK + " docker-compose.yml updated for TTS provider: " + TTS_PROVIDER)
	return 0
}

// updateDockerComposeForStt. bash: install_miniprem.sh:901
func updateDockerComposeForStt(sttChoice string) int {
	composeFile := PROJECT_ROOT + "/docker/docker-compose.yml"

	// Only proceed if docker-compose.yml exists
	if !ltIsFile(composeFile) {
		warning("docker-compose.yml not found, skipping STT configuration")
		return 1
	}

	info("Updating docker-compose.yml for selected STT backend...")

	const (
		wb, we = "### WHISPER BEGIN ###", "### WHISPER END ###"
		fb, fe = "### FASTWHISPER BEGIN ###", "### FASTWHISPER END ###"
	)
	if sttChoice == "1" {
		// Enable Whisper, disable FastWhisper
		instAbort(instSedRange(composeFile, wb, we, "  # ", "  "), 915)
		instAbort(instSedRange(composeFile, fb, fe, "  ", "  # "), 916)
	} else if sttChoice == "2" {
		// Enable FastWhisper, disable Whisper
		instAbort(instSedRange(composeFile, fb, fe, "  # ", "  "), 919)
		instAbort(instSedRange(composeFile, wb, we, "  ", "  # "), 920)
	} else if sttChoice == "3" {
		// Disable both Whisper and FastWhisper (use UneeQ default STT)
		instAbort(instSedRange(composeFile, wb, we, "  ", "  # "), 923)
		instAbort(instSedRange(composeFile, fb, fe, "  ", "  # "), 924)
	}

	success(CHECKMARK + " docker-compose.yml updated for STT backend")
	return 0
}
