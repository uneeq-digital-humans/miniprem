# コンテナログ

MiniPremスタックで実行中のコンテナからのリアルタイムログを表示します。この機能を使用すると、ドキュメントから直接サービスを監視できます。

## 利用可能なコンテナ

ドロップダウンからコンテナを選択してログを表示します:

```container-logs
flowise
vllm
redis
prometheus
grafana
renny
log-streamer
```

## 動作原理

この機能は、ポート8082で実行されているLog Streamerサービスに接続し、DockerログへのWebSocketインターフェースを提供します。コンテナを選択すると、WebSocket接続が確立されます:

```
ws://localhost:8082/logs/{container-name}
```

その後、ログストリーマーサービスはDockerに接続し、ログをリアルタイムにブラウザにストリーミングします。

## トラブルシューティング

ログが表示されない場合:

1. ログストリーマーサービスが実行されていることを確認します:
   ```bash
   docker ps | grep log-streamer
   ```

2. ログストリーマーサービスログを確認します:
   ```bash
   docker logs log-streamer
   ```

3. ブラウザがWebSocketをサポートし、localhost:8082にアクセスできることを確認します

4. それでもログが表示されない場合、サービスはデモンストレーション目的でシミュレートされたログに自動的にフォールバックします。