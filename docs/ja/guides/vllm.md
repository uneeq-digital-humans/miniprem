# vLLM LLM 統合

このガイドでは、MiniPremプラットフォームのvLLM大規模言語モデル（LLM）統合について説明します。これにより、自然言語理解機能が提供されます。

## 概要

[vLLM](https://vllm.ai/)は、大規模な言語モデルのための高性能なオープンソース推論エンジンです。MiniPremプラットフォームでは、vLLMは指示対応とチャットに最適化された最先端のオープンソース言語モデルであるMistral-7B-Instruct-v0.3を使用して会話型インテリジェンスを実現しています。

## 前提条件

- HuggingFaceアカウント
- Mistralモデルの利用規約への同意
- 読み取り権限を持つHuggingFace APIトークン

## 初期設定

インストール時にシステムは以下を行います：
1. HuggingFaceアカウントの作成/ログインをガイド
2. Mistralモデルの利用規約への同意をサポート
3. HuggingFace APIトークンの作成と設定をサポート
4. Mistralモデルのダウンロードと設定

## vLLMへのアクセス

- **APIエンドポイント**: http://localhost:8000/v1
- **コンテナ名**: `vllm`
- **モデルパス**: `facebook/opt-125m`

## デフォルトモデル

MiniPremには以下が事前設定されています：
- **モデル**: `Mistral-7B-Instruct-v0.3`
- **コンテキスト長**: 8,192トークン
- **パラメータ**: 70億
- **最適化**: GPU推論用に事前設定済み

## vLLMとの直接的な対話

### OpenAI互換APIの使用

vLLMとはOpenAI互換APIを介して直接対話できます：

```bash
# チャット補完
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "facebook/opt-125m",
    "messages": [
        {"role": "system", "content": "あなたは役立つAIアシスタントです。"},
        {"role": "user", "content": "人工知能とは何ですか？"}
    ]
}'
```

## 詳細な読み物

- [vLLM公式ドキュメント](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHubリポジトリ](https://github.com/vllm-project/vllm)
