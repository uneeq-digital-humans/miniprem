# FastWhisper GPU Speech-to-Text Setup (Ubuntu 24.04)

Diese Anleitung erklärt, wie man [faster-whisper](https://github.com/SYSTRAN/faster-whisper) für schnelle, genaue, GPU-beschleunigte Sprache-zu-Text auf Ubuntu 24.04 mit einer modernen NVIDIA-GPU einrichtet und verwendet.

---

## 1. Virtuelle Python-Umgebung

```bash
python3 -m venv ~/.venvs/voiceinput
source ~/.venvs/voiceinput/bin/activate
```

---

## 2. Installieren Sie PyTorch und faster-whisper (CUDA 12)

```bash
pip install torch --extra-index-url https://download.pytorch.org/whl/cu121
pip install faster-whisper
```

---

## 3. Audio-Abhängigkeiten installieren

```bash
pip install pyaudio webrtcvad
sudo apt install portaudio19-dev python3-pyaudio
```

---

## 4. Installieren Sie cuDNN für CUDA 12 (Ubuntu 24.04)

1. Laden Sie die cuDNN .deb von der NVIDIA-Website für Ubuntu 24.04 herunter.
2. Installieren Sie mit:
   ```bash
   wget https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
   sudo apt-get update
   sudo apt-get -y install cudnn cudnn-cuda-12
   ```
3. Überprüfen:
   ```bash
   ls /usr/lib/x86_64-linux-gnu/libcudnn*
   ```

---

## 5. PyTorch GPU-Zugriff testen

```bash
source ~/.venvs/voiceinput/bin/activate
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.__version__)"
```
Sollte `True` und eine Versionsnummer ausgeben.

---

## 6. Beispiel für die Skriptverwendung

- Verwenden Sie das mitgelieferte Skript `voice_input.sh` für Sprache-zu-Text mit einem Tastaturkürzel.
- Vergewissern Sie sich, dass das Skript das venv am Anfang aktiviert:
  ```bash
  source ~/.venvs/voiceinput/bin/activate
  ```
- Das Skript verwendet PyAudio und webrtcvad für die Aufnahme und faster-whisper für die GPU-Transkription.

---

## 7. Einrichtung von Tastaturkürzeln (GNOME-Beispiel)

1. Öffnen Sie Einstellungen → Tastatur → Tastaturkürzel.
2. Fügen Sie eine benutzerdefinierte Tastenkombination hinzu:
   - **Name:** Spracheingabe
   - **Befehl:** `/home/tyler/voice_input.sh &`
   - **Kurzbefehl:** Alt + /

---

## 8. Fehlersuche

- **Fehlende Module:** Installieren Sie in Ihrem Venv mit `pip install ...`.
- **cuDNN-Fehler:** Stellen Sie sicher, dass cuDNN für Ihre CUDA-Version installiert ist.
- **ALSA/JACK-Warnungen:** Normalerweise sicher zu ignorieren, wenn Audio funktioniert.
- **Kein Audio:** Überprüfen Sie die Mikrofonberechtigungen und die Geräteauswahl.
- **Um auf einer CPU zu testen:** Ändern Sie im Skript `device='cuda'` in `device='cpu'`.

---

## 9. Docker Compose-Integration

*Bald verfügbar: Anweisungen für die Verwendung von FastWhisper in Docker Compose als Teil dieses Projekts.*

---

## 10. Beste Praktiken

- Verwenden Sie für alle Python-Abhängigkeiten ein eigenes venv.
- Halten Sie Ihre NVIDIA-Treiber und Ihr CUDA-Toolkit auf dem neuesten Stand.
- Verwenden Sie das Modell `large-v3` für beste Genauigkeit, wenn Sie genügend GPU-Speicher haben (z.B. 48GB+).
- Überprüfen Sie `/tmp/voice_input.log` auf Skriptprotokolle und Fehler.

---

Für Fragen oder Hilfe wenden Sie sich bitte an die Projektbetreuer.