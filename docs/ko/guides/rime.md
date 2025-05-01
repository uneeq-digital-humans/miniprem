# RIME AI 통합

RIME AI는 미니프렘을 위한 고품질 텍스트 음성 변환(TTS) 서비스를 제공합니다. 이 가이드는 설정, API 사용법 및 요청 예시를 다룹니다.

## 설정

1. **quay.io에서 RIME 이미지 가져오기:**
   ```bash
   docker login -u="rimelabs+uneeq" -p="TOKEN GOES HERE" quay.io
   docker pull quay.io/rimelabs/api:v0.0.2-20250407
   docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403
   ```
2. **Docker Compose로 서비스 시작하기** 2.
   RIME API와 모델 컨테이너는 설치 관리자의 **Full Install** 옵션에 포함되어 있습니다(모듈식 Docker Compose 파일 사용).

3. **API 키:**
   RIME 대시보드에서 RIME API 키를 받습니다. 모든 요청에는 `Authorization` 헤더에 이 키가 필요합니다.

## API 사용량

RIME API는 `http://localhost:8100`에서 수신 대기합니다.

### 예제: JSON 응답
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I would love to have a conversation with you. The new model is out.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result_mist.txt
```

### 예제: MP3 응답
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mp3" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.mp3
```

### 예제: PCM 응답
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/pcm" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.pcm
```

## 참고
- 라이선스 및 사용량 확인을 위해 `http://optimize.rime.ai/usage` 및 `http://optimize.rime.ai/license`로 아웃바운드 네트워크 트래픽을 허용하세요.
- 요청을 보내기 전에 컨테이너를 시작한 후 최대 5분의 워밍업 시간이 소요될 것으로 예상됩니다.
- 기본적으로 모든 음성/모델을 사용할 수 있습니다.