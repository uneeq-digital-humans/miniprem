# Überblick über die MiniPrem-Dienste

Die MiniPrem-Plattform besteht aus mehreren integrierten Diensten, die zusammenarbeiten, um ein umfassendes digitales Erlebnis für den Menschen zu bieten. Dieser Leitfaden gibt einen Überblick über diese Dienste und ihr Zusammenspiel.

## Kerndienste

| Dienst | Zweck | Port | Dokumentation |
|---------|---------|------|---------------|
| Renny | Digitaler menschlicher Avatar | 8081 | [Renny Guide](renny.md) |
| vLLM | Großes Sprachmodell | 8000 | [vLLM Leitfaden](vllm.md) |
| Flowise | Workflow-Automatisierung | 3000 | [Flowise Leitfaden](flowise.md) |
| Redis | Warteschlangenverwaltung | 6379 | - |
| Prometheus | Metrics collection | 9090 | [Monitoring Guide](monitoring.md) |
| Grafana | Visualisierung von Metriken | 3001 | [Monitoring Guide](monitoring.md) |
| Audio2Face | Gesichtsanimation | 50000, 52000 | [Renny Guide](renny.md) |
| RIME | Text-to-Speech API | 8100 | [RIME-Anleitung](rime.md) |
| Whisper | Spracherkennung | 9000 | [Whisper Guide](whisper.md) |

## Dienstarchitektur

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Renny    │◄────┤ Audio2Face  │     │   Flowise   │
│Digital Human│     │ Animation   │     │ Workflow    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────┐
│                 Docker Network                      │
└─────────────┬─────────────┬─────────────┬───────────┘
              │             │             │
              ▼             ▼             ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │   vLLM      │ │    Redis    │ │ Prometheus  │
    │  LLM Engine │ │   Queue     │ │   Metrics   │
    └─────────────┘ └─────────────┘ └──────┬──────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │   Grafana   │
                                    │ Dashboards  │
                                    └─────────────┘
```

## Service-Abhängigkeiten

- **Renny** hängt ab von:
  - Audio2Face-Dienste für Gesichtsanimation
  - Azure Speech Services für Text-to-Speech (extern)
  - UneeQ-Plattform für die Darstellung von Avataren (extern)

- **Flowise** hängt ab von:
  - vLLM für Sprachmodellfunktionen
  - Redis für die Warteschlangenverwaltung
  - SQLite für die Datenbankspeicherung (eingebettet)

- **Überwachung** hängt ab von:
  - Prometheus für die Sammlung von Metriken
  - Grafana für die Visualisierung

## Umgebungsvariablen

Jeder Dienst wird über Umgebungsvariablen in der Docker Compose-Datei konfiguriert. Die wichtigsten Umgebungsvariablen sind:

- **Renny**:
  - `DHOP_ADDRESS`: Adresse der UneeQ-Plattform
  - A2F_ADDRESS": Adresse des Audio2Face-Dienstes
  - AZURE_REGION" & "AZURE_SPEECH": Anmeldeinformationen für den Sprachdienst

- **Flowise**:
  - `DATENBANK-TYP`: Für die lokale Datenbank auf SQLite eingestellt
  - FLOWISE_BENUTZERNAME" & "FLOWISE_PASSWORT": Anmeldedaten für die Authentifizierung
  - `REDIS_HOST` & `REDIS_PORT`: Redis-Verbindungsdetails

- **vLLM**:
  - `NVIDIA_VISIBLE_DEVICES`: GPU-Zuweisung für Modellinferenz

## Volumes

Persistente Daten werden in Docker-Volumes gespeichert:

- **vllm_data**: Speichert heruntergeladene Sprachmodelle
- **flowise_data**: Speichert Flowise-Konfigurationen und die Datenbank
- **redis_daten**: Speichert die Daten der Redis-Warteschlange
- **prometheus_data**: Speichert den Verlauf der Metriken
- **grafana_data**: Speichert Dashboard-Konfigurationen

## Netzwerk-Konfiguration

Die meisten Dienste verwenden das Standard-Docker-Netzwerk für die Kommunikation, mit diesen Ausnahmen:

- **Renny** verwendet `network_mode: "host"` für optimale Leistung
- Dienste referenzieren sich gegenseitig über den Containernamen (z.B. `http://vllm:8000`) innerhalb des Docker-Netzwerks

## Dienst-Gesundheitsprüfungen

Alle Dienste enthalten Gesundheitsprüfungen, um sicherzustellen, dass sie ordnungsgemäß funktionieren:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

Diese Gesundheitsprüfungen dienen der Koordinierung der Abhängigkeiten beim Start des Dienstes.