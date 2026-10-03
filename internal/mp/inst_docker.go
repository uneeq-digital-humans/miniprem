package mp

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of the docker / container lifecycle parts of install_miniprem.sh.

// instDockerArgs is `eval $DOCKER_CMD <args...>`: the eval'd words, split on blanks.
func instDockerArgs(dockerCmd string, args ...string) (string, []string) {
	f := dockerFields(dockerCmd + " " + strings.Join(args, " "))
	return f[0], f[1:]
}

// pullImagesParallel pulls every image in its own background job (goroutine), polls the
// per-job temp files, then reports in image order after `wait`. Only ever called from an
// `if !` (errexit off). bash: install_miniprem.sh:316
func pullImagesParallel(images ...string) int {
	var tempFiles []string
	var failedImages []string

	info(fmt.Sprintf("Pulling %d Docker images in parallel...", len(images)))

	// Start parallel pulls with progress tracking
	var wg sync.WaitGroup
	for _, image := range images {
		tempFile, _ := sh.MkTemp("")
		tempFiles = append(tempFiles, tempFile)

		wg.Add(1)
		go func(image, tempFile string) {
			defer wg.Done()
			f, err := os.OpenFile(tempFile, os.O_WRONLY|os.O_TRUNC, 0)
			status := 1
			if err == nil {
				name, a := instDockerArgs(DOCKER_CMD, "pull", image)
				// background jobs read /dev/null
				status = sh.C(name, a...).In("").Out(f).Err(f).Run()
				f.Close()
			}
			marker := "FAILED:" + image + "\n"
			if status == 0 {
				marker = "SUCCESS:" + image + "\n"
			}
			if af, err := os.OpenFile(tempFile, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o600); err == nil {
				af.WriteString(marker)
				af.Close()
			}
		}(image, tempFile)
	}

	// Show progress while waiting
	total := len(images)
	completed := 0

	for completed < total {
		completed = 0
		for _, tempFile := range tempFiles {
			if ltIsFile(tempFile) {
				if b, err := os.ReadFile(tempFile); err == nil &&
					(strings.Contains(string(b), "SUCCESS:") || strings.Contains(string(b), "FAILED:")) {
					completed++
				}
			}
		}

		fmt.Printf("\rProgress: %d/%d images completed", completed, total)
		sh.Sleep(time.Second)
		if os.Getenv("MINIPREM_FAKE_EPOCH") != "" {
			time.Sleep(10 * time.Millisecond) // sleep is a no-op under the harness: do not spin
		}
	}
	fmt.Printf("\n")

	// Wait for all background processes and check results
	wg.Wait()
	for i := range images {
		tempFile := tempFiles[i]
		image := images[i]

		content, _ := os.ReadFile(tempFile)
		lines := ltLines(string(content))
		re := ltBRE("SUCCESS:" + image)
		ok := false
		for _, l := range lines {
			if re.MatchString(l) {
				ok = true
				break
			}
		}

		if ok {
			success(CHECKMARK + " Successfully pulled " + image)
		} else {
			logError("Failed to pull " + image + ":")
			for _, l := range lines {
				if !strings.Contains(l, "SUCCESS:") && !strings.Contains(l, "FAILED:") {
					fmt.Println(l)
				}
			}
			failedImages = append(failedImages, image)
		}

		os.Remove(tempFile)
	}

	// Report overall status
	if len(failedImages) == 0 {
		success(CHECKMARK + " All Docker images pulled successfully")
		return 0
	}
	// ${failed_images[*]} joins with the first character of IFS (newline).
	warning("Some images failed to pull: " + strings.Join(failedImages, "\n"))
	return 1
}

// pullRequiredImages (never called). bash: install_miniprem.sh:385
func pullRequiredImages() {
	DOCKER_CMD = "sudo docker"

	// Only pull images for selected services
	if INSTALL_TYPE == "full" {
		// Pull common images in parallel
		info("Pulling basic services images...")
		images := []string{
			"prom/prometheus:v2.45.0",
			"grafana/grafana:10.2.0",
			"redis:latest",
			"vllm/vllm-openai:v0.24.0",
		}

		if pullImagesParallel(images...) != 0 {
			instFatal("Failed to pull some basic service images")
		}

		// Pull TTS-specific images based on selection
		if TTS_PROVIDER == "rime" {
			// RIME credentials and images are handled in setup_rime_credentials
			setupRimeCredentials()
		}
	} else {
		// Only pull images for Renny with internal speech processing
		info("Pulling Renny images...")
		if pullImagesParallel("cr.uneeq.io/uneeq/renny-renderer:0.1428-6654b") != 0 {
			instFatal("Failed to pull Renny image")
		}

		// If using RIME in default install, pull RIME images
		if TTS_PROVIDER == "rime" {
			setupRimeCredentials()
		}
	}
}

// instPsHasName is `sudo docker <ps args> | grep -q "^<name>$"` (pipefail) in a condition.
func instPsHasName(name string, psArgs ...string) bool {
	out, drc := sh.C("sudo", append([]string{"docker"}, psArgs...)...).Output()
	grc := 1
	if instGrepQ(out, "^"+name+"$") {
		grc = 0
	}
	return pipeStatus(drc, grc) == 0
}

// instHealthStatus is
// $(sudo docker inspect --format='{{.State.Health.Status}}' "$c" 2>/dev/null || echo "unknown").
func instHealthStatus(name string) string {
	var b strings.Builder
	c := sh.C("sudo", "docker", "inspect", "--format={{.State.Health.Status}}", name).NoErr()
	c.Stdout = &b
	if c.Run() != 0 {
		b.WriteString("unknown\n")
	}
	return strings.TrimRight(b.String(), "\n")
}

// checkContainerHealth: called as a bare statement from startMiniprem, so a failing
// `sudo docker logs` aborts (errexit) and a returned 1 aborts at the call site.
// bash: install_miniprem.sh:1243
func checkContainerHealth(containerName string, maxWait, healthCheckInterval int) int {
	info("Checking health of container: " + containerName)

	// First check if container exists
	if !instPsHasName(containerName, "ps", "-a", "--format", "table {{.Names}}") {
		logError("Container " + containerName + " not found")
		return 1
	}

	// Check if container is running
	if !instPsHasName(containerName, "ps", "--format", "table {{.Names}}") {
		logError("Container " + containerName + " is not running")
		info("Container logs:")
		instAbort(sh.Run("sudo", "docker", "logs", containerName, "--tail", "20"), 1260)
		return 1
	}

	elapsed := 0

	for elapsed < maxWait {
		// Get health status
		healthStatus := instHealthStatus(containerName)

		switch healthStatus {
		case "healthy":
			success(CHECKMARK + " Container " + containerName + " is healthy")
			return 0
		case "unhealthy":
			logError("Container " + containerName + " is unhealthy")
			info("Container logs:")
			instAbort(sh.Run("sudo", "docker", "logs", containerName, "--tail", "20"), 1278)
			return 1
		case "none", "unknown":
			// Container doesn't have health check, try basic connectivity
			pout, _ := sh.C("sudo", "docker", "port", containerName).NoErr().Output()
			ports := ""
			if pl := ltLines(pout); len(pl) > 0 {
				ports = ltCutField(ltCutField(pl[0], "-", 1), ":", 2)
			}
			if ports != "" && ports != "0" {
				// Try to connect to the first exposed port
				hout, _ := sh.C("sudo", "docker", "port", containerName).NoErr().Output()
				hostPort := ""
				if hl := ltLines(hout); len(hl) > 0 {
					hostPort = ltCutField(hl[0], ":", 2)
				}
				if sh.C("nc", "-z", "localhost", hostPort).NoErr().Run() == 0 {
					success(CHECKMARK + " Container " + containerName + " is responding on port " + hostPort)
					return 0
				}
			}

			// If no health check and no port, assume running is healthy
			if instPsHasName(containerName, "ps", "--format", "table {{.Names}}") {
				success(CHECKMARK + " Container " + containerName + " is running (no health check defined)")
				return 0
			}
		}

		// Show progress
		if elapsed%30 == 0 && elapsed > 0 {
			info("Still waiting for " + containerName + " to become healthy... (" + strconv.Itoa(elapsed) + "s elapsed)")
			// Show recent logs
			info("Recent container logs:")
			instAbort(sh.Run("sudo", "docker", "logs", containerName, "--tail", "5"), 1306)
		}

		sh.Sleep(time.Duration(healthCheckInterval) * time.Second)
		elapsed = elapsed + healthCheckInterval
	}

	warning("Container " + containerName + " health check timed out after " + strconv.Itoa(maxWait) + "s")
	info("Container status:")
	if sh.C("sudo", "docker", "inspect", "--format={{.State.Status}} - {{.State.Health.Status}}", containerName).NoErr().Run() != 0 {
		fmt.Println("unknown")
	}
	info("Container logs:")
	instAbort(sh.Run("sudo", "docker", "logs", containerName, "--tail", "20"), 1317)
	return 1
}

// startMiniprem. A bare `eval ... up -d X` followed by `if [ $? ... ]` aborts on failure
// (errexit), so the else/fatal branches are dead; reproduced as aborts.
// bash: install_miniprem.sh:1407
func startMiniprem() {
	logSection("Starting Miniprem")

	// Enable cleanup tracking before starting any services
	enableCleanup()

	// Monitor memory usage before starting services
	instAbort(monitorMemoryDuringOperation("service startup", 85), 1414)

	// Use the docker-compose command determined during prerequisites
	if DOCKER_COMPOSE_CMD == "" {
		// Fallback if not set
		if commandExists("docker-compose") {
			DOCKER_COMPOSE_CMD = "docker-compose"
		} else {
			DOCKER_COMPOSE_CMD = "docker compose"
		}
	}

	DOCKER_CMD = "sudo " + DOCKER_COMPOSE_CMD

	// eval $DOCKER_CMD $COMPOSE_FILES up -d <svc...>
	up := func(svc string, line int) {
		name, a := instDockerArgs(DOCKER_CMD, COMPOSE_FILES, "up", "-d", svc)
		instAbort(sh.Run(name, a...), line)
	}

	if INSTALL_TYPE == "full" {
		// Stop any local Redis instances that might be running
		info("Checking for local Redis instances...")
		var redisProcess string
		if commandExists("lsof") {
			redisProcess, _ = sh.C("lsof", "-i", ":6379", "-sTCP:LISTEN").NoErr().Output()
		} else {
			redisProcess, _ = sh.C("ss", "-ltnp", "sport = :6379").NoErr().Output()
		}

		if redisProcess != "" {
			info("Found Redis running on port 6379, attempting to stop it...")

			// Check for systemd service
			if sh.C("systemctl", "is-active", "--quiet", "redis-server").NoErr().Run() == 0 {
				info("Stopping redis-server.service...")
				instAbort(sh.C("sudo", "systemctl", "stop", "redis-server").Quiet().Run(), 1443)
			} else if sh.C("systemctl", "is-active", "--quiet", "redis").NoErr().Run() == 0 {
				info("Stopping redis.service...")
				instAbort(sh.C("sudo", "systemctl", "stop", "redis").Quiet().Run(), 1446)
			} else {
				warning("Redis is running but not managed by systemd, please stop it manually if you encounter port conflicts")
			}
		} else {
			info("No local Redis instances found running on port 6379")
		}

		// Only start vLLM for full installation
		// First, ensure vLLM volume directory exists and has correct permissions
		info("Preparing vLLM volume directory...")
		vdir := PROJECT_ROOT + "/docker/vllm_data"
		if !ltIsDir(vdir) {
			if err := os.MkdirAll(vdir, 0o777); err != nil {
				instAbort(1, 1458)
			}

			// Set secure permissions: rwxr-xr-x (755)
			if err := os.Chmod(vdir, 0o755); err != nil {
				instAbort(1, 1462)
			}

			// Verify permissions were set correctly (cross-platform compatible)
			if commandExists("stat") {
				actualPerms := ""
				// Try Linux/GNU stat first
				if out, rc := sh.C("stat", "-c", "%a", vdir).NoErr().Output(); rc == 0 {
					actualPerms = out
				} else if out, rc := sh.C("stat", "-f", "%A", vdir).NoErr().Output(); rc == 0 {
					// Fall back to BSD/macOS stat
					actualPerms = out
				} else {
					actualPerms = out
				}

				if actualPerms != "" && actualPerms != "755" {
					warning("Failed to set secure permissions on vLLM data directory (got " + actualPerms + " instead of 755)")
				}
			}

			info("vLLM data directory created with secure permissions (755)")
		}

		// Monitor memory before starting GPU-intensive services
		instAbort(monitorMemoryDuringOperation("vLLM startup", 80), 1484)

		// First, start just vLLM since it needs significant GPU memory
		info("Starting vLLM service first...")
		info("Note: Initial startup may fail as the model needs to be downloaded. This is expected.")
		up("vllm", 1489)

		// Register container for cleanup
		registerContainer("vllm")

		// Prepare the model while GPU is clean
		instAbort(prepareVllmModel(), 1498)

		// Now start other services EXCEPT A2F and TTS-specific ones
		info("Starting other services...")
		// Use the correct whisper service based on user's choice
		whisperService := "whisper"
		if instSttChoice == "2" {
			whisperService = "fastwhisper"
		}

		// Define services to start based on TTS provider
		ttsServices := ""
		if TTS_PROVIDER == "rime" {
			ttsServices = "rime-model rime-api"
		}

		// Start support services with health monitoring
		supportServices := "miniprem-monitor redis grafana prometheus " + ttsServices + " flowise " + whisperService

		// `for service in $support_services` with IFS=$'\n\t': the spaces do NOT split, so
		// this is ONE iteration whose "service" is the whole string (and no health check
		// case matches it). Reproduced as-is.
		for _, service := range sh.SplitIFS(supportServices) {
			info("Starting " + service + "...")
			up(service, 1519)
			registerContainer(service)
			// Check health for critical services
			switch service {
			case "redis", "grafana", "prometheus", "flowise":
				instAbort(checkContainerHealth(service, 180, 10), 1525)
			}
		}

		// Monitor memory after starting all services
		instAbort(monitorMemoryDuringOperation("full service startup", 90), 1534)

	} else {
		// Default install: start monitor for container monitoring
		info("Starting MiniPrem Monitor for container monitoring...")
		up("miniprem-monitor", 1539)
		registerContainer("miniprem-monitor")
		instAbort(checkContainerHealth("miniprem-monitor", 120, 10), 1542)

		// If using RIME in default install, start the RIME services
		if TTS_PROVIDER == "rime" {
			info("Starting RIME services...")
			for _, service := range []string{"rime-model", "rime-api"} {
				up(service, 1551)
				registerContainer(service)
				instAbort(checkContainerHealth(service, 180, 10), 1554)
			}
		}
	}

	// Start Renny with internal speech processing (required for both installation types)
	info("Starting Renny digital human service with internal speech processing...")
	up("renny", 1564)
	registerContainer("renny")
	instAbort(checkContainerHealth("renny", 300, 15), 1567)

	// Final memory check
	instAbort(monitorMemoryDuringOperation("post-startup", 90), 1573)

	success(CHECKMARK + " MiniPrem services started successfully")
	info("All containers are running and healthy")
}

// checkGpuUsage (only used by show_progress_spinner; never called).
// bash: install_miniprem.sh:1580
func checkGpuUsage() {
	if commandExists("nvidia-smi") {
		// Get GPU count (unused, but the command still runs)
		cnt, _ := sh.C("nvidia-smi", "--query-gpu=count", "--format=csv,noheader,nounits").Output()
		_ = cnt

		// Query all GPUs and format output
		gpuStats, _ := sh.C("nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader").Output()

		// Display each GPU's stats with index
		gpuIndex := 0
		for _, line := range strings.Split(gpuStats, "\n") {
			gpuIndex++
			fmt.Printf("GPU %d: %s\n", gpuIndex, line)
		}
	} else {
		fmt.Println("GPU monitoring not available (nvidia-smi not found)")
	}
}

// showProgressSpinner (never called). bash: install_miniprem.sh:1600
func showProgressSpinner(message string, pid int) {
	spinner := []rune("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
	i := 0
	statusUpdateInterval := 15 // Show status update every 15 seconds
	counter := 0

	for syscall.Kill(pid, 0) == nil {
		i = (i + 1) % len(spinner)
		fmt.Print(sh.EchoE(`\r` + message + " " + string(spinner[i]) + " "))

		// Every 15 seconds, show GPU status
		if counter == statusUpdateInterval {
			fmt.Print("\n")
			fmt.Println(sh.Now().Format("15:04:05") + " - Checking GPU status...")
			checkGpuUsage()
			fmt.Print(sh.EchoE("\n" + `\r` + message + " " + string(spinner[i]) + " "))
			counter = 0
		}

		sh.Sleep(500 * time.Millisecond)
		counter++
	}
	fmt.Print("\r")
}

// prepareVllmModel is called as a bare statement from startMiniprem: its return 1 aborts
// the install. bash: install_miniprem.sh:1628
func prepareVllmModel() int {
	logSection("Preparing vLLM LLM")

	dockerCmd := "sudo docker"

	info("Step 1: Waiting for vLLM container to become ready...")
	maxAttempts := 30 // 5 minutes (30 * 10s)
	attempt := 1

	for attempt <= maxAttempts {
		name, a := instDockerArgs(dockerCmd, "inspect", "vllm")
		if sh.C(name, a...).Quiet().Run() == 0 {
			success(CHECKMARK + " vLLM container exists")
			break
		}

		info("Waiting for vLLM container to start... (" + strconv.Itoa(attempt) + "/" + strconv.Itoa(maxAttempts) + ")")
		sh.Sleep(10 * time.Second)
		attempt = attempt + 1
	}

	if attempt > maxAttempts {
		instFatal("vLLM container failed to start within timeout")
	}

	info("Step 2: Waiting for vLLM API to become available...")
	info("In a separate terminal, run 'sudo docker logs -f vllm' to watch progress...")

	// Use the shared exponential backoff health check
	if waitForService("http://localhost:8800/v1/models", 60, 5, "vLLM API") != 0 {
		warning("vLLM API did not become available within the expected timeframe.")
		warning("Will attempt to continue anyway, but LLM services might not work properly.")
		return 1
	}

	// Do a final validation test using chat completions endpoint
	info("Step 3: Validating chat completions functionality...")

	response, _ := sh.C("curl", "-s", "-X", "POST", "http://localhost:8800/v1/chat/completions",
		"-H", "Content-Type: application/json",
		"-d", instChatPayload).Output()

	if instGrepQ(response, "error") {
		// error_msg=$(echo "$response" | jq -r '.error.message' 2>/dev/null || echo "$response")
		var b strings.Builder
		jc := sh.C("jq", "-r", ".error.message").In(response + "\n").NoErr()
		jc.Stdout = &b
		if jc.Run() != 0 {
			b.WriteString(response + "\n")
		}
		errorMsg := strings.TrimRight(b.String(), "\n")
		warning("Chat completions validation failed: " + errorMsg)
		warning("LLM services may not work correctly with Flowise.")
		// Show the full response for debugging
		info("Full response:")
		instAbort(sh.C("jq", ".").In(response+"\n").Run(), 1683)
		return 1
	}

	success(CHECKMARK + " Chat completions validated successfully")
	// Show a snippet of the response
	info("Sample response:")
	// echo "$response" | jq -r '...' | head -n 1   (pipefail)
	var jb strings.Builder
	jqc := sh.C("jq", "-r", ".choices[0].message.content").In(response + "\n")
	jqc.Stdout = &jb
	jrc := jqc.Run()
	if raw := jb.String(); raw != "" {
		if i := strings.IndexByte(raw, '\n'); i >= 0 {
			raw = raw[:i+1]
		}
		fmt.Print(raw)
	}
	instAbort(jrc, 1689)

	// Show final GPU memory usage
	info("Final GPU memory usage:")
	finalGpuStats, _ := sh.C("docker", "exec", "vllm", "nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader").Output()
	finalGpuIdx := 0
	for _, line := range strings.Split(finalGpuStats, "\n") {
		finalGpuIdx++
		info("  GPU " + strconv.Itoa(finalGpuIdx) + ": " + line)
	}

	info("vLLM is ready for use with Flowise (use /v1/chat/completions endpoint)")
	return 0
}

// instAppendFile opens path for `>>`.
func instAppendFile(path string) *os.File {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o666)
	if err != nil {
		return nil
	}
	return f
}

// setupFlowiseChatflow: called as a bare statement, so a returned 1 aborts the install.
// bash: install_miniprem.sh:1706
func setupFlowiseChatflow() int {
	logSection("Setting up Flowise Chatflow")

	// Save current directory
	currentDir, _ := os.Getwd()

	// Create logs directory in project root
	os.MkdirAll(PROJECT_ROOT+"/logs", 0o777)

	// Define the log file path using the project root
	logFile := PROJECT_ROOT + "/logs/flowise_setup_error.log"

	// Wait for Flowise to be ready using shared health check
	info("Waiting for Flowise to be ready...")
	info("This may take several minutes as Flowise needs to start up and connect to vLLM")

	// Use the shared exponential backoff health check
	if waitForService("http://localhost:3000/", 60, 5, "Flowise UI") != 0 {
		warning("Flowise service did not become available within the expected timeframe.")
		warning("However, the container might still be starting up properly.")
		if !seedConfirm("Do you want to proceed with creating the chatflow anyway?") {
			warning("Chatflow setup skipped. You can run it manually later with: setup-chatflow-post-deployment.sh")
			os.Chdir(currentDir) // Return to original directory
			return 1
		}
	}

	// Run the chatflow setup script
	info("Creating Chatflow with Ollama integration...")

	// Initialize setup_result to error by default
	setupResult := 1

	// Determine location of setup script
	setupScript := PROJECT_ROOT + "/setup-chatflow-post-deployment.sh"

	if !ltIsFile(setupScript) {
		setupScript = ""
	}

	// Run the setup script if found
	if setupScript != "" {
		// bare `bash script` then `setup_result=$?`: a failure aborts before the assignment
		instAbort(sh.Run("bash", setupScript), 1748)
		setupResult = 0
	} else {
		// Log the error with details about what was searched
		instEchoToFile(logFile, "Error: setup-chatflow-post-deployment.sh script not found.", 1752)
		appendLine := func(s string) {
			if f := instAppendFile(logFile); f != nil {
				f.WriteString(s + "\n")
				f.Close()
			}
		}
		appendLine("Current directory: " + currentDir)
		appendLine("Files in current directory:")
		if f := instAppendFile(logFile); f != nil {
			sh.C("ls", "-la", currentDir).Out(f).Run()
			f.Close()
		}

		if lastComponent(currentDir) == "docker" {
			appendLine("Files in parent directory:")
			if f := instAppendFile(logFile); f != nil {
				sh.C("ls", "-la", parentDir(currentDir)).Out(f).Run()
				f.Close()
			}
		}
	}

	if setupResult != 0 {
		warning("Failed to setup Flowise chatflow automatically.")
		// Update the log file with additional details
		if f := instAppendFile(logFile); f != nil {
			f.WriteString("Setup script exited with status code: " + strconv.Itoa(setupResult) + "\n")
			f.Close()
		}
		warning("Check logs/flowise_setup_error.log for details on what went wrong.")
		warning("You may need to run 'setup-chatflow-post-deployment.sh' manually later.")
		os.Chdir(currentDir) // Return to original directory
		return 1
	}
	success(CHECKMARK + " Flowise chatflow setup completed")
	info("Please visit http://localhost:3000 to configure the chatflow as described in README_FLOWISE_SETUP.md")

	// Return to original directory
	os.Chdir(currentDir)
	return 0
}

// lastComponent is `basename "$p"`; parentDir is `dirname "$p"`.
func lastComponent(p string) string {
	p = strings.TrimRight(p, "/")
	if p == "" {
		return "/"
	}
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}

func parentDir(p string) string {
	p = strings.TrimRight(p, "/")
	i := strings.LastIndexByte(p, '/')
	switch {
	case i < 0:
		return "."
	case i == 0:
		return "/"
	}
	return strings.TrimRight(p[:i], "/")
}

// instWriteHeredoc is `cat > path << EOF` under errexit.
func instWriteHeredoc(path, content string, line int) {
	if err := os.WriteFile(path, []byte(content), 0o666); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %s\n", path, ltErrText(err))
		instAbort(1, line)
	}
}

// instChmodX is `chmod +x path` (a+x, minus bits set in the umask).
func instChmodX(path string, line int) {
	st, err := os.Stat(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "chmod: cannot access '%s': No such file or directory\n", path)
		instAbort(1, line)
	}
	um := syscall.Umask(0)
	syscall.Umask(um)
	if err := os.Chmod(path, st.Mode().Perm()|(0o111&^os.FileMode(um))); err != nil {
		instAbort(1, line)
	}
}

// buildFastWhisperImage. bash: install_miniprem.sh:1993
func buildFastWhisperImage() {
	logSection("Building Fast Whisper Docker Image")

	DOCKER_CMD = "sudo docker"

	info("Building fast-whisper image from Dockerfile...")

	// Check if required directories exist
	if !ltIsDir(PROJECT_ROOT + "/docker/fast-whisper") {
		instFatal("Fast Whisper directory not found at " + PROJECT_ROOT + "/docker/fast-whisper")
	}

	if !ltIsFile(PROJECT_ROOT + "/docker/fast-whisper/Dockerfile") {
		instFatal("Fast Whisper Dockerfile not found at " + PROJECT_ROOT + "/docker/fast-whisper/Dockerfile")
	}

	// Create the requirements.txt file if it doesn't exist
	if !ltIsFile(PROJECT_ROOT + "/docker/fast-whisper/requirements.txt") {
		fmt.Println("Creating requirements.txt for fast-whisper...")
		instWriteHeredoc(PROJECT_ROOT+"/docker/fast-whisper/requirements.txt", instFwRequirements, 2012)
	}

	// Create start.sh if it doesn't exist
	if !ltIsFile(PROJECT_ROOT + "/docker/fast-whisper/start.sh") {
		fmt.Println("Creating start.sh for fast-whisper...")
		instWriteHeredoc(PROJECT_ROOT+"/docker/fast-whisper/start.sh", instFwStart, 2028)
		instChmodX(PROJECT_ROOT+"/docker/fast-whisper/start.sh", 2033)
	}

	// Create app directory and main.py if they don't exist
	if err := os.MkdirAll(PROJECT_ROOT+"/docker/fast-whisper/app", 0o777); err != nil {
		instAbort(1, 2037)
	}
	if !ltIsFile(PROJECT_ROOT + "/docker/fast-whisper/app/main.py") {
		fmt.Println("Creating main.py for fast-whisper...")
		instWriteHeredoc(PROJECT_ROOT+"/docker/fast-whisper/app/main.py", instFwMain, 2040)
	}

	// Build the Docker image: the bare subshell aborts on failure (errexit), so the
	// `if [ $? -ne 0 ]` fatal is dead.
	name, a := instDockerArgs(DOCKER_CMD, "build", "-t", "fast-whisper-optimized", "-f", "fast-whisper/Dockerfile", "./fast-whisper")
	instAbort(sh.C(name, a...).InDir(PROJECT_ROOT+"/docker").Run(), 2123)

	success(CHECKMARK + " Fast Whisper Docker image built successfully")
}

// pullDockerWithTtsProvider. bash: install_miniprem.sh:2135
func pullDockerWithTtsProvider() {
	// Export our TTS_PROVIDER so that the docker.sh script can access it
	if TTS_PROVIDER != "" {
		os.Setenv("TTS_PROVIDER", TTS_PROVIDER)
	}
	// Call the pull_docker_images function from scripts/docker.sh
	pullDockerImages()
}
