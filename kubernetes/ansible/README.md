# MiniPrem CNS Ansible Playbooks

Ansible playbooks for deploying and managing NVIDIA Cloud Native Stack (CNS) with MiniPrem.

## Directory Structure

```
ansible/
├── inventory/
│   ├── hosts.yml.example      # Example inventory file
│   └── group_vars/
│       ├── all.yml            # Global variables
│       └── cns.yml            # CNS-specific variables
├── playbooks/
│   ├── cns-install.yml        # Full CNS installation
│   ├── cns-upgrade.yml        # Upgrade CNS components
│   ├── cns-uninstall.yml      # Clean uninstall
│   ├── miniprem-deploy.yml    # Deploy MiniPrem stack
│   ├── phoenix-setup.yml      # Phoenix observability setup
│   └── validate.yml           # Validation checks
├── roles/
│   ├── common/                # System prerequisites
│   ├── nvidia-driver/         # NVIDIA driver installation
│   ├── container-runtime/     # containerd setup
│   ├── kubernetes/
│   │   ├── microk8s/         # MicroK8s installation
│   │   └── kubeadm/          # kubeadm installation
│   ├── gpu-operator/          # NVIDIA GPU Operator
│   ├── miniprem/             # MiniPrem Helm deployment
│   ├── phoenix/              # Phoenix observability
│   └── prometheus/           # Prometheus stack
└── vars/
    ├── cns_versions.yml      # Version pinning
    └── miniprem_config.yml   # MiniPrem configuration
```

## Prerequisites

1. **Ansible installed** on your control machine:
   ```bash
   # macOS
   brew install ansible

   # Ubuntu/Debian
   sudo apt-get install ansible

   # pip
   pip3 install ansible
   ```

2. **SSH access** to target servers with key-based authentication

3. **Target server requirements**:
   - Ubuntu 22.04+ or RHEL 8.7+
   - NVIDIA GPU(s)
   - Internet connectivity

## Quick Start

1. **Copy and configure inventory**:
   ```bash
   cp inventory/hosts.yml.example inventory/hosts.yml
   # Edit inventory/hosts.yml with your server details
   ```

2. **Set your NGC API key**:
   ```bash
   export NGC_API_KEY='your-ngc-api-key'
   ```

3. **Run the installation playbook**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml
   ```

## Playbooks

### cns-install.yml

Full CNS installation including Kubernetes, GPU Operator, and MiniPrem stack.

```bash
# Install with MicroK8s (default)
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml

# Install with kubeadm
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml -e "cns_k8s_type=kubeadm"
```

### miniprem-deploy.yml

Deploy or update MiniPrem components on an existing CNS cluster.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/miniprem-deploy.yml
```

### phoenix-setup.yml

Set up Phoenix observability for LLM tracing.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/phoenix-setup.yml
```

### validate.yml

Verify CNS installation and health.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/validate.yml
```

### cns-uninstall.yml

Remove CNS components.

```bash
# Remove MiniPrem only
ansible-playbook -i inventory/hosts.yml playbooks/cns-uninstall.yml

# Complete removal including Kubernetes
ansible-playbook -i inventory/hosts.yml playbooks/cns-uninstall.yml -e "purge_kubernetes=true"
```

## Configuration

### Inventory Variables

Key variables to set in your inventory:

```yaml
all:
  vars:
    # Kubernetes distribution
    cns_k8s_type: microk8s  # or 'kubeadm'

    # NGC API key for NVIDIA models
    ngc_api_key: "{{ lookup('env', 'NGC_API_KEY') }}"

    # Renny configuration
    renny_replicas: 2

    # GPU time-slicing
    gpu_timeslice_replicas: 4
```

### Version Pinning

Edit `vars/cns_versions.yml` to pin specific versions:

```yaml
microk8s_channel: "1.31/stable"
gpu_operator_version: "v24.9.0"
nim_operator_version: "1.0.0"
phoenix_version: "latest"
```

## Tags

Use tags to run specific parts of playbooks:

```bash
# Only install GPU operator
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml --tags "gpu-operator"

# Only deploy MiniPrem
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml --tags "miniprem"

# Skip validation
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml --skip-tags "validate"
```

## Troubleshooting

### Connection Issues

```bash
# Test connectivity
ansible -i inventory/hosts.yml all -m ping

# Verbose mode
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml -vvv
```

### GPU Not Detected

```bash
# Run validation playbook
ansible-playbook -i inventory/hosts.yml playbooks/validate.yml --tags "gpu"
```

### View Ansible Facts

```bash
ansible -i inventory/hosts.yml all -m setup | grep nvidia
```
