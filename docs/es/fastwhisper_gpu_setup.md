# Configuración de FastWhisper GPU para Voz a Texto (Ubuntu 24.04)

Esta guía explica cómo configurar y usar [faster-whisper](https://github.com/SYSTRAN/faster-whisper) para una conversión rápida y precisa de voz a texto con aceleración por GPU en Ubuntu 24.04 con una GPU NVIDIA moderna.

---

## 1. Entorno Virtual de Python

```bash
python3 -m venv ~/.venvs/voiceinput
source ~/.venvs/voiceinput/bin/activate
```

---

## 2. Instalar PyTorch y faster-whisper (CUDA 12)

```bash
pip install torch --extra-index-url https://download.pytorch.org/whl/cu121
pip install faster-whisper
```

---

## 3. Instalar Dependencias de Audio

```bash
pip install pyaudio webrtcvad
sudo apt install portaudio19-dev python3-pyaudio
```

---

## 4. Instalar cuDNN para CUDA 12 (Ubuntu 24.04)

1. Descarga el archivo .deb de cuDNN del sitio web de NVIDIA para Ubuntu 24.04.
2. Instala con:
   ```bash
   wget https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
   sudo apt-get update
   sudo apt-get -y install cudnn cudnn-cuda-12
   ```
3. Verifica:
   ```bash
   ls /usr/lib/x86_64-linux-gnu/libcudnn*
   ```

---

## 5. Probar el Acceso a GPU de PyTorch

```bash
source ~/.venvs/voiceinput/bin/activate
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.__version__)"
```
Debería imprimir `True` y un número de versión.

---

## 6. Uso del Script de Ejemplo

- Usa el script `voice_input.sh` proporcionado para la conversión de voz a texto con un atajo de teclado.
- Asegúrate de que el script active el venv al inicio:
  ```bash
  source ~/.venvs/voiceinput/bin/activate
  ```
- El script usa PyAudio y webrtcvad para la grabación, y faster-whisper para la transcripción con GPU.

---

## 7. Configuración de Atajo de Teclado (Ejemplo GNOME)

1. Abre Configuración → Teclado → Atajos de Teclado.
2. Agrega un atajo personalizado:
   - **Nombre:** Entrada de voz
   - **Comando:** `/home/tyler/voice_input.sh &`
   - **Atajo:** Alt + /

---

## 8. Solución de Problemas

- **Módulos faltantes:** Instala en tu venv con `pip install ...`.
- **Errores de cuDNN:** Asegúrate de que cuDNN esté instalado para tu versión de CUDA.
- **Advertencias de ALSA/JACK:** Generalmente se pueden ignorar si el audio funciona.
- **Sin audio:** Verifica los permisos del micrófono y la selección del dispositivo.
- **Para probar en CPU:** Cambia `device='cuda'` a `device='cpu'` en el script.

---

## 9. Integración con Docker Compose

*Próximamente: Instrucciones para usar FastWhisper en Docker Compose como parte de este proyecto.*

---

## 10. Mejores Prácticas

- Usa un venv dedicado para todas las dependencias de Python.
- Mantén tus controladores NVIDIA y el kit de herramientas CUDA actualizados.
- Usa el modelo `large-v3` para la mejor precisión si tienes suficiente memoria GPU (ej., 48GB+).
- Revisa `/tmp/voice_input.log` para ver los registros y errores del script.

---

Para preguntas o ayuda, contacta a los mantenedores del proyecto. 