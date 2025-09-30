# Fast Whisper 統合

MiniPremは、OpenAIのWhisperスピーチ認識モデルの最適化された実装であるfaster-whisperを統合して、正確なリアルタイム文字起こし機能を提供します。このガイドでは、MiniPremプラットフォーム内でFast Whisperサービスを使用および設定する方法について説明します。

## 概要

Fast Whisperは、元のWhisper実装よりも優れたパフォーマンスで自動音声認識（ASR）を提供します：

- WebSocketを介したリアルタイム音声文字起こし
- ファイルベースの文字起こしのためのREST API
- 多言語音声認識
- より高速な処理のためのGPUアクセラレーション
- ダークモードのテストインターフェース

## Webインターフェース

Fast Whisperには、次のURLでアクセス可能なブラウザベースのテストインターフェースが含まれています：

```
http://localhost:9000/static/index.html
```

このインターフェースでは以下が可能です：
- リアルタイムでマイク入力をテスト
- 話しながら文字起こし結果を確認
- 文字起こし履歴のクリア
- 接続状態の監視

## API使用法

### ベースURL

Fast Whisper APIは次の場所で利用可能です：

```
http://localhost:9000
```

### WebSocketリアルタイム文字起こし

リアルタイム音声認識には、WebSocketエンドポイントに接続します：

```
ws://localhost:9000/ws
```

音声データをbase64エンコードされたチャンクとして次の形式で送信します：
```json
{
  \"type\": \"audio\",
  \"data\": \"<base64エンコードされた音声データ>\"
}
```

文字起こしは利用可能になると受信されます：
```json
{
  \"type\": \"transcription\",
  \"text\": \"文字起こしされたテキストがここに表示されます。\",
  \"language\": \"ja\"
}
```

### ファイル文字起こしAPI

POSTリクエストを送信して音声ファイルを文字起こしできます：

```bash
curl -X 'POST' \\
  'http://localhost:9000/transcribe' \\
  -H 'accept: application/json' \\
  -H 'Content-Type: multipart/form-data' \\
  -F 'file=@あなたの音声ファイル.wav' \\
  -F 'language=ja'
```

## 設定

Fast Whisperサービスは`docker-compose.yml`ファイルで次のオプションで構成されています：

```yaml
fastwhisper:
  build:
    context: ./fast-whisper
    dockerfile: Dockerfile
  container_name: fastwhisper
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
    - MODEL_SIZE=tiny.en
    - COMPUTE_TYPE=float16
    - NUM_WORKERS=1
    - CPU_THREADS=4
  ports:
    - \"9000:9000\"
  volumes:
    - ./fast-whisper/app:/app/app
    - ./fast-whisper/models:/app/models
```

## トラブルシューティング

### WebSocket接続の問題

インターフェースでWebSocket接続エラーが表示される場合：

1. Fast Whisperサービスが実行されているか確認：`docker ps | grep fastwhisper`
2. サービスを再起動：`docker restart fastwhisper`
3. エラーのログを確認：`docker logs fastwhisper`
4. ブラウザがWebSocketsをサポートしているか確認

### サービスが起動しない

Fast Whisperサービスが起動しない場合：

1. 十分なGPUメモリがあるか確認
2. NVIDIAランタイムがDockerに適切に設定されているか確認
3. `MODEL_SIZE`環境変数を変更して小さいモデルを試す