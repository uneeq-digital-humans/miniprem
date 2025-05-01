# 위스퍼 통합

MiniPrem은 정확한 트랜스크립션 기능을 위해 OpenAI의 Whisper 음성 인식 모델을 통합합니다. 이 가이드는 MiniPrem 플랫폼 내에서 Whisper 서비스를 사용하고 구성하는 방법을 설명합니다.

## 개요

Whisper는 68만 시간의 다국어 및 멀티태스크 감독 데이터로 학습된 자동 음성 인식(ASR) 시스템입니다. 다음을 제공합니다:

- 다국어 음성 인식
- 음성 활동 감지
- 언어 식별
- 구두점 및 서식 지정

미니프렘 플랫폼에서 위스퍼는 오디오 파일이나 스트림을 트랜스크립션할 수 있는 컨테이너화된 API 서비스로 배포됩니다.

## API 사용

### 엔드포인트

위스퍼 API는 다음에서 사용할 수 있습니다:

```
http://localhost:9000
```

### 오디오 파일 전사

POST 요청을 보내 오디오 파일을 트랜스크립션할 수 있습니다:

```bash
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@your-audio-file.mp3;type=audio/mpeg' \
  -F 'encode=true'
```

API 매개변수 ###

| 매개변수 | 설명 | 기본값 |
|-----------|-------------|---------|
| `encode` | 응답을 base64 인코딩할지 여부 | `false` |
| `task` | 수행할 작업(`번역` 또는 `번역`) | `번역` |
| `언어` | 언어 코드(예: `en`, `fr`) | 자동 감지 |
| `initial_prompt` | 전사를 안내하는 선택적 프롬프트 | 없음 |
| `vad_filter` | 음성 활동 감지 필터 | `false` |
| `word_timestamps`` 각 단어에 타임스탬프 포함``false``

## 구성

위스퍼 서비스는 `docker-compose.yml` 파일에서 다음 옵션으로 구성됩니다:

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

### 환경 변수

| 변수 | 설명 | 기본값 |
|----------|-------------|---------|
| `ASR_MODEL` | 귓속말 모델 크기(작은, 기본, 작은, 중간, 큰) | `작은` |
| `ASR_ENGINE` | 음성 인식 엔진 | `openai_whisper` |
| '간격' | 로그 파일 확인 간격(초) | '5' |

## 모델 크기 변경

기본 구성은 정확도와 리소스 사용량 간의 균형이 잘 잡힌 '중간' 모델을 사용합니다. ASR_MODEL` 환경 변수를 업데이트하여 모델 크기를 변경할 수 있습니다:

```yaml
environment:
  - ASR_MODEL=large
```

사용 가능한 모델 크기:
- '소형': 가장 빠르고 정확도 낮음(~1GB VRAM)
- 기본`: 빠른 속도와 적당한 정확도(~1GB VRAM)
- 소형`: 균형 잡힌 속도/정확도(~2GB VRAM)
- 중간`: 양호한 정확도(~5GB VRAM)
- 대형`: 최상의 정확도(~10GB VRAM)

## 성능 모니터링

로그 뷰어와 일반 시스템 메트릭을 통해 귓속말 성능을 모니터링할 수 있습니다. 이 서비스는 오디오를 트랜스크립션할 때 상당한 GPU 리소스를 사용할 수 있으므로 GPU 사용량을 모니터링하세요:

```bash
nvidia-smi
```

## 플로우이즈와 통합

HTTP 요청 노드를 사용하여 Whisper API를 호출함으로써 Whisper를 플로우이즈 워크플로우와 통합할 수 있습니다. 이를 통해 대화 흐름의 일부로 오디오 입력을 처리할 수 있습니다.

## 문제 해결

### 서비스가 시작되지 않음

위스퍼 서비스가 시작되지 않는 경우:

1. 사용 가능한 GPU 메모리가 충분한지 확인합니다.
2. NVIDIA 런타임이 Docker에 맞게 올바르게 구성되었는지 확인합니다.
3. ASR_MODEL` 환경 변수를 변경하여 더 작은 모델을 사용해보십시오.

### 트랜스크립션 품질 불량

전사 품질이 좋지 않은 경우:

1. 더 큰 모델을 사용해 보세요(예: `ASR_MODEL=large`).
2. 오디오 입력의 품질이 좋고 배경 소음이 최소화되었는지 확인합니다.
3. 초기_프롬프트` 매개변수를 사용하여 도메인별 용어에 대한 컨텍스트를 제공합니다.

### 로그 보기

Whisper 서비스 로그를 보려면 다음과 같이 하세요:

```bash
docker logs whisper
```

또는 문서 포털의 로그 뷰어를 사용하세요.

## 통합 예시

다음은 Whisper를 bash 스크립트와 연동하는 방법의 예시입니다:

```bash
#!/bin/bash

# Record audio (requires ffmpeg)
ffmpeg -f alsa -i default -t 10 -acodec libmp3lame -ab 192k -ac 1 recording.mp3

# Transcribe with Whisper API
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@recording.mp3;type=audio/mpeg' \
  -F 'task=transcribe' \
  -F 'language=en'
```