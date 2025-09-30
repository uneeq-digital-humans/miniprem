# RIME AI統合

RIME AIは、MiniPremに高品質のテキストから音声への（TTS）サービスを提供します。このガイドでは、セットアップ、APIの使用方法、およびリクエストの例について説明します。

## セットアップ

1. **quay.ioからRIMEイメージをプルします:**
   ```bash
   docker login -u="rimelabs+uneeq" -p="TOKEN GOES HERE" quay.io
   docker pull quay.io/rimelabs/api:v0.0.2-20250407
   docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403
   ```
2. **Docker Composeでサービスを開始します:**
   RIME APIとモデルコンテナは、インストーラーの**フルインストール**オプション（モジュラーDocker Composeファイルを使用）に含まれています。

3. **APIキー:**
   RIMEダッシュボードからRIME APIキーを取得します。すべてのリクエストには、`Authorization`ヘッダーにこのキーが必要です。

## APIの使用方法

RIME APIは`http://localhost:8100`で待ち受けています。

### 例: JSONレスポンス
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I would love to have a conversation with you. The new model is out.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result_mist.txt
```

### 例: MP3レスポンス
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mp3" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.mp3
```

### 例: PCMレスポンス
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/pcm" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.pcm
```

## 注意
- ライセンスと使用状況の検証のために、`http://optimize.rime.ai/usage`と`http://optimize.rime.ai/license`へのアウトバウンドネットワークトラフィックを許可します。
- コンテナの起動後、リクエストを送信する前に最大5分のウォームアップを予想します。
- すべてのボイス/モデルはデフォルトで利用可能です。