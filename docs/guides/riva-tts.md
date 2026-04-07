<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# NVIDIA RIVA TTS Integration

> GPU-accelerated text-to-speech for MiniPrem using NVIDIA RIVA

</div>

## Table of Contents

- [Overview](#overview)
- [When to Use RIVA](#when-to-use-riva)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Configuration](#configuration)
- [Available Voices](#available-voices)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Copyright](#copyright)

## Overview

NVIDIA RIVA is a GPU-accelerated speech AI platform that provides low-latency text-to-speech (TTS) for MiniPrem deployments. MiniPrem supports RIVA as a TTS provider via gRPC on port **50051**.

RIVA is ideal for on-premises or air-gapped environments where cloud-based TTS providers are unavailable or where low-latency local inference is required.

## When to Use RIVA

| Scenario | Recommended Provider |
|----------|---------------------|
| On-premises / air-gapped deployment | **RIVA** |
| Low-latency local inference | **RIVA** |
| Multilingual support needed | **RIVA** or Azure |
| Avatar lip-sync required | Azure or ElevenLabs |
| Simplest cloud setup | Azure |
| Highest voice quality | ElevenLabs |
| Cost-effective local TTS | **RIVA** or RIME |

## Prerequisites

- NVIDIA GPU with CUDA support
- [NVIDIA proprietary drivers (version 580+)](nvidia-drivers.md)
- [NVIDIA Container Toolkit](nvidia-drivers.md#nvidia-container-toolkit) installed and configured
- Docker Engine on Ubuntu 24.04 LTS or newer
- NGC API key (from [NVIDIA NGC](https://ngc.nvidia.com/))
- Network access to RIVA gRPC endpoint (default port 50051)

!> **RIVA requires the NVIDIA Container Toolkit** — standard Docker alone is not sufficient. The container toolkit enables GPU access inside Docker containers.

## Setup

### 1. Authenticate with NGC Registry

```bash
docker login nvcr.io
# Username: $oauthtoken
# Password: <your NGC API key>
```

### 2. Pull the RIVA Container Image

```bash
docker pull nvcr.io/nvidia/riva/riva-speech:latest
```

### 3. Start RIVA with Docker Compose

Add the following to your Docker Compose configuration or use a dedicated RIVA compose file:

```yaml
services:
  riva:
    image: nvcr.io/nvidia/riva/riva-speech:latest
    ports:
      - "50051:50051"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    environment:
      - RIVA_API_KEY=${RIVA_API_KEY:-}
```

### 4. Verify RIVA is Running

```bash
docker logs riva
# Look for: "Riva server is ready"
```

?> **Warm-up time:** RIVA requires a few minutes of warm-up time after container startup before it can serve requests. Wait until the logs show "Riva server is ready" before testing.

## Configuration

### Environment Variables

Configure these environment variables for Renny to connect to RIVA:

| Variable | Description | Default |
|----------|-------------|---------|
| `RIVA_SERVER_ADDR` | RIVA gRPC server address | `localhost:50051` |
| `RIVA_API_KEY` | NGC API key for authentication (optional for self-hosted) | None |

Set these in your MiniPrem `.env` file or Docker Compose environment section:

```bash
RIVA_SERVER_ADDR=localhost:50051
RIVA_API_KEY=your-ngc-api-key
```

### Admin Portal Settings

Once RIVA is running, configure it in the UneeQ Admin Portal:

1. Log in to the Admin Portal
2. Navigate to your persona's **Voice** tab
3. Select **NVIDIA RIVA** as the TTS provider
4. Enter the voice name (e.g., `Magpie-Multilingual.EN-US.Leo`)
5. Optionally set the RIVA URL and API Key overrides
6. Save changes

## Available Voices

RIVA supports multiple voice models. Common voices include:

| Voice Name | Language | Gender |
|------------|----------|--------|
| `Magpie-Multilingual.EN-US.Leo` | English (US) | Male |
| `Magpie-Multilingual.EN-US.Emily` | English (US) | Female |
| `Magpie-Multilingual.EN-US.Aria` | English (US) | Female |

### List Voices from a Running Instance

Use `grpcurl` to query the RIVA gRPC endpoint (port 50051 serves gRPC, not HTTP REST):

```bash
grpcurl -plaintext localhost:50051 nvidia.riva.tts.RivaSpeechSynthesis/GetRivaSynthesisConfig
```

?> **Install grpcurl** if you don't have it: `go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest` or download from [GitHub releases](https://github.com/fullstorydev/grpcurl/releases). Alternatively, check RIVA's HTTP gateway port (if enabled) in your RIVA server configuration.

?> **Tip** Available voices depend on the models deployed in your RIVA instance. See the [NVIDIA RIVA TTS documentation](https://docs.nvidia.com/nim/riva/tts/latest/getting-started.html) for the complete list of supported voices and model downloads.

## Limitations

- **No word timing or viseme metadata** — RIVA is an audio-only provider. It does not return lip-sync timing data.
- **For avatar lip-sync**, Azure or ElevenLabs providers are recommended as they provide word boundary and viseme events.
- **GPU resources** — RIVA can run on the same GPU as Renny, but a dedicated GPU is recommended for production workloads.
- **Audio format** — Output is delivered at 48kHz 16-bit mono PCM to match Renny's renderer expectations. Adjust sample rate if needed (recommend 24000 Hz minimum).

?> **Future:** Audio2Face integration may provide lip-sync metadata for RIVA in future MiniPrem releases.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Connection refused on port 50051 | RIVA server not running | Check `docker logs riva` and ensure container is started |
| "Riva server is not ready" | Still warming up | Wait a few minutes after container startup |
| Audio quality issues | Sample rate mismatch | Adjust sample rate (recommend 24000 Hz) |
| GPU out of memory | Shared GPU resources | Dedicate a GPU to RIVA or reduce model size |
| Authentication failures | Invalid NGC API key | Verify `RIVA_API_KEY` environment variable |

For general troubleshooting, see the [MiniPrem Troubleshooting Guide](../troubleshooting.md).

---

## License

The MiniPrem documentation and installation scripts are open source under the MIT License - see the [LICENSE](../../LICENSE) file for details. Note: The Renny digital human application itself is commercially licensed by UneeQ and is not covered by this license.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
