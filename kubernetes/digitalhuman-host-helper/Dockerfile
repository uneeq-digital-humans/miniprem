FROM python:3.12-slim
# pactl (pulseaudio-utils) for audio; xrandr (x11-xserver-utils) for display
# resolution/rotation; docker CLI (static) for NIM pulls + Renny logs/restart;
# kubectl for kubeadm Renny deploys (no-op unless a kubeconfig is mounted).
RUN apt-get update && apt-get install -y --no-install-recommends pulseaudio-utils x11-xserver-utils curl ca-certificates \
    && curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz -o /tmp/d.tgz \
    && tar xzf /tmp/d.tgz -C /tmp && mv /tmp/docker/docker /usr/local/bin/ && rm -rf /tmp/d.tgz /tmp/docker \
    && curl -fsSL "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir fastapi==0.115.6 "uvicorn[standard]==0.34.0" pydantic==2.10.4
WORKDIR /app
COPY host_helper.py .
EXPOSE 8086
CMD ["uvicorn", "host_helper:app", "--host", "127.0.0.1", "--port", "8086"]
