# Getting Started

Diese Anleitung hilft Ihnen bei der Installation und Konfiguration der MiniPrem-Plattform auf Ihrem System.

## Voraussetzungen

Bevor Sie beginnen, stellen Sie sicher, dass Sie über die folgenden Voraussetzungen verfügen:

- **Hardware-Anforderungen**:
  - NVIDIA-GPU mit mindestens 8 GB VRAM (16 GB+ empfohlen)
  - 16 GB ODER MEHR RAM
  - 128GB+ freier Festplattenspeicher

- **Software-Anforderungen**:
  - Ubuntu 24.04 LTS oder neuere Version
  - NVIDIA-Treiber (mindestens Version 550.xx)
  - Docker und Docker Compose
  - NVIDIA Container-Werkzeugsatz

## Installation

### 1. Klonen Sie das Repository

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### 2. Führen Sie das Installationsskript aus

```bash
./install_miniprem.sh
```

Das Installationsprogramm wird Sie auffordern, entweder eine **Standardinstallation** (nur Renny + Audio2Face) oder eine **Vollinstallation** (alle Dienste: Renny, Audio2Face, Flowise, vLLM, Grafana, Prometheus, RIME, usw.).
Sie können das Installationsprogramm jederzeit erneut ausführen, um von der Standard- zur Vollinstallation zu wechseln oder Ihre Auswahl zu ändern.

### 3. Konfigurationswerte

Während der Installation benötigen Sie die folgenden Informationen:

| Konfiguration | Beschreibung | Beispiel |
|-----------------------|---------------------------------------------|----------------------------------------------|
| Adresse der UneeQ-Plattform | Adresse des UneeQ-Signalisierungsdienstes | api.enterprise.uneeq.io |
| UneeQ-Plattform-API-Schlüssel | API-Schlüssel für die UneeQ-Plattform | your_uneeq_api_key_here |
| Tenant ID | Ihre UneeQ-Mieterkennung | your_tenant_id_here |
| Azure Region | Azure Region für Sprachdienste | your_azure_region |
| Azure Speech Key | Azure Sprachdienst-API-Schlüssel | your_azure_speech_key_here |
| Renny Image | Docker Image für Renny digital human | facemeproduction/renny:latest |
| RIME API-Schlüssel | Docker Image für RIME Text-zu-Sprache | your_rime_api_key |
| Huggingface Token | Token für den Zugriff auf Huggingface | your_huggingface_token |
| UneeQ Docker Hub Token | Token für den Zugriff auf UneeQs Image-Repository | your_personal_access_token |

### 4. Überprüfen Sie die Installation

Überprüfen Sie nach Abschluss der Installation, ob alle Dienste ausgeführt werden:

```bash
./miniprem.sh status
```

Sie sollten sehen, dass alle Container in Ordnung sind und funktionieren.

## Verwaltung der Plattform

### Dienste starten

```bash
./miniprem.sh start
```

### Dienste stoppen

```bash
./miniprem.sh stop
```

### Logs ansehen

```bash
./miniprem.sh logs
```

Sie können auch Protokolle für einen bestimmten Dienst anzeigen:

```bash
./miniprem.sh logs renny
./miniprem.sh logs flowise
./miniprem.sh logs vllm
```

### Neustart der Dienste

```bash
./miniprem.sh restart
```

## Nächste Schritte

Sobald Ihre MiniPrem-Plattform betriebsbereit ist, fahren Sie fort mit:

1. [Configure Flowise](flowise.md), um Ihre Konversationsabläufe einzurichten
2. [Leistung überwachen](monitoring.md) mit Grafana-Dashboards
3. [Customize Renny](renny.md) für Ihren spezifischen Anwendungsfall