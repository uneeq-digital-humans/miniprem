# vLLM LLM統合

このガイドでは、MiniPremプラットフォームでのvLLM大規模言語モデル（LLM）統合について説明します。これにより、自然言語理解機能が提供されます。

## 概要

[vLLM](https://vllm.ai/)は、大規模な言語モデルのための高性能なオープンソース推論エンジンです。MiniPremプラットフォームでは、vLLMはGemma3:4bという最先端のオープンソース言語モデルを使用して会話型インテリジェンスを実現しています。

## vLLMへのアクセス

- **APIエンドポイント**: http://localhost:8000/v1
- **コンテナ名**: `vllm`

## デフォルトモデル

MiniPremには、以下の設定がプリコンフィグされています。
- **モデル**: `gemma-3-4b`（または選択したHuggingFace互換モデル）
- **コンテキスト長**: 8,192トークン（モデル依存）
- **パラメータ**: 40億（モデル依存）

## vLLMとの直接対話

### OpenAI互換APIの使用

vLLMのOpenAI互換APIを使用して直接対話することができます。

```bash
# チャット完了
curl -X POST http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-3-4b",
  "messages": [
    { "role": "user", "content": "人工知能とは何ですか？" }
  ]
}'
```

## 詳細な読み物

- [vLLM公式ドキュメント](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHubリポジトリ](https://github.com/vllm-project/vllm)