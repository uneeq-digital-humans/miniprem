<div align="center">

<img src="../images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="../images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# Harbor Registry Guide

> Container image registry access for MiniPrem deployments

</div>

## Table of Contents

- [Overview](#overview)
- [Getting Access](#getting-access)
- [Network Requirements](#network-requirements)
- [Testing Your Harbor Connection](#testing-your-harbor-connection)
- [Troubleshooting](#troubleshooting)
- [Support](#support)
- [License](#license)

## Overview

UneeQ hosts container images for MiniPrem and Renny digital human renderer on a private Harbor registry at `cr.uneeq.io`. The Harbor registry provides a secure, enterprise-grade container image repository with improved cost optimization, enhanced security, and granular access control compared to public Docker Hub registries.

### Why Harbor Registry?

**Cost Optimization**
- Reduced bandwidth costs through private registry hosting
- Efficient image layer caching and storage
- No public Docker Hub rate limiting or pulling costs

**Enhanced Security**
- Centralized credential management
- Audit logging for all image pull operations
- Image scanning and vulnerability detection
- Fine-grained role-based access control (RBAC)

**Operational Control**
- Granular access control per customer
- Audit trail of all registry operations
- Dedicated support for image access issues
- Consistent image versioning and tagging

### Migration from Docker Hub

If you've been pulling MiniPrem or Renny images from Docker Hub, you'll need to:
1. Request Harbor registry credentials from UneeQ
2. Update your image references to use `cr.uneeq.io`
3. Configure Docker/Kubernetes to authenticate with the new registry

## Getting Access

### Robot Account Concept

UneeQ uses "robot accounts" (service accounts) to manage automated container image pulls. Unlike personal user accounts, robot accounts are designed for programmatic use by deployment systems like Docker, Kubernetes, and CI/CD pipelines.

**Robot Account Format**:
```
Username: robot$customer-name
Password: [secure token provided by UneeQ]
```

### Requesting Credentials

To obtain Harbor registry credentials:

1. **Contact UneeQ Support**:
   - Email: `help@uneeq.com`
   - Provide your customer name and deployment environment
   - Request a robot account for harbor access

2. **What You'll Receive**:
   - Robot account username (format: `robot$customer-name`)
   - Secure password/token
   - Registry URL: `https://cr.uneeq.io`
   - Supported image repositories (e.g., `uneeq/renny-renderer`, `uneeq/renny-encoder`)

### Storing Credentials Securely

<div class="info-box">
<strong>🔐 Security Best Practice:</strong> Never commit Harbor credentials to version control. Use secure credential management systems appropriate for your deployment environment.
</div>

**Recommended Credential Storage Methods**:

- **Docker (Local Development)**:
  ```bash
  # Docker automatically encrypts credentials in ~/.docker/config.json
  docker login https://cr.uneeq.io
  ```

- **Kubernetes**:
  ```bash
  # Use Kubernetes Secrets for image pull credentials
  kubectl create secret docker-registry harbor-credentials \
    --docker-server=cr.uneeq.io \
    --docker-username='robot$customer-name' \
    --docker-password='your-password' \
    --docker-email='support@uneeq.com' \
    -n your-namespace
  ```

- **CI/CD Pipelines** (GitHub Actions, GitLab CI, etc.):
  - Store credentials as encrypted repository secrets
  - Reference secrets in your CI/CD configuration
  - Never hardcode credentials in workflow files

## Network Requirements

### Firewall Configuration

To pull images from the Harbor registry, you must ensure network connectivity to the registry endpoint.

<div class="warning-box">
<strong>🔥 Enterprise Firewall Alert:</strong> If you're deploying in an enterprise or corporate environment with strict firewall rules, ensure that your network administrator has whitelisted the Harbor registry.
</div>

**Registry Endpoint Details**:
- **Hostname**: `cr.uneeq.io`
- **Port**: 443 (HTTPS only)
- **Protocol**: HTTPS (TLS 1.2+)
- **DNS**: Public DNS resolution required

### Whitelist Requirements

Ensure your firewall rules allow outbound connections to:

```
Domain: cr.uneeq.io
Port: 443/tcp
Protocol: TLS 1.2+
Direction: Outbound
Service: Container Image Pull
```

### Testing Network Connectivity

Before deploying containers, verify that your network can reach the Harbor registry:

```bash
# Test DNS resolution
nslookup cr.uneeq.io

# Test HTTPS connectivity
curl -I https://cr.uneeq.io
```

## Testing Your Harbor Connection

Before deploying containers that pull from the Harbor registry, test your configuration with the following step-by-step validation.

### Prerequisites

- Docker installed and running
- Harbor registry credentials (robot account username and password)
- Network access to cr.uneeq.io on port 443

### Step 1: Test DNS Resolution

Verify that your system can resolve the Harbor registry hostname:

```bash
nslookup cr.uneeq.io
```

**Expected Output**:
```
Server:		8.8.8.8
Address:	8.8.8.8#53

Non-authoritative answer:
Name:	cr.uneeq.io
Address: 1.2.3.4
```

**Troubleshooting**: If you see "no such host" errors, check your DNS configuration or network connectivity.

### Step 2: Test HTTPS Connectivity

Verify that you can establish an HTTPS connection to the registry:

```bash
curl -I https://cr.uneeq.io
```

**Expected Output**:
```
HTTP/1.1 301 Moved Permanently
Location: https://cr.uneeq.io/v2/
Server: nginx
```

**Troubleshooting**: If you see connection timeouts or TLS errors, check your firewall rules and ensure port 443 is accessible.

### Step 3: Test Docker Authentication

Authenticate with the Harbor registry using your robot account credentials:

```bash
docker login https://cr.uneeq.io --username 'robot$your-customer-name'
# Enter password when prompted
```

**Expected Output**:
```
Password:
Login Succeeded
```

**Troubleshooting**: If you see "authentication required" errors, verify your robot account credentials are correct and the account hasn't expired.

### Step 4: Test Image Pull

Pull a test image from the Harbor registry to verify full read access:

```bash
docker pull cr.uneeq.io/uneeq/renny-renderer:latest
```

**Expected Output**:
```
latest: Pulling from uneeq/renny-renderer
e0a742c94bf5: Download complete
5e632e8c65ba: Download complete
[... more layers ...]
Digest: sha256:abcd1234efgh5678ijkl9012mnop3456qrst7890uvwx1234yzab5678cdef9
Status: Downloaded newer image for cr.uneeq.io/uneeq/renny-renderer:latest
```

**Troubleshooting**: If the pull fails, verify:
- Your internet connection is stable
- The image tag exists in the registry
- Your credentials have pull permissions

### Step 5: Verify Authentication Persistence

Confirm that Docker has stored your authentication credentials:

```bash
cat ~/.docker/config.json | grep -A 5 cr.uneeq.io
```

**Expected Output**:
```json
"cr.uneeq.io": {
  "auth": "cm9ib3QkY3VzdG9tZXItbmFtZTpwYXNzd29yZA=="
}
```

**Note**: The auth field shows base64-encoded credentials. This is normal and expected—Docker uses this format for stored credentials.

## Troubleshooting

### Common Issues and Solutions

#### "unauthorized: authentication required"

**Cause**: Docker login failed or credentials have expired.

**Solutions**:
1. Re-authenticate with Harbor registry:
   ```bash
   docker logout https://cr.uneeq.io
   docker login https://cr.uneeq.io --username 'robot$your-customer-name'
   ```

2. Verify robot account credentials are still valid:
   - Contact help@uneeq.com to confirm account status
   - Request new credentials if token has expired

3. Clear Docker credential cache and retry:
   ```bash
   rm ~/.docker/config.json
   docker login https://cr.uneeq.io
   ```

#### "dial tcp: lookup cr.uneeq.io: no such host"

**Cause**: DNS resolution failure—your system cannot resolve the registry hostname.

**Solutions**:
1. Verify DNS configuration:
   ```bash
   nslookup cr.uneeq.io
   dig cr.uneeq.io
   ```

2. Test with alternative DNS servers:
   ```bash
   nslookup cr.uneeq.io 8.8.8.8  # Google DNS
   nslookup cr.uneeq.io 1.1.1.1  # Cloudflare DNS
   ```

3. Check firewall rules allow DNS (port 53):
   - Contact your network administrator if behind corporate firewall
   - Ensure DNS queries reach public nameservers

4. For Kubernetes clusters, check CoreDNS is running:
   ```bash
   kubectl get pods -n kube-system | grep coredns
   ```

#### "x509: certificate signed by unknown authority"

**Cause**: TLS certificate verification failure—usually from corporate firewall/proxy intercepting HTTPS.

**Solutions**:
1. Verify the certificate is valid:
   ```bash
   openssl s_client -connect cr.uneeq.io:443 -showcerts
   ```

2. Check if your organization uses a proxy or certificate inspection:
   - Contact your network/security team
   - You may need to add the Harbor registry to your proxy's whitelist

3. For development only (NOT recommended for production):
   ```bash
   docker login https://cr.uneeq.io --username 'robot$your-customer-name' --insecure-skip-verify
   ```

4. Add custom CA certificate if behind corporate proxy:
   ```bash
   # Place your corporate CA certificate in /etc/docker/certs.d/cr.uneeq.io/ca.crt
   sudo mkdir -p /etc/docker/certs.d/cr.uneeq.io
   sudo cp /path/to/ca.crt /etc/docker/certs.d/cr.uneeq.io/ca.crt
   ```

#### "timeout waiting for network" or "connection timed out"

**Cause**: Network connectivity issue—firewall blocking or registry temporarily unavailable.

**Solutions**:
1. Test general network connectivity:
   ```bash
   ping cr.uneeq.io
   traceroute cr.uneeq.io
   ```

2. Verify firewall allows outbound HTTPS (port 443):
   ```bash
   curl -v https://cr.uneeq.io
   ```

3. Check if registry is available:
   - Visit https://cr.uneeq.io in a web browser
   - Should display Harbor login page

4. For corporate networks, verify:
   - HTTP proxy doesn't require authentication
   - HTTPS traffic isn't being blocked
   - Network administrator has whitelisted cr.uneeq.io

5. Retry with increased timeout:
   ```bash
   docker pull cr.uneeq.io/uneeq/renny-renderer:latest --timeout=60
   ```

#### "Error response from daemon: manifest not found"

**Cause**: Image tag doesn't exist in the registry or you don't have read access.

**Solutions**:
1. Verify the image tag exists and is correct:
   ```bash
   # Check available tags (requires Harbor API access)
   curl -H "Authorization: Bearer $(echo -n 'robot$customer-name:password' | base64)" \
     https://cr.uneeq.io/api/v2.0/projects/uneeq/repositories/renny-renderer/artifacts
   ```

2. Confirm you have pull permissions:
   - Contact help@uneeq.com to verify robot account permissions
   - Ensure your account is authorized for the image repository

3. Use a known working image tag:
   ```bash
   # Try a specific version instead of latest
   docker pull cr.uneeq.io/uneeq/renny-renderer:v1.2.3
   ```

### Kubernetes-Specific Issues

#### Pods in CrashLoopBackOff pulling from Harbor

**Diagnosis**:
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```

**Solutions**:
1. Verify image pull secret exists:
   ```bash
   kubectl get secrets -n your-namespace | grep harbor
   ```

2. Create/update the image pull secret:
   ```bash
   kubectl delete secret harbor-credentials -n your-namespace
   kubectl create secret docker-registry harbor-credentials \
     --docker-server=cr.uneeq.io \
     --docker-username='robot$customer-name' \
     --docker-password='your-password' \
     --docker-email='support@uneeq.com' \
     -n your-namespace
   ```

3. Ensure pod spec references the image pull secret:
   ```yaml
   spec:
     imagePullSecrets:
     - name: harbor-credentials
     containers:
     - name: renny
       image: cr.uneeq.io/uneeq/renny-renderer:latest
   ```

4. Verify network connectivity from pod:
   ```bash
   # Deploy test pod
   kubectl run -it --rm debug --image=alpine --restart=Never -- \
     wget -O- https://cr.uneeq.io
   ```

---

## Support

For additional help with Harbor registry access or container image issues:

- **Email**: help@uneeq.com
- **Documentation**: https://docs.uneeq.com
- **Harbor API Reference**: https://goharbor.io/docs/working-with-projects/working-with-images/

---

## License

Copyright © 2025 UneeQ Limited. All rights reserved.

All container images hosted on the Harbor registry are proprietary to UneeQ and subject to the terms of your deployment agreement.
