# Integración de Whisper

MiniPrem integra el modelo de reconocimiento de voz Whisper de OpenAI para capacidades de transcripción precisas. Esta guía explica cómo usar y configurar el servicio Whisper dentro de la plataforma MiniPrem.

## Descripción General

Whisper es un sistema de reconocimiento automático de voz (ASR) entrenado con 680,000 horas de datos supervisados multilingües y multitarea. Ofrece:

- Reconocimiento de voz multilingüe
- Detección de actividad de voz
- Identificación de idioma
- Puntuación y formato

En la plataforma MiniPrem, Whisper se implementa como un servicio API en contenedor que puede transcribir archivos o transmisiones de audio.

## Uso de la API

### Endpoint

La API de Whisper está disponible en:

```
http://localhost:9000
```

### Transcribir Archivo de Audio

Puedes transcribir un archivo de audio enviando una solicitud POST:

```bash
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@tu-archivo-audio.mp3;type=audio/mpeg' \
  -F 'encode=true'
```

### Parámetros de la API

| Parámetro | Descripción | Predeterminado |
|-----------|-------------|---------|
| `encode` | Si se debe codificar la respuesta en base64 | `false` |
| `task` | Tarea a realizar (`transcribe` o `translate`) | `transcribe` |
| `language` | Código de idioma (ej., `en`, `fr`) | Detección automática |
| `initial_prompt` | Prompt opcional para guiar la transcripción | Ninguno |
| `vad_filter` | Filtro de detección de actividad de voz | `false` |
| `word_timestamps` | Incluir marcas de tiempo para cada palabra | `false` |

## Configuración

El servicio Whisper se configura en el archivo `docker-compose.yml` con las siguientes opciones:

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

### Variables de Entorno

| Variable | Descripción | Predeterminado |
|----------|-------------|---------|
| `ASR_MODEL` | Tamaño del modelo Whisper (tiny, base, small, medium, large) | `small` |
| `ASR_ENGINE` | Motor de reconocimiento de voz | `openai_whisper` |
| `INTERVAL` | Intervalo de verificación de archivo de registro en segundos | `5` |

## Cambiar el Tamaño del Modelo

La configuración predeterminada usa el modelo `medium`, que ofrece un buen equilibrio entre precisión y uso de recursos. Puedes cambiar el tamaño del modelo actualizando la variable de entorno `ASR_MODEL`:

```yaml
environment:
  - ASR_MODEL=large
```

Tamaños de modelo disponibles:
- `tiny`: Más rápido, menor precisión (~1GB VRAM)
- `base`: Rápido con precisión razonable (~1GB VRAM)
- `small`: Equilibrio velocidad/precisión (~2GB VRAM)
- `medium`: Buena precisión (~5GB VRAM)
- `large`: Mejor precisión (~10GB VRAM)

## Monitoreo de Rendimiento

El rendimiento de Whisper se puede monitorear a través del visor de registros y métricas generales del sistema. El servicio puede usar recursos significativos de GPU al transcribir audio, así que monitorea el uso de tu GPU con:

```bash
nvidia-smi
```

## Integración con Flowise

Puedes integrar Whisper con flujos de trabajo de Flowise usando el nodo HTTP Request para llamar a la API de Whisper. Esto te permite procesar entradas de audio como parte de tus flujos de conversación.

## Solución de Problemas

### Servicio No Inicia

Si el servicio Whisper falla al iniciar:

1. Verifica si tienes suficiente memoria GPU disponible
2. Confirma que el runtime de NVIDIA esté configurado correctamente para Docker
3. Intenta usar un modelo más pequeño cambiando la variable de entorno `ASR_MODEL`

### Calidad de Transcripción Pobre

Si la calidad de la transcripción es pobre:

1. Intenta usar un modelo más grande (ej., `ASR_MODEL=large`)
2. Asegúrate de que la entrada de audio tenga buena calidad y ruido de fondo mínimo
3. Usa el parámetro `initial_prompt` para proporcionar contexto para terminología específica del dominio

### Ver Registros

Para ver los registros del servicio Whisper:

```bash
docker logs whisper
```

O usa el visor de registros en el portal de documentación.

## Ejemplo de Integración

Aquí hay un ejemplo de cómo integrar Whisper con un script bash:

```bash
#!/bin/bash

# Grabar audio (requiere ffmpeg)
ffmpeg -f alsa -i default -t 10 -acodec libmp3lame -ab 192k -ac 1 grabacion.mp3

# Transcribir con la API de Whisper
curl -X 'POST' \
  'http://localhost:9000/asr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'audio_file=@grabacion.mp3;type=audio/mpeg' \
  -F 'task=transcribe' \
  -F 'language=en'
```