# Fast Whisper Integration

MiniPrem integriert faster-whisper, eine optimierte Implementierung von OpenAIs Whisper-Spracherkennungsmodell für präzise Echtzeit-Transkriptionsfähigkeiten. Dieser Leitfaden erklärt, wie Sie den Fast Whisper-Dienst innerhalb der MiniPrem-Plattform verwenden und konfigurieren können.

## Überblick

Fast Whisper bietet automatische Spracherkennung (ASR) mit verbesserter Leistung gegenüber der ursprünglichen Whisper-Implementierung:

- Echtzeit-Sprachtranskription über WebSocket
- REST-API für dateibasierte Transkription
- Mehrsprachige Spracherkennung
- GPU-Beschleunigung für schnellere Verarbeitung
- Testoberfläche im Dunkelmodus

## Weboberfläche

Fast Whisper enthält eine browserbasierte Testoberfläche, die unter folgender URL zugänglich ist:

```
http://localhost:9000/static/index.html
```

Diese Oberfläche ermöglicht es Ihnen:
- Mikrofoneingang in Echtzeit zu testen
- Transkriptionsergebnisse während des Sprechens zu sehen
- Transkriptionsverlauf zu löschen
- Verbindungsstatus zu überwachen

## API-Nutzung

### Basis-URL

Die Fast Whisper API ist verfügbar unter:

```
http://localhost:9000
```

### WebSocket-Echtzeit-Transkription

Für die Echtzeit-Spracherkennung stellen Sie eine Verbindung zum WebSocket-Endpunkt her:

```
ws://localhost:9000/ws
```

Senden Sie Audiodaten als base64-kodierte Chunks in diesem Format:
```json
{
  \"type\": \"audio\",
  \"data\": \"<base64-kodierte-Audiodaten>\"
}
```

Empfangen Sie Transkriptionen, sobald sie verfügbar sind:
```json
{
  \"type\": \"transcription\",
  \"text\": \"Der transkribierte Text erscheint hier.\",
  \"language\": \"de\"
}
```

### Datei-Transkriptions-API

Sie können eine Audiodatei transkribieren, indem Sie eine POST-Anfrage senden:

```bash
curl -X 'POST' \\
  'http://localhost:9000/transcribe' \\
  -H 'accept: application/json' \\
  -H 'Content-Type: multipart/form-data' \\
  -F 'file=@ihre-audiodatei.wav' \\
  -F 'language=de'
```

## Konfiguration

Der Fast Whisper-Dienst wird in der Datei `docker-compose.yml` mit folgenden Optionen konfiguriert:

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

## Fehlerbehebung

### WebSocket-Verbindungsprobleme

Wenn in der Oberfläche WebSocket-Verbindungsfehler angezeigt werden:

1. Prüfen Sie, ob der Fast Whisper-Dienst läuft: `docker ps | grep fastwhisper`
2. Starten Sie den Dienst neu: `docker restart fastwhisper`
3. Überprüfen Sie die Logs auf Fehler: `docker logs fastwhisper`
4. Stellen Sie sicher, dass Ihr Browser WebSockets unterstützt

### Dienst startet nicht

Wenn der Fast Whisper-Dienst nicht startet:

1. Prüfen Sie, ob genügend GPU-Speicher verfügbar ist
2. Stellen Sie sicher, dass die NVIDIA-Laufzeit für Docker korrekt konfiguriert ist
3. Versuchen Sie, ein kleineres Modell zu verwenden, indem Sie die Umgebungsvariable `MODEL_SIZE` ändern