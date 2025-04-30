# Fast Whisper Voice Input

A lightweight Docker-based solution for voice dictation using faster-whisper with GPU acceleration. Press a keyboard shortcut, speak, and your words will be transcribed directly where your cursor is.

## Prerequisites

- Docker
- NVIDIA GPU with CUDA support
- NVIDIA Container Toolkit
- `sox` package for audio recording:
  ```bash
  sudo apt-get install sox
  ```
- `xdotool` for text input:
  ```bash
  sudo apt-get install xdotool
  ```

## Setup

1. Clone this repository:
```bash
git clone https://github.com/yourusername/fast-whisper-docker.git
cd fast-whisper-docker
```

2. Make the script executable:
```bash
chmod +x voice_input.sh
```

3. Start the Docker container:
```bash
docker compose up -d
```

4. Set up a keyboard shortcut (Alt+/) to run:
```bash
/path/to/fast-whisper-docker/voice_input.sh
```

## Usage

1. Place your cursor where you want the text to appear
2. Press Alt+/ (or your configured shortcut)
3. Speak clearly
4. Stop speaking for about 1 second
5. Your speech will be transcribed directly where your cursor is

## How it Works

1. When triggered, the script:
   - Records audio using `sox` with silence detection
   - Sends the audio to the Docker container running faster-whisper
   - Uses `xdotool` to type the transcribed text at your cursor position

2. The container stays running in the background, so there's minimal startup delay between uses.

## Configuration

You can modify the following settings in `docker-compose.yml`:
- `MODEL_SIZE`: Whisper model size (default: "base")
- `COMPUTE_TYPE`: GPU compute type (default: "int8")
- `LANGUAGE`: Language code (default: "en")

## Files

- `voice_input.sh`: Main script that handles recording and transcription
- `Dockerfile`: Sets up the container with CUDA and faster-whisper
- `docker-compose.yml`: Configures the container with GPU and audio access
- `requirements.txt`: Python package dependencies

## Troubleshooting

- If transcription is cutting off the start of your speech, try speaking a moment after pressing the shortcut
- If text isn't appearing, ensure `xdotool` is installed and X11 forwarding is working
- If audio isn't being recorded, check that `sox` is installed and your microphone is working
- For GPU issues, verify your NVIDIA drivers and CUDA installation

## License

This project is licensed under the MIT License - see the LICENSE file for details. 