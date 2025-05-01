# vLLM LLM 통합

이 가이드는 자연어 이해 기능을 제공하는 MiniPrem 플랫폼의 vLLM 대규모 언어 모델(LLM) 통합에 대해 다룹니다.

## 개요

[vLLM](https://vllm.ai/)은 대규모 언어 모델을 위한 고성능 오픈 소스 추론 엔진입니다. MiniPrem 플랫폼에서 vLLM은 지시 사항 따르기와 채팅에 최적화된 최첨단 오픈 소스 언어 모델인 Mistral-7B-Instruct-v0.3을 사용하여 대화형 지능을 제공합니다.

## 전제 조건

- HuggingFace 계정
- Mistral 모델 사용 약관 동의
- 읽기 권한이 있는 HuggingFace API 토큰

## 초기 설정

설치 중에 시스템은 다음을 수행합니다:
1. HuggingFace 계정 생성/로그인 안내
2. Mistral 모델 약관 동의 지원
3. HuggingFace API 토큰 생성 및 구성 지원
4. Mistral 모델 다운로드 및 구성

## vLLM 접근

- **API 엔드포인트**: http://localhost:8000/v1
- **컨테이너 이름**: `vllm`
- **모델 경로**: `mistralai/Mistral-7B-Instruct-v0.3`

## 기본 모델

MiniPrem은 다음과 같이 사전 구성되어 있습니다:
- **모델**: `Mistral-7B-Instruct-v0.3`
- **컨텍스트 길이**: 8,192 토큰
- **매개변수**: 70억
- **최적화**: 효율적인 GPU 추론을 위해 사전 구성됨

## vLLM과 직접 상호작용

### OpenAI 호환 API 사용

OpenAI 호환 API를 통해 vLLM과 직접 상호작용할 수 있습니다:

```bash
# 채팅 완성
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.3",
  "messages": [
      {"role": "system", "content": "당신은 도움이 되는 AI 어시스턴트입니다."},
      {"role": "user", "content": "인공지능이란 무엇인가요?"}
  ]
}'
```

## 추가 읽기

- vLLM 공식 문서](https://vllm.readthedocs.io/en/latest/)
- vLLM 깃허브 리포지토리](https://github.com/vllm-project/vllm)