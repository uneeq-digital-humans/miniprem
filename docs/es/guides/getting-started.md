# Primeros Pasos

Esta guía te ayudará a instalar y configurar la plataforma MiniPrem en tu sistema.

## Requisitos Previos

Antes de comenzar, asegúrate de tener lo siguiente:

- **Requisitos de Hardware**:
  - GPU NVIDIA con al menos 8GB de VRAM (se recomiendan 16GB+)
  - 16GB+ de RAM
  - 128GB+ de espacio libre en disco

- **Requisitos de Software**:
  - Ubuntu 24.04 LTS o más reciente
  - Controladores NVIDIA (versión mínima 550.xx)
  - Docker y Docker Compose
  - NVIDIA Container Toolkit

## Instalación

### 1. Clonar el Repositorio

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### 2. Ejecutar el Script de Instalación

```bash
./install_miniprem.sh
```

El instalador te pedirá que selecciones entre una **Instalación Predeterminada** (solo Renny + Audio2Face) o una **Instalación Completa** (todos los servicios: Renny, Audio2Face, Flowise, vLLM, Grafana, Prometheus, RIME, etc.).
Puedes volver a ejecutar el instalador en cualquier momento para actualizar de Predeterminada a Completa, o para cambiar tu selección.

### 3. Valores de Configuración

Necesitarás la siguiente información durante la instalación:

| Configuración | Descripción | Ejemplo |
|-----------------------|---------------------------------------------|----------------------------------------------|
| Dirección de UneeQ | Dirección del servicio de señalización UneeQ| api.uneeq.io |
| Clave API de UneeQ | Clave API para la plataforma UneeQ | tu_clave_api_uneeq_aquí |
| ID de Inquilino | Tu identificador de inquilino UneeQ | tu_id_inquilino_aquí |
| Región de Azure | Región de Azure para servicios de voz | tu_región_azure |
| Clave de Azure Speech | Clave API del servicio de voz de Azure | tu_clave_azure_speech_aquí |
| Imagen de Renny | Imagen Docker para el humano digital Renny | facemeproduction/renny:latest |
| Clave API de RIME | Imagen Docker para texto a voz de RIME | tu_clave_api_rime |
| Token de Huggingface | Token para acceso a Huggingface | tu_token_huggingface |
| Token Docker Hub de UneeQ | Token para acceso al repositorio de imágenes de UneeQ | tu_token_acceso_personal |

### 4. Verificar la Instalación

Después de completar la instalación, verifica que todos los servicios estén funcionando:

```bash
./miniprem.sh status
```

Deberías ver todos los contenedores en ejecución y saludables.

## Gestión de la Plataforma

### Iniciar Servicios

```bash
./miniprem.sh start
```

### Detener Servicios

```bash
./miniprem.sh stop
```

### Ver Registros

```bash
./miniprem.sh logs
```

También puedes ver los registros de un servicio específico:

```bash
./miniprem.sh logs renny
./miniprem.sh logs flowise
./miniprem.sh logs vllm
```

### Reiniciar Servicios

```bash
./miniprem.sh restart
```

## Siguientes Pasos

Una vez que tu plataforma MiniPrem esté instalada y funcionando, procede a:

1. [Configurar Flowise](flowise.md) para establecer tus flujos de conversación
2. [Monitorear el Rendimiento](monitoring.md) usando los paneles de Grafana
3. [Personalizar Renny](renny.md) para tu caso de uso específico