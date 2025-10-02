# Monitoring with Prometheus and Grafana

This guide covers how to use the built-in monitoring tools to track performance and usage metrics for your MiniPrem platform.

## Overview

MiniPrem includes two powerful monitoring tools:

1. **Prometheus**: A time-series database that collects and stores metrics
2. **Grafana**: A visualization platform that creates dashboards from Prometheus data

## Accessing Monitoring Tools

| Tool | URL | Default Credentials |
|------|-----|---------------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | N/A |

## Grafana Dashboards

### Pre-configured Dashboards

The MiniPrem installation includes a pre-configured dashboard for monitoring Flowise:

1. **Flowise Dashboard**: Shows key metrics for your Flowise instance:
   - HTTP Request Count
   - HTTP Request Duration
   - Memory Usage
   - CPU Usage

### Viewing Dashboards

1. Log in to Grafana at http://localhost:3001
2. Click on "Dashboards" in the left sidebar
3. Select "Flowise Dashboard" from the list

### Creating Custom Dashboards

1. Click the "+" icon in the sidebar
2. Select "Dashboard"
3. Click "Add new panel"
4. Choose your visualization type (graph, gauge, table, etc.)
5. Enter a Prometheus query in the query editor
6. Configure display options
7. Click "Save" to add the panel to your dashboard

## Prometheus Query Examples

### Basic Metrics

```promql
# HTTP request count
http_request_total

# Average request duration in the last 5 minutes
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Memory usage
process_resident_memory_bytes

# CPU usage
rate(process_cpu_seconds_total[1m])
```
