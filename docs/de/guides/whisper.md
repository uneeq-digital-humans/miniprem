# Whisper Integration

MiniPrem integriert das Whisper-Spracherkennungsmodell von OpenAI für präzise Transkriptionsfunktionen. Dieser Leitfaden erklärt, wie Sie den Whisper-Dienst innerhalb der MiniPrem-Plattform nutzen und konfigurieren.

## Überblick

Whisper ist ein automatisches Spracherkennungssystem (ASR), das auf 680.000 Stunden mehrsprachiger und multitasking-überwachter Daten trainiert wurde. Es bietet:

- Mehrsprachige Spracherkennung
- Erkennung von Sprachaktivitäten
- Identifizierung der Sprache
- Interpunktion und Formatierung

Auf der MiniPrem-Plattform wird Whisper als containerisierter API-Dienst bereitgestellt, der Audiodateien oder -ströme transkribieren kann.

## API-Nutzung

### Endpunkt

Die Whisper-API ist verfügbar unter:

```
http://localhost:9000
```

### Audiodatei transkribieren

Sie können eine Audiodatei transkribieren, indem Sie eine POST-Anfrage senden:

```bash
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@your-audio-file.mp3;type=audio/mpeg' \
  -F 'encode=true'
```

### API-Parameter

| Parameter | Beschreibung | Standard |
|-----------|-------------|---------|
| `encode` | Ob die Antwort base64 kodiert werden soll | `false` |
| `task` | Auszuführende Aufgabe (`transcribe` oder `translate`) | `transcribe` |
| `language` | Sprachcode (z.B. `en`, `fr`) | Auto-detect |
| `initial_prompt` | Optionale Eingabeaufforderung zur Anleitung der Transkription | Keine |
| `vad_filter` | Filter für Sprachaktivitätserkennung | `false` |
| `word_timestamps` | Zeitstempel für jedes Wort einbeziehen | `false` |

## Konfiguration

Der Whisper-Dienst wird in der Datei `docker-compose.yml` mit den folgenden Optionen konfiguriert:

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

### Umgebungsvariablen

| Variable | Beschreibung | Standard |
|----------|-------------|---------|
| `ASR_MODEL` | Größe des Flüstermodells (tiny, base, small, medium, large) | `small` |
| `ASR_ENGINE` | Spracherkennungs-Engine | `openai_whisper` |
| `INTERVAL` | Prüfintervall der Protokolldatei in Sekunden | `5` |

## Ändern der Modellgröße

Die Standardkonfiguration verwendet das Modell `medium`, das ein gutes Gleichgewicht zwischen Genauigkeit und Ressourcenverbrauch bietet. Sie können die Modellgröße ändern, indem Sie die Umgebungsvariable `ASR_MODEL` aktualisieren:

```yaml
environment:
  - ASR_MODEL=large
```

Verfügbare Modellgrößen:
- Winzig": Schnellste, niedrigste Genauigkeit (~1GB VRAM)
- Basis": Schnell mit angemessener Genauigkeit (~1GB VRAM)
- Klein": Ausgewogene Geschwindigkeit/Genauigkeit (~2GB VRAM)
- Mittel": Gute Genauigkeit (~5GB VRAM)
- `groß`: Beste Genauigkeit (~10GB VRAM)

## Leistungsüberwachung

Die Leistung von Whisper kann über den Log Viewer und allgemeine Systemmetriken überwacht werden. Der Dienst kann bei der Transkription von Audiodaten erhebliche GPU-Ressourcen beanspruchen, daher sollten Sie die GPU-Nutzung mit überwachen:

```bash
nvidia-smi
```

## Integration mit Flowise

Sie können Whisper in Flowise-Workflows integrieren, indem Sie den HTTP-Request-Knoten verwenden, um die Whisper-API aufzurufen. Dies ermöglicht Ihnen die Verarbeitung von Audio-Eingaben als Teil Ihrer Konversationsabläufe.

## Fehlersuche

### Dienst startet nicht

Wenn der Whisper-Dienst nicht startet:

1. Prüfen Sie, ob Sie genügend GPU-Speicher zur Verfügung haben
2. Überprüfen Sie, ob die NVIDIA-Laufzeitumgebung richtig für Docker konfiguriert ist.
3. Versuchen Sie, ein kleineres Modell zu verwenden, indem Sie die Umgebungsvariable "ASR_MODEL" ändern.

### Schlechte Transkriptionsqualität

Wenn die Transkriptionsqualität schlecht ist:

1. Versuchen Sie, ein größeres Modell zu verwenden (z. B. `ASR_MODEL=large`)
2. Stellen Sie sicher, dass die Audioeingabe eine gute Qualität und minimale Hintergrundgeräusche aufweist.
3. Verwenden Sie den Parameter `initial_prompt`, um einen Kontext für die domänenspezifische Terminologie zu schaffen.

### Logs anzeigen

So zeigen Sie die Protokolle des Whisper-Dienstes an:

```bash
docker logs whisper
```

Oder verwenden Sie den Protokoll-Viewer im Dokumentationsportal.

## Beispiel Integration

Hier ist ein Beispiel für die Integration von Whisper mit einem Bash-Skript:

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