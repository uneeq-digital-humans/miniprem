# Renny Digital Human

This guide covers the Renny digital human component of the MiniPrem platform, which provides the visual interface for human-like interactions.

## Overview

Renny is a digital human avatar powered by UneeQ's technology that provides a visual interface for AI interactions. It features an advanced internal speech processing system that handles facial animations, lip synchronization, and gesture capabilities to create a more engaging conversational experience with improved reliability and performance.

## Accessing Renny

- **Health Endpoint**: http://localhost:8081/health
- **Container Name**: `renny`

## Architecture

The Renny component interacts with several other services:

1. **Internal Speech Processing**: Built-in system converts audio to facial animations
2. **UneeQ Platform**: Manages the digital human rendering
3. **Azure Speech Services**: Optional fallback for text-to-speech capabilities

## Configuration

### Main Configuration File

The primary configuration for Renny is stored in `docker/configuration.dat`, which includes:

- **Server**: The UneeQ server endpoint
- **TenantId**: Your UneeQ tenant identifier
- **JWSSecret**: Authentication token for UneeQ services

### Environment Variables

Key environment variables in `docker/docker-compose.env`:

- **NEW_SPEECH_OVERRIDE**: Enable internal speech processing (set to 1)
- **DHOP_ADDRESS**: UneeQ platform address
- **DHOP_APIKEY**: UneeQ platform API key
- **DHOP_TENANTID**: UneeQ tenant ID
- **AZURE_REGION**: Azure region for speech services (optional fallback)
- **AZURE_SPEECH**: Azure speech service key (optional fallback)

## Health Monitoring

You can check Renny's health status using:

```bash
curl -f http://localhost:8081/health
```

This endpoint returns information about the service's current state and connections to dependent services.

## Network Configuration

Renny uses host networking mode to ensure optimal performance:

```yaml
network_mode: "host"
```

This allows Renny to directly access system network interfaces without Docker network isolation.

## GPU Acceleration

Renny leverages NVIDIA GPU acceleration for rendering:

```yaml
runtime: nvidia
```

This ensures smooth animation and facial expressions.

## Integration with LLM

The integration between Renny and the LLM (via Flowise) works as follows:

1. User input is captured (text or audio)
2. The input is processed by the Flowise/vLLM pipeline
3. The response is converted to speech via Renny's internal speech system
4. Internal speech processing generates facial animations synchronized with the speech
5. Renny renders the animated avatar speaking the response with improved reliability

## Advanced Customization

### Rendering Options

Renny supports various rendering configurations via command line parameters:

```
-RenderOffScreen  # Headless rendering
-ResX=1920        # Horizontal resolution
-ResY=1080        # Vertical resolution
```

For graphical display (rather than headless), you can modify the Docker configuration:

```yaml
# Uncomment for visual rendering
environment:
  - DISPLAY=$DISPLAY
volumes:
  - /tmp/.X11-unix:/tmp/.X11-unix
  - ~/.Xauthority:/home/ue4/.Xauthority
```

### Speech Processing Settings

Internal speech processing parameters can be controlled via environment variables:

- **NEW_SPEECH_OVERRIDE**: Primary switch for internal speech system (set to 1)
- **Lip Synchronization**: Built-in mouth movement accuracy controls
- **Expression Intensity**: Automatic facial expression strength adjustment
- **Blinking Parameters**: Built-in eye blinking frequency and style

## Troubleshooting

### Common Issues

1. **No Visual Output**:
   - Check if `-RenderOffScreen` is enabled
   - Verify GPU drivers and rendering capabilities

2. **Poor Animation Quality**:
   - Check internal speech processing logs
   - Verify NEW_SPEECH_OVERRIDE is set to 1

3. **Connection Issues**:
   - Verify UneeQ platform connectivity
   - Check network settings and firewall rules

4. **Audio-Visual Sync Problems**:
   - Internal speech system handles sync automatically
   - Check system performance for rendering lags
   - Verify GPU resources are available