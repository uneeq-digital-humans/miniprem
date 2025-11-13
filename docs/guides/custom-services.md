# MiniPrem Custom Services Guide

Complete guide to extending MiniPrem with custom Docker Compose services while preserving official updates.

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start (5 Minutes)](#quick-start-5-minutes)
3. [Detailed Guide](#detailed-guide)
4. [Common Patterns](#common-patterns)
5. [Merge Process](#merge-process)
6. [Updating MiniPrem](#updating-miniprem)
7. [CLI Commands](#cli-commands)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Topics](#advanced-topics)
10. [FAQ](#faq)

---

## Overview

### What Are Custom Services?

Custom services allow you to extend MiniPrem with additional Docker containers without modifying the official docker-compose files. This enables you to:

- Add databases (PostgreSQL, MySQL, MongoDB)
- Integrate caching layers (Redis, Memcached)
- Deploy custom APIs and microservices
- Include monitoring tools (Elasticsearch, Kibana)
- Add message queues (RabbitMQ, Kafka)

### How They Integrate

MiniPrem uses a **three-layer Docker Compose architecture**:

```
Layer 1: docker-compose.yml or docker-compose.full.yml
         ↓ (official MiniPrem services)
Layer 2: docker-compose.custom.yml
         ↓ (your custom services)
Layer 3: docker-compose.override.yml
         ↓ (merged result - auto-generated)
```

When you run `./miniprem.sh start`, Docker Compose automatically merges all three layers, giving you official services + your customizations.

### Benefits

- **Update-safe**: Pull official MiniPrem updates without losing your custom services
- **Isolated configuration**: Keep your services separate from official configs
- **Version control friendly**: Track custom services in your own repository
- **Modular**: Enable/disable custom services independently
- **No conflicts**: Official services and custom services coexist peacefully

### Use Cases

- **Development**: Add debugging tools, test databases, mock services
- **Integration**: Connect MiniPrem to existing infrastructure (databases, APIs)
- **Monitoring**: Enhanced logging, metrics, and observability stacks
- **Data processing**: ETL pipelines, data warehouses, analytics
- **Custom backends**: Your own API services that interact with MiniPrem

---

## Quick Start (5 Minutes)

### Step 1: Copy the Template

```bash
cd docker/
cp docker-compose.custom.yml.template docker-compose.custom.yml
```

If the template doesn't exist, create it:

```bash
cat > docker-compose.custom.yml <<'EOF'
# MiniPrem Custom Services
# This file is never overwritten by MiniPrem updates
# Add your custom services here

name: uneeq-miniprem

services:
  # Example: PostgreSQL database
  # postgres:
  #   image: postgres:16-alpine
  #   container_name: miniprem-postgres
  #   environment:
  #     - POSTGRES_USER=${DB_USER:-miniprem}
  #     - POSTGRES_PASSWORD=${DB_PASSWORD:-changeme}
  #     - POSTGRES_DB=${DB_NAME:-miniprem}
  #   ports:
  #     - "5432:5432"
  #   volumes:
  #     - postgres_data:/var/lib/postgresql/data
  #   restart: unless-stopped
  #   network_mode: host
  #   healthcheck:
  #     test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-miniprem}"]
  #     interval: 10s
  #     timeout: 5s
  #     retries: 5

# volumes:
#   postgres_data:
EOF
```

### Step 2: Add Your Service

Uncomment the PostgreSQL example (or add your own service):

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: miniprem-postgres
    environment:
      - POSTGRES_USER=miniprem
      - POSTGRES_PASSWORD=changeme
      - POSTGRES_DB=miniprem
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U miniprem"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Step 3: Start Services

```bash
./miniprem.sh start
```

Docker Compose automatically detects `docker-compose.custom.yml` and merges it with the official configuration.

### Step 4: Verify

```bash
docker ps | grep miniprem-postgres
# or
./miniprem.sh status
```

That's it! Your custom service is now running alongside MiniPrem.

---

## Detailed Guide

### Architecture Overview

#### The Three-Layer System

**Layer 1: Official MiniPrem Configuration**
- `docker-compose.yml` (default install: Renny + Monitor)
- `docker-compose.full.yml` (full install: all services)
- Managed by MiniPrem maintainers
- Updated via `git pull`
- **Never edit these files directly**

**Layer 2: Custom Services Configuration**
- `docker-compose.custom.yml` (your file)
- Add any services you need
- **Never overwritten by MiniPrem updates**
- Tracked in your own version control

**Layer 3: Merged Configuration**
- `docker-compose.override.yml` (auto-generated, optional)
- Docker Compose merges layers 1 + 2 automatically
- You can pre-generate this for validation

#### How Docker Compose Merges Files

Docker Compose automatically merges multiple configuration files in this order:

1. `docker-compose.yml` or `docker-compose.full.yml` (base)
2. `docker-compose.custom.yml` (if present)
3. `docker-compose.override.yml` (if present)

**Merge rules:**
- Services with different names are combined
- Services with the same name have their properties merged
- Arrays (ports, volumes) are concatenated
- Scalars (image, container_name) are overridden

### Naming Conventions

To avoid conflicts with official services, follow these naming guidelines:

#### Container Names
Prefix custom containers with `miniprem-`:

```yaml
services:
  postgres:
    container_name: miniprem-postgres  # ✅ Good
    # container_name: postgres         # ❌ Bad - might conflict
```

#### Service Names
Use descriptive, unique names:

```yaml
services:
  my-api:              # ✅ Good - clearly custom
    ...
  custom-cache:        # ✅ Good - prefixed
    ...
  redis:               # ⚠️  Careful - MiniPrem full install has redis
    ...
```

#### Volume Names
Prefix volumes to avoid collisions:

```yaml
volumes:
  my_app_data:         # ✅ Good
  custom_postgres:     # ✅ Good
  redis_data:          # ⚠️  Careful - MiniPrem uses this in full install
```

#### Network Names
MiniPrem uses `host` networking by default. If you create custom networks:

```yaml
networks:
  miniprem-custom:     # ✅ Good
    driver: bridge
```

### Best Practices for Custom Services

#### 1. Use Environment Variables

Never hardcode sensitive values:

```yaml
# ❌ BAD
services:
  mydb:
    environment:
      - DB_PASSWORD=supersecret123

# ✅ GOOD
services:
  mydb:
    environment:
      - DB_PASSWORD=${MYDB_PASSWORD}
```

Create a `.env` file in the `docker/` directory:

```bash
# docker/.env
MYDB_PASSWORD=supersecret123
```

Add `.env` to `.gitignore`:

```bash
echo ".env" >> docker/.gitignore
```

#### 2. Add Health Checks

Ensure services are truly ready before dependencies start:

```yaml
services:
  mydb:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

#### 3. Use Persistent Volumes

Don't lose data when containers restart:

```yaml
services:
  mydb:
    volumes:
      - mydb_data:/var/lib/postgresql/data  # Named volume (persistent)
      # - /tmp/data:/data                    # Host path (ephemeral on macOS/Windows)

volumes:
  mydb_data:  # Define at bottom of file
```

#### 4. Configure Logging

Prevent log files from consuming disk space:

```yaml
services:
  myapp:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

#### 5. Add Restart Policies

Keep services running after crashes or reboots:

```yaml
services:
  myapp:
    restart: unless-stopped  # Recommended
    # restart: always         # Too aggressive (restarts even if you stop manually)
    # restart: on-failure     # Only restart on errors
    # restart: "no"           # Never restart (default)
```

#### 6. Security Hardening

```yaml
services:
  myapp:
    security_opt:
      - no-new-privileges:true  # Prevent privilege escalation
    read_only: true             # Make filesystem read-only (if possible)
    user: "1000:1000"           # Run as non-root user
    cap_drop:
      - ALL                     # Drop all capabilities
    cap_add:
      - NET_BIND_SERVICE        # Only add what's needed
```

#### 7. Resource Limits

Prevent services from consuming all system resources:

```yaml
services:
  myapp:
    deploy:
      resources:
        limits:
          cpus: '2.0'           # Max 2 CPU cores
          memory: 4G            # Max 4GB RAM
        reservations:
          cpus: '0.5'           # Guaranteed 0.5 cores
          memory: 1G            # Guaranteed 1GB RAM
```

---

## Common Patterns

### PostgreSQL Database

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: miniprem-postgres
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-miniprem}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_DB=${POSTGRES_DB:-miniprem}
      - PGDATA=/var/lib/postgresql/data/pgdata
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-miniprem}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  postgres_data:
```

### MySQL Database

```yaml
services:
  mysql:
    image: mysql:8.0
    container_name: miniprem-mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-changeme}
      - MYSQL_DATABASE=${MYSQL_DATABASE:-miniprem}
      - MYSQL_USER=${MYSQL_USER:-miniprem}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD:-changeme}
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD:-changeme}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  mysql_data:
```

### MongoDB Database

```yaml
services:
  mongodb:
    image: mongo:7.0
    container_name: miniprem-mongodb
    environment:
      - MONGO_INITDB_ROOT_USERNAME=${MONGO_USER:-admin}
      - MONGO_INITDB_ROOT_PASSWORD=${MONGO_PASSWORD:-changeme}
      - MONGO_INITDB_DATABASE=${MONGO_DB:-miniprem}
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
      - mongodb_config:/data/configdb
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  mongodb_data:
  mongodb_config:
```

### Redis Cache

> **Note**: MiniPrem full install already includes Redis. Only add this if you need a separate Redis instance.

```yaml
services:
  custom-redis:
    image: redis:7-alpine
    container_name: miniprem-custom-redis
    ports:
      - "6380:6379"  # Different port to avoid conflict
    volumes:
      - custom_redis_data:/data
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-changeme}
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  custom_redis_data:
```

### RabbitMQ Message Queue

```yaml
services:
  rabbitmq:
    image: rabbitmq:3.13-management-alpine
    container_name: miniprem-rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-admin}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD:-changeme}
    ports:
      - "5672:5672"   # AMQP port
      - "15672:15672" # Management UI
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  rabbitmq_data:
```

### Elasticsearch + Kibana

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: miniprem-elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: miniprem-kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://localhost:9200
    ports:
      - "5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  elasticsearch_data:
```

### Custom FastAPI Backend

```yaml
services:
  custom-api:
    build:
      context: ./custom-api
      dockerfile: Dockerfile
    container_name: miniprem-custom-api
    environment:
      - API_KEY=${CUSTOM_API_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}
    ports:
      - "8080:8080"
    volumes:
      - ./custom-api:/app  # For development (hot reload)
    restart: unless-stopped
    network_mode: host
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## Merge Process

### How Merge Works

Docker Compose performs an **automatic merge** when multiple configuration files are present. You don't need to run a merge script manually - Docker Compose handles it.

#### Automatic Merge (Recommended)

Just create `docker-compose.custom.yml` and run:

```bash
./miniprem.sh start
```

Docker Compose automatically finds and merges:
1. `docker-compose.yml` or `docker-compose.full.yml`
2. `docker-compose.custom.yml`
3. `docker-compose.override.yml` (if exists)

#### Manual Merge Validation (Optional)

To see the merged result before starting services:

```bash
cd docker/
docker compose -f docker-compose.yml -f docker-compose.custom.yml config > docker-compose.merged.yml
# or for full install:
docker compose -f docker-compose.full.yml -f docker-compose.custom.yml config > docker-compose.merged.yml
```

This generates the merged configuration for inspection.

### Conflict Resolution

#### Scenario 1: Different Service Names

**No conflict** - services are simply combined:

```yaml
# docker-compose.yml
services:
  renny:
    image: facemeproduction/renny:latest
    ...

# docker-compose.custom.yml
services:
  postgres:
    image: postgres:16
    ...

# Result: Both renny and postgres run
```

#### Scenario 2: Same Service Name, Different Properties

Properties are **merged** (arrays concatenated, scalars overridden):

```yaml
# docker-compose.yml
services:
  renny:
    image: facemeproduction/renny:latest
    ports:
      - "8081:8081"
    environment:
      - VAR1=value1

# docker-compose.custom.yml
services:
  renny:
    ports:
      - "8082:8082"  # Added to existing ports
    environment:
      - VAR2=value2  # Added to existing environment

# Result:
services:
  renny:
    image: facemeproduction/renny:latest
    ports:
      - "8081:8081"
      - "8082:8082"  # Both ports
    environment:
      - VAR1=value1
      - VAR2=value2  # Both variables
```

#### Scenario 3: Same Service Name, Same Property

**Last file wins** (override):

```yaml
# docker-compose.yml
services:
  renny:
    image: facemeproduction/renny:0.758-f9e3f
    container_name: renny

# docker-compose.custom.yml
services:
  renny:
    image: facemeproduction/renny:0.800-custom  # Override

# Result:
services:
  renny:
    image: facemeproduction/renny:0.800-custom  # Custom wins
    container_name: renny
```

> **Warning**: Overriding official services can break MiniPrem. Only do this if you know what you're doing.

### Understanding docker-compose.override.yml

This file, if present, is **always applied last** and has the highest priority:

```
Priority: docker-compose.yml < docker-compose.custom.yml < docker-compose.override.yml
```

**Use cases:**
- Local development overrides (don't commit to git)
- Temporary testing configurations
- Environment-specific tweaks

**Best practice:** Add to `.gitignore`:

```bash
echo "docker-compose.override.yml" >> docker/.gitignore
```

---

## Updating MiniPrem

### Step-by-Step Update Process

#### 1. Back Up Your Custom Configuration

Before pulling updates:

```bash
cd docker/
cp docker-compose.custom.yml docker-compose.custom.yml.backup
cp .env .env.backup  # If you have environment variables
```

#### 2. Pull Official Updates

```bash
cd /path/to/miniprem-2025/
git pull origin main
```

#### 3. Review Changes

Check what changed in official files:

```bash
git log --oneline -10                    # Recent commits
git diff HEAD~1 docker/docker-compose.yml # Changes to default compose
git diff HEAD~1 docker/docker-compose.full.yml  # Changes to full compose
```

#### 4. Verify Custom Services Still Work

```bash
cd docker/
docker compose -f docker-compose.yml -f docker-compose.custom.yml config
# or
docker compose -f docker-compose.full.yml -f docker-compose.custom.yml config
```

Look for errors or warnings in the output.

#### 5. Restart Services

```bash
./miniprem.sh stop
./miniprem.sh start
```

#### 6. Check Service Status

```bash
./miniprem.sh status
docker ps -a | grep miniprem
```

Ensure all custom services are running.

### Handling Conflicts

#### Scenario: MiniPrem Adds a Service You're Using

**Example:** You added a custom PostgreSQL service, and MiniPrem now includes PostgreSQL officially.

**Solution 1: Rename Your Service**

```yaml
# docker-compose.custom.yml (before)
services:
  postgres:
    image: postgres:16
    container_name: miniprem-postgres
    ...

# docker-compose.custom.yml (after)
services:
  custom-postgres:  # Renamed
    image: postgres:16
    container_name: miniprem-custom-postgres
    ...
```

Update any services that depend on it:

```yaml
services:
  my-api:
    environment:
      - DATABASE_URL=postgresql://user:pass@localhost:5433/db  # New port
```

**Solution 2: Remove Your Custom Service**

If the official service meets your needs:

```bash
# Remove custom postgres from docker-compose.custom.yml
# Update dependent services to use official postgres connection details
./miniprem.sh restart
```

#### Scenario: Port Conflicts

**Example:** MiniPrem adds a service on port 8080, which you're using.

**Solution: Change Your Service Port**

```yaml
# docker-compose.custom.yml
services:
  my-api:
    ports:
      - "8081:8080"  # Changed from 8080:8080
```

#### Scenario: Volume Name Conflicts

**Example:** MiniPrem adds a volume with the same name as yours.

**Solution: Rename Your Volume**

```yaml
# docker-compose.custom.yml (before)
volumes:
  app_data:

# docker-compose.custom.yml (after)
volumes:
  custom_app_data:

# Update service to use new volume name
services:
  my-app:
    volumes:
      - custom_app_data:/data
```

### Handling Deprecated Services

If MiniPrem removes a service you depend on:

#### 1. Check Release Notes

```bash
git log --grep="remove\|deprecate" --oneline -20
```

#### 2. Add Removed Service to Custom Config

Copy the service definition from the previous version:

```bash
git show HEAD~1:docker/docker-compose.full.yml | grep -A 20 "service-name"
```

Paste into `docker-compose.custom.yml`.

#### 3. Update Dependencies

If other services depend on the removed service, adjust your configuration accordingly.

---

## CLI Commands

### Current MiniPrem Commands

```bash
./miniprem.sh start     # Start services (includes custom services)
./miniprem.sh stop      # Stop all services
./miniprem.sh restart   # Restart all services
./miniprem.sh status    # Check service status
./miniprem.sh logs      # View service logs
./miniprem.sh setup     # Run Flowise chatflow setup
```

### Useful Docker Compose Commands

#### View Merged Configuration

```bash
cd docker/
docker compose config  # Shows final merged configuration
```

#### List All Services

```bash
docker compose ps      # Running services
docker compose ps -a   # All services (including stopped)
```

#### Start Specific Service

```bash
docker compose up -d postgres  # Start only postgres
```

#### Stop Specific Service

```bash
docker compose stop postgres   # Stop postgres
```

#### View Service Logs

```bash
docker compose logs -f postgres         # Follow postgres logs
docker compose logs --tail=100 postgres # Last 100 lines
```

#### Restart Specific Service

```bash
docker compose restart postgres
```

#### Rebuild Service After Code Changes

```bash
docker compose up -d --build custom-api
```

#### Remove Service and Volumes

```bash
docker compose down postgres            # Remove container
docker compose down -v postgres         # Remove container + volume
```

#### Validate Configuration

```bash
docker compose config --quiet  # Exit code 0 = valid, 1 = invalid
```

### Proposed Custom Service Commands

These commands could be added to `miniprem.sh`:

```bash
# List custom services
./miniprem.sh custom list

# Add a custom service from template
./miniprem.sh custom add postgres

# Validate custom configuration
./miniprem.sh validate

# Show merged configuration
./miniprem.sh config

# Pull latest images (official + custom)
./miniprem.sh pull
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue: Custom Service Not Starting

**Symptoms:**
```bash
docker ps | grep my-service
# No output
```

**Diagnosis:**

```bash
docker compose ps -a | grep my-service  # Check if container exists
docker compose logs my-service          # Check logs
docker inspect my-service               # Detailed info
```

**Common causes:**

1. **Port conflict**
   ```bash
   # Check if port is already in use
   lsof -i :8080  # macOS/Linux
   netstat -ano | findstr :8080  # Windows
   ```
   **Solution:** Change the port in `docker-compose.custom.yml`

2. **Missing environment variable**
   ```bash
   docker compose config | grep -A 5 my-service
   # Check if environment variables are resolved
   ```
   **Solution:** Add missing variables to `docker/.env`

3. **Image pull failure**
   ```bash
   docker compose logs my-service | grep -i "error\|failed"
   ```
   **Solution:** Check image name, Docker Hub authentication

4. **Health check failure**
   ```bash
   docker inspect my-service | grep -A 10 Health
   ```
   **Solution:** Adjust health check command or increase start_period

#### Issue: Service Crashes Immediately

**Diagnosis:**

```bash
docker compose logs --tail=50 my-service
docker inspect my-service | grep -i state -A 10
```

**Common causes:**

1. **Missing required environment variable**
   ```yaml
   # Add default values
   environment:
     - MY_VAR=${MY_VAR:-default_value}
   ```

2. **Wrong command or entrypoint**
   ```bash
   docker compose config | grep -A 5 "my-service"
   # Verify command looks correct
   ```

3. **Volume mount issues**
   ```bash
   ls -la /path/to/host/volume  # Check permissions
   ```
   **Solution:** Fix permissions or use named volumes

#### Issue: Cannot Connect to Custom Service

**Symptoms:**
```bash
curl http://localhost:8080
# Connection refused
```

**Diagnosis:**

```bash
docker compose ps | grep my-service  # Is it running?
docker compose logs my-service       # Any errors?
docker port my-service               # Port mappings
```

**Common causes:**

1. **Service not using host networking**
   ```yaml
   # docker-compose.custom.yml
   services:
     my-service:
       network_mode: host  # Add this
   ```

2. **Service listening on 127.0.0.1 instead of 0.0.0.0**
   ```yaml
   # Configure your app to bind to 0.0.0.0
   environment:
     - HOST=0.0.0.0  # Not 127.0.0.1
   ```

3. **Firewall blocking the port**
   ```bash
   sudo ufw allow 8080  # Linux
   # Or configure Windows Firewall / macOS firewall
   ```

#### Issue: Merge Validation Errors

**Symptoms:**
```bash
docker compose config
# Error: services.my-service.ports contains an invalid type
```

**Diagnosis:**

```bash
docker compose -f docker-compose.yml config  # Test official file
docker compose -f docker-compose.custom.yml config  # Test custom file
```

**Solution:** Fix YAML syntax in `docker-compose.custom.yml`:

```yaml
# ❌ Wrong
ports:
  - 8080:8080  # Missing quotes

# ✅ Correct
ports:
  - "8080:8080"
```

#### Issue: Volume Data Not Persisting

**Symptoms:** Data lost after container restart.

**Diagnosis:**

```bash
docker volume ls | grep my-volume
docker volume inspect my_volume
```

**Common causes:**

1. **Using host path instead of named volume**
   ```yaml
   # ❌ Bad (ephemeral on some systems)
   volumes:
     - /tmp/data:/data

   # ✅ Good (persistent)
   volumes:
     - myapp_data:/data

   volumes:
     myapp_data:  # Define at bottom
   ```

2. **Volume not defined**
   ```yaml
   services:
     myapp:
       volumes:
         - myapp_data:/data  # Referenced

   volumes:
     myapp_data:  # Must be defined here
   ```

#### Issue: High Memory/CPU Usage

**Diagnosis:**

```bash
docker stats  # Real-time resource usage
docker stats --no-stream | grep my-service
```

**Solution:** Add resource limits:

```yaml
services:
  my-service:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
```

### Debugging Service Connectivity

#### Test Network Connectivity

```bash
# From host to container
curl http://localhost:8080/health

# From container to container (if using host networking)
docker exec my-service curl http://localhost:5432

# From container to host
docker exec my-service ping host.docker.internal
```

#### Inspect Network Configuration

```bash
docker network ls
docker network inspect host  # If using network_mode: host
```

#### Check DNS Resolution

```bash
docker exec my-service nslookup postgres
docker exec my-service cat /etc/hosts
```

### Checking Docker Logs

#### View Logs for All Custom Services

```bash
docker compose logs -f $(docker compose config --services | grep -v "renny\|flowise\|vllm")
```

#### Search Logs for Errors

```bash
docker compose logs | grep -i "error\|exception\|failed"
```

#### Export Logs for Analysis

```bash
docker compose logs --no-color > /tmp/miniprem-logs.txt
```

### Resetting to Defaults

#### Remove Custom Services Only

```bash
# Stop custom services
docker compose stop $(docker compose config --services | grep -v "renny\|flowise\|vllm")

# Remove custom services
docker compose rm -f $(docker compose config --services | grep -v "renny\|flowise\|vllm")
```

#### Complete Reset (All Services)

```bash
cd docker/
./miniprem.sh stop
docker compose down -v  # Remove all containers and volumes
rm docker-compose.custom.yml  # Remove custom config
./miniprem.sh start  # Start fresh
```

#### Reset Custom Configuration

```bash
cd docker/
cp docker-compose.custom.yml docker-compose.custom.yml.old
cp docker-compose.custom.yml.template docker-compose.custom.yml
```

---

## Advanced Topics

### Environment Variable Management

#### Centralized .env File

Create `docker/.env` for all environment variables:

```bash
# docker/.env

# PostgreSQL
POSTGRES_USER=miniprem
POSTGRES_PASSWORD=secure_password_here
POSTGRES_DB=miniprem

# Custom API
API_KEY=your_api_key_here
API_SECRET=your_api_secret_here

# Redis
REDIS_PASSWORD=redis_password_here

# Common
TZ=America/New_York
```

Reference in `docker-compose.custom.yml`:

```yaml
services:
  postgres:
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
```

#### Per-Service .env Files

```yaml
services:
  my-api:
    env_file:
      - .env                 # Common variables
      - .env.my-api          # Service-specific variables
```

### Secret Handling

> **Never commit secrets to version control!**

#### Using Environment Variables (Basic)

```bash
# .env (add to .gitignore)
DB_PASSWORD=super_secret

# .env.example (commit to git)
DB_PASSWORD=changeme
```

#### Using Docker Secrets (Advanced)

For production environments:

```yaml
# docker-compose.custom.yml
services:
  postgres:
    secrets:
      - db_password
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt  # Add to .gitignore
```

Create secret:

```bash
mkdir -p docker/secrets
echo "super_secret_password" > docker/secrets/db_password.txt
chmod 600 docker/secrets/db_password.txt
echo "secrets/" >> docker/.gitignore
```

### Multi-Environment Setups

#### Development Environment

```yaml
# docker-compose.custom.dev.yml
services:
  my-api:
    build:
      context: ./custom-api
      target: development  # Multi-stage Dockerfile
    volumes:
      - ./custom-api:/app  # Hot reload
    environment:
      - DEBUG=true
      - LOG_LEVEL=debug
```

Run with:

```bash
docker compose -f docker-compose.yml -f docker-compose.custom.yml -f docker-compose.custom.dev.yml up
```

#### Production Environment

```yaml
# docker-compose.custom.prod.yml
services:
  my-api:
    build:
      context: ./custom-api
      target: production
    restart: always
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
    environment:
      - DEBUG=false
      - LOG_LEVEL=warning
```

### Performance Tuning

#### Database Optimization

**PostgreSQL:**

```yaml
services:
  postgres:
    environment:
      - POSTGRES_INITDB_ARGS=--data-checksums --encoding=UTF8
    command:
      - postgres
      - -c max_connections=200
      - -c shared_buffers=256MB
      - -c effective_cache_size=1GB
      - -c maintenance_work_mem=64MB
      - -c checkpoint_completion_target=0.9
      - -c wal_buffers=16MB
      - -c default_statistics_target=100
```

**MongoDB:**

```yaml
services:
  mongodb:
    command:
      - mongod
      - --wiredTigerCacheSizeGB 1.5
      - --wiredTigerCollectionBlockCompressor snappy
```

#### Redis Optimization

```yaml
services:
  redis:
    command:
      - redis-server
      - --maxmemory 2gb
      - --maxmemory-policy allkeys-lru
      - --save 900 1 300 10 60 10000  # Persistence tuning
      - --appendonly yes
      - --tcp-backlog 511
```

### Resource Limits Best Practices

#### CPU Limits

```yaml
services:
  # CPU-intensive service
  my-worker:
    deploy:
      resources:
        limits:
          cpus: '4.0'        # Max 4 cores
        reservations:
          cpus: '1.0'        # Guaranteed 1 core

  # Lightweight service
  my-api:
    deploy:
      resources:
        limits:
          cpus: '0.5'        # Max 0.5 core
```

#### Memory Limits

```yaml
services:
  # Memory-intensive service (ML model, database)
  my-ml-service:
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          memory: 4G

  # Standard web service
  my-api:
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
```

#### GPU Allocation

```yaml
services:
  my-gpu-service:
    runtime: nvidia
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1              # Number of GPUs
              capabilities: [gpu]
```

### Advanced Networking

#### Custom Bridge Network

```yaml
# docker-compose.custom.yml
services:
  my-api:
    networks:
      - custom-network

  postgres:
    networks:
      - custom-network

networks:
  custom-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

#### Service Discovery

Services on the same network can reference each other by service name:

```yaml
services:
  my-api:
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/db
    networks:
      - app-network

  postgres:
    networks:
      - app-network

networks:
  app-network:
```

---

## FAQ

### Can I modify official MiniPrem services?

**Yes, but carefully.** You can override service properties in `docker-compose.custom.yml`:

```yaml
# docker-compose.custom.yml
services:
  renny:  # Official service
    environment:
      - MY_CUSTOM_VAR=value  # Add environment variable
```

However:

- **Avoid changing `image:`** - breaks official functionality
- **Avoid changing `command:` or `entrypoint:`** - may cause crashes
- **Safe to add:** environment variables, volumes, labels
- **Risky to change:** ports, networks, depends_on

**Better approach:** If you need substantial modifications, create a new service that depends on the official one.

### What about volumes and networks?

**Volumes:**

- Official MiniPrem volumes are defined in `docker-compose.yml` or `docker-compose.full.yml`
- You can create your own volumes in `docker-compose.custom.yml`
- You can mount official volumes in custom services (careful with data integrity)

```yaml
# docker-compose.custom.yml
services:
  my-backup-service:
    volumes:
      - flowise_data:/backup/flowise:ro  # Mount official volume read-only

volumes:
  flowise_data:
    external: true  # Indicates this is defined elsewhere
```

**Networks:**

- MiniPrem uses `host` networking by default
- Custom services should also use `host` networking for simplicity
- You can create custom bridge networks if needed

### Can custom services depend on official ones?

**Yes!** Use `depends_on`:

```yaml
# docker-compose.custom.yml
services:
  my-api:
    depends_on:
      redis:
        condition: service_healthy  # Wait for official redis to be healthy
      flowise:
        condition: service_started  # Wait for flowise to start
```

**Note:** This only works if the official service has a health check defined.

### What if MiniPrem adds a service I'm also adding?

**Three options:**

#### 1. Rename Your Service

```yaml
# docker-compose.custom.yml
services:
  custom-postgres:  # Rename from 'postgres' to 'custom-postgres'
    image: postgres:16
    container_name: miniprem-custom-postgres
    ports:
      - "5433:5432"  # Different port
```

#### 2. Remove Your Custom Service

If the official service meets your needs:

```bash
# Edit docker-compose.custom.yml and remove your service
# Update any dependent services to use official service instead
./miniprem.sh restart
```

#### 3. Keep Both Services

If you need both:

```yaml
# docker-compose.custom.yml
services:
  custom-postgres:  # Your custom PostgreSQL
    image: postgres:16
    ports:
      - "5433:5432"  # Different port
    volumes:
      - custom_postgres_data:/var/lib/postgresql/data

  # Official postgres runs on port 5432
  # Your custom postgres runs on port 5433

volumes:
  custom_postgres_data:
```

### How do I update a custom service?

#### Update Image Version

```yaml
# docker-compose.custom.yml
services:
  postgres:
    image: postgres:17-alpine  # Changed from postgres:16-alpine
```

Then:

```bash
docker compose pull postgres    # Pull new image
docker compose up -d postgres   # Recreate container
```

#### Update Service Configuration

```yaml
# docker-compose.custom.yml
services:
  postgres:
    environment:
      - POSTGRES_MAX_CONNECTIONS=200  # Add new config
```

Then:

```bash
docker compose up -d postgres   # Recreate container
```

#### Update Service Code (Custom Built Images)

```bash
# Edit your code in ./custom-api/
docker compose up -d --build custom-api  # Rebuild and restart
```

### How do I share custom services with my team?

#### 1. Version Control

```bash
cd docker/
git add docker-compose.custom.yml
git add .env.example  # Template for environment variables
git commit -m "Add custom PostgreSQL service"
git push
```

#### 2. Documentation

Create `docker/CUSTOM_SERVICES_TEAM.md`:

```markdown
# Team Custom Services

## Setup Instructions

1. Copy environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and fill in credentials:
   ```bash
   vim .env  # Set POSTGRES_PASSWORD, API_KEY, etc.
   ```

3. Start services:
   ```bash
   ./miniprem.sh start
   ```

## Custom Services

- **postgres**: Team database (port 5432)
- **custom-api**: Our internal API (port 8080)
```

#### 3. Team Onboarding

```bash
# New team member setup
git clone <your-repo>
cd miniprem-2025/docker
cp .env.example .env
# Edit .env with credentials from team secrets manager
./miniprem.sh start
```

### Can I use Docker Swarm or Kubernetes?

**Docker Swarm:**

Yes, but requires modifications. Docker Compose v3 syntax with deploy keys:

```yaml
# docker-compose.custom.swarm.yml
version: '3.8'
services:
  postgres:
    image: postgres:16
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == worker
```

Deploy with:

```bash
docker stack deploy -c docker-compose.yml -c docker-compose.custom.swarm.yml miniprem
```

**Kubernetes:**

MiniPrem already has Kubernetes support in `kubernetes/` directory. For custom services:

```bash
kubectl apply -f custom-postgres.yaml
```

See `kubernetes/manifests/` for examples.

### What's the performance impact of custom services?

**Depends on:**

- **Number of services**: Each container has overhead (~50-200MB RAM)
- **Resource limits**: Properly configured limits prevent contention
- **Disk I/O**: Multiple databases can cause I/O bottlenecks
- **Network**: Host networking is faster than bridge networking

**Best practices:**

1. Use resource limits on all custom services
2. Monitor with `docker stats`
3. Use named volumes (faster than bind mounts on macOS/Windows)
4. Keep lightweight services (alpine images when possible)

**Example monitoring:**

```bash
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
```

---

## Additional Resources

### Official Documentation

- [Docker Compose File Reference](https://docs.docker.com/compose/compose-file/)
- [Docker Compose CLI Reference](https://docs.docker.com/compose/reference/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

### MiniPrem Documentation

- **Main README**: `/Users/tyler/Software_Development/miniprem-2025/README.md`
- **Docker Installation Guide**: `/Users/tyler/Software_Development/miniprem-2025/docker/README.md`
- **Kubernetes Guide**: `/Users/tyler/Software_Development/miniprem-2025/kubernetes/README.md`

### Community

- **Issues**: Report bugs or request features on the MiniPrem GitHub repository
- **Discussions**: Share your custom service configurations with the community

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review Docker Compose logs: `docker compose logs`
3. Validate configuration: `docker compose config`
4. Search existing GitHub issues
5. Create a new issue with:
   - Your `docker-compose.custom.yml` (redact secrets!)
   - Output of `docker compose config`
   - Relevant logs from `docker compose logs`

---

## Appendix: Complete Example

Here's a complete example with PostgreSQL, Redis, and a custom API:

```yaml
# docker-compose.custom.yml
name: uneeq-miniprem

services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: miniprem-postgres
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-miniprem}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - POSTGRES_DB=${POSTGRES_DB:-miniprem}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-miniprem}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G

  # Redis Cache (separate from MiniPrem's official redis)
  custom-redis:
    image: redis:7-alpine
    container_name: miniprem-custom-redis
    ports:
      - "6380:6379"
    volumes:
      - custom_redis_data:/data
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-changeme}
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6379", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M

  # Custom API
  custom-api:
    build:
      context: ./custom-api
      dockerfile: Dockerfile
    container_name: miniprem-custom-api
    environment:
      - API_KEY=${API_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER:-miniprem}:${POSTGRES_PASSWORD:-changeme}@localhost:5432/${POSTGRES_DB:-miniprem}
      - REDIS_URL=redis://:${REDIS_PASSWORD:-changeme}@localhost:6380
      - LOG_LEVEL=${LOG_LEVEL:-info}
    ports:
      - "8080:8080"
    restart: unless-stopped
    network_mode: host
    depends_on:
      postgres:
        condition: service_healthy
      custom-redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G

volumes:
  postgres_data:
  custom_redis_data:
```

**Corresponding .env file:**

```bash
# docker/.env

# PostgreSQL
POSTGRES_USER=miniprem
POSTGRES_PASSWORD=secure_postgres_password
POSTGRES_DB=miniprem

# Redis
REDIS_PASSWORD=secure_redis_password

# Custom API
API_KEY=your_secure_api_key_here
LOG_LEVEL=info
```

**Start everything:**

```bash
cd docker/
./miniprem.sh start
```

**Verify:**

```bash
docker ps | grep miniprem
curl http://localhost:8080/health
psql -h localhost -U miniprem -d miniprem  # Enter password when prompted
redis-cli -p 6380 -a secure_redis_password ping
```

---

## Document Version

- **Version**: 1.0.0
- **Last Updated**: 2025-11-13
- **MiniPrem Compatibility**: v2025+

---

**Happy containerizing!** If you have questions or suggestions for this guide, please open an issue on the MiniPrem GitHub repository.
