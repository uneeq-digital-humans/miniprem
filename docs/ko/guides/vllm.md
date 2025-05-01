# vLLM LLM 통합

이 가이드에서는 자연어 이해 기능을 제공하는 MiniPrem 플랫폼의 vLLM LLM(대규모 언어 모델) 통합에 대해 설명합니다.

## 개요

[vLLM](https://vllm.ai/)은 대규모 언어 모델을 위한 고성능 오픈 소스 추론 엔진입니다. MiniPrem 플랫폼에서 vLLM은 최첨단 오픈 소스 언어 모델인 Gemma3:4b를 사용하여 대화형 인텔리전스를 강화합니다.

## vLLM에 액세스하기

- **API 엔드포인트**: http://localhost:8000/v1
- **컨테이너 이름**: `vllm`

## 기본 모델

MiniPrem은 다음과 같이 사전 구성되어 제공됩니다:
- **모델**: `gemma-3-4b`(또는 사용자가 선택한 허깅페이스 호환 모델)
- **컨텍스트 길이**: 8,192 토큰(모델에 따라 다름)
- **파라미터**: 40억 (모델에 따라 다름)

## vLLM과 직접 상호작용

### OpenAI 호환 API 사용

OpenAI 호환 API를 통해 vLLM과 직접 상호 작용할 수 있습니다:

```bash
# Chat completion
curl -X POST http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-3-4b",
  "messages": [
    { "role": "user", "content": "What is artificial intelligence?" }
  ]
}'
```

## 추가 읽기

- vLLM 공식 문서](https://vllm.readthedocs.io/en/latest/)
- vLLM 깃허브 리포지토리](https://github.com/vllm-project/vllm)