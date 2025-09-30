# API-Referenz

Dieser Abschnitt bietet eine detaillierte Dokumentation für die APIs, die auf der MiniPrem-Plattform verfügbar sind.

## Flowise API

Die Flowise API ermöglicht es Ihnen, Ihre Chatflows programmgesteuert zu bearbeiten.

### Authentifizierung

Fügen Sie dem folgenden Header zu Ihren API-Anfragen hinzu:
```
Authorization: Bearer Ihre_API_Schlüssel_hier
```

### Endpunkte

#### Vorhersage-API

Machen Sie Vorhersagen mithilfe eines bestimmten Chatflows.

```
POST /api/v1/prediction/{CHATFLOW_ID}
```

**Anfrage-Body:**
```json
{
  "question": "Ihre Frage hier",
  "history": [
    {
      "type": "human",
      "message": "Vorherige Frage"
    },
    {
      "type": "ai",
      "message": "Vorherige Antwort"
    }
  ]
}
```

**Antwort:**
```json
{
  "result": "Die Antwort auf Ihre Frage...",
  "history": [
    {
      "type": "human",
      "message": "Vorherige Frage"
    },
    {
      "type": "ai",
      "message": "Vorherige Antwort"
    },
    {
      "type": "human",
      "message": "Ihre Frage hier"
    },
    {
      "type": "ai",
      "message": "Die Antwort auf Ihre Frage..."
    }
  ]
}
```

#### Chatflows-API

Listen Sie alle verfügbaren Chatflows auf.

```
GET /api/v1/chatflows
```

**Antwort:**
```json
[
  {
    "id": "chatflow-123",
    "name": "vLLM Gemma3 Chatflow",
    "description": "Chatflow mit HuggingFaceH4/zephyr-7b-beta über vLLM mit Buffer Memory"
  }
]
```

Rufen Sie einen bestimmten Chatflow ab.

```
GET /api/v1/chatflows/{CHATFLOW_ID}
```

## vLLM API

vLLM bietet eine einfache API für die Generierung von Text und Chat-Komplettierungen.

### Endpunkte

#### Generieren-API

Generieren Sie Text-Komplettierungen.

```
POST /api/generate
```

**Anfrage-Body:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "prompt": "Was ist künstliche Intelligenz?",
  "stream": false
}
```

**Antwort:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "response": "Künstliche Intelligenz (KI) bezieht sich auf die Simulation menschlicher Intelligenz in Maschinen...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

#### Chat-API

Generieren Sie Chat-Komplettierungen.

```
POST /api/chat
```

**Anfrage-Body:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "messages": [
    {
      "role": "user",
      "content": "Was ist künstliche Intelligenz?"
    }
  ]
}
```

**Antwort:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "message": {
    "role": "assistant",
    "content": "Künstliche Intelligenz (KI) bezieht sich auf die Simulation menschlicher Intelligenz in Maschinen..."
  },
  "done": true,
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

## Renny Health API

Überprüfen Sie den Gesundheitsstatus des Renny-Dienstes.

```
GET /health
```

**Antwort:**
```json
{
  "status": "ok",
  "version": "0.477-c3972",
  "connections": {
    "a2f": "verbunden",
    "uneeq": "verbunden",
    "azure_speech": "verbunden"
  }
}
```

## Prometheus API

Abfragen Sie Metriken von Prometheus.

```
GET /api/v1/query
```

**Abfrage-Parameter:**
- `query`: Die Prometheus-Abfragezeichenfolge
- `time`: Auswertungstimestamp (optional)

**Beispiel:**
```
GET /api/v1/query?query=http_requests_total
```

**Antwort:**
```json
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "http_requests_total",
          "instance": "flowise:3000",
          "job": "flowise"
        },
        "value": [1609746000, "42"]
      }
    ]
  }
}
```

## Grafana API

Greifen Sie über die Grafana API auf Ihre Dashboards und Visualisierungen zu.

```
GET /api/dashboards/uid/{dashboard-uid}
```

**Antwort:**
```json
{
  "dashboard": {
    "id": 1,
    "uid": "flowise-dashboard",
    "title": "Flowise Dashboard",
    "tags": [],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 1,
    "panels": [...]
  },
  "meta": {
    "isStarred": false,
    "url": "/d/flowise-dashboard",
    "folderId": 0,
    "folderUid": "",
    "folderTitle": "Allgemein",
    "folderUrl": ""
  }
}
```