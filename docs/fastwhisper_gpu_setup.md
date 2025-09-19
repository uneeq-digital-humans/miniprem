# FastWhisper GPU Speech-to-Text Setup (Ubuntu 24.04)

This guide explains how to set up and use [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for fast, accurate, GPU-accelerated speech-to-text on Ubuntu 24.04 with a modern NVIDIA GPU.

---

## 1. Python Virtual Environment

```bash
python3 -m venv ~/.venvs/voiceinput
source ~/.venvs/voiceinput/bin/activate
```

---

## 2. Install PyTorch and faster-whisper (CUDA 12)

```bash
pip install torch --extra-index-url https://download.pytorch.org/whl/cu121
pip install faster-whisper
```

---

## 3. Install Audio Dependencies

```bash
pip install pyaudio webrtcvad
sudo apt install portaudio19-dev python3-pyaudio
```

---

## 4. Install cuDNN for CUDA 12 (Ubuntu 24.04)

1. Download the cuDNN .deb from NVIDIA's website for Ubuntu 24.04.
2. Install with:
   ```bash
   wget https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
   sudo apt-get update
   sudo apt-get -y install cudnn cudnn-cuda-12
   ```
3. Verify:
   ```bash
   ls /usr/lib/x86_64-linux-gnu/libcudnn*
   ```

---

## 5. Test PyTorch GPU Access

```bash
source ~/.venvs/voiceinput/bin/activate
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.__version__)"
```
Should print `True` and a version number.

---

## 6. Example Script Usage

- Use the provided `voice_input.sh` script for speech-to-text with a keyboard shortcut.
- Make sure the script activates the venv at the top:
  ```bash
  source ~/.venvs/voiceinput/bin/activate
  ```
- The script uses PyAudio and webrtcvad for recording, and faster-whisper for GPU transcription.

---

## 7. Keyboard Shortcut Setup (GNOME Example)

1. Open Settings → Keyboard → Keyboard Shortcuts.
2. Add a custom shortcut:
   - **Name:** Voice input
   - **Command:** `/home/tyler/voice_input.sh &`
   - **Shortcut:** Alt + /

---

## 8. Troubleshooting

- **Missing modules:** Install in your venv with `pip install ...`.
- **cuDNN errors:** Ensure cuDNN is installed for your CUDA version.
- **ALSA/JACK warnings:** Usually safe to ignore if audio works.
- **No audio:** Check microphone permissions and device selection.
- **To test on CPU:** Change `device='cuda'` to `device='cpu'` in the script.

---

## 9. Docker Compose Integration

*Coming soon: Instructions for using FastWhisper in Docker Compose as part of this project.*

---

## 10. Best Practices

- Use a dedicated venv for all Python dependencies.
- Keep your NVIDIA drivers and CUDA toolkit up to date.
- Use the `large-v3` model for best accuracy if you have enough GPU memory (e.g., 48GB+).
- Check `/tmp/voice_input.log` for script logs and errors.

---

For questions or help, contact the project maintainers. 