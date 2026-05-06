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

## Flowise Integration

Flowise is instrumented via OpenTelemetry using `@arizeai/openinference-instrumentation-langchain`.
This is loaded automatically via `docker/flowise/otel-init.js` — no code changes to Flowise are needed.

To enable tracing, set `PHOENIX_ENABLED=true` when starting the stack:

```bash
PHOENIX_ENABLED=true docker compose -f docker-compose.full.yml --profile phoenix up -d
```

Every LLM call, chain run, tool call, and agent step in Flowise will appear as a trace in Phoenix at http://localhost:6006.

**How it works**: The init script at `/otel/otel-init.js` is injected into Node.js via `NODE_OPTIONS=--require` before Flowise starts. It instruments LangChain.js callbacks and exports spans to Phoenix's OTLP gRPC endpoint on port 4317. If Phoenix is not running, Flowise continues normally — the exporter fails silently.

## Kubernetes Deployment

For CNS/Kubernetes deployments, Phoenix is deployed via Ansible or Helm:

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
