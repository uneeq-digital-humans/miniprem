# New Claude Code Skills for MiniPrem Team

## TL;DR

Three new automation skills that save 1-2 hours per day on common tasks:

| Skill | What it does | Time saved |
|-------|-------------|------------|
| `/mr-review 123` | Automated code review with GitLab integration | 30-60 min/MR |
| `/k8s-debug gpu` | Systematic K8s troubleshooting with fix commands | 15-45 min/incident |
| `/deploy-status aws` | Health check with drift detection & scoring | 20-30 min/check |

---

## Why We Built These

### The Problems
- **Inconsistent reviews**: Different engineers check different things
- **Slow debugging**: New team members don't know which commands to run
- **Unknown state**: "Is production healthy?" requires 10+ commands to answer

### The Solution
Encode our best practices into reusable skills that anyone can run.

---

## Demo: 60 Seconds Each

### `/mr-review` - Code Review Automation

```bash
# In Claude Code
/mr-review 847
```

**What happens**:
1. Fetches MR #847 from GitLab
2. Analyzes all diffs for security, quality, patterns
3. Creates draft notes positioned on exact code lines
4. Posts summary with severity-ranked issues

**Output example**:
```
Created 7 draft notes:
- 2 CRITICAL (SQL injection, missing auth check)
- 3 HIGH (error handling, resource leak)
- 2 MEDIUM (type safety, test coverage)

Summary posted. Review and publish drafts when ready.
```

---

### `/k8s-debug` - Kubernetes Troubleshooting

```bash
# Full diagnostics
/k8s-debug all

# GPU-specific issues (most common)
/k8s-debug gpu
```

**What happens**:
1. Collects pods, events, logs, GPU status
2. Checks operator health and time-slicing
3. Identifies root causes
4. Provides copy-paste fix commands

**Output example**:
```markdown
## Issues Found

### CRITICAL: GPU Not Scheduling
- **Symptom**: 2 pods pending with "Insufficient nvidia.com/gpu"
- **Root Cause**: Time-slicing ConfigMap not applied after node restart
- **Fix**:
  ```bash
  kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
  ```
```

---

### `/deploy-status` - Deployment Health Check

```bash
# Check AWS deployment
/deploy-status aws

# Auto-detect platform
/deploy-status
```

**What happens**:
1. Checks Terraform for drift
2. Collects cloud + K8s resource status
3. Verifies GPU stack and application health
4. Calculates health score (0-100)

**Output example**:
```markdown
## Health Score: 87/100

| Component | Status | Score |
|-----------|--------|-------|
| Infrastructure | Healthy | 25/25 |
| Kubernetes | Healthy | 25/25 |
| GPU Stack | Degraded | 17/25 |
| Application | Healthy | 20/25 |

### Issues
- GPU utilization at 92% on node-2 (warning)
- 3 pod restarts in last hour (investigate)

### Drift Detected
terraform.tfvars shows 4 replicas, deployed has 3
```

---

## How to Use

### Prerequisites
- Claude Code installed
- In the miniprem-2025 repo directory
- Appropriate credentials (GitLab token, kubectl context, cloud CLI)

### Just Run It
```bash
cd ~/uneeq/miniprem-2025
claude

# Then in Claude Code:
/mr-review 123
/k8s-debug all
/deploy-status aws
```

---

## Use Cases

### Before Creating a PR
Run `/deploy-status` to ensure your target environment is healthy.

### Reviewing PRs
1. Run `/mr-review <MR-ID>` first
2. Review the draft notes it creates
3. Add your domain-specific feedback
4. Publish the combined review

### On-Call Incidents
1. Run `/k8s-debug all` immediately
2. Follow the severity-ranked fix commands
3. Document any new patterns for the skill

### Before Customer Demos
Run `/deploy-status aws --costs` and verify score > 90.

---

## FAQ

**Q: Will these break anything?**
A: No. They're read-only except `/mr-review` which creates draft notes (you decide to publish).

**Q: Do I need to understand K8s/Terraform to use these?**
A: No. That's the point - the skills encode the expertise.

**Q: Can I customize them?**
A: Yes, edit `.claude/commands/*.md` to add patterns specific to your work.

---

## Getting Started

1. Pull latest main (skills are in `.claude/commands/`)
2. Open Claude Code in the repo
3. Try `/deploy-status` to see it in action
4. Read full docs: `docs/claude-code-skills.md`

---

## Feedback

These skills will evolve based on usage. When you find:
- A check that should be added
- A false positive that's annoying
- A new debugging pattern

Create an issue with the `claude-code-skills` label or ping in #engineering.

---

*Built from real debugging sessions and MR reviews. If it helped us, it'll help you.*
