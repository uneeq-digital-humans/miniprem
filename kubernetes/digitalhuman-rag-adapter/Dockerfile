FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8085

WORKDIR /app

# ffmpeg: audio-strip + thumbnail generation for the idle-video library.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
# Default persona prompt; overridden by the mounted ConfigMap in k8s.
COPY prompts/digital-human-system-prompt.md /etc/rag-adapter/digital-human-system-prompt.md

EXPOSE 8085

# Single worker: in-flight SSE streams + per-session ordering stay simple.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8085"]
