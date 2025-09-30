# Fast Whisper 통합

MiniPrem은 OpenAI의 Whisper 음성 인식 모델의 최적화된 구현인 faster-whisper를 통합하여 정확한 실시간 전사 기능을 제공합니다. 이 가이드는 MiniPrem 플랫폼 내에서 Fast Whisper 서비스를 사용하고 구성하는 방법을 설명합니다.

## 개요

Fast Whisper는 원래 Whisper 구현보다 향상된 성능으로 자동 음성 인식(ASR)을 제공합니다:

- WebSocket을 통한 실시간 음성 전사
- 파일 기반 전사를 위한 REST API
- 다국어 음성 인식
- 더 빠른 처리를 위한 GPU 가속
- 다크 모드 테스트 인터페이스

## 웹 인터페이스

Fast Whisper에는 다음 URL에서 접근 가능한 브라우저 기반 테스트 인터페이스가 포함되어 있습니다:

```
http://localhost:9000/static/index.html
```

이 인터페이스에서는 다음이 가능합니다:
- 실시간으로 마이크 입력 테스트
- 말하는 동안 전사 결과 확인
- 전사 기록 지우기
- 연결 상태 모니터링

## API 사용법

### 기본 URL

Fast Whisper API는 다음에서 사용할 수 있습니다:

```
http://localhost:9000
```

### WebSocket 실시간 전사

실시간 음성 인식을 위해 WebSocket 엔드포인트에 연결합니다:

```
ws://localhost:9000/ws
```

오디오 데이터를 다음 형식의 base64 인코딩 청크로 보냅니다:
```json
{
  \"type\": \"audio\",
  \"data\": \"<base64로 인코딩된 오디오 데이터>\"
}
```

전사는 사용 가능해지면 수신됩니다:
```json
{
  \"type\": \"transcription\",
  \"text\": \"전사된 텍스트가 여기에 나타납니다.\",
  \"language\": \"ko\"
}
```

### 파일 전사 API

POST 요청을 보내 오디오 파일을 전사할 수 있습니다:

```bash
curl -X 'POST' \\
  'http://localhost:9000/transcribe' \\
  -H 'accept: application/json' \\
  -H 'Content-Type: multipart/form-data' \\
  -F 'file=@오디오파일.wav' \\
  -F 'language=ko'
```

## 구성

Fast Whisper 서비스는 `docker-compose.yml` 파일에서 다음 옵션으로 구성됩니다:

```yaml
fastwhisper:
  build:
    context: ./fast-whisper
    dockerfile: Dockerfile
  container_name: fastwhisper
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
    - MODEL_SIZE=tiny.en
    - COMPUTE_TYPE=float16
    - NUM_WORKERS=1
    - CPU_THREADS=4
  ports:
    - \"9000:9000\"
  volumes:
    - ./fast-whisper/app:/app/app
    - ./fast-whisper/models:/app/models
```

## 문제 해결

### WebSocket 연결 문제

인터페이스에서 WebSocket 연결 오류가 표시되는 경우:

1. Fast Whisper 서비스가 실행 중인지 확인: `docker ps | grep fastwhisper`
2. 서비스 재시작: `docker restart fastwhisper`
3. 오류 로그 확인: `docker logs fastwhisper`
4. 브라우저가 WebSockets을 지원하는지 확인

### 서비스가 시작되지 않음

Fast Whisper 서비스가 시작되지 않는 경우:

1. 충분한 GPU 메모리가 있는지 확인
2. NVIDIA 런타임이 Docker에 올바르게 구성되어 있는지 확인
3. `MODEL_SIZE` 환경 변수를 변경하여 더 작은 모델 시도