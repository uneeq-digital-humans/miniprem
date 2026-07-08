# Docker Compose Merge Script Documentation

## Overview

The `merge-compose.sh` script intelligently merges official MiniPrem Docker Compose files with custom user-defined services. This allows you to extend MiniPrem with additional services while maintaining the ability to update the official compose files.

## Quick Start

### 1. Create Your Custom Compose File

```bash
cd /Users/tyler/Software_Development/miniprem-2025/docker
cp docker-compose.custom.yml.example docker-compose.custom.yml
# Edit docker-compose.custom.yml with your custom services
```

### 2. Run the Merge Script

```bash
./scripts/merge-compose.sh
```

This generates `docker-compose.override.yml` which Docker Compose automatically uses.

### 3. Start Services

```bash
# Docker Compose automatically merges docker-compose.yml + docker-compose.override.yml
docker-compose up -d

# Or explicitly specify both files
docker-compose -f docker-compose.yml -f docker-compose.override.yml up -d
```

## Script Features

### Intelligent Merging

- **Services**: Appends custom services to official services
- **Volumes**: Merges volume definitions (no duplicates)
- **Networks**: Merges network definitions
- **Environment Variables**: Custom env vars can override official ones (within service definitions)

### Conflict Detection

The script detects when a custom service has the same name as an official service and provides multiple resolution strategies.

### Validation

- YAML syntax validation before and after merge
- Docker Compose config validation (ensures valid compose file)
- Clear error messages for any issues

### Metadata

Generated override files include helpful comments:
- Merge timestamp
- Source files
- Conflict resolution strategy
- List of conflicts (if any)

## Usage Examples

### Basic Merge (Default Behavior)

```bash
./scripts/merge-compose.sh
```

- Input: `docker-compose.yml` + `docker-compose.custom.yml`
- Output: `docker-compose.override.yml`
- Strategy: Custom services override official ones with same name

### Check for Conflicts Without Writing

```bash
./scripts/merge-compose.sh --check
```

Returns exit code 2 if conflicts exist, 0 if no conflicts.

### Different Conflict Resolution Strategies

#### Prefer Custom (Default)

```bash
./scripts/merge-compose.sh --prefer-custom
```

When a service name conflicts, keep the custom version.

#### Prefer Official

```bash
./scripts/merge-compose.sh --prefer-official
```

When a service name conflicts, keep the official version (custom service ignored).

#### Rename Custom Services

```bash
./scripts/merge-compose.sh --rename-custom "custom-"
```

When a service name conflicts, rename the custom service with the specified prefix.

Example: If both files have a `redis` service, custom one becomes `custom-redis`.

### Custom Input/Output Files

```bash
./scripts/merge-compose.sh \
  --file my-services.yml \
  --output my-override.yml
```

### Verbose Output

```bash
./scripts/merge-compose.sh --verbose
```

Shows detailed debug information about the merge process.

### Combined Options

```bash
./scripts/merge-compose.sh \
  --file docker-compose.custom.yml \
  --output docker-compose.override.yml \
  --rename-custom "myapp-" \
  --verbose
```

## Exit Codes

- **0**: Success (no conflicts or conflicts resolved)
- **1**: Error (validation failed, missing dependencies, syntax error)
- **2**: Conflicts detected (informational, may still succeed based on strategy)

## Conflict Scenarios

### Scenario 1: No Conflicts (Best Case)

**Official:**
```yaml
services:
  renny:
    image: cr.uneeq.io/uneeq/renny-renderer:0.1332-decd6
  flowise:
    image: flowiseai/flowise:latest
```

**Custom:**
```yaml
services:
  postgres:
    image: postgres:15
  custom-api:
    image: mycompany/api:latest
```

**Result:** All four services in merged file. No conflicts.

### Scenario 2: Service Name Conflict

**Official:**
```yaml
services:
  redis:
    image: redis:7-alpine
```

**Custom:**
```yaml
services:
  redis:
    image: redis:6-alpine
    command: redis-server --maxmemory 256mb
```

**Resolution Options:**

1. **--prefer-custom (default)**: Use custom Redis configuration
2. **--prefer-official**: Use official Redis configuration
3. **--rename-custom "my-"**: Creates `my-redis` with custom config, keeps official `redis`

### Scenario 3: Volume Conflicts

When both files define the same volume name, the custom definition takes precedence.

**Official:**
```yaml
volumes:
  redis_data:
```

**Custom:**
```yaml
volumes:
  redis_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/redis-data
```

**Result:** Custom volume definition is used.

## Best Practices

### 1. Use Unique Service Names

Avoid naming your custom services the same as official services unless you explicitly want to override them.

**Good:**
```yaml
services:
  my-postgres:  # Unique name
  my-api:       # Unique name
```

**Risky:**
```yaml
services:
  redis:  # Conflicts with official redis service
```

### 2. Use Dependencies Correctly

Your custom services can depend on official services:

```yaml
services:
  my-api:
    depends_on:
      - redis      # Official service
      - flowise    # Official service
      - my-postgres # Custom service
```

### 3. Maintain Your Custom File Separately

Keep `docker-compose.custom.yml` in version control separate from the official files. This allows you to:
- Update official compose files without losing customizations
- Share custom services across team
- Track changes to your custom services

### 4. Test Before Production

Always test merged configurations:

```bash
# Check for conflicts
./scripts/merge-compose.sh --check

# Validate merged output
docker-compose -f docker-compose.override.yml config

# Test startup
docker-compose up -d
docker-compose ps
```

### 5. Document Your Custom Services

Add comments to your `docker-compose.custom.yml` explaining:
- What each service does
- Why it's needed
- Any dependencies or configuration requirements

## Troubleshooting

### Error: "Missing required tools: yq"

**Solution:**
```bash
# macOS
brew install yq

# Linux
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

### Error: "Invalid YAML syntax"

**Solution:** Check your custom compose file for syntax errors:
```bash
yq eval '.' docker-compose.custom.yml
```

Common issues:
- Incorrect indentation (use 2 spaces, not tabs)
- Missing colons
- Unquoted special characters
- Missing quotes around port mappings

### Error: "docker-compose config validation failed"

**Solution:** The merged file has structural issues. Check:
```bash
docker-compose -f docker-compose.override.yml config
```

Common issues:
- Invalid service dependencies
- Port conflicts between services
- Invalid volume or network references

### Warning: "Conflicts detected"

**Solution:** Review conflicts and choose appropriate strategy:
```bash
# See what conflicts exist
./scripts/merge-compose.sh --check

# Choose resolution strategy
./scripts/merge-compose.sh --prefer-official
# OR
./scripts/merge-compose.sh --rename-custom "custom-"
```

## Advanced Usage

### Merging Multiple Custom Files

```bash
# First merge
./scripts/merge-compose.sh \
  --file custom-databases.yml \
  --output temp-override.yml

# Second merge (merge temp-override.yml with more custom services)
./scripts/merge-compose.sh \
  --file custom-apis.yml \
  --output docker-compose.override.yml
```

### Conditional Services

Use environment variables in your custom file:

```yaml
services:
  optional-service:
    image: myimage:latest
    environment:
      - ENABLE_FEATURE=${ENABLE_FEATURE:-false}
```

Then control at runtime:
```bash
ENABLE_FEATURE=true docker-compose up -d
```

### Automated Merging in CI/CD

```bash
#!/bin/bash
set -e

# Merge custom services
./scripts/merge-compose.sh --check || exit 1
./scripts/merge-compose.sh

# Validate
docker-compose config > /dev/null

# Deploy
docker-compose up -d
```

## Integration with MiniPrem

### Default Installation

MiniPrem's default `docker-compose.yml` includes:
- `miniprem-monitor`: Real-time monitoring dashboard
- `renny`: Digital human renderer

### Full Installation

`docker-compose.full.yml` includes:
- All default services
- `vllm`: LLM inference
- `flowise`: Workflow automation
- `redis`: Message queue
- `prometheus`: Metrics collection
- `grafana`: Metrics visualization
- `fastwhisper`: Speech-to-text

### Adding Custom Services

You can add services that integrate with MiniPrem:

```yaml
services:
  # Custom chatbot backend
  my-chatbot:
    image: mycompany/chatbot:latest
    environment:
      - FLOWISE_URL=http://localhost:3000
      - VLLM_URL=http://localhost:8000
    depends_on:
      - flowise
      - vllm
    network_mode: host
```

## File Locations

- **Script**: `/Users/tyler/Software_Development/miniprem-2025/docker/scripts/merge-compose.sh`
- **Official Compose**: `/Users/tyler/Software_Development/miniprem-2025/docker/docker-compose.yml`
- **Official Full**: `/Users/tyler/Software_Development/miniprem-2025/docker/docker-compose.full.yml`
- **Custom Template**: `/Users/tyler/Software_Development/miniprem-2025/docker/docker-compose.custom.yml.example`
- **Your Custom File**: `/Users/tyler/Software_Development/miniprem-2025/docker/docker-compose.custom.yml`
- **Generated Override**: `/Users/tyler/Software_Development/miniprem-2025/docker/docker-compose.override.yml`

## Security Considerations

### Default Security Settings

The script preserves security settings from official services:
- `security_opt: no-new-privileges:true`
- `read_only: true` (where applicable)
- Logging limits
- Healthchecks

### Custom Service Security

Always include security settings in your custom services:

```yaml
services:
  my-service:
    image: myimage:latest
    # ... other settings ...
    security_opt:
      - no-new-privileges:true
    read_only: true  # If possible
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Secrets Management

Avoid hardcoding secrets in compose files:

**Bad:**
```yaml
environment:
  - DB_PASSWORD=mysecretpassword
```

**Good:**
```yaml
environment:
  - DB_PASSWORD=${DB_PASSWORD}
```

Then use `.env` file or environment variables.

## Getting Help

```bash
# Show help message
./scripts/merge-compose.sh --help

# Check script version and options
head -20 ./scripts/merge-compose.sh
```

## Contributing

Found a bug or have a feature request? The merge script is part of the MiniPrem project. Please report issues or contribute improvements.

## License

Part of the MiniPrem project. See project license for details.
