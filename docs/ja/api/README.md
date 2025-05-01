# APIリファレンス

このセクションでは、MiniPremプラットフォームで利用可能なAPIの詳細なドキュメントを提供します。

## Flowise API

Flowise APIを使用すると、チャットフローをプログラムで操作できます。

### 認証

APIリクエストに以下のヘッダーを追加します:
```
Authorization: Bearer your_api_key_here
```

### エンドポイント

#### 予測API

特定のチャットフローを使用して予測を行います。

```
POST /api/v1/prediction/{CHATFLOW_ID}
```

**リクエストボディ:**
```json
{
  "question": "あなたの質問はこちら",
  "history": [
    {
      "type": "human",
      "message": "前の質問"
    },
    {
      "type": "ai",
      "message": "前の回答"
    }
  ]
}
```

**レスポンス:**
```json
{
  "result": "あなたの質問の答え...",
  "history": [
    {
      "type": "human",
      "message": "前の質問"
    },
    {
      "type": "ai",
      "message": "前の回答"
    },
    {
      "type": "human",
      "message": "あなたの質問はこちら"
    },
    {
      "type": "ai",
      "message": "あなたの質問の答え..."
    }
  ]
}
```

#### チャットフローAPI

利用可能なチャットフローをすべてリストします。

```
GET /api/v1/chatflows
```

**レスポンス:**
```json
[
  {
    "id": "chatflow-123",
    "name": "vLLM Gemma3 Chatflow",
    "description": "vLLMを介したGemma3:4bを使用したチャットフロー"
  }
]
```

特定のチャットフローを取得します。

```
GET /api/v1/chatflows/{CHATFLOW_ID}
```

## vLLM API

vLLMは、テキストとチャット完了を生成するためのシンプルなAPIを提供します。

### エンドポイント

#### 生成API

テキスト完了を生成します。

```
POST /api/generate
```

**リクエストボディ:**
```json
{
  "model": "Gemma3:4b",
  "prompt": "人工知能とは何ですか?",
  "stream": false
}
```

**レスポンス:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "response": "人工知能（AI）とは、機械における人間の知能のシミュレーションを指します...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

#### チャットAPI

チャット完了を生成します。

```
POST /api/chat
```

**リクエストボディ:**
```json
{
  "model": "Gemma3:4b",
  "messages": [
    {
      "role": "user",
      "content": "人工知能とは何ですか?"
    }
  ]
}
```

**レスポンス:**
```json
{
  "model": "Gemma3:4b",
  "created_at": "2023-11-09T14:15:22.339408Z",
  "message": {
    "role": "assistant",
    "content": "人工知能（AI）とは、機械における人間の知能のシミュレーションを指します..."
  },
  "done": true,
  "total_duration": 2157865125,
  "load_duration": 1364520,
  "prompt_eval_duration": 40123456,
  "eval_count": 291,
  "eval_duration": 2116376561
}
```

## RennyヘルスAPI

Rennyサービスのヘルスステータスを確認します。

```
GET /health
```

**レスポンス:**
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

Prometheusからメトリクスをクエリします。

```
GET /api/v1/query
```

**クエリパラメータ:**
- `query`: Prometheusクエリ文字列
- `time`: 評価タイムスタンプ（オプション）

**例:**
```
GET /api/v1/query?query=http_requests_total
```

**レスポンス:**
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

Grafana APIを使用して、ダッシュボードとビジュアライゼーションにアクセスします。

```
GET /api/dashboards/uid/{dashboard-uid}
```

**レスポンス:**
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