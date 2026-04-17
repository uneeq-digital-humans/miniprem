# Claude Code Skills for MiniPrem Engineering

## Overview

These custom Claude Code skills automate common engineering workflows, standardize processes, and reduce time spent on repetitive tasks. Each skill is designed to be used by any team member regardless of their familiarity with the specific tooling.

## Quick Start

### Installation
The skills are already installed in the `.claude/commands/` directory. Any engineer with Claude Code can use them immediately.

### Usage
In Claude Code, type the command followed by any arguments:
```bash
/mr-review 123
/k8s-debug gpu
/deploy-status aws
```

---

## Available Skills

### 1. `/sync-docs` - Documentation Synchronization Check

**Purpose**: Detect drift between documentation and actual code/configuration before every PR.

**What it does**:
- Validates port mappings against docker-compose and kubernetes values files
- Checks all file/script paths referenced in docs exist
- Verifies bash command syntax in code blocks
- Tests internal markdown links for broken references
- Detects configuration drift between code and docs
- Generates severity-ranked report with specific line numbers and fixes

**Usage**:
```bash
/sync-docs                    # Full documentation scan
/sync-docs --path docs/guides/ # Scan specific directory
/sync-docs --changed          # Only check docs related to changed files
/sync-docs --fix              # Auto-fix trivial issues (use with caution)
```

**Output**:
- Structured drift report with CRITICAL/HIGH/MEDIUM/LOW issues
- Specific line numbers and exact diff fixes
- Broken link detection
- Command validation results
- Auto-fix suggestions for trivial issues

**Time saved**: 10-20 minutes per PR (catches issues before reviewers do)

**Example Issues Caught**:
- Port 3001 vs 3000 confusion in docs
- Moved scripts with old paths in documentation
- Broken internal links after file renames
- API endpoints documented but don't exist
- Missing environment variable documentation

---

### 2. `/mr-review` - Merge Request Deep Review

**Purpose**: Automated, comprehensive code review that posts structured feedback directly to GitLab.

**What it does**:
- Fetches MR metadata, diffs, and existing discussions
- Analyzes for security vulnerabilities (OWASP Top 10)
- Checks code quality, patterns, and testing
- Creates draft notes positioned on specific code lines
- Generates summary with severity-ranked issues

**Usage**:
```bash
/mr-review 123              # Review MR #123
/mr-review 456 --focus security  # Security-focused review
```

**Output**:
- Draft notes on GitLab MR (publish when ready)
- Summary comment with issue counts
- Recommended actions before merge

**Time saved**: 30-60 minutes per complex MR

---

### 3. `/k8s-debug` - Kubernetes Troubleshooting

**Purpose**: Systematic debugging of Kubernetes issues with diagnosis and fix recommendations.

**What it does**:
- Collects pod status, events, logs across namespaces
- Checks GPU operator and time-slicing configuration
- Analyzes network, storage, and resource issues
- Provides cloud-specific diagnostics (EKS/AKS/GKE)
- Generates actionable fix commands

**Usage**:
```bash
/k8s-debug all              # Full cluster diagnostics
/k8s-debug gpu              # GPU-specific issues
/k8s-debug pods             # Pod troubleshooting
/k8s-debug network          # Network issues
/k8s-debug pods --namespace kube-system
```

**Output**:
- Structured diagnosis report
- Severity-ranked issues
- Copy-paste fix commands

**Time saved**: 15-45 minutes per incident

---

### 4. `/deploy-status` - Multi-Cloud Deployment Health

**Purpose**: Comprehensive health check with drift detection and scoring across cloud platforms.

**What it does**:
- Checks Terraform state for drift
- Collects cloud provider resource status
- Analyzes Kubernetes resources and GPU stack
- Verifies application health endpoints
- Calculates health score (0-100)
- Estimates running costs

**Usage**:
```bash
/deploy-status all          # Check all platforms
/deploy-status aws          # AWS EKS only
/deploy-status azure        # Azure AKS only
/deploy-status              # Auto-detect from context
/deploy-status aws --costs  # Include cost analysis
```

**Output**:
- Health score with component breakdown
- Drift detection report
- Resource utilization summary
- Cost analysis
- Pre-demo readiness checklist

**Time saved**: 20-30 minutes per status check

---

## How These Skills Help

### For New Engineers
- **No deep knowledge required**: Skills encode best practices and tribal knowledge
- **Consistent process**: Same steps every time, nothing missed
- **Learning tool**: See what commands are run and why

### For Experienced Engineers
- **Speed**: Automate repetitive data collection
- **Focus**: Spend time on analysis, not gathering
- **Standardization**: Team follows same review criteria

### For Team Leads
- **Quality consistency**: Reviews meet same standards
- **Visibility**: Deployment health always known
- **On-call efficiency**: Faster incident response

---

## Best Practices

### MR Reviews
1. Run `/mr-review` before manual review to catch obvious issues
2. Review the draft notes and adjust tone/priority as needed
3. Add context-specific feedback that requires domain knowledge
4. Publish drafts when satisfied

### Kubernetes Debugging
1. Start with `/k8s-debug all` for unknown issues
2. Use specific modes (`gpu`, `network`, `pods`) for known problem areas
3. Follow the recommended actions in order of severity
4. Document any new patterns in the skill for future use

### Deployment Health
1. Run `/deploy-status` before customer demos
2. Target health score > 90 for production
3. Address any drift immediately
4. Use for change validation after deployments

---

## Customization

### Adding New Checks
Edit the skill files in `.claude/commands/`:
```bash
vim .claude/commands/mr-review.md
vim .claude/commands/k8s-debug.md
vim .claude/commands/deploy-status.md
```

### Common Customizations
- Add project-specific security patterns to `/mr-review`
- Add new troubleshooting scenarios to `/k8s-debug`
- Adjust health score weights in `/deploy-status`

### Environment Variables
Skills respect these environment variables:
- `GITLAB_PROJECT_ID`: Default GitLab project
- `GITLAB_API_URL`: GitLab instance URL
- `AWS_PROFILE`: AWS credentials profile
- `AZURE_SUBSCRIPTION_ID`: Azure subscription

---

## Troubleshooting Skills

### "Command not found"
Ensure you're in the miniprem-2025 directory:
```bash
cd /path/to/miniprem-2025
```

### GitLab authentication errors
Check GitLab token is configured:
```bash
# In Claude Code settings or environment
export GITLAB_TOKEN=your_token
```

### Kubernetes connection errors
Verify kubectl context:
```bash
kubectl config current-context
kubectl cluster-info
```

### AWS/Azure authentication
Refresh cloud credentials:
```bash
aws sso login --profile uneeq-admin
az login
```

---

## Contributing

### Adding New Skills
1. Create `.claude/commands/your-skill.md`
2. Follow the existing skill structure
3. Include clear input/output documentation
4. Add usage examples
5. Update this documentation

### Improving Existing Skills
1. Identify gaps or inefficiencies
2. Test changes locally
3. Document what changed and why
4. Share improvements with the team

---

## FAQ

**Q: Do these skills modify code or infrastructure?**
A: No. They only read and analyze. `/mr-review` creates draft notes (you publish them), `/k8s-debug` and `/deploy-status` are read-only.

**Q: Can I use these on other projects?**
A: Yes, copy the `.claude/commands/` directory to other repos. Adjust project-specific patterns as needed.

**Q: How do I see what commands Claude is running?**
A: Claude Code shows all commands executed. The skills are designed to be transparent.

**Q: What if a skill gives incorrect advice?**
A: Skills are guidance, not automation. Always verify recommendations before executing, especially for production changes.

---

## Contact

For skill improvements or issues:
- Create an issue in the miniprem-2025 repo
- Tag with `claude-code-skills` label
- Include example of the problem and expected behavior
