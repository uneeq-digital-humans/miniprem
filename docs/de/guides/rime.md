# RIME AI Integration

RIME AI bietet hochwertige Text-to-Speech (TTS) Dienste für MiniPrem. Dieser Leitfaden behandelt die Einrichtung, die Verwendung der API und Beispielanfragen.

## Einrichtung

1. **RIME Bilder von quay.io ziehen:**
   ```bash
   docker login -u="rimelabs+uneeq" -p="TOKEN GOES HERE" quay.io
   docker pull quay.io/rimelabs/api:v0.0.2-20250407
   docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403
   ```
2. **Start der Dienste mit Docker Compose:**
   RIME API und Model Container sind in der **Full Install** Option des Installers enthalten (unter Verwendung von modularen Docker Compose Dateien).

3. **API Schlüssel:**
   Beziehen Sie Ihren RIME API Schlüssel aus dem RIME Dashboard. Alle Anfragen benötigen diesen Schlüssel im `Authorization` Header.

## API Verwendung

Die RIME API lauscht auf `http://localhost:8100`.

### Beispiel: JSON-Antwort
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

### Beispiel: MP3-Antwort
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

### Beispiel: PCM-Antwort
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

## Anmerkungen
- Erlauben Sie ausgehenden Netzwerkverkehr zu `http://optimize.rime.ai/usage` und `http://optimize.rime.ai/license` zur Lizenzierung und Nutzungsüberprüfung.
- Rechnen Sie mit bis zu 5 Minuten Aufwärmzeit nach dem Start der Container, bevor Sie Anfragen senden.
- Alle Stimmen/Modelle sind standardmäßig verfügbar.