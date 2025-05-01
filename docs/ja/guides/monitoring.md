# PrometheusとGrafanaによる監視

このガイドでは、MiniPremプラットフォームのパフォーマンスと使用状況の指標を追跡するために、組み込みの監視ツールを使用する方法について説明します。

## 概要

MiniPremには、2つの強力な監視ツールが含まれています:

1. **Prometheus**: 時系列データベースで、メトリクスを収集して保存します
2. **Grafana**: Prometheusデータからダッシュボードを作成するビジュアライゼーションプラットフォーム

## 監視ツールのアクセス

| ツール | URL | デフォルトの資格情報 |
|------|-----|---------------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | なし |

## Grafanaダッシュボード

### 事前に構成されたダッシュボード

MiniPremのインストールには、Flowiseの監視用に事前に構成されたダッシュボードが含まれています:

1. **Flowiseダッシュボード**: Flowiseインスタンスの主要なメトリクスを表示します:
   - HTTPリクエスト数
   - HTTPリクエストの期間
   - メモリ使用量
   - CPU使用量

### ダッシュボードの表示

1. http://localhost:3001でGrafanaにログインします
2. 左のサイドバーで「Dashboards」をクリックします
3. リストから「Flowise Dashboard」を選択します

### カスタムダッシュボードの作成

1. サイドバーで「+」アイコンをクリックします
2. 「Dashboard」を選択します
3. 「Add new panel」をクリックします
4. ビジュアライゼーションの種類（グラフ、ゲージ、テーブルなど）を選択します
5. クエリエディターでPrometheusクエリを入力します
6. 表示オプションを構成します
7. ダッシュボードにパネルを追加するには「Save」をクリックします

## Prometheusクエリの例

### 基本的なメトリクス

```promql
# HTTPリクエスト数
http_request_total

# 過去5分間の平均リクエスト時間
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# メモリ使用量
process_resident_memory_bytes

# CPU使用量
rate(process_cpu_seconds_total[1m])
```