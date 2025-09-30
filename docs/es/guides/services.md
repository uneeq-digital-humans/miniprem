# Descripción General de los Servicios de MiniPrem

La plataforma MiniPrem consiste en varios servicios integrados que trabajan juntos para proporcionar una experiencia completa de humano digital. Esta guía proporciona una descripción general de estos servicios y cómo interactúan.

## Servicios Principales

| Servicio | Propósito | Puerto | Documentación |
|---------|---------|------|---------------|
| Renny | Avatar de humano digital | 8081 | [Guía de Renny](renny.md) |
| vLLM | Modelo de lenguaje grande | 8000 | [Guía de vLLM](vllm.md) |
| Flowise | Automatización de flujos de trabajo | 3000 | [Guía de Flowise](flowise.md) |
| Redis | Gestión de colas | 6379 | - |
| Prometheus | Recopilación de métricas | 9090 | [Guía de Monitoreo](monitoring.md) |
| Grafana | Visualización de métricas | 3001 | [Guía de Monitoreo](monitoring.md) |
| Audio2Face | Animación facial | 50000, 52000 | [Guía de Renny](renny.md) |
| RIME | API de texto a voz | 8100 | [Guía de RIME](rime.md) |
| Whisper | Reconocimiento de voz | 9000 | [Guía de Whisper](whisper.md) |

## Arquitectura de Servicios

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Renny    │◄────┤ Audio2Face  │     │   Flowise   │
│Humano Digital│     │ Animación  │     │ Flujo de   │
└──────┬──────┘     └──────┬──────┘     │ Trabajo    │
       │                   │             └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────┐
│                 Red Docker                          │
└─────────────┬─────────────┬─────────────┬───────────┘
              │             │             │
              ▼             ▼             ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │   vLLM      │ │    Redis    │ │ Prometheus  │
    │  Motor LLM  │ │    Cola     │ │  Métricas   │
    └─────────────┘ └─────────────┘ └──────┬──────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │   Grafana   │
                                    │  Paneles    │
                                    └─────────────┘
```

## Dependencias de Servicios

- **Renny** depende de:
  - Servicios de Audio2Face para animación facial
  - Servicios de Azure Speech para texto a voz (externo)
  - Plataforma UneeQ para renderizado de avatar (externo)

- **Flowise** depende de:
  - vLLM para capacidades de modelo de lenguaje
  - Redis para gestión de colas
  - SQLite para almacenamiento de base de datos (integrado)

- **Monitoreo** depende de:
  - Prometheus para recopilación de métricas
  - Grafana para visualización

## Variables de Entorno

Cada servicio se configura mediante variables de entorno en el archivo Docker Compose. Las variables de entorno clave incluyen:

- **Renny**:
  - `DHOP_ADDRESS`: Dirección de la plataforma UneeQ
  - `A2F_ADDRESS`: Dirección del servicio Audio2Face
  - `AZURE_REGION` y `AZURE_SPEECH`: Credenciales del servicio de voz

- **Flowise**:
  - `DATABASE_TYPE`: Establecido en SQLite para base de datos local
  - `FLOWISE_USERNAME` y `FLOWISE_PASSWORD`: Credenciales de autenticación
  - `REDIS_HOST` y `REDIS_PORT`: Detalles de conexión a Redis

- **vLLM**:
  - `NVIDIA_VISIBLE_DEVICES`: Asignación de GPU para inferencia del modelo

## Volúmenes

Los datos persistentes se almacenan en volúmenes Docker:

- **vllm_data**: Almacena modelos de lenguaje descargados
- **flowise_data**: Almacena configuraciones y base de datos de Flowise
- **redis_data**: Almacena datos de cola de Redis
- **prometheus_data**: Almacena historial de métricas
- **grafana_data**: Almacena configuraciones de paneles

## Configuración de Red

La mayoría de los servicios utilizan la red Docker predeterminada para la comunicación, con estas excepciones:

- **Renny** usa `network_mode: "host"` para un rendimiento óptimo
- Los servicios se referencian entre sí por nombre de contenedor (por ejemplo, `http://vllm:8000`) dentro de la red Docker

## Verificaciones de Salud de Servicios

Todos los servicios incluyen verificaciones de salud para asegurar que estén funcionando correctamente:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

Estas verificaciones de salud se utilizan para coordinar las dependencias de inicio de servicios.