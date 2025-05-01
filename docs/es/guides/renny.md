# Renny Humano Digital

Esta guía cubre el componente Renny humano digital de la plataforma MiniPrem, que proporciona la interfaz visual para interacciones similares a las humanas.

## Descripción General

Renny es un avatar humano digital impulsado por la tecnología de UneeQ que proporciona una interfaz visual para interacciones de IA. Combina animaciones faciales, sincronización de labios y capacidades de gestos para crear una experiencia conversacional más atractiva.

## Acceso a Renny

- **Endpoint de Salud**: http://localhost:8081/health
- **Nombre del Contenedor**: `renny`

## Arquitectura

El componente Renny interactúa con varios otros servicios:

1. **Integración Audio2Face**: Convierte audio en animaciones faciales
2. **Plataforma UneeQ**: Gestiona el renderizado del humano digital
3. **Servicios de Voz de Azure**: Proporciona capacidades de texto a voz

## Configuración

### Archivo de Configuración Principal

La configuración principal para Renny se almacena en `docker/configuration.dat`, que incluye:

- **Servidor**: El endpoint del servidor UneeQ
- **TenantId**: Tu identificador de inquilino de UneeQ
- **JWSSecret**: Token de autenticación para los servicios de UneeQ

### Variables de Entorno

Variables de entorno clave en `docker/docker-compose.env`:

- **A2F_ADDRESS**: Dirección del servicio Audio2Face
- **DHOP_ADDRESS**: Dirección de la plataforma UneeQ
- **DHOP_APIKEY**: Clave API de la plataforma UneeQ
- **DHOP_TENANTID**: ID de inquilino de UneeQ
- **AZURE_REGION**: Región de Azure para servicios de voz
- **AZURE_SPEECH**: Clave del servicio de voz de Azure

## Monitoreo de Salud

Puedes verificar el estado de salud de Renny usando:

```bash
curl -f http://localhost:8081/health
```

Este endpoint devuelve información sobre el estado actual del servicio y las conexiones a los servicios dependientes.

## Configuración de Red

Renny usa el modo de red host para garantizar un rendimiento óptimo:

```yaml
network_mode: "host"
```

Esto permite que Renny acceda directamente a las interfaces de red del sistema sin aislamiento de red de Docker.

## Aceleración por GPU

Renny aprovecha la aceleración por GPU de NVIDIA para el renderizado:

```yaml
runtime: nvidia
```

Esto garantiza animaciones suaves y expresiones faciales fluidas.

## Integración con LLM

La integración entre Renny y el LLM (a través de Flowise) funciona de la siguiente manera:

1. Se captura la entrada del usuario (texto o audio)
2. La entrada es procesada por la canalización Flowise/vLLM
3. La respuesta se convierte a voz mediante TTS de Azure
4. Audio2Face genera animaciones faciales sincronizadas con el habla
5. Renny renderiza el avatar animado hablando la respuesta

## Personalización Avanzada

### Opciones de Renderizado

Renny admite varias configuraciones de renderizado a través de parámetros de línea de comandos:

```
-RenderOffScreen  # Renderizado sin pantalla
-ResX=1920        # Resolución horizontal
-ResY=1080        # Resolución vertical
```

Para visualización gráfica (en lugar de sin pantalla), puedes modificar la configuración de Docker:

```yaml
# Descomentar para renderizado visual
environment:
  - DISPLAY=$DISPLAY
volumes:
  - /tmp/.X11-unix:/tmp/.X11-unix
  - ~/.Xauthority:/home/ue4/.Xauthority
```

### Configuración de Animación

Los parámetros de animación de Audio2Face se pueden ajustar en los archivos de configuración de A2F:

- **Sincronización de Labios**: Controla la precisión del movimiento de la boca
- **Intensidad de la Expresión**: Ajusta la fuerza de las expresiones faciales
- **Parámetros de Parpadeo**: Controla la frecuencia y el estilo del parpadeo

## Solución de Problemas

### Problemas Comunes

1. **Sin Salida Visual**:
   - Verifica si `-RenderOffScreen` está habilitado
   - Comprueba los controladores de GPU y las capacidades de renderizado

2. **Calidad de Animación Pobre**:
   - Verifica la salud del servicio A2F
   - Comprueba la calidad del audio y el procesamiento

3. **Problemas de Conexión**:
   - Verifica la conectividad con la plataforma UneeQ
   - Comprueba la configuración de red y las reglas del firewall

4. **Problemas de Sincronización Audio-Visual**:
   - Ajusta el parámetro `A2F_AUDIO_DELAY_TIME_MS`
   - Comprueba el rendimiento del sistema para retrasos en el renderizado