# Referencia de API

Esta sección proporciona documentación detallada para las APIs disponibles en la plataforma MiniPrem.

## API de Flowise

La API de Flowise te permite interactuar con tus chatflows mediante programación.

### Autenticación

Agrega el siguiente encabezado a tus solicitudes de API:
```
Authorization: Bearer your_api_key_here
```

### Endpoints

#### API de Predicción

Realiza predicciones usando un chatflow específico.

```
POST /api/v1/prediction/{CHATFLOW_ID}
```

**Cuerpo de la Solicitud:**
```json
{
  "question": "Tu pregunta aquí",
  "history": [
    {
      "type": "human",
      "message": "Pregunta anterior"
    },
    {
      "type": "ai",
      "message": "Respuesta anterior"
    }
  ]
}
```

**Respuesta:**
```json
{
  "result": "La respuesta a tu pregunta...",
  "history": [
    {
      "type": "human",
      "message": "Pregunta anterior"
    },
    {
      "type": "ai",
      "message": "Respuesta anterior"
    },
    {
      "type": "human",
      "message": "Tu pregunta aquí"
    },
    {
      "type": "ai",
      "message": "La respuesta a tu pregunta..."
    }
  ]
}
```

#### API de Chatflows

Lista todos los chatflows disponibles.

```
GET /api/v1/chatflows
```

**Respuesta:**
```json
[
  {
    "id": "chatflow-123",
    "name": "Chatflow vLLM Gemma3",
    "description": "Chatflow usando Gemma3:4b a través de vLLM con Buffer Memory"
  }
]
```

Obtén un chatflow específico.

```
GET /api/v1/chatflows/{CHATFLOW_ID}
```

## API de vLLM

vLLM proporciona una API simple para generar texto y completados de chat.

### Endpoints

#### API de Generación

Genera completados de texto.

```
POST /api/generate
```

**Cuerpo de la Solicitud:**
```json
{
  "model": "Gemma3:4b",
  "prompt": "¿Qué es la inteligencia artificial?",
  "stream": false
}
```

**Respuesta:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "response": "La inteligencia artificial (IA) se refiere a la simulación de la inteligencia humana en máquinas...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

#### API de Chat

Genera completados de chat.

```
POST /api/chat
```

**Cuerpo de la Solicitud:**
```json
{
  "model": "Gemma3:4b",
  "messages": [
    {
      "role": "user",
      "content": "¿Qué es la inteligencia artificial?"
    }
  ]
}
```

**Respuesta:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "message": {
    "role": "assistant",
    "content": "La inteligencia artificial (IA) se refiere a la simulación de la inteligencia humana en máquinas..."
  },
  "done": true,
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

## API de Salud de Renny

Verifica el estado de salud del servicio Renny.

```
GET /health
```

**Respuesta:**
```json
{
  "status": "ok",
  "version": "0.477-c3972",
  "connections": {
    "a2f": "connected",
    "uneeq": "connected",
    "azure_speech": "connected"
  }
}
```

## API de Prometheus

Consulta métricas de Prometheus.

```
GET /api/v1/query
```

**Parámetros de Consulta:**
- `query`: La cadena de consulta de Prometheus
- `time`: Marca de tiempo de evaluación (opcional)

**Ejemplo:**
```
GET /api/v1/query?query=http_requests_total
```

**Respuesta:**
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

## API de Grafana

Accede a tus paneles y visualizaciones a través de la API de Grafana.

```
GET /api/dashboards/uid/{dashboard-uid}
```

**Respuesta:**
```json
{
  "dashboard": {
    "id": 1,
    "uid": "flowise-dashboard",
    "title": "Panel de Flowise",
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
    "folderTitle": "General",
    "folderUrl": ""
  }
}
```