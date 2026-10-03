package mp

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/uneeq-digital-humans/miniprem/internal/sh"
)

// cliDockerCompose runs `$DOCKER_CMD compose $COMPOSE_FILE <extra...>` (both unquoted:
// word-split on blanks) with the given stderr; returns the status.
func cliDockerCompose(stderr io.Writer, extra ...string) int {
	a := append(dockerFields(DOCKER_CMD), "compose")
	a = append(a, dockerFields(cliComposeFile)...)
	a = append(a, extra...)
	c := sh.C(a[0], a[1:]...)
	if stderr != nil {
		c.Err(stderr)
	}
	return c.Run()
}

// bash: miniprem.sh:264
func cliStartServices() int {
	logSection("Starting MiniPrem Services")

	envFile := PROJECT_ROOT + "/docker/docker-compose.env"
	if !ltIsFile(envFile) {
		cliEcho("")
		logError("Environment file not found: " + envFile)
		cliEcho("")
		cliEcho("Run the Docker install script first:")
		cliEcho("  ./docker/scripts/install_miniprem.sh")
		cliEcho("")
		cliEcho("Or use: ./miniprem.sh deploy")
		cliEcho("")
		sh.Exit(1)
	}

	if ensureHarborCredentials() != 0 {
		fatal("Cannot start services without valid Harbor credentials")
	}

	startDockerCompose(cliComposeFile)
	return 0
}

// bash: miniprem.sh:289
func cliStopServices() int {
	logSection("Stopping MiniPrem Services")
	stopDockerCompose(cliComposeFile)
	return 0
}

// bash: miniprem.sh:294
func cliRestartServices() int {
	logSection("Restarting MiniPrem Services")
	cliStopServices()
	return cliStartServices()
}

// bash: miniprem.sh:300
func cliCheckStatus() int {
	logSection("MiniPrem Services Status")
	DOCKER_CMD = getDockerCommand()
	return cliDockerCompose(nil, "ps")
}

// bash: miniprem.sh:306
func cliViewLogs() int {
	logSection("MiniPrem Services Logs")
	DOCKER_CMD = getDockerCommand()
	return cliDockerCompose(nil, "logs", "-f")
}

const cliFlowiseURL = "http://localhost:3000/"

func cliFlowiseUp() bool {
	return sh.Run("curl", "--output", "/dev/null", "--silent", "--head", "--fail", cliFlowiseURL) == 0
}

// bash: miniprem.sh:312
func cliSetupFlowise() int {
	logSection("Setting up Flowise Chatflow")

	if !cliFlowiseUp() {
		warning("Flowise service is not running. Starting services first...")
		cliStartServices()

		info("Waiting for Flowise to be ready...")
		maxAttempts := 60
		attempt := 1

		for attempt <= maxAttempts {
			if cliFlowiseUp() {
				success(CHECKMARK + " Flowise is up and running!")
				break
			}

			fmt.Print(".")
			sh.Sleep(5 * time.Second)
			attempt++

			if attempt > maxAttempts {
				fatal("Flowise service did not become available within the expected timeframe.")
			}
		}
	}

	return sh.Run("bash", PROJECT_ROOT+"/setup-chatflow-post-deployment.sh")
}

// cliGitQuiet is `git ... >/dev/null 2>&1` style helpers.
func cliGit(args ...string) *sh.Cmd { return sh.C("git", args...) }

// bash: miniprem.sh:345
func cliPullUpdates(arg1 string) int {
	logSection("Pulling Latest MiniPrem Updates")

	regenerate := false
	if arg1 == "--regenerate" {
		regenerate = true
	}

	if cliGit("rev-parse", "--git-dir").Quiet().Run() != 0 {
		fatal("Not a git repository. Cannot pull updates.")
	}

	if cliGit("diff-index", "--quiet", "HEAD", "--").NoErr().Run() != 0 {
		warning("You have uncommitted changes. Please commit or stash them first.")
		info("Current changes:")
		cliGit("status", "--short").Run()
		fatal("Aborting pull to avoid conflicts.")
	}

	info("Pulling latest changes from git...")
	if cliGit("pull").Run() != 0 {
		fatal(CROSS + " Failed to pull updates from git.")
	}
	success(CHECKMARK + " Successfully pulled latest updates.")

	if ltIsFile(PROJECT_ROOT + "/docker/docker-compose.custom.yml") {
		info("Custom services file detected.")

		if regenerate {
			info("Regenerating merge with custom services...")
			rc := sh.Run("bash", PROJECT_ROOT+"/docker/scripts/merge-compose.sh")
			// bash: `[ $? -eq 0 ] || [ $? -eq 2 ]` - the second $? is the status of the
			// failed first test (1), so a merge exit of 2 is NOT accepted. Preserved.
			if rc == 0 {
				success(CHECKMARK + " Merge regenerated successfully.")
			} else {
				fatal(CROSS + " Failed to regenerate merge.")
			}
		} else {
			warning("Custom services exist. Run 'pull --regenerate' to update merge.")
		}
	}

	info("Recent changes:")
	return cliGit("log", "--oneline", "-5").Run()
}

// cliCopyFile is `cp src dst` for regular files (dst keeps its mode if it exists,
// else takes src's mode through the umask).
func cliCopyFile(src, dst string) bool {
	st, err := os.Stat(src)
	if err != nil {
		return false
	}
	b, err := os.ReadFile(src)
	if err != nil {
		return false
	}
	return os.WriteFile(dst, b, st.Mode().Perm()) == nil
}

// backup_config_files is only ever used as $(backup_config_files): info() goes to the
// (inherited) stderr, the echoed path is the captured value.
// bash: miniprem.sh:414
func cliBackupConfigFiles() string {
	backupDir := PROJECT_ROOT + "/.config_backup_" + sh.Now().Format("20060102_150405")
	os.MkdirAll(backupDir, 0o777)

	backedUp := 0
	for _, file := range cliConfigFilesToPreserve {
		fullPath := PROJECT_ROOT + "/" + file
		if ltIsFile(fullPath) {
			dir := cliDirname(file)
			os.MkdirAll(backupDir+"/"+dir, 0o777)
			cliCopyFile(fullPath, backupDir+"/"+file)
			backedUp++
		}
	}

	if backedUp > 0 {
		info(fmt.Sprintf("Backed up %d config file(s) to %s", backedUp, backupDir))
	}
	return backupDir
}

// cliDirname is `dirname`.
func cliDirname(p string) string {
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

// bash: miniprem.sh:435
func cliRestoreConfigFiles(backupDir string) int {
	if !ltIsDir(backupDir) {
		warning("Backup directory not found: " + backupDir)
		return 1
	}

	restored := 0
	for _, file := range cliConfigFilesToPreserve {
		backupFile := backupDir + "/" + file
		targetFile := PROJECT_ROOT + "/" + file
		if ltIsFile(backupFile) {
			os.MkdirAll(cliDirname(targetFile), 0o777)
			cliCopyFile(backupFile, targetFile)
			restored++
		}
	}

	if restored > 0 {
		success(fmt.Sprintf("%s Restored %d config file(s)", CHECKMARK, restored))
	}

	os.RemoveAll(backupDir)
	return 0
}

// bash: miniprem.sh:463
func cliUpgradeServices() int {
	logSection("Upgrading MiniPrem (Docker)")

	cliEcho("")
	info("This will:")
	cliEcho("  1. Backup your config files (credentials, etc.)")
	cliEcho("  2. Pull latest code from git")
	cliEcho("  3. Restore your config files")
	cliEcho("  4. Pull latest Renny image from Harbor")
	cliEcho("  5. Rebuild MiniPrem Monitor")
	cliEcho("")
	cliEcho("After upgrade, run './miniprem.sh restart' to apply changes.")
	cliEcho("")

	if cliGit("rev-parse", "--git-dir").Quiet().Run() != 0 {
		fatal("Not a git repository. Cannot upgrade.")
	}

	info("Step 1/5: Backing up config files...")
	backupDir := cliBackupConfigFiles()

	info("Step 2/5: Pulling latest code from git...")

	if cliGit("diff-index", "--quiet", "HEAD", "--").NoErr().Run() != 0 {
		warning("Stashing uncommitted changes...")
		cliGit("stash", "push", "-m", "miniprem-upgrade-"+sh.Now().Format("20060102_150405")).Run()
	}

	if cliGit("pull").Run() != 0 {
		warning("Git pull failed. Restoring config files...")
		cliRestoreConfigFiles(backupDir)
		fatal(CROSS + " Failed to pull updates from git.")
	}
	success(CHECKMARK + " Git pull successful")

	info("Step 3/5: Restoring config files...")
	cliRestoreConfigFiles(backupDir)

	info("Step 4/5: Pulling latest Renny image...")

	if ensureHarborCredentials() != 0 {
		fatal("Cannot pull Renny image without valid Harbor credentials")
	}

	DOCKER_CMD = getDockerCommand()

	info("Pulling cr.uneeq.io/uneeq/renny-renderer:0.1428-6654b...")
	pullArgs := append(dockerFields(DOCKER_CMD), "pull", "cr.uneeq.io/uneeq/renny-renderer:0.1428-6654b")
	if sh.Run(pullArgs[0], pullArgs[1:]...) == 0 {
		success(CHECKMARK + " Renny image updated")
	} else {
		warning("Failed to pull Renny image. Check Harbor credentials.")
	}

	info("Step 5/5: Rebuilding MiniPrem Monitor...")

	os.Chdir(PROJECT_ROOT + "/docker")
	if cliDockerCompose(io.Discard, "build", "--no-cache", "--pull", "miniprem-monitor") == 0 {
		success(CHECKMARK + " MiniPrem Monitor rebuilt")
	} else {
		if cliDockerCompose(io.Discard, "build", "--no-cache", "miniprem-monitor") == 0 {
			success(CHECKMARK + " MiniPrem Monitor rebuilt")
		} else {
			warning("Could not rebuild MiniPrem Monitor automatically.")
			cliEcho("  Try manually: cd docker && docker compose build --no-cache miniprem-monitor")
		}
	}
	os.Chdir(PROJECT_ROOT)

	cliEcho("")
	success("═══════════════════════════════════════════════════════════════")
	success("  Upgrade Complete!")
	success("═══════════════════════════════════════════════════════════════")
	cliEcho("")
	info("Recent changes pulled:")
	cliGit("log", "--oneline", "-5").Run()
	cliEcho("")
	info("Next steps:")
	cliEcho("  1. Review the changes above")
	cliEcho("  2. Restart services: ./miniprem.sh restart")
	cliEcho("")
	info("To verify after restart:")
	cliEcho("  ./miniprem.sh status")
	cliEcho("  docker exec miniprem-monitor docker version  # Should show API 1.46+")
	cliEcho("")
	return 0
}

// bash: miniprem.sh:561
func cliValidateCustomServices() int {
	logSection("Validating Custom Services Configuration")

	if !ltIsFile(PROJECT_ROOT + "/docker/docker-compose.custom.yml") {
		info("No custom services file found at docker/docker-compose.custom.yml")
		success(CHECKMARK + " No validation needed.")
		sh.Exit(0)
	}

	info("Validating custom services configuration...")

	exitCode := sh.Run("bash", PROJECT_ROOT+"/docker/scripts/merge-compose.sh", "--check", "--verbose")

	switch exitCode {
	case 0:
		success(CHECKMARK + " Custom services configuration is valid. No conflicts detected.")
		sh.Exit(0)
	case 1:
		logError(CROSS + " Validation failed. Please fix errors in docker-compose.custom.yml")
		sh.Exit(1)
	case 2:
		warning("Validation completed with warnings. Conflicts detected but can be resolved.")
		sh.Exit(2)
	default:
		logError(CROSS + " Unknown validation error.")
		sh.Exit(1)
	}
	return 0
}

// bash: miniprem.sh:597
func cliShowConfig(arg1 string) int {
	logSection("Docker Compose Configuration")

	showCustomOnly := false
	if arg1 == "--custom" {
		showCustomOnly = true
	}

	DOCKER_CMD = getDockerCommand()

	if showCustomOnly {
		custom := PROJECT_ROOT + "/docker/docker-compose.custom.yml"
		if !ltIsFile(custom) {
			info("No custom services file found.")
			sh.Exit(0)
		}

		info("Custom services configuration:")
		b, err := os.ReadFile(custom)
		if err != nil {
			fmt.Fprintf(os.Stderr, "cat: %s: %v\n", custom, err)
			return 1
		}
		os.Stdout.Write(b)
		return 0
	}

	info("Final merged Docker Compose configuration:")
	override := PROJECT_ROOT + "/docker/docker-compose.override.yml"
	if ltIsFile(override) {
		return cliDockerCompose(nil, "-f", override, "config")
	}
	return cliDockerCompose(nil, "config")
}

// cliGrepAltRe builds the BRE `^S$\|^.*[-_]S[-_].*$` used by grep -q at miniprem.sh:660
// with S spliced in unescaped (BRE metacharacters of S keep their BRE meaning).
func cliGrepAltRe(s string) *regexp.Regexp {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '[':
			j := i + 1
			if j < len(s) && s[j] == '^' {
				j++
			}
			if j < len(s) && s[j] == ']' {
				j++
			}
			for j < len(s) && s[j] != ']' {
				j++
			}
			if j >= len(s) {
				b.WriteString(regexp.QuoteMeta("["))
			} else {
				b.WriteString(s[i : j+1])
				i = j
			}
		case c == '.' || (c == '*' && i > 0):
			b.WriteByte(c)
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	p := b.String()
	re, err := regexp.Compile("^" + p + "$|^.*[-_]" + p + "[-_].*$")
	if err != nil {
		q := regexp.QuoteMeta(s)
		return regexp.MustCompile("^" + q + "$|^.*[-_]" + q + "[-_].*$")
	}
	return re
}

// bash: miniprem.sh:629
func cliListCustomServices() int {
	logSection("Custom Services")

	custom := PROJECT_ROOT + "/docker/docker-compose.custom.yml"
	if !ltIsFile(custom) {
		info("No custom services defined yet.")
		info("Use './miniprem.sh custom add [SERVICE_NAME]' to add a custom service.")
		sh.Exit(0)
	}

	services, _ := sh.C("yq", "eval", ".services | keys | .[]", custom).NoErr().Output()

	if services == "" {
		info("No custom services defined in docker-compose.custom.yml")
		sh.Exit(0)
	}

	info("Custom services defined:")
	cliEcho("")

	DOCKER_CMD = getDockerCommand()

	da := append(dockerFields(DOCKER_CMD), "ps", "--format", "{{.Names}}")
	runningContainers, _ := sh.Output(da[0], da[1:]...)
	runningLines := strings.Split(runningContainers, "\n")

	// while IFS= read -r service; ... done <<< "$services"  (stdin of the loop body
	// is the here-string, so children never touch the real stdin)
	for _, service := range strings.Split(services, "\n") {
		status := "stopped"
		statusColor := RED

		re := cliGrepAltRe(service)
		for _, l := range runningLines {
			if re.MatchString(l) {
				status = "running"
				statusColor = GREEN
				break
			}
		}

		image, _ := sh.C("yq", "eval", ".services."+service+".image // \"N/A\"", custom).In("").Output()
		var pb bytes.Buffer
		sh.C("yq", "eval", ".services."+service+".ports[]? // \"N/A\"", custom).In("").Out(&pb).Run()
		ports := strings.ReplaceAll(pb.String(), "\n", ",")
		ports = strings.TrimSuffix(ports, ",")

		cliEchoE("  " + BOLD + service + NC)
		cliEchoE("    Status: " + statusColor + status + NC)
		cliEchoE("    Image:  " + image)
		if ports != "N/A" && ports != "" {
			cliEchoE("    Ports:  " + ports)
		}
		cliEcho("")
	}
	return 0
}

// cliSedFirst emulates sed "s/^  [a-z]*:/  NAME:/" on each line of text.
var cliSedLeadRe = regexp.MustCompile(`^  [a-z]*:`)

func cliSedRename(text, name string) string {
	lines := strings.Split(text, "\n")
	for i, l := range lines {
		if loc := cliSedLeadRe.FindStringIndex(l); loc != nil {
			rep, _ := sedReplacement("  "+name+":", l[loc[0]:loc[1]])
			lines[i] = rep + l[loc[1]:]
		}
	}
	return strings.Join(lines, "\n")
}

// cliTemplates returns the `$(cat <<'EOF' ...)` bodies (trailing newlines stripped).
func cliTemplate(choice, serviceName string) string {
	switch choice {
	case "1":
		return `  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: miniprem
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - miniprem-network

volumes:
  postgres_data:`
	case "2":
		return `  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - miniprem-network

volumes:
  redis_data:`
	case "3":
		return `  mongodb:
    image: mongo:6
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: admin
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    networks:
      - miniprem-network

volumes:
  mongodb_data:`
	case "4":
		return `  mysql:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: miniprem
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - miniprem-network

volumes:
  mysql_data:`
	case "5":
		return `  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/html:/usr/share/nginx/html
    networks:
      - miniprem-network`
	}
	// unquoted heredoc: ${service_name} expands
	return `  ` + serviceName + `:
    image: # TODO: Specify image
    ports:
      - "8080:80"  # TODO: Configure ports
    environment:
      # TODO: Add environment variables
    networks:
      - miniprem-network`
}

// bash: miniprem.sh:679
func cliAddCustomService(serviceName string) int {
	logSection("Add Custom Service")

	templateChoice := "" // global in bash; empty when the name came from argv

	if serviceName == "" {
		cliEchoE(BOLD + "Available service templates:" + NC)
		cliEcho("  1) postgres   - PostgreSQL database")
		cliEcho("  2) redis      - Redis cache")
		cliEcho("  3) mongodb    - MongoDB database")
		cliEcho("  4) mysql      - MySQL database")
		cliEcho("  5) nginx      - Nginx web server")
		cliEcho("  6) custom     - Custom service (manual configuration)")
		cliEcho("")
		templateChoice, _ = sh.ReadLine(sh.ReadOpts{Prompt: "Select a template (1-6) or press Enter to cancel: "})

		switch templateChoice {
		case "1":
			serviceName = "postgres"
		case "2":
			serviceName = "redis"
		case "3":
			serviceName = "mongodb"
		case "4":
			serviceName = "mysql"
		case "5":
			serviceName = "nginx"
		case "6":
			serviceName = "custom"
		default:
			info("Cancelled.")
			sh.Exit(0)
		}

		if serviceName != "custom" {
			customName, _ := sh.ReadLine(sh.ReadOpts{Prompt: "Service name [" + serviceName + "]: "})
			if customName != "" {
				serviceName = customName
			}
		} else {
			serviceName, _ = sh.ReadLine(sh.ReadOpts{Prompt: "Enter service name: "})
			if serviceName == "" {
				fatal("Service name cannot be empty.")
			}
		}
	}

	custom := PROJECT_ROOT + "/docker/docker-compose.custom.yml"
	if !ltIsFile(custom) {
		info("Creating new docker-compose.custom.yml...")
		os.WriteFile(custom, []byte("version: '3.8'\n\nservices:\n"), 0o644)
	}

	// yq eval ".services.NAME" file | grep -qv "null"  (any line lacking "null")
	yqOut, _ := sh.C("yq", "eval", ".services."+serviceName, custom).Output()
	if yqOut != "" {
		for _, l := range strings.Split(yqOut, "\n") {
			if !strings.Contains(l, "null") {
				fatal("Service '" + serviceName + "' already exists in docker-compose.custom.yml")
			}
		}
	}

	template := cliTemplate(templateChoice, serviceName)
	template = cliSedRename(template, serviceName)

	if f, err := os.OpenFile(custom, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644); err == nil {
		f.WriteString(template + "\n")
		f.Close()
	}

	success(CHECKMARK + " Service '" + serviceName + "' added to docker-compose.custom.yml")

	info("Merging custom services with official configuration...")
	rc := sh.Run("bash", PROJECT_ROOT+"/docker/scripts/merge-compose.sh")
	// `[ $? -eq 0 ] || [ $? -eq 2 ]`: the second $? is 1 after a failed first test, so
	// exit 2 is NOT accepted (preserved).
	if rc == 0 {
		success(CHECKMARK + " Merge completed successfully.")
		info("You can now start the service with: ./miniprem.sh restart")
	} else {
		warning("Merge encountered issues. Please review docker-compose.custom.yml")
	}
	return 0
}

// bash: miniprem.sh:919-953 (deploy branch of the dispatcher)
func cliDeploy() int {
	cliEcho("")
	cliEcho("MiniPrem Deployment")
	cliEcho("")
	cliEcho("No existing installation detected. Choose your deployment type:")
	cliEcho("")
	cliEcho("  1) Docker (Local Development)")
	cliEcho("     - Quick setup for local development and testing")
	cliEcho("     - Requires: Docker, NVIDIA GPU with drivers")
	cliEcho("")
	cliEcho("  2) NVIDIA CNS (Bare Metal Production)")
	cliEcho("     - Kubernetes-based deployment with GPU time-slicing")
	cliEcho("     - Multiple Renny instances on a single GPU")
	cliEcho("     - Requires: Ubuntu 24.04, NVIDIA GPU with drivers")
	cliEcho("")
	deployChoice, _ := sh.ReadLine(sh.ReadOpts{Prompt: "Select deployment type [1-2]: "})

	switch deployChoice {
	case "1":
		cliEcho("")
		cliEcho("Starting Docker installation...")
		cliExec(PROJECT_ROOT + "/docker/scripts/install_miniprem.sh")
	case "2":
		cliEcho("")
		cliEcho("Starting NVIDIA CNS installation...")
		cliExec("sudo", PROJECT_ROOT+"/kubernetes/scripts/cns/deploy-local.sh")
	default:
		cliEcho("Invalid selection")
		sh.Exit(1)
	}
	return 0
}
