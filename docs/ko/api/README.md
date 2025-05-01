# API 참조

이 섹션에서는 MiniPrem 플랫폼에서 사용 가능한 API에 대한 자세한 문서를 제공합니다.

## Flowise API

Flowise API를 사용하면 대화 흐름과 프로그래밍 방식으로 상호 작용할 수 있습니다.

### 인증

API 요청에 다음 헤더를 추가하세요:
```
Authorization: Bearer your_api_key_here
```

### 엔드포인트

#### 예측 API

특정 대화 흐름을 사용하여 예측을 수행합니다.

```
POST /api/v1/prediction/{CHATFLOW_ID}
```

**요청 본문:**
```json
{
  "question": "질문 여기에",
  "history": [
    {
      "type": "human",
      "message": "이전 질문"
    },
    {
      "type": "ai",
      "message": "이전 답변"
    }
  ]
}
```

**응답:**
```json
{
  "result": "질문에 대한 답변...",
  "history": [
    {
      "type": "human",
      "message": "이전 질문"
    },
    {
      "type": "ai",
      "message": "이전 답변"
    },
    {
      "type": "human",
      "message": "질문 여기에"
    },
    {
      "type": "ai",
      "message": "질문에 대한 답변..."
    }
  ]
}
```

#### 대화 흐름 API

사용 가능한 모든 대화 흐름을 나열합니다.

```
GET /api/v1/chatflows
```

**응답:**
```json
[
  {
    "id": "chatflow-123",
    "name": "vLLM Gemma3 대화 흐름",
    "description": "vLLM을 사용한 Gemma3:4b 대화 흐름(Buffer Memory 포함)"
  }
]
```

특정 대화 흐름을 가져옵니다.

```
GET /api/v1/chatflows/{CHATFLOW_ID}
```

## vLLM API

vLLM은 텍스트 및 대화 완성을 생성하기 위한 간단한 API를 제공합니다.

### 엔드포인트

#### 생성 API

텍스트 완성을 생성합니다.

```
POST /api/generate
```

**요청 본문:**
```json
{
  "model": "Gemma3:4b",
  "prompt": "인공지능이란 무엇인가?",
  "stream": false
}
```

**응답:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "response": "인공지능(AI)은 기계에서 인간 지능을 시뮬레이션하는 것을 말합니다...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

#### 대화 API

대화 완성을 생성합니다.

```
POST /api/chat
```

**요청 본문:**
```json
{
  "model": "Gemma3:4b",
  "messages": [
    {
      "role": "user",
      "content": "인공지능이란 무엇인가?"
    }
  ]
}
```

**응답:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "message": {
    "role": "assistant",
    "content": "인공지능(AI)은 기계에서 인간 지능을 시뮬레이션하는 것을 말합니다..."
  },
  "done": true,
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

## Renny 상태 API

Renny 서비스의 상태 정보를 확인합니다.

```
GET /health
```

**응답:**
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

## Prometheus API

Prometheus에서 메트릭을 쿼리합니다.

```
GET /api/v1/query
```

**쿼리 매개변수:**
- `query`: Prometheus 쿼리 문자열
- `time`: 평가 타임스탬프(선택 사항)

**예시:**
```
GET /api/v1/query?query=http_requests_total
```

**응답:**
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

Grafana API를 통해 대시보드 및 시각화에 액세스합니다.

```
GET /api/dashboards/uid/{dashboard-uid}
```

**응답:**
```json
{
  "dashboard": {
    "id": 1,
    "uid": "flowise-dashboard",
    "title": "Flowise 대시보드",
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
    "folderTitle": "일반",
    "folderUrl": ""
  }
}
```