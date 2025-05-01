# Whisper統合

MiniPremは、OpenAIのWhisper音声認識モデルを統合して、高精度の文字起こし機能を提供します。このガイドでは、MiniPremプラットフォームでのWhisperサービスの使用方法と設定方法について説明します。

## 概要

Whisperは、68万時間の多言語およびマルチタスクの教師付きデータで訓練された自動音声認識（ASR）システムです。

- 多言語音声認識
- 音声アクティビティ検出
- 言語識別
- 句読点とフォーマット

MiniPremプラットフォームでは、Whisperはコンテナ化されたAPIサービスとして展開され、オーディオファイルまたはストリームを文字起こしできます。

## APIの使用

### エンドポイント

Whisper APIは以下で利用できます。

```
http://localhost:9000
```

### オーディオファイルの文字起こし

POSTリクエストを送信することで、オーディオファイルを文字起こしできます。

```bash
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@your-audio-file.mp3;type=audio/mpeg' \
  -F 'encode=true'
```

### APIパラメータ

| パラメータ | 説明 | デフォルト |
|-----------|-------------|---------|
| `encode` | レスポンスをbase64エンコードするかどうか | `false` |
| `task` | 実行するタスク（`transcribe`または`translate`） | `transcribe` |
| `language` | 言語コード（例：`en`、`fr`） | 自動検出 |
| `initial_prompt` | 文字起こしをガイドするためのオプションのプロンプト | なし |
| `vad_filter` | 音声アクティビティ検出フィルター | `false` |
| `word_timestamps` | 各単語のタイムスタンプを含めるかどうか | `false` |

## 設定

Whisperサービスは、`docker-compose.yml`ファイルで以下のオプションを使用して設定されます。

```yaml
whisper:
  image: onerahmet/openai-whisper-asr-webservice:latest
  container_name: whisper
  ports:
    - "9000:9000"
  volumes:
    - whisper_data:/root/.cache/whisper
  runtime: nvidia
  environment:
    - ASR_MODEL=medium
    - ASR_ENGINE=openai_whisper
    - NVIDIA_VISIBLE_DEVICES=all
    - INTERVAL=5
```

### 環境変数

| 変数 | 説明 | デフォルト |
|----------|-------------|---------|
| `ASR_MODEL` | Whisperモデルのサイズ（tiny、base、small、medium、large） | `small` |
| `ASR_ENGINE` | 音声認識エンジン | `openai_whisper` |
| `INTERVAL` | ログファイルチェック間隔（秒） | `5` |

## モデルのサイズの変更

デフォルトの設定では、`medium`モデルが使用されます。このモデルは、精度とリソース使用量のバランスが取れています。`ASR_MODEL`環境変数を更新することで、モデルのサイズを変更できます。

```yaml
environment:
  - ASR_MODEL=large
```

利用可能なモデルサイズ：
- `tiny`：最速、低精度（約1GB VRAM）
- `base`：高速で妥当な精度（約1GB VRAM）
- `small`：バランスの取れた速度/精度（約2GB VRAM）
- `medium`：良好な精度（約5GB VRAM）
- `large`：最高の精度（約10GB VRAM）

## パフォーマンスの監視

Whisperのパフォーマンスは、ログビューアーと一般的なシステムメトリクスを通じて監視できます。音声を文字起こしする際には、GPUリソースを大量に使用する場合があるため、以下のコマンドでGPU使用量を監視できます。

```bash
nvidia-smi
```

## Flowiseとの統合

FlowiseワークフローにWhisperを統合するには、HTTPリクエストノードを使用してWhisper APIを呼び出すことができます。これにより、会話フローの一部としてオーディオ入力を処理できます。

## トラブルシューティング

### サービスが開始しない

Whisperサービスが開始しない場合：

1. 利用可能なGPUメモリが十分にあることを確認する
2. NVIDIAランタイムがDockerに対して適切に構成されていることを確認する
3. `ASR_MODEL`環境変数を変更して、より小さいモデルを使用してみる

### 文字起こしの品質が悪い

文字起こしの品質が悪い場合：

1. より大きなモデル（例：`ASR_MODEL=large`）を使用してみる
2. オーディオ入力の品質が良く、背景ノイズが少ないことを確認する
3. `initial_prompt`パラメータを使用して、ドメイン固有の専門用語のコンテキストを提供する

### ログの表示

Whisperサービスのログを表示するには：

```bash
docker logs whisper
```

または、ドキュメンテーション portal のログビューアーを使用する。

## 例の統合

以下は、bashスクリプトを使用してWhisperを統合する例です。

```bash
#!/bin/bash

# オーディオを録音する（ffmpegが必要）
ffmpeg -f alsa -i default -t 10 -acodec libmp3lame -ab 192k -ac 1 recording.mp3

# Whisper APIで文字起こしする
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@recording.mp3;type=audio/mpeg' \
  -F 'task=transcribe' \
  -F 'language=en'
```