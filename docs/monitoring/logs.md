# Live Container Logs

View the live logs from various services in the MiniPrem stack.

## Container Logs

Select a service from the dropdown to view its logs:

```terminal
```container-logs
flowise
ollama
redis
prometheus
grafana
uneeq
```

## How it Works

The terminal above connects to the Docker container logs for each service. This allows you to:

1. Debug issues in real-time
2. Monitor application activity
3. Track system performance

## Log Collection

Logs are collected using Docker's logging system and streamed to this interface. In a production environment, you might want to consider more robust logging solutions such as:

- ELK Stack (Elasticsearch, Logstash, Kibana)
- Loki (part of the Grafana stack)
- Datadog or other cloud monitoring solutions