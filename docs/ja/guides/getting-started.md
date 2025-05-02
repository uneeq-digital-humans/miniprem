# クイックスタートガイド

このガイドは、MiniPremプラットフォームをシステムにインストールして構成するのに役立ちます。

## 前提条件

始める前に、以下の要件を満たしていることを確認してください:

- **ハードウェア要件**:
  - 8GB以上のVRAMを搭載したNVIDIA GPU（16GB以上推奨）
  - 16GB以上のRAM
  - 50GB以上の空きディスク容量

- **ソフトウェア要件**:
  - Ubuntu 24.04 LTS以降
  - NVIDIAドライバー（バージョン550.xx以降）
  - DockerとDocker Compose
  - NVIDIAコンテナツールキット

## インストール

### 1. リポジトリをクローンする

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### 2. インストールスクリプトを実行する

```bash
./install_miniprem.sh
```

インストーラーは、**デフォルトのインストール**（Renny + Audio2Faceのみ）または**フルインストール**（Renny、Audio2Face、Flowise、vLLM、Grafana、Prometheus、RIMEなどのすべてのサービス）のいずれかを選択するように促します。必要に応じて、いつでもデフォルトからフルにアップグレードしたり、選択を変更したりできます。

### 3. 設定値

インストール時に、以下の情報が必要になります:

| 設定 | 説明 | 例 |
|-----------------------|------------------------------------------------|------------------------------------------------|
| UneeQプラットフォームアドレス | UneeQシグナリングサービスのアドレス | api.uneeq.io |
| UneeQプラットフォームAPIキー | UneeQプラットフォームのAPIキー | your_uneeq_api_key_here |
| テナントID | UneeQテナント識別子 | your_tenant_id_here |
| Azureリージョン | スピーチサービス用のAzureリージョン | your_azure_region |
| Azureスピーチキー | AzureスピーチサービスAPIキー | your_azure_speech_key_here |
| Rennyイメージ | RennyデジタルヒューマンのDockerイメージ | facemeproduction/renny:latest |
| RIME APIキー | RIMEテキスト読み上げ用のDockerイメージ | your_rime_api_key |
| Huggingfaceトークン | Huggingfaceアクセス用のトークン | your_huggingface_token |
| UneeQ Docker Hubトークン | UneeQのイメージリポジトリアクセス用のトークン | your_personal_access_token |

### 4. インストールを検証する

インストールが完了したら、すべてのサービスが実行されていることを確認します:

```bash
./miniprem.sh status
```

すべてのコンテナが実行され、正常であることを確認する必要があります。

## プラットフォームの管理

### サービスの起動

```bash
./miniprem.sh start
```

### サービスの停止

```bash
./miniprem.sh stop
```

### ログの表示

```bash
./miniprem.sh logs
```

特定のサービスのログも表示できます:

```bash
./miniprem.sh logs renny
./miniprem.sh logs flowise
./miniprem.sh logs vllm
```

### サービスの再起動

```bash
./miniprem.sh restart
```

## 次のステップ

MiniPremプラットフォームが稼働したら、以下の手順に進んでください:

1. [Flowiseを構成する](flowise.md)して会話フローを設定する
2. [Grafanaダッシュボードを使用してパフォーマンスを監視する](monitoring.md)
3. [Rennyをカスタマイズする](renny.md)して特定のユースケースに合わせる