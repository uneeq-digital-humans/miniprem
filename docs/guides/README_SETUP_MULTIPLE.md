# Multiple Renny Configuration - Quick Start

## What This Script Does

`setup_multiple_rennys.sh` automatically configures multiple Renny containers to run in parallel on Docker, with:

- **Automatic port allocation** (8080-8111+ depending on instance count)
- **Per-instance environment files** (renny-second.env, renny-third.env, etc.)
- **Service definitions** automatically added to docker-compose.yml
- **Health verification** to ensure all containers are running
- **Idempotent operations** - can be run multiple times safely

## Quick Start

### Interactive Mode
```bash
cd /path/to/miniprem-2025
./docker/scripts/setup_multiple_rennys.sh
# Prompts for number of instances
```

### Direct Configuration
```bash
./docker/scripts/setup_multiple_rennys.sh -n 4
# Sets up 4 Renny instances immediately
```

## Before Running

Ensure you have:
1. Completed MiniPrem installation: `./docker/scripts/install_miniprem.sh`
2. Docker daemon running
3. Sufficient GPU VRAM (2-3 GB per instance minimum)

## Port Allocation

The script automatically assigns ports based on instance number:

| Instance | Health Port | Metrics Port | Container Name |
|----------|-------------|--------------|-----------------|
| 1 | 8081 | 8080 | `renny` |
| 2 | 8091 | 8090 | `renny-second` |
| 3 | 8101 | 8100 | `renny-third` |
| 4 | 8111 | 8110 | `renny-fourth` |

**Formula**: `base_port + (instance_num - 1) * 10`

## After Setup

```bash
# Check status
./miniprem.sh status

# View logs
./miniprem.sh logs

# Monitor dashboard
# Open browser: http://localhost:3001/

# Stop all services
./miniprem.sh stop

# Start all services
./miniprem.sh start
```

## What Gets Created

- **Environment files**: `docker/renny-{ordinal}.env` for each instance
- **Service definitions**: Added to your docker-compose.yml
- **Backup file**: `docker/docker-compose.yml.backup.{timestamp}`

## Troubleshooting

### "MiniPrem installation not completed"
```bash
./docker/scripts/install_miniprem.sh
```

### "Docker daemon is not running"
- Start Docker Desktop or daemon, then retry

### Port conflicts
```bash
# Check which process uses a port
lsof -i :8091
# Or stop the conflicting application
```

### Containers not starting
```bash
# Check logs
./miniprem.sh logs

# Or specific container
docker logs renny-second
```

## Instance Count Recommendations

- **2 instances**: Basic failover
- **3-4 instances**: Balanced (RECOMMENDED)
- **5-10 instances**: High capacity
- **Max 30 instances**: System limit

## Full Documentation

See [SETUP MULTIPLE RENNYS](../../docs/guides/SETUP_MULTIPLE_RENNYS.md) for comprehensive documentation including:
- Detailed workflow explanation
- Advanced configuration
- Performance considerations
- CI/CD integration examples
- Complete troubleshooting guide

## Examples

### Example 1: Set up 2 instances
```bash
./docker/scripts/setup_multiple_rennys.sh -n 2
```

### Example 2: Interactive setup
```bash
./docker/scripts/setup_multiple_rennys.sh
# Prompts: Enter number of Renny instances (2-30): 4
```

### Example 3: Scale from 2 to 5 instances
```bash
# Initial setup
./docker/scripts/setup_multiple_rennys.sh -n 2

# Later, expand to 5
./docker/scripts/setup_multiple_rennys.sh -n 5
# Script cleans old configuration and creates new setup
```

## File Locations

- **Script**: `docker/scripts/setup_multiple_rennys.sh`
- **Full Docs**: `docker/scripts/SETUP_MULTIPLE_RENNYS.md`
- **This File**: `docker/scripts/README_SETUP_MULTIPLE.md`
- **Compose File**: `docker/docker-compose.yml` (modified)
- **Env Files**: `docker/renny-{ordinal}.env` (created)
- **Backups**: `docker/docker-compose.yml.backup.*` (timestamped)

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review logs: `./miniprem.sh logs`
3. See full documentation: [SETUP MULTIPLE RENNYS](../../docs/guides/SETUP_MULTIPLE_RENNYS.md)
4. Run help: `./docker/scripts/setup_multiple_rennys.sh --help`
