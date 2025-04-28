# RIME AI Integration

RIME AI provides high-quality text-to-speech (TTS) services for MiniPrem. This guide covers setup, API usage, and example requests.

## Setup

1. **Pull RIME images from quay.io:**
   ```bash
   docker login -u="rimelabs+uneeq" -p="TOKEN GOES HERE" quay.io
   docker pull quay.io/rimelabs/api:v0.0.2-20250407
   docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403
   ```
2. **Start services with Docker Compose:**
   RIME API and model containers are included in the main `docker-compose.yml`.

3. **API Key:**
   Obtain your RIME API key from the RIME dashboard. All requests require this key in the `Authorization` header.

## API Usage

The RIME API listens on `http://localhost:8100`.

### Example: JSON response
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

### Example: MP3 response
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

### Example: PCM response
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

## Notes
- Allow outbound network traffic to `http://optimize.rime.ai/usage` and `http://optimize.rime.ai/license` for licensing and usage verification.
- Expect up to 5 minutes warm-up after starting the containers before sending requests.
- All voices/models are available by default. 