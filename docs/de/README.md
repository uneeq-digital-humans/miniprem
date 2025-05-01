# MiniPrem-Plattform

> Eine umfassende Plattform für digitale Menschen mit LLM-Integration, Echtzeit-Gesichtsanimation und Überwachungsfunktionen.

## Überblick

MiniPrem ist eine integrierte Plattform, die eine digitale menschliche Schnittstelle (Renny) mit LLM-Funktionen (vLLM), Workflow-Automatisierung (Flowise) und umfassenden Überwachungswerkzeugen (Prometheus + Grafana) kombiniert. Mit diesem Setup können Sie erweiterte KI-Interaktionen über eine virtuelle menschliche Schnittstelle bereitstellen und verwalten.

## Funktionen

- **Digitale menschliche Schnittstelle**: Powered by Renny, mit Echtzeit-Gesichtsanimation
- **LLM-Integration**: vLLM mit Gemma3 für natürliches Sprachverständnis
- **Workflow-Automatisierung**: Flowise für die Erstellung und Verwaltung von KI-Workflows
- **Metriken und Überwachung**: Prometheus und Grafana für die Leistungsverfolgung in Echtzeit
- **Warteschlangenverwaltung**: Redis für zuverlässige Nachrichtenverarbeitung
- **RIME AI**: Hochwertige Text-to-Speech über eine einfache API

## Schnellstart

### Voraussetzungen

- Docker und Docker Compose
- NVIDIA GPU mit entsprechenden Treibern
- Ubuntu Linux (empfohlen)
- Erforderliche Anmeldeinformationen von UneeQ (Plattformadresse, API-Schlüssel, Mieter-ID)
- Anmeldedaten für den Azure Speech-Dienst (Region und API-Schlüssel)

### Installation

Vollständige Installationsanweisungen finden Sie in unserem [Getting Started Guide](guides/getting-started.md).

## Plattform-Komponenten

MiniPrem umfasst die folgenden Komponenten:

- **Renny**: Digitale menschliche Schnittstelle mit Echtzeit-Gesichtsanimation
- **vLLM**: Großes Sprachmodell, das mit Gemma3 bedient wird
- **Flowise**: Visueller Workflow-Builder für KI-Anwendungen
- **Prometheus & Grafana**: Echtzeit-Überwachung und Dashboards
- *Redis**: Nachrichtenwarteschlange für zuverlässige Verarbeitung
- **RIME**: Hochwertige Text-to-Speech-Engine

## Nächste Schritte

- Erste Schritte](guides/getting-started.md): Installation und grundlegende Einrichtung
- Überblick über die Dienste](guides/services.md): Details zu jeder Komponente
- Fehlerbehebung](troubleshooting.md): Lösungen für häufige Probleme
