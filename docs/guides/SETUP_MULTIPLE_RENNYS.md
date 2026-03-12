# Setup Multiple Rennys - Documentation

## Overview

`setup_multiple_rennys.sh` is a comprehensive bash script that configures multiple Renny containers for Docker deployments. It automates the process of setting up parallel Renny instances with proper port allocation, environment configuration, and service management.

## Location

```
docker/scripts/setup_multiple_rennys.sh
```

## Quick Start

### Interactive Mode (Recommended)
```bash
# Change to project root
cd /path/to/miniprem-2025

# Run the script (prompts for number of instances)
./docker/scripts/setup_multiple_rennys.sh
```

### Direct Configuration
```bash
# Configure 4 Renny instances directly
./docker/scripts/setup_multiple_rennys.sh -n 4
```

## Command-Line Options

```
-n, --number <count>    Number of Renny instances (2-30)
                        Default: interactive prompt

-h, --help              Display usage information
```

## Requirements

Before running the script, ensure:

1. **MiniPrem Installation Completed**
   - `.miniprem_install_type` file exists in project root
   - Installation script has been run: `./docker/scripts/install_miniprem.sh`

2. **Environment Files**
   - `docker/docker-compose.env` must exist
   - `docker/docker-compose.yml` or `docker/docker-compose.full.yml` based on install type

3. **Docker Requirements**
   - Docker daemon running and accessible
   - Sufficient GPU VRAM (2-3 GB per instance recommended)
   - Sufficient system RAM (2-4 GB per instance)
   - 1-2 CPU cores per instance

## Features

### Automatic Port Allocation

The script allocates ports in a predictable pattern to avoid conflicts:

```
Instance 1 (renny):
  Health URL: http://0.0.0.0:8081/health
  Metrics Port: 8080

Instance 2 (renny-second):
  Health URL: http://0.0.0.0:8091/health
  Metrics Port: 8090

Instance 3 (renny-third):
  Health URL: http://0.0.0.0:8101/health
  Metrics Port: 8100

Pattern: base_port + (instance_num - 1) * 10
```

### Environment File Management

For each instance, the script:

1. Copies `docker-compose.env` to `renny-{ordinal}.env`
2. Updates `HEALTH_URL` with instance-specific port
3. Updates `METRICS_PORT` with instance-specific port
4. Preserves all other environment variables unchanged

Example environment files created:
- `renny-second.env` - Environment for instance 2
- `renny-third.env` - Environment for instance 3
- `renny-fourth.env` - Environment for instance 4
- etc.

### Idempotent Operations

The script can be run multiple times safely:
- Existing custom instances are cleaned before adding new ones
- Base `renny` service definition is never deleted
- Compose file is backed up before modifications
- Failed operations can be rolled back from backup

### Service Definition Generation

The script automatically:
1. Extracts the base `renny` service configuration
2. Creates modified copies with:
   - Unique container names (`renny-second`, `renny-third`, etc.)
   - Instance-specific environment files
   - Correct healthcheck ports
   - Proper YAML indentation (2 spaces)
3. Appends to the compose file with blank line separators

### Health Verification

After deployment, the script:
1. Waits up to 30 seconds for containers to stabilize
2. Verifies all containers are running
3. Checks healthcheck status for each container
4. Reports any failed containers with diagnostic information

## Workflow

### Step 1: Validation
- Verifies MiniPrem installation is complete
- Checks installation type and selects appropriate compose file
- Confirms `docker-compose.env` exists
- Validates Docker daemon is running

### Step 2: Configuration
- Prompts for or validates number of instances (2-30)
- Extracts base `renny` service definition from compose file
- Creates backup of compose file

### Step 3: Setup
- Cleans any existing custom Renny instances (idempotent)
- Creates environment files for all new instances
- Generates service definitions with proper port allocation
- Appends services to compose file

### Step 4: Deployment
- Stops current services gracefully
- Starts services with new configuration
- Waits for containers to stabilize

### Step 5: Verification
- Verifies all containers are running
- Checks healthcheck status
- Reports success or failures with diagnostics

## Instance Count Recommendations

### 2 Instances (Minimum)
- **Use case**: Basic failover and redundancy
- **Resource per instance**: ~2-3 GB GPU VRAM, 1 core, 2-4 GB RAM
- **Total GPU VRAM needed**: 4-6 GB
- **Typical hardware**: Single consumer GPU (RTX 3090, A6000, etc.)

### 3-4 Instances (Recommended)
- **Use case**: Balanced performance and resource utilization
- **Resource per instance**: ~2-3 GB GPU VRAM, 1-2 cores, 2-4 GB RAM
- **Total GPU VRAM needed**: 6-12 GB
- **Typical hardware**: Professional GPU (A100, H100), dual consumer GPUs

### 5-10 Instances
- **Use case**: High-capacity deployments
- **Resource per instance**: ~2-3 GB GPU VRAM, 1 core, 2 GB RAM
- **Total GPU VRAM needed**: 10-30 GB
- **Typical hardware**: Multiple professional GPUs

### 10+ Instances
- **Use case**: Massive parallel deployments
- **Resource per instance**: ~1-2 GB GPU VRAM (with time-slicing)
- **Total GPU VRAM needed**: Depends on time-slicing configuration
- **Typical hardware**: High-end GPU clusters, cloud deployment

## Docker Compose Integration

### How It Works

1. **Base Configuration**
   - Original `renny` service remains unchanged
   - Used by miniprem.sh to manage services

2. **Custom Services**
   - Each instance (2+) gets own service definition
   - Services named: `renny-second`, `renny-third`, etc.
   - All services use same image, differ in:
     - Container name
     - Environment file (renny-{ordinal}.env)
     - Healthcheck port

3. **docker-compose Commands**
   ```bash
   # Start all Renny instances
   docker compose -f docker-compose.yml up -d

   # Check status of all instances
   docker compose -f docker-compose.yml ps

   # View logs from all instances
   docker compose -f docker-compose.yml logs -f

   # Scale to specific instance
   docker compose -f docker-compose.yml start renny-second
   ```

## Environment File Configuration

### File Format
Each environment file (`renny-{ordinal}.env`) contains:

```bash
# Audio2face settings (same for all instances)
A2F_ADDRESS=http://audio2face-gateway:52000
A2F_AUDIO_DELAY_TIME_MS=240
A2F_AUDIO_SAMPLE_RATE=16000

# Platform settings (same for all instances)
# US: api.enterprise.uneeq.io / EU: api-eu.enterprise.uneeq.io
DHOP_ADDRESS=wss://api.enterprise.uneeq.io/signalling-service/v2/ws/renderer
DHOP_PIXELSTREAMING_ADDRESS=wss://api.enterprise.uneeq.io:443/signalling-service/v1/ws/pixelstreaming

# Installation credentials (same for all instances)
DHOP_APIKEY=<YOUR_API_KEY>
DHOP_TENANTID=<YOUR_TENANT_ID>

# Instance-specific settings (MODIFIED BY SCRIPT)
HEALTH_URL=http://0.0.0.0:{health_port}/health    # Unique per instance
METRICS_PORT={metrics_port}                        # Unique per instance

# Other settings (same for all instances)
SLEEP_TIMER_SECS=5.0
AZURE_REGION=<YOUR_REGION>
AZURE_SPEECH_KEY=<YOUR_KEY>
```

### Modifications
The script updates only these fields in instance-specific env files:
- `HEALTH_URL`: Instance-specific healthcheck port
- `METRICS_PORT`: Instance-specific metrics port

All other fields remain identical to `docker-compose.env`.

## Monitoring and Management

### View Service Status
```bash
# Check all services
./miniprem.sh status

# Or directly with docker-compose
docker compose -f docker/docker-compose.yml ps
```

### View Logs
```bash
# View all logs
./miniprem.sh logs

# Or view specific container
docker logs renny-second

# Or follow logs in real-time
docker logs -f renny-second
```

### Monitor via Web Dashboard
```
http://localhost:3001/
```

The MiniPrem Monitor dashboard shows:
- Status of all Renny instances
- Container health indicators
- Resource utilization per instance
- Real-time metrics

### Manual Container Management

```bash
# Stop specific instance
docker stop renny-second

# Start specific instance
docker start renny-second

# Restart specific instance
docker restart renny-second

# Remove stopped instance (requires reconfig)
docker rm renny-second
```

## Troubleshooting

### Issue: "MiniPrem installation not completed"

**Solution**: Run the installation script first
```bash
./docker/scripts/install_miniprem.sh
```

### Issue: "Docker daemon is not running"

**Solution**: Start Docker Desktop or Docker daemon
```bash
# macOS with Docker Desktop
open /Applications/Docker.app

# Linux
sudo systemctl start docker
```

### Issue: Port conflicts when starting containers

**Possible causes**:
- Ports already in use by other applications
- Previous instances not fully cleaned up

**Solution**:
```bash
# Check which process is using a port
lsof -i :8091  # Check port 8091
netstat -an | grep 8091  # Alternative method

# Stop conflicting process or choose different port
# Re-run the setup script
./docker/scripts/setup_multiple_rennys.sh -n 4
```

### Issue: Containers not starting / immediate failures

**Check logs**:
```bash
# View container logs
docker logs renny-second

# Follow logs in real-time
docker logs -f renny-second

# Check through miniprem.sh
./miniprem.sh logs
```

**Common causes**:
- Missing environment variables in env file
- GPU not available (check with `nvidia-smi`)
- Insufficient GPU VRAM
- Port conflicts
- Corrupted docker-compose.yml (check syntax)

### Issue: Health checks failing

**Solution**: Check the health endpoint
```bash
# Test health endpoint directly
curl http://localhost:8091/health

# Check container process status
docker ps -f name=renny-second

# View logs for errors
docker logs renny-second
```

### Issue: Slow container startup

**Explanation**: Renny containers take 30-60 seconds to fully initialize as they load the game engine and graphics system.

**Expected behavior**:
- Container starts immediately
- Health check begins (typically after 10-15 seconds)
- Health status transitions through states
- Returns "healthy" after successful initialization

### Restore from Backup

If something goes wrong, restore the original compose file:

```bash
# Find backup file (created with timestamp)
ls -la docker/docker-compose.yml.backup.*

# Restore specific backup
cp docker/docker-compose.yml.backup.1234567890 docker/docker-compose.yml

# Restart services
./miniprem.sh restart
```

## Performance Considerations

### GPU Time-Slicing

With GPU time-slicing enabled (default in Kubernetes), multiple containers can share one GPU:

```bash
# Check time-slicing configuration in Kubernetes
kubectl get configmap -n gpu-operator
kubectl describe configmap renny-time-slicing-config -n gpu-operator
```

In Docker, time-slicing is not directly supported but can be approximated through:
- Limiting GPU memory per container
- Load balancing across multiple GPU instances

### Resource Limits

Recommended per-instance allocation:

| Resource | Recommended | Minimum | Note |
|----------|-------------|---------|------|
| GPU VRAM | 3 GB | 2 GB | 24GB GPU supports 6-12 instances |
| System RAM | 4 GB | 2 GB | Total RAM = base OS + (4GB × instances) |
| CPU Cores | 2 | 1 | More cores improve frame rate |
| Disk Space | 20 GB | 10 GB | Per instance, for cache/logs |

### Monitoring Resource Usage

```bash
# View GPU utilization
nvidia-smi

# View Docker container resource usage
docker stats

# View detailed container stats
docker stats renny-second --no-stream
```

## Advanced Usage

### Custom Instance Count Validation

The script enforces these limits:
- **Minimum**: 2 instances (required for failover capability)
- **Maximum**: 30 instances (practical limit for 30 ordinal names)

### Modifying Port Allocation

To change port numbers, manually edit environment files:

```bash
# Edit specific instance env file
vim docker/renny-second.env

# Update these lines:
# HEALTH_URL=http://0.0.0.0:8091/health
# METRICS_PORT=8090

# Then update compose file healthcheck port:
# test: "curl -f http://localhost:8091/health"

# Restart services
./miniprem.sh restart
```

### Running Multiple Deployments

For multiple independent deployments, use separate directories:

```bash
# Deployment 1
cp -r miniprem-2025 miniprem-deployment-1
cd miniprem-deployment-1
./docker/scripts/setup_multiple_rennys.sh -n 4

# Deployment 2
cp -r miniprem-2025 miniprem-deployment-2
cd miniprem-deployment-2
# Modify docker-compose.yml to use unique ports (e.g., 9081-9101)
./docker/scripts/setup_multiple_rennys.sh -n 4
```

## Integration with CI/CD

### GitLab CI/CD Example

```yaml
deploy_multiple_rennys:
  stage: deploy
  script:
    - cd docker/scripts
    - ./setup_multiple_rennys.sh -n $RENNY_INSTANCE_COUNT
  variables:
    RENNY_INSTANCE_COUNT: 4
  only:
    - main
```

### GitHub Actions Example

```yaml
name: Deploy Multiple Rennys
on: push

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Multiple Rennys
        run: |
          cd docker/scripts
          ./setup_multiple_rennys.sh -n 4
```

## Script Functions Reference

### Core Functions

- `display_usage()` - Show help information
- `parse_arguments()` - Parse CLI arguments
- `validate_installation()` - Verify MiniPrem is installed
- `validate_docker()` - Check Docker daemon status
- `prompt_for_instance_count()` - Interactive instance count input
- `validate_instance_count()` - Validate provided instance count
- `extract_renny_service()` - Extract base Renny config
- `create_service_definitions()` - Generate all service definitions
- `clean_existing_instances()` - Remove old custom instances
- `create_instance_env_file()` - Create per-instance env file
- `calculate_ports()` - Compute instance port numbers
- `get_ordinal_name()` - Get English ordinal (second, third, etc.)
- `backup_compose_file()` - Create timestamped backup
- `restart_services()` - Stop and start services
- `verify_containers_healthy()` - Wait and check container health
- `display_summary()` - Show configuration results

### Utility Functions

- `main()` - Entry point and orchestration

## Error Handling

The script implements comprehensive error handling:

1. **Pre-flight Checks**
   - Installation validation
   - Docker availability
   - File existence
   - Environment setup

2. **Operation Safety**
   - Backup before modifications
   - Idempotent cleanup
   - Rollback on failure
   - Graceful shutdown handling

3. **Error Reporting**
   - Clear error messages
   - Helpful troubleshooting tips
   - Logs location and commands
   - Failed container reporting

## Support and Logs

### Log Files

Script logs are stored in:
- `logs/install_miniprem_TIMESTAMP.log` - Installation logs
- Docker container logs: `docker logs <container_name>`
- Docker compose logs: `./miniprem.sh logs`

### Viewing Logs

```bash
# All recent logs from Docker
./miniprem.sh logs

# Specific container logs
docker logs renny-second

# Follow logs in real-time
docker logs -f renny-second

# Last 100 lines
docker logs --tail 100 renny-second
```

### Getting Help

1. Check troubleshooting section above
2. Review container logs for specific errors
3. Run `./docker/scripts/setup_multiple_rennys.sh --help`
4. Check Docker compose file syntax: `docker compose config`

## File Structure Created

After running the script, expect:

```
docker/
├── docker-compose.yml          (modified with new services)
├── docker-compose.yml.backup.* (timestamped backup)
├── docker-compose.env          (original, unchanged)
├── renny-second.env            (new - instance 2)
├── renny-third.env             (new - instance 3)
├── renny-fourth.env            (new - instance 4)
└── scripts/
    └── setup_multiple_rennys.sh
```

## Examples

### Example 1: Basic 2-Instance Setup

```bash
# Run script
./docker/scripts/setup_multiple_rennys.sh -n 2

# Expected output:
# - Creates renny-second.env
# - Adds renny-second service to docker-compose.yml
# - Starts both renny and renny-second containers
# - Health checks on ports 8081, 8091

# Verify
./miniprem.sh status
docker ps -f name="renny"
```

### Example 2: Medium 4-Instance Deployment

```bash
# Run script
./docker/scripts/setup_multiple_rennys.sh -n 4

# Expected services:
# - renny (primary)
# - renny-second
# - renny-third
# - renny-fourth

# Ports in use:
# - 8080, 8081 (instance 1)
# - 8090, 8091 (instance 2)
# - 8100, 8101 (instance 3)
# - 8110, 8111 (instance 4)
```

### Example 3: Re-configuration

```bash
# Initially deployed with 2 instances
./docker/scripts/setup_multiple_rennys.sh -n 2

# Later expand to 5 instances
./docker/scripts/setup_multiple_rennys.sh -n 5

# Script automatically:
# - Backs up current compose file
# - Cleans previous custom instances
# - Creates 4 new custom instances (renny-second through renny-fifth)
# - Restarts all services
```

## License and Attribution

This script is part of the MiniPrem project. See main project LICENSE for details.

---

**Last Updated**: 2025-11-07
**Script Version**: 1.0
**Compatible with**: MiniPrem 2025
