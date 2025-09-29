# API Reference

This section provides detailed documentation for the APIs available in the MiniPrem platform.

## Flowise API

The Flowise API allows you to interact with your chatflows programmatically.

### Authentication

Add the following header to your API requests:
```
Authorization: Bearer your_api_key_here
```

### Endpoints

#### Prediction API

Make predictions using a specific chatflow.

```
POST /api/v1/prediction/{CHATFLOW_ID}
```

**Request Body:**
```json
{
  "question": "Your question here",
  "history": [
    {
      "type": "human",
      "message": "Previous question"
    },
    {
      "type": "ai",
      "message": "Previous answer"
    }
  ]
}
```

**Response:**
```json
{
  "result": "The answer to your question...",
  "history": [
    {
      "type": "human",
      "message": "Previous question"
    },
    {
      "type": "ai",
      "message": "Previous answer"
    },
    {
      "type": "human",
      "message": "Your question here"
    },
    {
      "type": "ai",
      "message": "The answer to your question..."
    }
  ]
}
```

#### Chatflows API

List all available chatflows.

```
GET /api/v1/chatflows
```

**Response:**
```json
[
  {
    "id": "chatflow-123",
    "name": "vLLM Gemma3 Chatflow",
    "description": "Chatflow using HuggingFaceH4/zephyr-7b-beta via vLLM with Buffer Memory"
  }
]
```

Get a specific chatflow.

```
GET /api/v1/chatflows/{CHATFLOW_ID}
```

## vLLM API

vLLM provides a simple API for generating text and chat completions.

### Endpoints

#### Generate API

Generate text completions.

```
POST /api/generate
```

**Request Body:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "prompt": "What is artificial intelligence?",
  "stream": false
}
```

**Response:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "response": "Artificial intelligence (AI) refers to the simulation of human intelligence in machines...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

#### Chat API

Generate chat completions.

```
POST /api/chat
```

**Request Body:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "messages": [
    {
      "role": "user",
      "content": "What is artificial intelligence?"
    }
  ]
}
```

**Response:**
```json
{
  "model": "HuggingFaceH4/zephyr-7b-beta",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "message": {
    "role": "assistant",
    "content": "Artificial intelligence (AI) refers to the simulation of human intelligence in machines..."
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

Check the health status of the Renny service.

```
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "version": "5.6mha",
  "connections": {
    "internal_speech": "enabled",
    "uneeq": "connected",
    "azure_speech": "fallback_available"
  }
}
```

## Prometheus API

Query metrics from Prometheus.

```
GET /api/v1/query
```

**Query Parameters:**
- `query`: The Prometheus query string
- `time`: Evaluation timestamp (optional)

**Example:**
```
GET /api/v1/query?query=http_requests_total
```

**Response:**
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

Access your dashboards and visualizations via the Grafana API.

```
GET /api/dashboards/uid/{dashboard-uid}
```

**Response:**
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
    "folderTitle": "General",
    "folderUrl": ""
  }
}
```