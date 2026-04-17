# Phoenix LLM Observability Setup

This guide explains how to set up and use Arize Phoenix for LLM observability in MiniPrem deployments.

## What is Phoenix?

[Arize Phoenix](https://docs.arize.com/phoenix/) is an open-source LLM observability platform that provides:

- **Tracing**: Track LLM requests, responses, and latencies
- **Debugging**: Identify issues in AI workflows
- **Evaluation**: Analyze model performance
- **Prometheus Metrics**: Export metrics for monitoring

## Quick Start

### Docker Deployment

Phoenix is included in the full install docker-compose but disabled by default. To enable:

```bash
# Start with Phoenix profile
cd docker
docker compose -f docker-compose.full.yml --profile phoenix up -d

# Or set environment variable
export COMPOSE_PROFILES=phoenix
docker compose -f docker-compose.full.yml up -d
```

### Access Phoenix UI

Once running, access the Phoenix UI at:
- **URL**: http://localhost:6006

### Ports

| Port | Service |
|------|---------|
| 6006 | Phoenix Web UI |
| 4317 | OTLP gRPC Collector |
| 9091 | Prometheus Metrics |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PHOENIX_ENABLE_PROMETHEUS` | `true` | Enable Prometheus metrics endpoint |
| `PHOENIX_WORKING_DIR` | `/phoenix` | Data storage directory |
| `PHOENIX_PORT` | `6006` | Web UI port |

### Prometheus Integration

Phoenix exposes metrics on port 9091. The `prometheus.yml` is pre-configured to scrape Phoenix:

```yaml
scrape_configs:
  - job_name: 'phoenix'
    static_configs:
      - targets: ['localhost:9091']
    metrics_path: /metrics
```

## Instrumenting Your Applications

### Python Applications

Install the Phoenix instrumentation library:

```bash
pip install arize-phoenix openinference-instrumentation-openai
```

Configure tracing:

```python
import phoenix as px
from openinference.instrumentation.openai import OpenAIInstrumentor

# Connect to Phoenix
px.launch_app()  # or px.connect(endpoint="http://localhost:6006")

# Instrument OpenAI client
OpenAIInstrumentor().instrument()

# Your LLM calls are now traced
from openai import OpenAI
client = OpenAI()
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### Flowise Integration

Flowise workflows can be traced by enabling LangChain tracing:

```yaml
# In docker-compose.env or environment
LANGCHAIN_TRACING_V2=true
LANGCHAIN_ENDPOINT=http://localhost:4317
```

### vLLM Integration

For vLLM-based inference:

```python
from openinference.instrumentation.openai import OpenAIInstrumentor

# Instrument vLLM's OpenAI-compatible API
OpenAIInstrumentor().instrument()

# Point to vLLM
client = OpenAI(base_url="http://localhost:8800/v1")
```

## Kubernetes Deployment

For CNS/Kubernetes deployments, Phoenix is deployed via Ansible or Helm.

### CNS (MicroK8s) Deployment

Phoenix is **not** deployed by default when you run `./miniprem.sh deploy`. Enable it explicitly:

```bash
# From the repo root on the CNS host
cd kubernetes/ansible
ansible-playbook -i inventory/hosts.yml playbooks/phoenix-setup.yml
```

After deployment, verify and access the UI:

```bash
# Check Phoenix pod is running
sudo microk8s kubectl get pods -n observability

# Port-forward the Phoenix UI to your workstation (run from your workstation, not the CNS host)
ssh -L 6006:localhost:6006 <cns-host>
sudo microk8s kubectl port-forward -n observability svc/phoenix 6006:6006
# Then open http://localhost:6006 in your browser

# Alternative: expose via NodePort for LAN access
sudo microk8s kubectl patch svc phoenix -n observability \
  -p '{"spec": {"type": "NodePort"}}'
sudo microk8s kubectl get svc phoenix -n observability  # Shows the assigned NodePort
```

**Connecting instrumentation to Phoenix on CNS:**

Point your OTLP exporters at the in-cluster Phoenix service (from other pods) or the NodePort (from off-cluster):

```bash
# From another pod in the cluster:
export OTEL_EXPORTER_OTLP_ENDPOINT=http://phoenix.observability.svc.cluster.local:4317

# From off-cluster (NodePort):
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<cns-host>:<otlp-nodeport>
```

**Scraping Phoenix metrics into the MiniPrem Prometheus**: Phoenix exposes `/metrics` on port 9090 (or 9091 in Docker). The CNS deployment annotates the pod with `prometheus.io/scrape: "true"` so any Prometheus configured to auto-discover annotated pods will pick it up.

### Using Ansible

```bash
ansible-playbook -i inventory/hosts.yml playbooks/phoenix-setup.yml
```

### Manual Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phoenix
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phoenix
  template:
    metadata:
      labels:
        app: phoenix
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      containers:
      - name: phoenix
        image: arizephoenix/phoenix:latest
        ports:
        - containerPort: 6006
          name: ui
        - containerPort: 4317
          name: otlp
        - containerPort: 9090
          name: prometheus
        env:
        - name: PHOENIX_ENABLE_PROMETHEUS
          value: "true"
```

## Viewing Traces

### Phoenix UI Features

1. **Traces View**: See all LLM requests with timing and token counts
2. **Spans View**: Detailed breakdown of each operation
3. **Evaluations**: Run LLM-as-judge evaluations on traces
4. **Datasets**: Export traces as evaluation datasets

### Filtering Traces

- Filter by model name
- Filter by latency
- Filter by error status
- Search by content

## Prometheus Metrics

Phoenix exposes these key metrics:

| Metric | Description |
|--------|-------------|
| `phoenix_traces_total` | Total number of traces |
| `phoenix_spans_total` | Total number of spans |
| `phoenix_latency_seconds` | Request latency histogram |
| `phoenix_token_count` | Token usage counter |

### Grafana Dashboard

Import Phoenix metrics into Grafana for visualization alongside other MiniPrem metrics.

## Troubleshooting

### Phoenix Not Starting

```bash
# Check container logs
docker logs phoenix

# Verify port availability
netstat -tlnp | grep -E "6006|4317|9091"
```

### No Traces Appearing

1. Verify instrumentation is installed
2. Check OTLP endpoint connectivity
3. Ensure traces are being sent to `localhost:4317`

### High Memory Usage

Phoenix stores traces in memory by default. For production:

```yaml
environment:
  - PHOENIX_SQL_DATABASE_URL=postgresql://user:pass@host:5432/phoenix
```

## Resources

- [Phoenix Documentation](https://docs.arize.com/phoenix/)
- [OpenInference SDK](https://github.com/Arize-ai/openinference)
- [Phoenix GitHub](https://github.com/Arize-ai/phoenix)
