<div align="center">

<img src="../images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="../images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# First Steps: Diagnosing MiniPrem Issues

> A beginner-friendly guide to gathering diagnostic information before contacting support

</div>

## Table of Contents

- [Before You Contact Support](#before-you-contact-support)
- [Step 1: Identify Your Deployment Type](#step-1-identify-your-deployment-type)
- [Step 2: Check If Your Platform Is Running](#step-2-check-if-your-platform-is-running)
- [Step 3: Check Service Health](#step-3-check-service-health)
- [Step 4: Check Renny Specifically](#step-4-check-renny-specifically)
- [Step 5: Gather Logs](#step-5-gather-logs)
- [Quick Checklist](#quick-checklist)
- [License](#license)
- [Copyright](#copyright)

---

## Before You Contact Support

When something isn't working with your MiniPrem installation, gathering the right information **before** contacting support helps resolve issues faster. This guide walks you through the five essential diagnostic steps.

**What you'll learn:**
- How to identify which type of deployment you're running
- How to verify your platform is actually running
- How to check if services are healthy
- How to find and interpret logs
- What information to provide when contacting support

> **Tip**: Even if you're not experiencing issues, running through these steps periodically helps you understand your system better.

---

## Step 1: Identify Your Deployment Type

MiniPrem can run in two different environments. Knowing which one you're using is the first step in troubleshooting.

### Docker Deployment (Single Machine)

You're using Docker if:
- You installed using `./docker/scripts/install_miniprem.sh`
- You manage services with `./miniprem.sh start|stop|status`
- Everything runs on a single machine

**How to verify:**
```bash
# If this command shows "uneeq-miniprem" containers, you're using Docker
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(renny|miniprem)"
```

**Example output (Docker deployment):**
```
NAMES               STATUS
renny               Up 2 hours (healthy)
miniprem-monitor    Up 2 hours (healthy)
```

### Kubernetes Deployment (Cluster)

You're using Kubernetes if:
- You deployed using scripts in `kubernetes/scripts/`
- You manage services with `kubectl` commands
- Your workloads run across multiple nodes in a cluster

**How to verify:**
```bash
# If this command shows pods, you're using Kubernetes
kubectl get pods -n uneeq-renderer 2>/dev/null
```

**Example output (Kubernetes deployment):**
```
NAME                        READY   STATUS    RESTARTS   AGE
renny-renderer-abc123-xyz   1/1     Running   0          2d
renny-renderer-def456-uvw   1/1     Running   0          2d
```

### Why This Matters

- **Docker**: Issues are typically related to container configuration, port conflicts, or local resources
- **Kubernetes**: Issues may involve cluster networking, node scheduling, or cloud provider configuration

---

## Step 2: Check If Your Platform Is Running

Before checking individual services, verify that the underlying platform (Docker or Kubernetes) is operational.

### For Docker Deployments

**Check if Docker Engine is running:**
```bash
docker info > /dev/null 2>&1 && echo "Docker is running" || echo "Docker is NOT running"
```

**Good output:**
```
Docker is running
```

**Bad output:**
```
Docker is NOT running
```

**If Docker isn't running, start it:**
```bash
# On Linux with systemd
sudo systemctl start docker

# On macOS/Windows
# Open Docker Desktop application
```

### For Kubernetes Deployments

**Check if kubectl can reach your cluster:**
```bash
kubectl cluster-info
```

**Good output:**
```
Kubernetes control plane is running at https://your-cluster.example.com
CoreDNS is running at https://your-cluster.example.com/api/v1/...

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

**Bad output:**
```
The connection to the server was refused - did you specify the right host or port?
```

**If you can't reach your cluster:**
```bash
# Check your current context
kubectl config current-context

# List available contexts
kubectl config get-contexts

# For EKS, you may need to refresh credentials
aws sso login --profile your-profile
aws eks update-kubeconfig --region your-region --name your-cluster
```

---

## Step 3: Check Service Health

Now let's check if MiniPrem services are running and healthy.

### For Docker Deployments

**Run the status command:**
```bash
./miniprem.sh status
```

**Good output (all services healthy):**
```
=== MiniPrem Status ===
Installation type: default

Container Status:
NAME               STATUS              HEALTH
renny              Up 2 hours          healthy
miniprem-monitor   Up 2 hours          healthy

All services are running normally.
```

**Problem output (service unhealthy):**
```
=== MiniPrem Status ===
Installation type: default

Container Status:
NAME               STATUS              HEALTH
renny              Up 10 minutes       unhealthy
miniprem-monitor   Up 10 minutes       healthy

WARNING: Some services are unhealthy. Run './miniprem.sh logs <service>' for details.
```

**Understanding Container States:**

| State | Meaning | Action |
|-------|---------|--------|
| `Up X hours (healthy)` | Service is running and responding correctly | No action needed |
| `Up X minutes (unhealthy)` | Service is running but health checks are failing | Check logs for errors |
| `Exited (1)` | Service crashed with an error | Check logs, then restart |
| `Exited (0)` | Service stopped normally | Restart if needed |
| `Restarting` | Service is in a restart loop | Check logs for crash reason |

**Check individual container health:**
```bash
docker inspect --format='{{.State.Health.Status}}' renny
```

### For Kubernetes Deployments

**Check pod status:**
```bash
kubectl get pods -n uneeq-renderer -o wide
```

**Good output:**
```
NAME                        READY   STATUS    RESTARTS   AGE   IP           NODE
renny-renderer-abc123-xyz   1/1     Running   0          2d    10.17.2.15   ip-10-17-2-248.ec2.internal
renny-renderer-def456-uvw   1/1     Running   0          2d    10.17.3.22   ip-10-17-3-112.ec2.internal
```

**Problem output:**
```
NAME                        READY   STATUS             RESTARTS   AGE   IP           NODE
renny-renderer-abc123-xyz   0/1     CrashLoopBackOff   5          10m   10.17.2.15   ip-10-17-2-248.ec2.internal
```

**Understanding Pod States:**

| State | Meaning | Action |
|-------|---------|--------|
| `Running` | Pod is running normally | Check READY column (should be 1/1) |
| `Pending` | Pod is waiting to be scheduled | Check node resources, check events |
| `CrashLoopBackOff` | Pod keeps crashing and restarting | Check logs with `kubectl logs` |
| `ImagePullBackOff` | Cannot pull container image | Check image name, registry credentials |
| `Error` | Pod failed to start | Check logs and events |

**Get more details on a problem pod:**
```bash
kubectl describe pod <pod-name> -n uneeq-renderer
```

---

## Step 4: Check Renny Specifically

Renny is the core digital human service. Let's verify it's responding correctly.

### Health Endpoint Check

**For Docker:**
```bash
curl -s http://localhost:8081/health | head -20
```

**For Kubernetes (from a machine with cluster access):**
```bash
# First, get the pod name
kubectl get pods -n uneeq-renderer -o name | head -1

# Then check health (replace with your pod name)
kubectl exec -n uneeq-renderer <pod-name> -- curl -s http://localhost:8081/health | head -20
```

**Good output (healthy Renny):**
```json
{
  "status": "healthy",
  "version": "0.758-f9e3f",
  "uptime": "2h 15m 30s",
  "connections": {
    "platform": "connected",
    "speech": "ready"
  }
}
```

**Problem output (unhealthy Renny):**
```json
{
  "status": "unhealthy",
  "version": "0.758-f9e3f",
  "uptime": "0h 5m 12s",
  "connections": {
    "platform": "disconnected",
    "speech": "error"
  },
  "errors": [
    "Failed to connect to UneeQ platform",
    "Speech service initialization failed"
  ]
}
```

**If the health endpoint doesn't respond:**
```bash
# Check if the port is listening (Docker)
docker exec renny netstat -tlnp | grep 8081

# Or check if the container is actually running
docker ps | grep renny
```

### Common Renny Health Issues

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| `platform: disconnected` | Invalid API key or network issue | Check `configuration.dat` credentials |
| `speech: error` | Azure Speech credentials invalid | Verify Azure region and speech key |
| No response at all | Renny crashed or port not exposed | Check container logs |
| `status: starting` | Renny still initializing | Wait 1-2 minutes, check again |

---

## Step 5: Gather Logs

Logs contain detailed information about what's happening inside your services. Here's how to find and interpret them.

### Viewing Logs

**For Docker:**
```bash
# View recent logs
./miniprem.sh logs renny

# Or with more options
docker logs renny --tail 100

# Follow logs in real-time (Ctrl+C to stop)
docker logs -f renny
```

**For Kubernetes:**
```bash
# View logs from a specific pod
kubectl logs <pod-name> -n uneeq-renderer --tail 100

# Follow logs in real-time
kubectl logs -f <pod-name> -n uneeq-renderer

# View logs from all Renny pods
kubectl logs -l app=renny-renderer -n uneeq-renderer --tail 50
```

### Understanding Log Format

Renny uses JSON-formatted logs. Here's how to read them:

**Example log entry:**
```json
{"timestamp":"2025-01-08T15:30:45.123Z","service":"renderer","log_level":"info","message":"Session started successfully","client_session_id":"abc123"}
```

**Key fields:**
- `timestamp`: When the event occurred
- `log_level`: Severity (debug, info, warn, error, fatal)
- `message`: What happened
- `client_session_id`: Which user session (if applicable)

### Finding Errors in Logs

**Search for errors (Docker):**
```bash
docker logs renny 2>&1 | grep -i "error\|fatal\|failed"
```

**Search for errors (Kubernetes):**
```bash
kubectl logs <pod-name> -n uneeq-renderer | grep -i "error\|fatal\|failed"
```

**Example error output:**
```
{"timestamp":"2025-01-08T15:30:45.123Z","log_level":"error","message":"Failed to connect to UneeQ platform: connection timeout"}
{"timestamp":"2025-01-08T15:31:00.456Z","log_level":"error","message":"Speech service unavailable: invalid credentials"}
```

### Saving Logs to a File

When contacting support, save logs to a file:

**Docker:**
```bash
docker logs renny > renny_logs_$(date +%Y%m%d_%H%M%S).txt 2>&1
```

**Kubernetes:**
```bash
kubectl logs <pod-name> -n uneeq-renderer > renny_logs_$(date +%Y%m%d_%H%M%S).txt
```

### Log Levels Explained

| Level | Meaning | When to Worry |
|-------|---------|---------------|
| `debug` | Detailed diagnostic info | Only useful for deep troubleshooting |
| `info` | Normal operations | These are expected, not a problem |
| `warn` | Potential issues | Worth noting, may indicate future problems |
| `error` | Something failed | Investigate these - something went wrong |
| `fatal` | Critical failure | Service likely crashed, immediate attention needed |

---

## Quick Checklist

Use this checklist when gathering information for support:

### Essential Information

- [ ] **Deployment type**: Docker or Kubernetes?
- [ ] **Platform status**: Is Docker/Kubernetes running?
- [ ] **Service status**: Output of `./miniprem.sh status` or `kubectl get pods`
- [ ] **Renny health**: Output of health endpoint check
- [ ] **Recent logs**: Last 100 lines of Renny logs (saved to file)

### Additional Context (if available)

- [ ] **Installation type**: Default or Full install?
- [ ] **When did the issue start?**: After an update? Configuration change?
- [ ] **Error messages**: Exact text of any error messages
- [ ] **Steps to reproduce**: What were you doing when the issue occurred?

### Information for Support Ticket

When contacting support, include:

```
Subject: [MiniPrem Issue] Brief description

Deployment: Docker / Kubernetes
Installation Type: Default / Full
Issue Started: Date/time or "after X"

Problem Description:
[What's happening vs what you expected]

Diagnostic Results:
- Platform running: Yes/No
- Service status: [paste output]
- Health check: [paste output]

Logs attached: renny_logs_YYYYMMDD_HHMMSS.txt

Steps to Reproduce:
1. [First step]
2. [Second step]
3. [Issue occurs]
```

---

## Next Steps

- **Issue not resolved?** See the detailed [Troubleshooting Guide](../troubleshooting.md) for service-specific solutions
- **Need help with setup?** Return to [Getting Started](getting-started.md)
- **Want to understand the architecture?** See [Services Overview](services.md)

---

## License

The MiniPrem documentation and installation scripts are open source under the MIT License - see the [LICENSE](../../LICENSE) file for details. Note: The Renny digital human application itself is commercially licensed by UneeQ and is not covered by this license.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="../images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="../images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
