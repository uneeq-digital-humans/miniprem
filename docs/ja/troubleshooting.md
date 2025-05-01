# トラブルシューティングガイド

このガイドは、MiniPremプラットフォームを実行しているときに発生する一般的な問題に対する解決策を提供します。

## 一般的なトラブルシューティング手順

1. **サービスステータスの確認**：
   ```bash
   ./miniprem.sh status
   ```

2. **サービスログの確認**：
   ```bash
   ./miniprem.sh logs
   # または特定のサービス
   ./miniprem.sh logs renny
   ```

3. **サービス再起動**：
   ```bash
   ./miniprem.sh restart
   ```

4. **Dockerリソースの確認**：
   ```bash
   docker stats
   ```

## vLLMの問題

### vLLMコンテナが起動しない

**症状**：vLLMコンテナが起動直後に停止する

**解決策**：
1. GPUの可用性を確認：
   ```bash
   nvidia-smi
   ```

2. NVIDIAランタイムが適切に構成されていることを確認：
   ```bash
   docker info | grep -i runtime
   ```

3. ポート競合を確認：
   ```bash
   sudo lsof -i :8000
   ```

4. vLLMログを確認：
   ```bash
   docker logs vllm
   ```

### モードルの読み込み問題

**症状**：モデルを使用しようとしたときのエラーメッセージ

**解決策**：
1. モデルがダウンロードされていることを確認：
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. モデルを再プル：
   ```bash
   facebook/opt-125mgemma-3-4b
   ```

3. GPUメモリが十分であることを確認：
   ```bash
   nvidia-smi
   ```

4. テスト用に小さいモデルを試す：
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## Flowiseの問題

### Flowise UIにアクセスできない

**症状**：http://localhost:3000でFlowiseにアクセスできない

**解決策**：
1. コンテナが実行されていることを確認：
   ```bash
   docker ps | grep flowise
   ```

2. コンテナログを確認：
   ```bash
   docker logs flowise
   ```

3. ポートの可用性を確認：
   ```bash
   curl -I http://localhost:3000
   ```

### チャットフローの作成失敗

**症状**：チャットフローを作成または保存できない

**解決策**：
1. データベース接続を確認：
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. ボリューム権限を確認：
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. セットアップスクリプトを手動で実行してみる：
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### API認証の問題

**症状**：APIにアクセスするときの認証エラー

**解決策**：
1. 正しいAPIキーを使用していることを確認：
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. APIキーをリセット：
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   次に、適切なコンポーズファイル（docker-compose.base.ymlまたはdocker-compose.extras.yml）で`FLOWISE_SECRETKEY_OVERWRITE`を更新します。

## Rennyの問題

### Rennyのヘルスチェックの失敗

**症状**：Rennyコンテナがアンヘルシーなステータスを報告する

**解決策**：
1. Rennyログを確認：
   ```bash
   docker logs renny
   ```

2. UneeQプラットフォームの接続を確認：
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. Audio2Faceサービスを確認：
   ```bash
   docker ps | grep audio2face
   ```

4. configuration.datファイルを検証：
   ```bash
   cat docker/configuration.dat
   ```

### Audio2Face接続の問題

**症状**：顔のアニメーションが正しく機能しない

**解決策**：
1. Audio2Faceサービスを確認：
   ```bash
   docker logs audio2face_with_emotion
   docker logs audio2face_controller
   ```

2. ネットワーク構成を検証：
   ```bash
   docker exec -it renny ping audio2face-gateway
   ```

3. A2F構成を確認：
   ```bash
   cat docker/a2f-config.yml
   ```

## モニタリングの問題

### Prometheusがメトリクスを収集しない

**症状**：Grafanaダッシュボードにメトリクスがない

**解決策**：
1. Prometheusが実行されていることを確認：
   ```bash
   docker ps | grep prometheus
   ```

2. Prometheusターゲットを確認：
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Prometheus構成を検証：
   ```bash
   cat docker/prometheus.yml
   ```

### Grafanaログインの問題

**症状**：Grafanaにログインできない

**解決策**：
1. デフォルトの資格情報（admin/admin）を使用

2. 管理者パスワードをリセット：
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Grafanaログを確認：
   ```bash
   docker logs grafana
   ```

## ネットワークの問題

### ポート競合

**症状**：ポートがすでに使用されているためサービスが起動しない

**解決策**：
1. ポートを使用しているプロセスを確認：
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. 競合するプロセスを停止するか、適切なコンポーズファイル（docker-compose.base.ymlまたはdocker-compose.extras.yml）でポートを変更します。

3. ファイアウォール設定を確認：
   ```bash
   sudo ufw status
   ```

### Dockerネットワークの問題

**症状**：サービスが互いに通信できない

**解決策**：
1. Dockerネットワークを確認：
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. コンテナ接続を確認：
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Dockerを再起動：
   ```bash
   sudo systemctl restart docker
   ```

## リソースの問題

### メモリ不足

**症状**：サービスがOOMエラーでクラッシュする

**解決策**：
1. メモリ使用量を確認：
   ```bash
   free -h
   docker stats
   ```

2. ホストのスワップスペースを増やす：
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Dockerメモリ制限を調整：
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### GPUメモリの問題

**症状**：GPUメモリ不足エラー

**解決策**：
1. GPU使用量を監視：
   ```bash
   nvidia-smi -l 1
   ```

2. 小さいモデルを使用：
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. MiniPrem操作中に他のアプリケーションがGPUを使用しないようにする

サービスを追加したり、インストールタイプを変更する場合は、インストーラーを再度実行し、目的のオプションを選択してください。