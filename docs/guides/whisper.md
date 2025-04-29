# Whisper Integration

MiniPrem integrates OpenAI's Whisper speech recognition model for accurate transcription capabilities. This guide explains how to use and configure the Whisper service within the MiniPrem platform.

## Overview

Whisper is an automatic speech recognition (ASR) system trained on 680,000 hours of multilingual and multitask supervised data. It offers:

- Multilingual speech recognition
- Voice activity detection
- Language identification
- Punctuation and formatting

In the MiniPrem platform, Whisper is deployed as a containerized API service that can transcribe audio files or streams.

## API Usage

### Endpoint

The Whisper API is available at:

```
http://localhost:9000
```

### Transcribe Audio File

You can transcribe an audio file by sending a POST request:

```bash
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@your-audio-file.mp3;type=audio/mpeg' \
  -F 'encode=true'
```

### API Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `encode` | Whether to base64 encode the response | `false` |
| `task` | Task to perform (`transcribe` or `translate`) | `transcribe` |
| `language` | Language code (e.g., `en`, `fr`) | Auto-detect |
| `initial_prompt` | Optional prompt to guide the transcription | None |
| `vad_filter` | Voice activity detection filter | `false` |
| `word_timestamps` | Include timestamps for each word | `false` |

## Configuration

The Whisper service is configured in the `docker-compose.yml` file with the following options:

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

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ASR_MODEL` | Whisper model size (tiny, base, small, medium, large) | `small` |
| `ASR_ENGINE` | Speech recognition engine | `openai_whisper` |
| `INTERVAL` | Log file check interval in seconds | `5` |

## Changing the Model Size

The default configuration uses the `medium` model, which offers a good balance between accuracy and resource usage. You can change the model size by updating the `ASR_MODEL` environment variable:

```yaml
environment:
  - ASR_MODEL=large
```

Available model sizes:
- `tiny`: Fastest, lowest accuracy (~1GB VRAM)
- `base`: Fast with reasonable accuracy (~1GB VRAM)
- `small`: Balanced speed/accuracy (~2GB VRAM)
- `medium`: Good accuracy (~5GB VRAM)
- `large`: Best accuracy (~10GB VRAM)

## Performance Monitoring

Whisper performance can be monitored through the log viewer and general system metrics. The service may use significant GPU resources when transcribing audio, so monitor your GPU usage with:

```bash
nvidia-smi
```

## Integration with Flowise

You can integrate Whisper with Flowise workflows by using the HTTP Request node to call the Whisper API. This allows you to process audio inputs as part of your conversation flows.

## Troubleshooting

### Service Not Starting

If the Whisper service fails to start:

1. Check if you have enough GPU memory available
2. Verify that NVIDIA runtime is properly configured for Docker
3. Try using a smaller model by changing the `ASR_MODEL` environment variable

### Poor Transcription Quality

If transcription quality is poor:

1. Try using a larger model (e.g., `ASR_MODEL=large`)
2. Ensure audio input has good quality and minimal background noise
3. Use the `initial_prompt` parameter to provide context for domain-specific terminology

### View Logs

To view the Whisper service logs:

```bash
docker logs whisper
```

Or use the log viewer in the documentation portal.

## Example Integration

Here's an example of how to integrate Whisper with a bash script:

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