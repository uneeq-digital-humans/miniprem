# Fast Whisper Integration

MiniPrem integrates faster-whisper, an optimized implementation of OpenAI's Whisper speech recognition model for accurate real-time transcription capabilities. This guide explains how to use and configure the Fast Whisper service within the MiniPrem platform.

## Overview

Fast Whisper provides automatic speech recognition (ASR) with improved performance over the original Whisper implementation. It offers:

- Real-time speech transcription via WebSocket
- REST API for file-based transcription
- Multilingual speech recognition
- GPU acceleration for faster processing
- Dark mode testing interface

## Web Interface

Fast Whisper includes a browser-based testing interface accessible at:

```
http://localhost:9000/static/index.html
```

This interface allows you to:
- Test microphone input in real-time
- See transcription results as you speak
- Clear transcription history
- Monitor connection status

## API Usage

### Base URL

The Fast Whisper API is available at:

```
http://localhost:9000
```

### WebSocket Real-time Transcription

For real-time speech recognition, connect to the WebSocket endpoint:

```
ws://localhost:9000/ws
```

Send audio data as base64-encoded chunks in this format:
```json
{
  \"type\": \"audio\",
  \"data\": \"<base64-encoded-audio-data>\"
}
```

Receive transcriptions as they become available:
```json
{
  \"type\": \"transcription\",
  \"text\": \"The transcribed text will appear here.\",
  \"language\": \"en\"
}
```

### File Transcription API

You can transcribe an audio file by sending a POST request:

```bash
curl -X 'POST' \\
  'http://localhost:9000/transcribe' \\
  -H 'accept: application/json' \\
  -H 'Content-Type: multipart/form-data' \\
  -F 'file=@your-audio-file.wav' \\
  -F 'language=en'
```

### API Parameters

| Parameter | Description | Default |
|-----------|-------------|----------|
| `file` | Audio file to transcribe | Required |
| `language` | Language code (e.g., `en`, `fr`) | Auto-detect |
| `initial_prompt` | Optional prompt to guide the transcription | None |

## Configuration

The Fast Whisper service is configured in the `docker-compose.yml` file with the following options:

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

### Environment Variables

| Variable | Description | Default |
|----------|-------------|----------|
| `MODEL_SIZE` | Whisper model size (tiny.en, base.en, small.en, etc.) | `tiny.en` |
| `COMPUTE_TYPE` | GPU compute type (float16, float32, int8) | `float16` |
| `NUM_WORKERS` | Number of worker threads | `1` |
| `CPU_THREADS` | Number of CPU threads (for CPU fallback) | `4` |

## Changing the Model Size

The default configuration uses the `tiny.en` model, which offers quick processing with moderate accuracy. You can change the model size by updating the `MODEL_SIZE` environment variable:

```yaml
environment:
  - MODEL_SIZE=base.en
```

Available model sizes:
- `tiny.en`: Fastest, lowest accuracy (~1GB VRAM)
- `base.en`: Fast with reasonable accuracy (~1GB VRAM)
- `small.en`: Balanced speed/accuracy (~2GB VRAM)
- `medium.en`: Good accuracy (~5GB VRAM)
- `large-v3`: Best accuracy (~10GB VRAM)

## Integration with Other Services

### Desktop Voice Input

You can use Fast Whisper as a voice-to-text input method with this example script:

```bash
#!/bin/bash
# Record audio with silence detection
sox -d -r 16000 -c 1 -b 16 /tmp/dictation.wav silence 1 0.1 3% 1 1.0 3%

# Send to Fast Whisper for transcription
TEXT=$(curl -s -X POST \"http://localhost:9000/transcribe\" \\
  -H \"accept: application/json\" \\
  -H \"Content-Type: multipart/form-data\" \\
  -F \"file=@/tmp/dictation.wav\" | jq -r .text)

# Type the text at the current cursor position
xdotool type \"$TEXT\"
```

### Flowise Integration

You can integrate Fast Whisper with Flowise workflows by using the HTTP Request node to call the transcription API, or create a custom WebSocket node for real-time transcription.

## Troubleshooting

### WebSocket Connection Issues

If you see WebSocket connection errors in the interface:

1. Check if the Fast Whisper service is running: `docker ps | grep fastwhisper`
2. Restart the service: `docker restart fastwhisper`
3. Check logs for errors: `docker logs fastwhisper`
4. Verify your browser supports WebSockets

### Service Not Starting

If the Fast Whisper service fails to start:

1. Check if you have enough GPU memory available
2. Verify that NVIDIA runtime is properly configured for Docker
3. Try using a smaller model by changing the `MODEL_SIZE` environment variable

### Poor Transcription Quality

If transcription quality is poor:

1. Try using a larger model (e.g., `MODEL_SIZE=medium.en`)
2. Ensure audio input has good quality and minimal background noise
3. Use the `initial_prompt` parameter to provide context for domain-specific terminology

### View Logs

To view the Fast Whisper service logs:

```bash
docker logs fastwhisper
```

Or use the log viewer in the documentation portal.