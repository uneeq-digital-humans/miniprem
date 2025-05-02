# Integración de Fast Whisper

MiniPrem integra faster-whisper, una implementación optimizada del modelo de reconocimiento de voz Whisper de OpenAI para capacidades de transcripción en tiempo real precisas. Esta guía explica cómo usar y configurar el servicio Fast Whisper dentro de la plataforma MiniPrem.

## Descripción general

Fast Whisper proporciona reconocimiento automático de voz (ASR) con un rendimiento mejorado sobre la implementación original de Whisper:

- Transcripción de voz en tiempo real a través de WebSocket
- API REST para transcripción basada en archivos
- Reconocimiento de voz multilingüe
- Aceleración GPU para un procesamiento más rápido
- Interfaz de prueba en modo oscuro

## Interfaz web

Fast Whisper incluye una interfaz de prueba basada en navegador accesible en:

```
http://localhost:9000/static/index.html
```

Esta interfaz te permite:
- Probar la entrada del micrófono en tiempo real
- Ver resultados de transcripción mientras hablas
- Borrar el historial de transcripción
- Monitorear el estado de la conexión

## Uso de la API

### URL base

La API de Fast Whisper está disponible en:

```
http://localhost:9000
```

### Transcripción en tiempo real WebSocket

Para el reconocimiento de voz en tiempo real, conéctate al punto final WebSocket:

```
ws://localhost:9000/ws
```

Envía datos de audio como fragmentos codificados en base64 en este formato:
```json
{
  \"type\": \"audio\",
  \"data\": \"<datos-de-audio-codificados-en-base64>\"
}
```

Recibe transcripciones a medida que estén disponibles:
```json
{
  \"type\": \"transcription\",
  \"text\": \"El texto transcrito aparecerá aquí.\",
  \"language\": \"es\"
}
```

### API de transcripción de archivos

Puedes transcribir un archivo de audio enviando una solicitud POST:

```bash
curl -X 'POST' \\
  'http://localhost:9000/transcribe' \\
  -H 'accept: application/json' \\
  -H 'Content-Type: multipart/form-data' \\
  -F 'file=@tu-archivo-de-audio.wav' \\
  -F 'language=es'
```

## Configuración

El servicio Fast Whisper se configura en el archivo `docker-compose.yml` con las siguientes opciones:

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

## Solución de problemas

### Problemas de conexión WebSocket

Si ves errores de conexión WebSocket en la interfaz:

1. Verifica si el servicio Fast Whisper está en ejecución: `docker ps | grep fastwhisper`
2. Reinicia el servicio: `docker restart fastwhisper`
3. Revisa los registros para ver errores: `docker logs fastwhisper`
4. Verifica que tu navegador sea compatible con WebSockets

### El servicio no se inicia

Si el servicio Fast Whisper no se inicia:

1. Comprueba si tienes suficiente memoria GPU disponible
2. Verifica que el runtime de NVIDIA esté configurado correctamente para Docker
3. Intenta usar un modelo más pequeño cambiando la variable de entorno `MODEL_SIZE`