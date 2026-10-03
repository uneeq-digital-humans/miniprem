package mp

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// Port of the system-check / service-setup parts of install_miniprem.sh.
// NOTE: command_exists (install_miniprem.sh:160) is the already-defined commandExists in
// lib_docker.go (identical body).

var instAwkNumRe = regexp.MustCompile(`^[ \t]*[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?`)

// instAwkNum is awk's string-to-number conversion of a field (numeric prefix, else 0).
func instAwkNum(s string) float64 {
	m := instAwkNumRe.FindString(s)
	if m == "" {
		return 0
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(m), 64)
	if err != nil {
		return 0
	}
	return f
}

// instTestInt parses the operand of `[ $x -lt|-gt N ]`; ok is false when `[` would raise
// an error (empty / non-integer), which makes the test fail.
func instTestInt(s string) (int, bool) {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		return 0, false
	}
	return n, true
}

// instLT / instGT are `[ $s -lt N ]` / `[ $s -gt N ]` in a condition.
func instLT(s string, n int) bool {
	v, ok := instTestInt(s)
	return ok && v < n
}

func instGT(s string, n int) bool {
	v, ok := instTestInt(s)
	return ok && v > n
}

// instFreeField is `free ... | awk 'NR==2{print $f}'`.
func instFreeField(out string, f int) string {
	lines := ltLines(out)
	if len(lines) < 2 {
		return ""
	}
	return ltAwkField(lines[1], f)
}

// instMemPercent is `free | awk 'NR==2{printf "%.0f", $3*100/$2}'` ("" on division by zero).
func instMemPercent(out string) string {
	lines := ltLines(out)
	if len(lines) < 2 {
		return ""
	}
	total := instAwkNum(ltAwkField(lines[1], 2))
	used := instAwkNum(ltAwkField(lines[1], 3))
	if total == 0 {
		return ""
	}
	return fmt.Sprintf("%.0f", used*100/total)
}

// checkDiskSpace. bash: install_miniprem.sh:165
func checkDiskSpace(requiredGB int, path string) {
	out, _ := sh.C("df", path).Output()
	availableGB := ""
	if lines := ltLines(out); len(lines) >= 2 {
		availableGB = strconv.FormatInt(int64(instAwkNum(ltAwkField(lines[1], 4))/1024/1024), 10)
	}

	if instLT(availableGB, requiredGB) {
		instFatal("Insufficient disk space. Required: " + strconv.Itoa(requiredGB) + "GB, Available: " + availableGB + "GB on " + path)
	}

	success(CHECKMARK + " Sufficient disk space: " + availableGB + "GB available (required: " + strconv.Itoa(requiredGB) + "GB)")
}

// checkMemoryUsage returns the function status (1 = above threshold). bash: install_miniprem.sh:178
func checkMemoryUsage(thresholdPercent int) int {
	if commandExists("free") {
		out, _ := sh.C("free").Output()
		memoryPercent := instMemPercent(out)
		if instGT(memoryPercent, thresholdPercent) {
			warning("High memory usage: " + memoryPercent + "% (threshold: " + strconv.Itoa(thresholdPercent) + "%)")
			warning("Consider freeing up memory before proceeding")
			return 1
		}
		success(CHECKMARK + " Memory usage acceptable: " + memoryPercent + "%")
		return 0
	}
	info("Memory check skipped (free command not available)")
	return 0
}

// validateSystemResources. A bare `check_memory_usage` returning 1 aborts (errexit).
// bash: install_miniprem.sh:198
func validateSystemResources() {
	logSection("Validating System Resources")

	// Check disk space (64GB minimum for full installation, 20GB for default)
	requiredSpace := 20
	if INSTALL_TYPE == "full" {
		requiredSpace = 64
	}

	checkDiskSpace(requiredSpace, "/")

	// Check memory usage
	instAbort(checkMemoryUsage(85), 210)

	// Check available RAM (minimum 16GB)
	if commandExists("free") {
		out, _ := sh.C("free", "-g").Output()
		totalGB := instFreeField(out, 2)
		if instLT(totalGB, 16) {
			warning("Low total RAM: " + totalGB + "GB (recommended: 16GB or more)")
		} else {
			success(CHECKMARK + " Sufficient RAM: " + totalGB + "GB")
		}
	}
}

var (
	instAddrRe = regexp.MustCompile(`^[a-zA-Z0-9.-]+$`)
	instPortRe = regexp.MustCompile(`^[0-9]+$`)
)

// validateCloudService (never called). bash: install_miniprem.sh:224
func validateCloudService(address, port string) {
	// Input validation for address (hostname or IP)
	if !instAddrRe.MatchString(address) {
		logError("Invalid address format: " + address)
		instFatal("Address must contain only alphanumeric characters, dots, and hyphens")
	}

	// Input validation for port (must be numeric, 1-65535)
	if !instPortRe.MatchString(port) || instLT(port, 1) || instGT(port, 65535) {
		logError("Invalid port number: " + port)
		instFatal("Port must be a number between 1 and 65535")
	}

	// Perform a curl request to the given address and port (using validated inputs)
	response, rc := sh.C("curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://"+address+":"+port).Output()
	instAbort(rc, 241)

	// Check if the response code is 200 (OK)
	if v, ok := instTestInt(response); ok && v == 200 {
		fmt.Println("Success: Service at " + address + ":" + port + " is reachable.")
	} else {
		fmt.Println("Error: Service at " + address + ":" + port + " is not reachable. HTTP status code: " + response)
		sh.Exit(1)
	}
}

// waitForService is only used inside `if !` conditions. bash: install_miniprem.sh:425
func waitForService(url string, maxAttempts, baseDelay int, serviceName string) int {
	attempt := 1

	info("Waiting for " + serviceName + " to become available...")

	for attempt <= maxAttempts {
		if sh.Run("curl", "--output", "/dev/null", "--silent", "--fail", "--max-time", "2", url) == 0 {
			success(CHECKMARK + " " + serviceName + " is ready")
			return 0
		}

		// Show progress with exponential backoff
		delay := baseDelay * attempt
		if delay > 30 {
			delay = 30 // Cap at 30 seconds
		}

		if attempt%6 == 0 {
			info("Still waiting for " + serviceName + "... (attempt " + strconv.Itoa(attempt) + "/" + strconv.Itoa(maxAttempts) + ", " + strconv.Itoa(delay) + "s delay)")
		} else {
			fmt.Print(".")
		}

		sh.Sleep(time.Duration(delay) * time.Second)
		attempt = attempt + 1
	}

	fmt.Print("\n")
	warning(serviceName + " did not become available within timeout")
	return 1
}

// validateNetworkConnectivity: called as a bare statement; fatal exits.
// bash: install_miniprem.sh:462
func validateNetworkConnectivity(host string, timeout int) {
	t := strconv.Itoa(timeout)

	// Use curl instead of ping since many servers block ICMP
	// Try HTTPS first, then HTTP as fallback
	if sh.C("curl", "--max-time", t, "--silent", "--fail", "--output", "/dev/null", "https://"+host).NoErr().Run() == 0 {
		success(CHECKMARK + " Network connectivity to " + host + " verified (HTTPS)")
		return
	} else if sh.C("curl", "--max-time", t, "--silent", "--head", "--output", "/dev/null", "https://"+host).NoErr().Run() == 0 {
		success(CHECKMARK + " Network connectivity to " + host + " verified (HTTPS, any status)")
		return
	} else if sh.C("curl", "--max-time", t, "--silent", "--head", "--output", "/dev/null", "http://"+host).NoErr().Run() == 0 {
		success(CHECKMARK + " Network connectivity to " + host + " verified (HTTP)")
		return
	}
	// Final fallback: check if DNS resolves
	if sh.C("nslookup", host).Quiet().Run() == 0 || sh.C("host", host).Quiet().Run() == 0 {
		warning("DNS resolves but HTTP/HTTPS connection failed for " + host)
		info("This may be normal if the server requires specific paths or authentication")
		return
	}
	instFatal("Cannot reach " + host + " within " + t + " seconds (tried HTTPS, HTTP, and DNS)")
}

// retryNetworkOperation: `retry_network_operation max base cmd...` (never called); cmd is
// the command to run. bash: install_miniprem.sh:489
func retryNetworkOperation(maxAttempts, baseDelay int, cmd func() int) int {
	attempt := 1

	for attempt <= maxAttempts {
		if cmd() == 0 {
			return 0
		}

		if attempt < maxAttempts {
			delay := baseDelay * attempt
			warning("Operation failed, retrying in " + strconv.Itoa(delay) + "s (attempt " + strconv.Itoa(attempt) + "/" + strconv.Itoa(maxAttempts) + ")")
			sh.Sleep(time.Duration(delay) * time.Second)
		}

		attempt = attempt + 1
	}

	logError("Operation failed after " + strconv.Itoa(maxAttempts) + " attempts")
	return 1
}

var instHTTPStatusRe = regexp.MustCompile(`^HTTP/1\.[01] [0-9]{3}`)

// checkWssService. bash: install_miniprem.sh:514
func checkWssService(url string) {
	// Map ws/wss to http/https for curl.
	probeURL := strings.Replace(url, "wss:", "https:", 1)
	probeURL = strings.Replace(probeURL, "ws:", "http:", 1)

	info("Testing WebSocket connection to " + url + "...")

	validKey, orc := sh.C("openssl", "rand", "-base64", "16").Output()
	instAbort(orc, 526)

	response, curlExit := sh.C("curl", "-sS", "-i", "--http1.1",
		"--connect-timeout", "5",
		"--max-time", "20",
		"-H", "Connection: Upgrade",
		"-H", "Upgrade: websocket",
		"-H", "Sec-WebSocket-Key: "+validKey,
		"-H", "Sec-WebSocket-Version: 13",
		probeURL).Combined()

	// Pull the first HTTP status line out of curl's combined output.
	statusLine := ""
	for _, l := range strings.Split(response, "\n") {
		if instHTTPStatusRe.MatchString(l) {
			statusLine = l
			break
		}
	}

	if statusLine != "" {
		info("  Response: " + statusLine)
		success(CHECKMARK + " Service at " + url + " is reachable.")
	} else {
		warning(CROSS + " Could not verify " + url + " (curl exit " + strconv.Itoa(curlExit) + ", no HTTP status line).")
		warning("Installation will continue — verify network allows port 443 outbound before starting Renny.")
	}
}

// checkCloudServices. bash: install_miniprem.sh:652
func checkCloudServices(dhopAddress, dhopPsAddress string) {
	logSection("Check Cloud Service Accessibility")

	// Check if the DHOP address is reachable
	checkWssService(dhopAddress)

	// Check if the DHOP pixel streaming address is reachable
	checkWssService(dhopPsAddress)
}

// instProcInfo is the lsof/ss "name pid" probe (`... | awk ... | head -n1 || true`).
func instProcInfo(port string) string {
	if commandExists("lsof") {
		out, _ := sh.C("lsof", "-i", ":"+port, "-sTCP:LISTEN", "-nP").NoErr().Output()
		lines := ltLines(out)
		for i, l := range lines {
			if i == 0 { // NR>1
				continue
			}
			return ltAwkField(l, 1) + " " + ltAwkField(l, 2)
		}
		return ""
	}
	out, _ := sh.C("ss", "-ltnp", "sport = :"+port).NoErr().Output()
	if out != "" {
		out += "\n"
	}
	// The awk program has an unterminated regex literal (upstream defect); run the real awk
	// so its behaviour/diagnostics are whatever the host awk does.
	res, _ := sh.C("awk", `NR>1 {gsub(/users:\(\(","",$NF); split($NF,a,","); print a[1], a[2]}`).In(out).Output()
	if lines := ltLines(res); len(lines) > 0 {
		return lines[0]
	}
	return ""
}

// checkEnvironment. bash: install_miniprem.sh:1797
func checkEnvironment() {
	logSection("Checking Environment")

	// Safeguard: Ensure INSTALL_TYPE is set (should be set by prompt_for_install_type)
	if INSTALL_TYPE == "" {
		// Try to read from marker file as fallback
		if ltIsFile(PROJECT_ROOT + "/.miniprem_install_type") {
			b, _ := os.ReadFile(PROJECT_ROOT + "/.miniprem_install_type")
			INSTALL_TYPE = strings.TrimRight(string(b), "\n")
			info("Recovered installation type from marker file: " + INSTALL_TYPE)
		} else {
			instFatal("INSTALL_TYPE is not set. This should not happen. Please report this bug.")
		}
	}

	// Determine docker-compose command (v1 or v2)
	if commandExists("docker-compose") {
		DOCKER_COMPOSE_CMD = "docker-compose"
	} else {
		DOCKER_COMPOSE_CMD = "docker compose"
	}

	DOCKER_CMD = "sudo " + DOCKER_COMPOSE_CMD

	// First, stop any existing miniprem containers
	info("Stopping any existing Miniprem containers...")

	if ltIsFile(PROJECT_ROOT + "/miniprem.sh") {
		sh.C(PROJECT_ROOT+"/miniprem.sh", "stop").Quiet().Run()
		success(CHECKMARK + " Existing Miniprem containers stopped using miniprem.sh")
	} else if ltIsDir(PROJECT_ROOT + "/docker") {
		name, a := instDockerArgs(DOCKER_CMD, "down")
		sh.C(name, a...).InDir(PROJECT_ROOT + "/docker").Quiet().Run()
		success(CHECKMARK + " Existing Miniprem containers stopped using docker compose")
	} else {
		info("No existing Miniprem containers found")
	}

	if INSTALL_TYPE == "full" {
		// Only check for common local daemon ports that might conflict
		portMap := []string{"6379:Redis"}
		found := 0
		boxWidth := 65 // Fixed width for the box

		for _, portEntry := range portMap {
			// Split entry into port and service name
			port := portEntry[:strings.Index(portEntry, ":")]
			service := portEntry[strings.Index(portEntry, ":")+1:]

			// Try lsof first, fallback to ss
			procInfo := instProcInfo(port)
			if procInfo != "" {
				procName := ltAwkField(procInfo, 1)
				procPid := ltAwkField(procInfo, 2)
				// Special handling for redis-server on 6379
				if port == "6379" && procName == "redis-server" {
					fmt.Print(ltEchoE(`\nRedis appears to be running locally on port 6379.`))
					if seedConfirm("Would you like to try stopping it automatically?") {
						sh.Run("sudo", "service", "redis-server", "stop")
						sh.Run("sudo", "systemctl", "stop", "redis")
						// Re-check if port is still in use
						procInfo = instProcInfo(port)
						if procInfo == "" {
							success(CHECKMARK + " Successfully stopped redis-server on port 6379.")
							continue
						}
						warning("redis-server is still running on port 6379. Please stop it manually.")
					}
				}

				found = 1
				// Create horizontal border line with consistent width
				border := strings.Repeat("-", boxWidth)

				fmt.Print(ltEchoE(`\n+` + border + `+`))
				fmt.Printf("| %s |\n", ltPadBytes("⚠️  LOCAL SERVICE CONFLICT DETECTED", boxWidth))
				fmt.Println("+" + border + "+")

				// Format each line with proper right alignment
				fmt.Printf("| Port %s is in use by local process '%s' (PID %s) |\n", ltPadBytes(port, 5), ltPadBytes(procName, 12), ltPadBytes(procPid, 6))
				fmt.Printf("| %s |\n", ltPadBytes("", boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("This will prevent the "+service+" service from starting", boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("correctly. You appear to have a local instance of "+service, boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("running on your system.", boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("", boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("To resolve:", boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("    sudo kill "+procPid, boxWidth))
				fmt.Printf("| %s |\n", ltPadBytes("Then re-run this installer.", boxWidth))
				fmt.Println("+" + border + "+")
			}
		}
		if found == 1 {
			fmt.Print(ltEchoE(`\n\e[1;33m[WARNING] Local service conflicts detected.\e[0m`))
			if seedIsInteractive() {
				if _, ok := sh.ReadLine(sh.ReadOpts{Prompt: "Press Enter to exit and resolve the conflict(s)..."}); !ok {
					instAbort(1, 1902)
				}
			}
			instLineno = 1904
			sh.Exit(1)
		}
	}
}

// checkDuplicateInstallations. bash: install_miniprem.sh:1910
func checkDuplicateInstallations() {
	logSection("Checking for Duplicate Installations")

	// Create a marker file if it doesn't exist yet
	markerFile := PROJECT_ROOT + "/.miniprem_installation_marker"
	if !ltIsFile(markerFile) {
		f, err := os.OpenFile(markerFile, os.O_WRONLY|os.O_CREATE, 0o666)
		if err != nil {
			fmt.Fprintf(os.Stderr, "touch: cannot touch '%s': %s\n", markerFile, ltErrText(err))
			instAbort(1, 1916)
		}
		f.Close()
		info("Created installation marker file: " + markerFile)
	}

	info("Searching for duplicate MiniPrem installations in common locations...")

	// Define likely installation locations (much faster, safer search)
	searchPaths := []string{os.Getenv("HOME"), "/opt", "/usr/local", "/var/lib"}

	// Search only likely locations with depth limit
	miniPremDirs := ""
	for _, searchPath := range searchPaths {
		if ltIsDir(searchPath) {
			// maxdepth 4: prevents deep recursion, finds most installations
			// timeout 30s: prevents hanging on network mounts
			found, _ := sh.C("timeout", "30s", "find", searchPath, "-maxdepth", "4", "-type", "d", "-iname", "*miniprem*",
				"-not", "-path", `*/\.git/*`,
				"-not", "-path", "*/node_modules/*",
				"-not", "-path", PROJECT_ROOT,
				"-not", "-path", PROJECT_ROOT+"/*").NoErr().Output()

			if found != "" {
				miniPremDirs = miniPremDirs + "\n" + found
			}
		}
	}

	// Remove leading/trailing newlines and get count (sed '/^$/d')
	var kept []string
	for _, l := range strings.Split(miniPremDirs, "\n") {
		if l != "" {
			kept = append(kept, l)
		}
	}
	miniPremDirs = strings.Join(kept, "\n")
	// grep -c "^" over `echo "$dirs"`: an empty value still prints one (empty) line
	dirCount := len(kept)
	if dirCount == 0 {
		dirCount = 1
	}

	if dirCount > 0 && miniPremDirs != "" {
		boxWidth := 75 // Fixed width for the box
		border := strings.Repeat("-", boxWidth)

		fmt.Print(ltEchoE(`\n+` + border + `+`))
		fmt.Printf("| %s |\n", ltPadBytes("⚠️  MULTIPLE MINIPREM INSTALLATIONS DETECTED", boxWidth))
		fmt.Println("+" + border + "+")

		fmt.Printf("| %s |\n", ltPadBytes("Found "+strconv.Itoa(dirCount)+" other directories with 'miniprem' in their name:", boxWidth))

		for _, dir := range kept {
			dir = strings.Trim(dir, "\t") // read -r with IFS=$'\n\t'
			if dir != "" {
				// Truncate path if too long
				displayPath := dir
				if r := []rune(displayPath); len(r) > boxWidth-4 {
					displayPath = "..." + string(r[len(r)-boxWidth+7:])
				}
				fmt.Printf("| %s |\n", ltPadBytes("  - "+displayPath, boxWidth))
			}
		}

		fmt.Printf("| %s |\n", ltPadBytes("", boxWidth))
		fmt.Printf("| %s |\n", ltPadBytes("Having multiple installations may cause conflicts and unexpected behavior.", boxWidth))
		fmt.Printf("| %s |\n", ltPadBytes("It's recommended to use only one installation of MiniPrem.", boxWidth))
		fmt.Println("+" + border + "+")

		if seedConfirm("Do you want to continue with this installation despite duplicates?") {
			warning("Continuing with installation despite duplicate installations detected.")
		} else {
			instFatal("Installation aborted due to multiple MiniPrem installations detected.")
		}
	} else {
		success(CHECKMARK + " No duplicate MiniPrem installations detected.")
	}
}

// enableSystemdAutostart returns the function status (1 = could not enable the unit); the
// caller is a bare statement, so that aborts. bash: install_miniprem.sh:2143
func enableSystemdAutostart() int {
	logSection("Enabling MiniPrem Auto-start at Boot")

	// Only meaningful on systemd-based Linux (Ubuntu workstations qualify).
	if !commandExists("systemctl") || !ltIsDir("/run/systemd/system") {
		info("systemd not detected, skipping auto-start setup")
		return 0
	}

	// Must be root to write unit files and enable services.
	idOut, _ := sh.C("id", "-u").Output()
	if n, ok := instTestInt(idOut); ok && n != 0 {
		warning("Not running as root; skipping auto-start setup.")
		warning("Re-run the installer with sudo to enable boot-time auto-start.")
		return 0
	}

	unitPath := "/etc/systemd/system/miniprem.service"
	tmpUnit, err := sh.MkTemp("")
	if err != nil {
		instAbort(1, 2161)
	}

	instWriteHeredoc(tmpUnit, strings.ReplaceAll(instSystemdUnit, "@ROOT@", PROJECT_ROOT), 2163)

	// Idempotent install: only rewrite the unit if content differs.
	if ltIsFile(unitPath) && sh.C("cmp", "-s", tmpUnit, unitPath).Run() == 0 {
		info("miniprem.service already up-to-date at " + unitPath)
		os.Remove(tmpUnit)
	} else {
		instAbort(sh.Run("install", "-m", "0644", tmpUnit, unitPath), 2188)
		os.Remove(tmpUnit)
		success(CHECKMARK + " Wrote " + unitPath)
		instAbort(sh.Run("systemctl", "daemon-reload"), 2191)
	}

	// Make sure dockerd itself comes up at boot.
	if sh.C("systemctl", "is-enabled", "--quiet", "docker.service").NoErr().Run() != 0 {
		if sh.C("systemctl", "enable", "docker.service").Quiet().Run() == 0 {
			success(CHECKMARK + " Enabled docker.service at boot")
		} else {
			warning("Could not enable docker.service; check 'systemctl status docker'")
		}
	} else {
		info("docker.service already enabled at boot")
	}

	// Enable miniprem.service for boot. Do NOT --now.
	if sh.C("systemctl", "enable", "miniprem.service").Quiet().Run() == 0 {
		success(CHECKMARK + " miniprem.service enabled — will auto-start at boot")
	} else {
		logError("Failed to enable miniprem.service")
		return 1
	}

	info("Verify with: systemctl status miniprem.service")
	info("Disable with: sudo systemctl disable miniprem.service")
	return 0
}

// createDesktopShortcut. bash: install_miniprem.sh:2219
func createDesktopShortcut() {
	home := os.Getenv("HOME")
	// Only create shortcut if running Ubuntu Desktop (has desktop environment)
	if !ltIsDir(home+"/Desktop") || os.Getenv("XDG_CURRENT_DESKTOP") == "" {
		info("Desktop environment not detected, skipping shortcut creation")
		return
	}

	logSection("Creating Desktop Shortcut")

	desktopFile := home + "/Desktop/Start-MiniPrem.desktop"

	// Check if shortcut already exists and points to the correct location
	if ltIsFile(desktopFile) {
		// Check if existing shortcut points to same PROJECT_ROOT
		b, _ := os.ReadFile(desktopFile)
		if instGrepQ(string(b), "Path="+PROJECT_ROOT) {
			info("Desktop shortcut already exists and is up-to-date")
			return
		}
		// Update existing shortcut with new path
		info("Updating existing desktop shortcut with new path")
	}

	// Create or update the .desktop file
	instWriteHeredoc(desktopFile, strings.ReplaceAll(instDesktopEntry, "@ROOT@", PROJECT_ROOT), 2244)

	// Set proper permissions
	instChmodX(desktopFile, 2260)

	// Mark as trusted (bypasses "Allow Launching" prompt in Ubuntu)
	if commandExists("gio") {
		sh.C("gio", "set", desktopFile, "metadata::trusted", "true").NoErr().Run()
	}

	// Alternative method: set execute bit on the file (older Ubuntu versions)
	if st, err := os.Stat(desktopFile); err != nil {
		instAbort(1, 2269)
	} else if err := os.Chmod(desktopFile, st.Mode().Perm()|0o100); err != nil {
		instAbort(1, 2269)
	}

	success(CHECKMARK + " Desktop shortcut created: ~/Desktop/Start-MiniPrem.desktop")
	info("Double-click 'Start MiniPrem' on your desktop to launch after reboot")
}

// monitorMemoryDuringOperation returns 1 above the threshold (a bare call site aborts).
// bash: install_miniprem.sh:1322
func monitorMemoryDuringOperation(operationName string, thresholdPercent int) int {
	if commandExists("free") {
		out, _ := sh.C("free").Output()
		memoryPercent := instMemPercent(out)
		if instGT(memoryPercent, thresholdPercent) {
			warning("High memory usage during " + operationName + ": " + memoryPercent + "%")
			warning("This may affect operation performance")
			return 1
		}
	}
	return 0
}

var instYesRe = regexp.MustCompile(`^(y|yes)$`)

// promptCustomServices. bash: install_miniprem.sh:2276
func promptCustomServices() {
	templateFile := PROJECT_ROOT + "/docker/docker-compose.custom.template.yml"
	customFile := PROJECT_ROOT + "/docker/docker-compose.custom.yml"
	mergeScript := PROJECT_ROOT + "/docker/scripts/merge-compose.sh"

	instPrintEcho(instCustomBanner, "")

	// Non-interactive path: a pre-authored file may be supplied; otherwise skip.
	if seedIsNonInteractive() {
		if CUSTOM_SERVICES_FILE_SEED != "" {
			if !ltIsFile(CUSTOM_SERVICES_FILE_SEED) {
				instFatal("MINIPREM_SEED_CUSTOM_SERVICES_FILE points to a missing file: " + CUSTOM_SERVICES_FILE_SEED)
			}
			info("Installing custom services from seeded file: " + CUSTOM_SERVICES_FILE_SEED)
			if !instCopyFile(CUSTOM_SERVICES_FILE_SEED, customFile) {
				instFatal("Failed to copy custom services file into " + customFile)
			}
			if ltIsFile(mergeScript) {
				if sh.Run(mergeScript, "--prefer-custom") != 0 {
					warning("Custom services merge reported issues; review docker-compose.override.yml")
				}
			}
			return
		}
		switch ltOr(CUSTOM_SERVICES_CHOICE, "no") {
		case "y", "yes", "Y", "YES", "Yes":
			warning("MINIPREM_SEED_CUSTOM_SERVICES=yes but no MINIPREM_SEED_CUSTOM_SERVICES_FILE provided; skipping (non-interactive cannot open editor).")
		default:
			info("Skipping custom services setup (non-interactive).")
		}
		return
	}

	info("Would you like to add custom Docker services (database, cache, etc.)?")
	fmt.Println("")

	maxRetries := 3
	attempts := 0

	for attempts < maxRetries {
		userResponse := readOrDie("Add custom services? [y/N]: ")

		// Default to 'no' if user just presses enter
		if userResponse == "" {
			userResponse = "n"
		}

		switch strings.ToLower(userResponse) {
		case "y", "yes":
			info("Setting up custom services configuration...")

			// Check if template file exists
			if !ltIsFile(templateFile) {
				warning("Template file not found: " + templateFile)
				info("You can add custom services later with: ./miniprem.sh custom add")
				return
			}

			// Copy template to custom file
			if !instCopyFile(templateFile, customFile) {
				warning("Failed to copy template file")
				info("You can manually copy it with: cp " + templateFile + " " + customFile)
				return
			}

			success(CHECKMARK + " Created docker-compose.custom.yml from template")

			// Detect and launch editor
			editor := os.Getenv("EDITOR")
			if editor == "" {
				// Try to detect available editors in order of preference
				if commandExists("code") {
					editor = "code"
				} else if commandExists("nano") {
					editor = "nano"
				} else if commandExists("vim") {
					editor = "vim"
				} else if commandExists("vi") {
					editor = "vi"
				} else {
					warning("No suitable editor found. Please edit manually: " + customFile)
					info("You can add custom services later with: ./miniprem.sh custom add")
					return
				}
			}

			info("Opening " + customFile + " in " + editor + "...")
			info("Uncomment and modify the services you need, then save and exit.")
			fmt.Println("")
			readOrDie("Press Enter to open the editor...")

			// Open editor and wait for user to finish
			if editor == "code" {
				// VSCode: open and wait for window to close
				instAbort(sh.Run(editor, "--wait", customFile), 2375)
			} else {
				// Terminal editors
				instAbort(sh.Run(editor, customFile), 2378)
			}

			// Validate YAML syntax
			info("Validating YAML syntax...")
			if commandExists("yq") {
				if sh.C("yq", "eval", ".", customFile).Quiet().Run() != 0 {
					warning("YAML syntax validation failed")
					reedit := readOrDie("Would you like to re-edit the file? [y/N]: ")
					if instYesRe.MatchString(strings.ToLower(reedit)) {
						instAbort(sh.Run(editor, customFile), 2388)
						// Re-validate after editing
						if sh.C("yq", "eval", ".", customFile).Quiet().Run() != 0 {
							warning("YAML syntax still invalid. Skipping merge.")
							info("Fix the YAML syntax and run: " + mergeScript)
							return
						}
					} else {
						info("Fix the YAML syntax and run: " + mergeScript)
						return
					}
				}
				success(CHECKMARK + " YAML syntax is valid")
			} else {
				info("yq not found, skipping YAML validation")
				info("Install yq for validation: brew install yq (macOS)")
			}

			// Check if merge script exists
			if !ltIsFile(mergeScript) {
				warning("Merge script not found: " + mergeScript)
				info("Your custom services file has been created at: " + customFile)
				info("You'll need to manually integrate it with docker-compose")
				return
			}

			// Run merge script with --check first.
			// `"$merge_script" --check 2>&1 | grep -q "conflict"` under pipefail: a non-zero
			// merge status (2 = conflicts) makes the whole pipeline fail even when grep matched.
			info("Checking for conflicts with official services...")
			checkOut, mrc := sh.C(mergeScript, "--check").Combined()
			grc := 1
			if instGrepQ(checkOut, "conflict") {
				grc = 0
			}
			if pipeStatus(mrc, grc) == 0 {
				warning("Conflicts detected between custom and official services")
				fmt.Println("")
				out2, mrc2 := sh.C(mergeScript, "--check").Combined()
				grc2 := 1
				reWC := regexp.MustCompile(`WARN|conflict`)
				for _, l := range strings.Split(out2, "\n") {
					if reWC.MatchString(l) {
						fmt.Println(l)
						grc2 = 0
					}
				}
				instAbort(pipeStatus(mrc2, grc2), 2419)
				fmt.Println("")
				if !seedConfirm("Continue with merge? Custom services will override official ones.") {
					info("Skipping merge. Edit " + customFile + " to resolve conflicts.")
					info("Run merge manually when ready: " + mergeScript)
					return
				}
			}

			// Perform the merge
			info("Merging custom services with official configuration...")
			if mergeExit := sh.Run(mergeScript, "--prefer-custom"); mergeExit == 0 {
				success(CHECKMARK + " Custom services merged successfully")
				success(CHECKMARK + " Generated: " + PROJECT_ROOT + "/docker/docker-compose.override.yml")
				fmt.Println("")
				info("Your custom services have been configured!")
				info("Restart MiniPrem to apply changes: " + PROJECT_ROOT + "/miniprem.sh restart")
			} else {
				if mergeExit == 2 {
					warning("Merge completed with conflicts (resolved automatically)")
					info("Review the generated file: " + PROJECT_ROOT + "/docker/docker-compose.override.yml")
					info("Restart MiniPrem to apply changes: " + PROJECT_ROOT + "/miniprem.sh restart")
				} else {
					warning("Merge failed. Check the error messages above.")
					info("You can retry manually with: " + mergeScript)
					return
				}
			}

			return
		case "n", "no":
			info("Skipping custom services setup")
			info("You can add custom services later with: ./miniprem.sh custom add")
			return
		default:
			attempts = attempts + 1
			if attempts < maxRetries {
				fmt.Println("Please enter 'y' or 'n'. (Attempt " + strconv.Itoa(attempts) + "/" + strconv.Itoa(maxRetries) + ")")
			} else {
				warning("Invalid response after " + strconv.Itoa(maxRetries) + " attempts. Skipping custom services.")
				info("You can add custom services later with: ./miniprem.sh custom add")
				return
			}
		}
	}
}
