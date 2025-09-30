# Überwachung mit Prometheus und Grafana

In diesem Leitfaden erfahren Sie, wie Sie die integrierten Überwachungstools verwenden, um Leistungs- und Nutzungsmetriken für Ihre MiniPrem-Plattform zu verfolgen.

## Überblick

MiniPrem enthält zwei leistungsstarke Überwachungstools:

1. **Prometheus**: Eine Zeitseriendatenbank, die Metriken sammelt und speichert
2. **Grafana**: Eine Visualisierungsplattform, die Dashboards aus Prometheus-Daten erstellt

## Zugriff auf Monitoring-Tools

| Tool | URL | Standard Credentials |
|------|-----|---------------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | N/A |

## Grafana Dashboards

### Vorkonfigurierte Dashboards

Die MiniPrem-Installation enthält ein vorkonfiguriertes Dashboard zur Überwachung von Flowise:

1. **Flowise Dashboard**: Zeigt die wichtigsten Metriken für Ihre Flowise-Instanz an:
   - Anzahl der HTTP-Anfragen
   - Dauer der HTTP-Anfrage
   - Speicherauslastung
   - CPU-Nutzung

### Anzeigen von Dashboards

1. Melden Sie sich bei Grafana unter http://localhost:3001 an.
2. Klicken Sie auf "Dashboards" in der linken Seitenleiste
3. Wählen Sie "Flowise Dashboard" aus der Liste

### Benutzerdefinierte Dashboards erstellen

1. Klicken Sie auf das "+"-Symbol in der Seitenleiste
2. Wählen Sie "Dashboard".
3. Klicken Sie auf "Neues Panel hinzufügen".
4. Wählen Sie Ihren Visualisierungstyp (Diagramm, Messgerät, Tabelle usw.)
5. Geben Sie eine Prometheus-Abfrage in den Abfrage-Editor ein
6. Konfigurieren Sie die Anzeigeoptionen
7. Klicken Sie auf "Speichern", um das Panel zu Ihrem Dashboard hinzuzufügen

## Prometheus-Abfragebeispiele

### Grundlegende Metriken

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
