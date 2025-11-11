<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# MiniPrem Troubleshooting Guide

> Solutions for common issues when running the MiniPrem platform

</div>

## Table of Contents

- [General Troubleshooting Steps](#general-troubleshooting-steps)
- [vLLM Issues](#vllm-issues)
- [Flowise Issues](#flowise-issues)
- [Renny Issues](#renny-issues)
  - [Renny Health Check Failures](#renny-health-check-failures)
  - [Speech Processing Issues](#speech-processing-issues)
  - [Rendering Quality Issues](#rendering-quality-issues)
- [Monitoring Issues](#monitoring-issues)
- [Network Issues](#network-issues)
- [Resource Issues](#resource-issues)
- [License](#license)
- [Copyright](#copyright)

## General Troubleshooting Steps

1. **Check Service Status**:
   ```bash
   ./miniprem.sh status
   ```

2. **View Service Logs**:
   ```bash
   ./miniprem.sh logs
   # Or for a specific service
   ./miniprem.sh logs renny
   ```

3. **Restart Services**:
   ```bash
   ./miniprem.sh restart
   ```

4. **Check Docker Resources**:
   ```bash
   docker stats
   ```

## vLLM Issues

### vLLM Container Fails to Start

**Symptoms**: vLLM container stops immediately after starting

**Solutions**:
1. Check GPU availability:
   ```bash
   nvidia-smi
   ```

2. Verify NVIDIA runtime is properly configured:
   ```bash
   docker info | grep -i runtime
   ```

3. Check for port conflicts:
   ```bash
   sudo lsof -i :8000
   ```

4. Check vLLM logs:
   ```bash
   docker logs vllm
   ```

### Model Loading Issues

**Symptoms**: Error messages when trying to use the model

**Solutions**:
1. Check if model is downloaded:
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. Re-pull the model:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model facebook/opt-125m
   ```

3. Check for sufficient GPU memory:
   ```bash
   nvidia-smi
   ```

4. Try a smaller model for testing:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## Flowise Issues

### Flowise UI Not Accessible

**Symptoms**: Cannot access Flowise at http://localhost:3000

**Solutions**:
1. Check if the container is running:
   ```bash
   docker ps | grep flowise
   ```

2. Check container logs:
   ```bash
   docker logs flowise
   ```

3. Verify port availability:
   ```bash
   curl -I http://localhost:3000
   ```

### Chatflow Creation Failures

**Symptoms**: Cannot create or save chatflows

**Solutions**:
1. Check database connectivity:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. Check volume permissions:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. Try running the setup script manually:
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### API Authentication Issues

**Symptoms**: Unauthorized errors when accessing the API

**Solutions**:
1. Check if you're using the correct API key:
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. Reset the API key:
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   Then update the `FLOWISE_SECRETKEY_OVERWRITE` in the appropriate compose file (docker-compose.base.yml or docker-compose.extras.yml, depending on your install type).

## Renny Issues

### Renny Health Check Failures

**Symptoms**: Renny container reports unhealthy status

**Solutions**:
1. Check Renny logs:
   ```bash
   docker logs renny
   ```

2. Verify UneeQ platform connectivity:
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. Check internal speech processing:
   ```bash
   docker logs renny | grep -i speech
   ```

4. Verify configuration.dat file:
   ```bash
   cat docker/configuration.dat
   ```

### Speech Processing Issues

**Symptoms**: Facial animations or speech not working correctly

**Solutions**:
1. Check speech processing configuration:
   ```bash
   docker logs renny | grep -i "speech\|audio"
   ```

2. Verify NEW_SPEECH_OVERRIDE environment variable:
   ```bash
   docker exec -it renny env | grep NEW_SPEECH_OVERRIDE
   ```

3. Check Renny internal speech system status:
   ```bash
   curl -s http://localhost:8081/health | grep -i speech
   ```

### Rendering Quality Issues

**Symptoms**: Poor visual quality or unexpected rendering behavior

**Solutions**:
1. Check RENNY_QUALITY_LEVEL setting:
   ```bash
   # Docker
   grep RENNY_QUALITY_LEVEL docker/docker-compose.env

   # Docker (check running container)
   docker exec renny env | grep RENNY_QUALITY_LEVEL

   # Kubernetes
   kubectl get pods -n uneeq-renderer -o yaml | grep RENNY_QUALITY_LEVEL
   ```

2. Verify deployment target matches quality setting:
   - **Dedicated hardware** → Should use `RENNY_QUALITY_LEVEL=miniprem`
   - **Cloud platforms** → Should use `RENNY_QUALITY_LEVEL=web`

3. Change quality level if needed:
   ```bash
   # Docker: Edit docker/docker-compose.env
   RENNY_QUALITY_LEVEL=miniprem  # or web

   # Then restart
   docker compose restart renny
   ```

4. For Kubernetes deployments:
   ```bash
   # Edit kubernetes/values/renny-values.yaml
   # Change RENNY_QUALITY_LEVEL value to "miniprem" or "web"

   # Reapply with Helm
   helm upgrade renny ./kubernetes/renny -f kubernetes/values/renny-values.yaml
   ```

5. For cloud deployments with quality issues:
   - Verify GPU availability: `nvidia-smi` (Docker) or `kubectl exec` (Kubernetes)
   - Check GPU memory usage and adjust if needed
   - Review GPU time-slicing settings in `kubernetes/values/renny-values.yaml`
   - Consider the quality setting matches your deployment type (web for cloud)

See [Renny Quality Settings](guides/renny.md#quality-settings) for detailed configuration.

## Monitoring Issues

### Prometheus Not Collecting Metrics

**Symptoms**: No metrics in Grafana dashboards

**Solutions**:
1. Check if Prometheus is running:
   ```bash
   docker ps | grep prometheus
   ```

2. Check Prometheus targets:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Verify Prometheus configuration:
   ```bash
   cat docker/prometheus.yml
   ```

### Grafana Login Issues

**Symptoms**: Cannot log in to Grafana

**Solutions**:
1. Use default credentials (admin/admin)

2. Reset admin password:
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Check Grafana logs:
   ```bash
   docker logs grafana
   ```

## Network Issues

### Port Conflicts

**Symptoms**: Services fail to start due to port already in use

**Solutions**:
1. Find which process is using the port:
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. Stop the conflicting process or modify the port in the appropriate compose file (docker-compose.base.yml or docker-compose.extras.yml).

3. Check firewall settings:
   ```bash
   sudo ufw status
   ```

### Docker Network Issues

**Symptoms**: Services cannot communicate with each other

**Solutions**:
1. Check Docker network:
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. Verify container connectivity:
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```

## Resource Issues

### Out of Memory

**Symptoms**: Services crashing with OOM errors

**Solutions**:
1. Check memory usage:
   ```bash
   free -h
   docker stats
   ```

2. Increase host swap space:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Adjust Docker memory limits:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### GPU Memory Issues

**Symptoms**: GPU out of memory errors

**Solutions**:
1. Monitor GPU usage:
   ```bash
   nvidia-smi -l 1
   ```

2. Use a smaller model:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. Prevent other applications from using the GPU during MiniPrem operation

If you want to add more services or change your install type, re-run the installer and select the desired option.

---

## License

This troubleshooting guide is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>