# MiniPrem Telemetry and Privacy Policy

## Overview

MiniPrem includes **anonymous telemetry** to help UneeQ understand deployment health, improve product quality, and provide better support. All telemetry is:

- **Anonymous**: No personally identifiable information is collected
- **Transparent**: This document explains exactly what data is collected
- **Privacy-first**: Designed with your privacy as the top priority

## What Data We Collect

### Installation Event (One-Time)

Sent once when MiniPrem is first installed:

- **Installation ID**: Anonymous UUID generated locally (not linked to any user)
- **Machine ID**: SHA-256 hash of primary GPU UUID (for hardware deduplication, cannot be reversed)
- **Version**: MiniPrem version number (e.g., "2.1.0")
- **Platform**: Deployment type ("docker", "kubernetes", "eks", "aks", "gke")
- **OS**: Operating system name (e.g., "linux", "darwin")
- **Architecture**: CPU architecture (e.g., "x86_64", "aarch64")
- **Python Version**: Runtime version (e.g., "3.11.7")
- **Instance Details**: Pod name (Kubernetes) or container ID (Docker), node name (Kubernetes only)

### Heartbeat Events (Every 5 Minutes)

Sent periodically to indicate the installation is active:

- **Installation ID**: Same anonymous UUID from installation event
- **Machine ID**: Same GPU UUID hash from installation event
- **Version**: MiniPrem version number
- **Platform**: Deployment type
- **Status**: Health status ("online")
- **Instance Details**: Pod name, container ID, node name (for tracking instances per GPU)
- **Renny Pod Count**: Number of active Renny instances (no names or details)

### Example Telemetry Payload

```json
{
  "installation_id": "a3f5b8c9-1234-5678-9abc-def012345678",
  "machine_id": "8f3a9b2c1d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0",
  "instance_name": "renny-gpu-0-abc123",
  "instance_type": "kubernetes-pod",
  "node_name": "ip-10-0-1-50.ec2.internal",
  "event_type": "heartbeat",
  "timestamp": "2025-10-22T14:30:00Z",
  "version": "2.1.0",
  "platform": "eks",
  "os": "linux",
  "platform_arch": "x86_64",
  "python_version": "3.11.7",
  "status": "online",
  "renny_pods_running": 4
}
```

**Note**: The `machine_id` is a SHA-256 hash and cannot be used to identify the original GPU UUID or any individual user.

### Why We Collect GPU Hardware Identifier

The GPU UUID hash (machine_id) is used **exclusively** to prevent duplicate counting when:

- Users reinstall MiniPrem on the same hardware
- Kubernetes pods are recreated/redeployed on the same GPU node
- Multiple pods share the same GPU via time-slicing

**Privacy Protection**:
- Original GPU UUID is **never transmitted** to our servers
- SHA-256 one-way hash makes it **impossible to reverse** to the original UUID
- Hash is 64 characters long (256 bits), making brute force impractical
- If nvidia-smi fails, system falls back to installation_id (no GPU tracking)

**Use Case Example**: If you deploy 4 Kubernetes pods on 1 GPU node, we count:
- 1 unique machine (GPU node)
- 4 active Renny instances (pods)

Without the GPU identifier, we would incorrectly count this as 4 separate machines.

## What Data We DO NOT Collect

We are committed to your privacy and **do not collect**:

- ❌ IP addresses, hostnames, or network identifiers
- ❌ UneeQ API keys, credentials, or authentication tokens
- ❌ **Conversation data or chat history** (no digital human interactions tracked)
- ❌ Customer data, session content, or user inputs
- ❌ User emails, names, or organizational information
- ❌ Geographic location or deployment region details
- ❌ Raw GPU UUID (only one-way SHA-256 hash collected)
- ❌ Container/pod names beyond instance tracking
- ❌ Any personally identifiable information (PII)

## How We Use This Data

Telemetry data is used exclusively for:

1. **Product Improvement**: Understanding deployment patterns to prioritize features
2. **Reliability Monitoring**: Detecting widespread issues or outages
3. **Support**: Helping diagnose problems when customers request assistance
4. **Usage Statistics**: Aggregate metrics (e.g., total active installations)

**We do NOT**:

- Sell or share telemetry data with third parties
- Use telemetry for marketing or advertising
- Track individual users or installations
- Link telemetry data to customer accounts without explicit consent

## Data Retention

- **Heartbeat Data**: Retained for 30 days, then automatically deleted
- **Installation Events**: Retained indefinitely for aggregate usage statistics
- **IP Addresses**: Not collected or logged

## Data Security

- **HTTPS Only**: All telemetry data is transmitted over encrypted HTTPS connections
- **Timeout Protection**: Requests timeout after 5 seconds to prevent blocking
- **Silent Failures**: Network errors are logged locally but never interrupt operations
- **Read-Only Access**: Telemetry service cannot modify your installation

## Data Export and Deletion

Under privacy regulations (GDPR, CCPA), you have the right to:

- **Request Data Export**: Receive a copy of telemetry data associated with your installation ID
- **Request Data Deletion**: Permanently delete all telemetry data for your installation ID

To exercise these rights:

1. Email: [privacy@uneeq.io](mailto:privacy@uneeq.io)
2. Include: Your installation ID (found in `/tmp/miniprem_installation_id`)
3. Specify: Export or deletion request

We will respond within 30 days.

## Technical Implementation

### Architecture

- **Local Generation**: Installation ID is generated locally using `uuidgen`
- **Container Mount**: ID file is mounted read-only into the monitor container
- **Background Service**: Telemetry runs as a background asyncio task
- **Non-Blocking**: All network operations use async/await with timeouts
- **Graceful Degradation**: Failures are logged locally but never surface to users

### Code Locations

- **Backend Service**: `miniprem-monitor/backend/app/services/telemetry.py`
- **Installation Script**: `docker/scripts/install_miniprem.sh`
- **Docker Compose**: `docker/docker-compose.full.yml` and `docker/docker-compose.yml`
- **Integration**: `miniprem-monitor/backend/app/main.py`

### Testing

All telemetry code includes comprehensive pytest tests:

```bash
cd miniprem-monitor/backend
pytest tests/test_telemetry.py -v
```

## Changes to This Policy

We may update this privacy policy to reflect changes in data collection practices. When significant changes occur:

1. **Notification**: Email notification to registered users
2. **Consent**: Re-prompt for consent during next installation/update

## Contact

For questions about telemetry or privacy:

- **Email**: [privacy@uneeq.io](mailto:privacy@uneeq.io)

---

**Last Updated**: October 22, 2025
**Effective Date**: October 22, 2025
**Version**: 1.0
