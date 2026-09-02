# Deepgram TTS adapter (BYO v1 HTTP -> self-hosted stem /v2/speak).
# python:3.12-slim + websocket-client. Single file, no build args.
FROM python:3.12-slim

RUN pip install --no-cache-dir websocket-client

COPY adapter.py /opt/adapter.py

ENV DEEPGRAM_STEM_URL=http://deepgram-api:8080 \
    DEEPGRAM_TTS_MODEL=flux-hannah-en \
    DEEPGRAM_TTS_SR=16000 \
    ADAPTER_PORT=8086

EXPOSE 8086
CMD ["python3", "/opt/adapter.py"]
