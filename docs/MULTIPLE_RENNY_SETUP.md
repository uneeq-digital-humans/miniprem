# Scaling Renny Instances - Multiple Container Setup

Scaling multiple Renny digital human instances on Docker allows you to serve more concurrent users with improved performance and redundancy. This guide covers everything you need to know about running multiple Renny containers on a single host.

## Table of Contents

- [Overview](#overview)
- [GPU Capacity Planning](#gpu-capacity-planning)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Re-running the Script](#re-running-the-script)
- [Port Reference](#port-reference)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Overview

### What This Feature Enables

This feature allows you to run multiple Renny containers on the same Docker host, enabling:

- **Concurrent User Support**: Multiple users can interact with different Renny instances simultaneously
- **Load Distribution**: Workload spread across multiple containers reduces per-instance CPU/memory pressure
- **Redundancy**: If one instance has issues, others continue operating
- **Scalability**: Easy to add or remove instances as needed
- **Resource Optimization**: Better utilization of multi-GPU systems

### When to Use Multiple Renny Instances

Consider running multiple Renny instances when:

- You need to support multiple concurrent conversations
- A single Renny instance experiences performance degradation under load
- You want to implement load balancing or failover systems
- Your GPU has sufficient memory to support parallel workloads
- You're testing high-concurrency scenarios

### Prerequisites

Before setting up multiple Renny instances, ensure:

- MiniPrem is fully installed using `./docker/scripts/install_miniprem.sh`
- Docker and Docker Compose are running
- You have verified that the primary Renny instance (port 8081) is working correctly
- Your GPU has sufficient memory for multiple instances (see GPU Capacity Planning)
- All services are healthy: `docker-compose ps`

## GPU Capacity Planning

Running multiple Renny instances consumes significant GPU memory. Proper capacity planning prevents resource contention and container crashes.

### GPU Memory Requirements

Each Renny instance requires approximately:

- **Baseline**: 2-3 GB VRAM (internal speech processing + rendering)
- **With Active Rendering**: 4-6 GB VRAM (animations, expressions)
- **Peak Usage**: Up to 8 GB VRAM under full load

### Recommended Configuration by GPU Type

| GPU Model | VRAM | Recommended Instances | Notes |
|-----------|------|----------------------|-------|
| NVIDIA ADA6000 | 48 GB | 4-6 instances | Most capable, supports heavy workloads |
| NVIDIA RTX A6000 | 48 GB | 4-6 instances | Excellent for production use |
| NVIDIA A100 | 40-80 GB | 5-8 instances | Enterprise-grade, highest performance |
| NVIDIA A10G | 24 GB | 2-3 instances | AWS-common, good balance |
| NVIDIA RTX 4090 | 24 GB | 2-3 instances | Consumer high-end, good for testing |
| NVIDIA T4 | 16 GB | 2 instances | Cloud-common, conservative approach |
| NVIDIA V100 | 32 GB | 3-4 instances | Older but capable hardware |
| NVIDIA Tesla P100 | 16 GB | 1-2 instances | Legacy GPU, single or paired only |

### How to Measure GPU Utilization

Check current GPU usage:

```bash
# Real-time monitoring (updates every 1 second)
watch -n 1 nvidia-smi

# Single snapshot
nvidia-smi

# Detailed GPU memory breakdown
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
```

**Key metrics to monitor:**

```
+--------+------+-------+
| GPU    | Mem  | Temp  |
+--------+------+-------+
| 0      | 12GB | 68°C  | <- Example: 50% utilization
+--------+------+-------+
```

Check per-container GPU usage:

```bash
# View GPU processes
nvidia-smi pmon -c 5

# Monitor container-level GPU usage
docker stats --no-stream
```

### Signs of Oversubscription

Watch for these warning signs:

1. **GPU Memory Errors**:
   ```
   CUDA out of memory
   RuntimeError: CUDA out of memory
   ```

2. **Container Crashes**:
   ```
   docker ps
   # Renny instances showing "Exited" status
   ```

3. **High Memory Pressure**:
   ```bash
   nvidia-smi | grep MiB
   # Values near 90-100% of total VRAM
   ```

4. **Severe Slowdowns**:
   - Long response times from Renny instances
   - Frame rate drops in rendering
   - High container CPU usage (100%+)

5. **Health Check Failures**:
   ```bash
   docker ps | grep unhealthy
   # Multiple containers showing unhealthy status
   ```

**If oversubscription occurs:**

- Reduce the number of instances
- Stop background services consuming GPU memory
- Restart containers to clear GPU memory leaks
- Consider upgrading GPU hardware

## Quick Start

### Running the Setup Script

The simplest way to create multiple Renny instances is using the provided script:

```bash
# Navigate to the docker directory
cd docker/

# Run the multiple Renny setup script
./scripts/setup-multiple-rennys.sh
```

### Example Interactive Session

```
$ ./scripts/setup-multiple-rennys.sh

=== MiniPrem Multiple Renny Setup ===

Current installation: full
Current services: vllm, miniprem-monitor, renny (1 instance)

How many total Renny instances do you want? (1-10): 3

Configuration Summary:
- First instance (renny): ports 8080-8081
- Second instance (renny-second): ports 8090-8091
- Third instance (renny-third): ports 8100-8101

Proceed with this configuration? (yes/no): yes

Creating additional Renny instances...
✓ renny-second: ports 8090-8091
✓ renny-third: ports 8100-8101

Updating docker-compose file...
✓ Successfully updated docker-compose.full.yml

Rebuilding service configuration...
✓ Docker Compose configuration validated

Starting new instances...
✓ renny-second started successfully
✓ renny-third started successfully

Verifying health checks...
✓ All instances passing health checks
✓ All instances are healthy and ready

Configuration saved to: .miniprem_renny_config

Total instances running: 3
Container names: renny, renny-second, renny-third
Ready for concurrent connections!
```

### Expected Output

After successful setup, verify your instances:

```bash
# Check all Renny containers are running
docker ps | grep renny

# Expected output:
# CONTAINER_ID  IMAGE                            STATUS
# abc123...     cr.uneeq.io/uneeq/renny-renderer Up 2 minutes (healthy)
# def456...     cr.uneeq.io/uneeq/renny-renderer Up 1 minute (healthy)
# ghi789...     cr.uneeq.io/uneeq/renny-renderer Up 30 seconds (healthy)

# Test health endpoints
curl http://localhost:8081/health  # First instance
curl http://localhost:8091/health  # Second instance
curl http://localhost:8101/health  # Third instance
```

## How It Works

### Port Allocation Pattern

Multiple Renny instances use a structured port allocation scheme:

```
Instance 1 (renny):           8080 (metrics) / 8081 (health)
Instance 2 (renny-second):    8090 (metrics) / 8091 (health)
Instance 3 (renny-third):     8100 (metrics) / 8101 (health)
Instance 4 (renny-fourth):    8110 (metrics) / 8111 (health)
Instance 5 (renny-fifth):     8120 (metrics) / 8121 (health)
...continuing pattern...
```

**Pattern Rule**: For instance N (1-indexed):
- Metrics port: `8080 + (N-1)*10`
- Health port: `8081 + (N-1)*10`

### Container Naming Convention

Containers follow a consistent naming pattern:

```
renny                    # First instance (primary)
renny-second             # Second instance
renny-third              # Third instance
renny-fourth             # Fourth instance
renny-fifth              # Fifth instance
renny-sixth              # Sixth instance
renny-seventh            # Seventh instance
renny-eighth             # Eighth instance
renny-ninth              # Ninth instance
renny-tenth              # Tenth instance
```

### Environment File Structure

Each Renny instance uses the same environment configuration:

```yaml
renny:
  container_name: renny
  env_file:
    - docker-compose.env  # Shared configuration
  environment:
    - NEW_SPEECH_OVERRIDE=1
    - PLATFORM=docker
    - MINIPREM_TELEMETRY_DISABLED=${MINIPREM_TELEMETRY_DISABLED:-0}
  volumes:
    - ./configuration.dat:/opt/renny/Renny/Binaries/Linux/configuration.dat

renny-second:
  container_name: renny-second
  env_file:
    - docker-compose.env  # Same shared configuration
  environment:
    - NEW_SPEECH_OVERRIDE=1
    - PLATFORM=docker
    - MINIPREM_TELEMETRY_DISABLED=${MINIPREM_TELEMETRY_DISABLED:-0}
  volumes:
    - ./configuration.dat:/opt/renny/Renny/Binaries/Linux/configuration.dat
```

All instances share:
- Same Docker image
- Same configuration.dat (UneeQ credentials)
- Same environment variables
- Same volumes

### Docker Compose Service Duplication

The Docker Compose file is extended with additional service definitions. Original structure:

```yaml
services:
  vllm:
    # ... configuration
  miniprem-monitor:
    # ... configuration
  renny:
    container_name: renny
    # ... configuration
```

After running the setup script:

```yaml
services:
  vllm:
    # ... configuration (unchanged)
  miniprem-monitor:
    # ... configuration (unchanged)
  renny:
    container_name: renny
    ports:
      - "8080:8080"
    # ... configuration
  renny-second:
    container_name: renny-second
    ports:
      - "8090:8090"
      - "8091:8091"
    # ... inherited from renny (modified ports, container_name)
  renny-third:
    container_name: renny-third
    ports:
      - "8100:8100"
      - "8101:8101"
    # ... inherited from renny (modified ports, container_name)
```

## Re-running the Script

### Idempotent Behavior

The setup script is **idempotent**, meaning it can be run multiple times safely:

- If you already have 3 instances and run the script requesting 3 instances, nothing changes
- If you have 3 instances and run the script requesting 5, it adds 2 more
- If you have 5 instances and run the script requesting 2, it removes 3

### Scaling Up

To add more instances:

```bash
cd docker/
./scripts/setup-multiple-rennys.sh

# When prompted: "How many total Renny instances do you want?"
# Enter a number higher than current count
# Example: 3 (current) → 5 (adds 2 new instances)
```

### Scaling Down

To reduce the number of instances:

```bash
cd docker/
./scripts/setup-multiple-rennys.sh

# When prompted: "How many total Renny instances do you want?"
# Enter a number lower than current count
# Example: 5 (current) → 2 (removes 3 instances)
```

**Important**: Scaling down stops and removes the specified instances:

```bash
# Scaling from 3 to 2 instances removes renny-third
docker stop renny-third
docker rm renny-third
# Docker Compose file is updated to remove the service definition
```

### What Happens to Existing Configurations

When re-running the script:

1. **Existing instances**: Continue running without interruption
2. **Existing ports**: Not reallocated or changed
3. **Docker Compose file**: Intelligently updated (preserves existing services)
4. **Configuration**: Not modified (reuses docker-compose.env, configuration.dat)
5. **Health checks**: Continuously validated across all instances

Example workflow:

```bash
# Initial setup: 2 instances
./scripts/setup-multiple-rennys.sh
# User enters: 2

# ... time passes, running successfully ...

# Decide to scale to 4
./scripts/setup-multiple-rennys.sh
# User enters: 4
# Script detects 2 existing instances
# Adds: renny-third, renny-fourth
# Existing: renny, renny-second (unchanged)
```

## Port Reference

Complete port mapping for all possible Renny instances:

| Instance | Container Name | Metrics Port | Health Port | First Instance | Second Instance |
|----------|----------------|--------------|-------------|----------------|-----------------|
| 1 | renny | 8080 | 8081 | N/A | N/A |
| 2 | renny-second | 8090 | 8091 | 8080 | 8090 |
| 3 | renny-third | 8100 | 8101 | 8080 | 8100 |
| 4 | renny-fourth | 8110 | 8111 | 8080 | 8110 |
| 5 | renny-fifth | 8120 | 8121 | 8080 | 8120 |
| 6 | renny-sixth | 8130 | 8131 | 8080 | 8130 |
| 7 | renny-seventh | 8140 | 8141 | 8080 | 8140 |
| 8 | renny-eighth | 8150 | 8151 | 8080 | 8150 |
| 9 | renny-ninth | 8160 | 8161 | 8080 | 8160 |
| 10 | renny-tenth | 8170 | 8171 | 8080 | 8170 |

### Health Check URLs

Test connectivity to any instance:

```bash
# Primary instance
curl http://localhost:8081/health

# Second instance
curl http://localhost:8091/health

# Third instance
curl http://localhost:8101/health

# Batch health check for all instances
for port in 8081 8091 8101 8111 8121; do
  echo -n "Port $port: "
  curl -s http://localhost:$port/health | jq -r '.status' 2>/dev/null || echo "No response"
done
```

## Troubleshooting

### Container Fails Health Check

**Symptoms:**
```
docker ps | grep unhealthy
# Output shows: "(unhealthy)" status
```

**Common Causes:**

1. **Insufficient GPU Memory**

   Check GPU status:
   ```bash
   nvidia-smi | grep -i memory
   ```

   If near 100%, reduce instance count:
   ```bash
   ./scripts/setup-multiple-rennys.sh
   # Enter lower number (e.g., 2 instead of 4)
   ```

2. **Port Conflict**

   Check for port binding errors:
   ```bash
   docker logs renny-second 2>&1 | grep -i "port\|bind"
   ```

   Verify ports are free:
   ```bash
   netstat -tulpn | grep LISTEN | grep 809
   ```

3. **Configuration Issue**

   Verify configuration.dat exists:
   ```bash
   ls -lh docker/configuration.dat
   # Should exist and be readable
   ```

**Resolution:**

```bash
# Stop the unhealthy instance
docker stop renny-second

# Check logs for specific errors
docker logs renny-second

# Restart the instance
docker start renny-second

# Monitor health check recovery
docker ps | grep renny-second
```

### Port Conflicts

**Symptoms:**
```
Error: bind: address already in use
docker-compose up: container failed to start
```

**Diagnosis:**

Check which process is using the port:

```bash
# Find process using port 8091
lsof -i :8091

# Or using netstat
netstat -tulpn | grep 8091
```

**Resolution:**

1. If it's another container, stop it:
   ```bash
   docker stop <container_name>
   ```

2. If it's a different service, either:
   - Stop that service
   - Choose different ports (edit docker-compose file manually)

3. Verify ports are free before starting:
   ```bash
   for port in 8080 8081 8090 8091 8100 8101; do
     echo -n "Port $port: "
     (echo >/dev/tcp/localhost/$port) 2>/dev/null && echo "IN USE" || echo "FREE"
   done
   ```

### Script Fails During Execution

**Symptoms:**
```
Setup failed: Cannot create renny-second
```

**Common Causes:**

1. **Docker Not Running**

   ```bash
   # Check Docker status
   docker ps
   # If error: "Cannot connect to Docker daemon"

   # Start Docker
   sudo systemctl start docker  # Linux
   open -a Docker              # macOS
   ```

2. **Docker Compose Version Issues**

   ```bash
   # Verify Docker Compose version (need 2.0+)
   docker-compose --version

   # Update if needed
   docker-compose up -d  # Uses updated version
   ```

3. **Invalid Configuration**

   ```bash
   # Validate Docker Compose syntax
   cd docker/
   docker-compose config > /dev/null
   # Should complete without errors
   ```

4. **Permission Issues**

   ```bash
   # Verify script is executable
   chmod +x scripts/setup-multiple-rennys.sh

   # Verify Docker permissions
   sudo usermod -aG docker $USER
   newgrp docker
   ```

**Resolution:**

```bash
# Run with detailed output to see exact error
cd docker/
bash -x scripts/setup-multiple-rennys.sh

# Check Docker daemon status
docker info

# Validate current state
docker-compose ps -a
docker-compose logs renny-second  # For specific container logs
```

### Rollback Instructions

If something goes wrong and you need to return to the previous state:

1. **Revert to Single Instance**

   ```bash
   cd docker/
   ./scripts/setup-multiple-rennys.sh
   # When prompted, enter: 1
   ```

2. **Manually Stop Additional Instances**

   ```bash
   docker stop renny-second renny-third renny-fourth
   docker rm renny-second renny-third renny-fourth
   ```

3. **Restore Original Docker Compose**

   ```bash
   cd docker/
   # If you have git, discard changes
   git checkout docker-compose.full.yml

   # Or manually remove extra service definitions
   ```

4. **Verify Rollback**

   ```bash
   docker-compose ps
   # Should show only original services
   curl http://localhost:8081/health
   # Primary instance should respond
   ```

## Technical Details

### Files Modified by Setup Script

When you run `./scripts/setup-multiple-rennys.sh`, the following files are modified:

| File | Change | Purpose |
|------|--------|---------|
| `docker-compose.full.yml` | Add renny-second, renny-third, etc. services | Define additional container instances |
| `.miniprem_renny_config` | Updated with instance count | Store configuration state |
| docker-compose | Automatically reloaded | Apply new service definitions |

### YAML Structure Changes

Original docker-compose.full.yml (simplified):

```yaml
services:
  renny:
    container_name: renny
    image: "cr.uneeq.io/uneeq/renny-renderer:0.1332-decd6"
    ports:
      - "8080:8080"
      - "8081:8081"
    env_file:
      - docker-compose.env
    environment:
      - NEW_SPEECH_OVERRIDE=1
      - PLATFORM=docker
```

After adding second instance:

```yaml
services:
  renny:
    container_name: renny
    image: "cr.uneeq.io/uneeq/renny-renderer:0.1332-decd6"
    ports:
      - "8080:8080"
      - "8081:8081"
    env_file:
      - docker-compose.env
    environment:
      - NEW_SPEECH_OVERRIDE=1
      - PLATFORM=docker

  renny-second:
    container_name: renny-second
    image: "cr.uneeq.io/uneeq/renny-renderer:0.1332-decd6"
    ports:
      - "8090:8090"
      - "8091:8091"
    env_file:
      - docker-compose.env
    environment:
      - NEW_SPEECH_OVERRIDE=1
      - PLATFORM=docker
```

### Environment Variable Differences

All instances share the same environment variables through `docker-compose.env`:

```bash
# docker-compose.env (shared by all instances)
DHOP_ADDRESS=<your-uneeq-server>
DHOP_APIKEY=<your-api-key>
DHOP_TENANTID=<your-tenant-id>
AZURE_REGION=<optional-region>
AZURE_SPEECH=<optional-speech-key>
```

No per-instance environment variable overrides are needed. All configuration is centralized.

### Integration with miniprem.sh

The `miniprem.sh` management script automatically handles all instances:

```bash
# Start all Renny instances
./miniprem.sh start

# Stop all instances
./miniprem.sh stop

# Check status (shows all instances)
./miniprem.sh status

# View logs from all instances
./miniprem.sh logs

# Restart all instances
./miniprem.sh restart
```

Under the hood, `miniprem.sh` uses:

```bash
docker-compose -f docker/docker-compose.full.yml up -d
docker-compose -f docker/docker-compose.full.yml down
docker-compose -f docker/docker-compose.full.yml ps
```

These commands automatically handle all services defined in the compose file, including all Renny instances.

## Best Practices

### Start Conservative

When first configuring multiple instances:

1. **Start with 2 instances**: Verify they both work before adding more
   ```bash
   ./scripts/setup-multiple-rennys.sh
   # Enter: 2
   ```

2. **Monitor GPU and CPU**: Let it run for 5-10 minutes
   ```bash
   watch -n 1 nvidia-smi
   docker stats
   ```

3. **Verify health checks pass**: All instances should show "healthy"
   ```bash
   docker ps | grep renny
   ```

4. **Test connectivity**: Manually test health endpoints
   ```bash
   for port in 8081 8091; do
     curl http://localhost:$port/health
   done
   ```

5. **Gradually increase**: Add instances one at a time
   ```bash
   # After 2 instances work well, scale to 3
   ./scripts/setup-multiple-rennys.sh
   # Enter: 3
   ```

### Monitor GPU Utilization

Continuously monitor GPU metrics:

```bash
# Terminal 1: Real-time GPU monitoring
watch -n 2 'nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature --format=csv,noheader'

# Terminal 2: Per-process GPU usage
watch -n 2 'nvidia-smi pmon -c 5'

# Terminal 3: Overall system stats
watch -n 2 'docker stats --no-stream'
```

**Warning signs to watch for:**

- GPU memory exceeding 85% capacity
- Temperature rising above 80°C
- Container restart loops
- Health check timeouts

### Test Health Checks After Deployment

Verify all instances are responding:

```bash
#!/bin/bash
# test-renny-health.sh

echo "Testing Renny instance health checks..."
passed=0
failed=0

for port in 8081 8091 8101 8111 8121; do
  response=$(curl -s -w "\n%{http_code}" http://localhost:$port/health 2>/dev/null)
  http_code=$(echo "$response" | tail -1)

  if [ "$http_code" = "200" ]; then
    echo "✓ Port $port: Healthy"
    ((passed++))
  else
    echo "✗ Port $port: Failed (HTTP $http_code)"
    ((failed++))
  fi
done

echo ""
echo "Results: $passed passed, $failed failed"
exit $failed
```

Run it:

```bash
chmod +x test-renny-health.sh
./test-renny-health.sh
```

### Keep Configurations Documented

Document your instance configuration:

```bash
# Create a documentation file
cat > RENNY_INSTANCES.md << 'EOF'
# MiniPrem Renny Configuration

## Deployment Date
- 2024-01-15

## Instance Configuration
- Total Instances: 3
- GPU: NVIDIA A10G (24GB)
- Average Memory per Instance: ~6GB

## Port Mapping
| Instance | Health Port | Status |
|----------|-------------|--------|
| renny | 8081 | Primary |
| renny-second | 8091 | Secondary |
| renny-third | 8101 | Tertiary |

## Load Distribution
- Production traffic: renny (primary)
- Backup: renny-second
- Development: renny-third

## Notes
- Start conservative with monitoring
- Monitor GPU temp to stay below 80°C
EOF
```

### Regular Maintenance

Implement regular maintenance checks:

```bash
#!/bin/bash
# monthly-renny-maintenance.sh

echo "MiniPrem Renny Maintenance Check"
echo "=================================="

# Check all instances running
echo "1. Instance Status:"
docker ps | grep renny

# Check GPU health
echo ""
echo "2. GPU Status:"
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader

# Check container logs for errors
echo ""
echo "3. Recent Errors (last 100 lines):"
for container in renny renny-second renny-third; do
  echo "--- $container ---"
  docker logs --tail 10 $container 2>&1 | grep -i error || echo "No errors"
done

# Check disk space
echo ""
echo "4. Disk Usage:"
du -sh docker/
du -sh ~/.docker/

# Recommendations
echo ""
echo "Recommendations:"
docker ps | grep -q unhealthy && echo "⚠ Warning: Unhealthy containers detected"
nvidia-smi | grep -q "100%" && echo "⚠ Warning: GPU at max capacity"
```

## Examples

### 2 Instance Setup Walkthrough

Scenario: You want to support 2 concurrent conversations.

1. **Verify prerequisites:**

   ```bash
   docker ps  # Confirm Docker is running
   nvidia-smi  # Confirm GPU available (at least 12GB free)
   ```

2. **Run setup script:**

   ```bash
   cd docker/
   ./scripts/setup-multiple-rennys.sh
   ```

3. **Respond to prompts:**

   ```
   How many total Renny instances do you want? (1-10): 2
   ```

4. **Verify configuration:**

   ```
   Configuration Summary:
   - First instance (renny): ports 8080-8081
   - Second instance (renny-second): ports 8090-8091

   Proceed with this configuration? (yes/no): yes
   ```

5. **Monitor startup:**

   ```bash
   docker ps | grep renny
   # Watch for both containers to reach "Up" status
   ```

6. **Test connectivity:**

   ```bash
   curl http://localhost:8081/health  # Should return 200
   curl http://localhost:8091/health  # Should return 200
   ```

7. **Monitor performance:**

   ```bash
   watch -n 2 nvidia-smi  # Observe GPU usage stabilizes
   ```

### 4 Instance Setup for ADA6000

Scenario: NVIDIA ADA6000 GPU (48GB VRAM) handling 4 concurrent conversations.

1. **Verify GPU capacity:**

   ```bash
   nvidia-smi -L
   # Output: GPU 0: NVIDIA RTX 6000 Ada (48GB)

   nvidia-smi | grep -i memory
   # Confirm 48GB total available
   ```

2. **Calculate requirements:**

   ```
   4 instances × 6GB average per instance = 24GB
   Headroom: 48GB - 24GB = 24GB free (50% utilization)
   Status: ✓ Safe configuration
   ```

3. **Run setup:**

   ```bash
   cd docker/
   ./scripts/setup-multiple-rennys.sh
   # Enter: 4
   ```

4. **Verify all running:**

   ```bash
   docker ps | grep renny | wc -l
   # Should output: 4
   ```

5. **Test all health endpoints:**

   ```bash
   for port in 8081 8091 8101 8111; do
     echo -n "Port $port: "
     curl -s http://localhost:$port/health | jq -r '.status'
   done
   ```

### Scaling from 2 to 4 Instances

Scenario: You're currently running 2 instances and need to expand to 4.

1. **Check current status:**

   ```bash
   docker ps | grep renny
   # Confirm: renny, renny-second running
   ```

2. **Run setup script:**

   ```bash
   cd docker/
   ./scripts/setup-multiple-rennys.sh
   ```

3. **Respond with new count:**

   ```
   How many total Renny instances do you want? (1-10): 4
   ```

4. **Confirm scaling:**

   ```
   Detected 2 existing instances
   Will add: 2 new instances

   Proceed? (yes/no): yes
   ```

5. **Watch new instances start:**

   ```bash
   # Terminal 1: Watch startup
   docker ps | grep renny

   # Terminal 2: Monitor GPU
   watch -n 1 nvidia-smi
   ```

6. **Verify all running:**

   ```bash
   docker ps | grep renny | wc -l
   # Should output: 4
   ```

7. **Performance baseline:**

   ```bash
   # Take baseline before load testing
   nvidia-smi > baseline.txt
   docker stats --no-stream >> baseline.txt

   # Now ready for 4 concurrent connections
   ```

### Reducing from 4 to 2 Instances

Scenario: Need to free up resources; reducing from 4 to 2 instances.

1. **Verify current configuration:**

   ```bash
   docker ps | grep renny | wc -l
   # Should output: 4
   ```

2. **Prepare for reduction:**

   ```bash
   # Stop accepting new connections to instances 3 and 4
   # or gracefully drain existing connections
   ```

3. **Run setup script:**

   ```bash
   cd docker/
   ./scripts/setup-multiple-rennys.sh
   ```

4. **Confirm reduction:**

   ```
   How many total Renny instances do you want? (1-10): 2
   ```

5. **Authorize removal:**

   ```
   Detected 4 existing instances
   Will remove: 2 instances (renny-third, renny-fourth)

   Proceed? (yes/no): yes
   ```

6. **Verify reduction:**

   ```bash
   docker ps | grep renny | wc -l
   # Should output: 2

   docker ps | grep renny
   # Should show only: renny, renny-second
   ```

7. **Free resources confirmed:**

   ```bash
   nvidia-smi | grep -i memory
   # GPU memory usage should decrease significantly
   ```

---

## Support and Further Help

For additional assistance:

- Check the [Troubleshooting Guide](/docs/troubleshooting.md)
- Review [Renny Documentation](/docs/guides/renny.md)
- Check logs: `docker logs renny-<instance-name>`
- Review Docker Compose configuration: `cat docker/docker-compose.full.yml | grep -A 30 "renny:"`

For production deployments with even higher concurrency, consider the Kubernetes deployment options in `/docs/guides/kubernetes-multi-cloud.md`.
