# Live Container Logs

Zeigen Sie die Live-Protokolle der verschiedenen Dienste im MiniPrem-Stack an.

## Container Logs

Wählen Sie einen Dienst aus der Dropdown-Liste aus, um dessen Protokolle anzuzeigen:

```terminal
```container-logs
flowise
vllm
redis
prometheus
grafana
uneeq
```

## Wie es funktioniert

Das obige Terminal stellt eine Verbindung zu den Docker-Container-Protokollen für jeden Dienst her. Dies ermöglicht es Ihnen,:

1. Probleme in Echtzeit zu debuggen
2. Überwachung der Anwendungsaktivität
3. Systemleistung verfolgen

## Protokollsammlung

Logs werden mit dem Logging-System von Docker gesammelt und zu dieser Schnittstelle gestreamt. In einer Produktionsumgebung sollten Sie möglicherweise robustere Protokollierungslösungen in Betracht ziehen, wie z. B.:

- ELK Stack (Elasticsearch, Logstash, Kibana)
- Loki (Teil des Grafana-Stacks)
- Datadog oder andere Cloud-Überwachungslösungen