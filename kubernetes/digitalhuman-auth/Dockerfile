FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY auth.py ./auth.py
EXPOSE 8087
# localhost-only: the kiosk reaches it through the nginx /auth/ proxy on the box.
CMD ["uvicorn", "auth:app", "--host", "127.0.0.1", "--port", "8087"]
