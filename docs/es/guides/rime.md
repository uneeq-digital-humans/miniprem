# Integración de RIME AI

RIME AI proporciona servicios de texto a voz (TTS) de alta calidad para MiniPrem. Esta guía cubre la configuración, uso de la API y ejemplos de solicitudes.

## Configuración

1. **Extraer imágenes de RIME desde quay.io:**
   ```bash
   docker login -u="rimelabs+uneeq" -p="TOKEN GOES HERE" quay.io
   docker pull quay.io/rimelabs/api:v0.0.2-20250407
   docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403
   ```
2. **Iniciar servicios con Docker Compose:**
   Los contenedores de la API de RIME y los modelos están incluidos en la opción de **Instalación Completa** del instalador (usando archivos modulares de Docker Compose).

3. **Clave de API:**
   Obtén tu clave de API de RIME desde el panel de control de RIME. Todas las solicitudes requieren esta clave en el encabezado `Authorization`.

## Uso de la API

La API de RIME escucha en `http://localhost:8100`.

### Ejemplo: Respuesta JSON
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

### Ejemplo: Respuesta MP3
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

### Ejemplo: Respuesta PCM
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

## Notas
- Permite el tráfico de red saliente a `http://optimize.rime.ai/usage` y `http://optimize.rime.ai/license` para la verificación de licencias y uso.
- Espera hasta 5 minutos de calentamiento después de iniciar los contenedores antes de enviar solicitudes.
- Todas las voces/modelos están disponibles por defecto. 