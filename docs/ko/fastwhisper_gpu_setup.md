# FastWhisper GPU 음성-텍스트 변환 설정(Ubuntu 24.04)

이 가이드는 최신 NVIDIA GPU가 탑재된 우분투 24.04에서 빠르고 정확한 GPU 가속 음성-텍스트 변환을 위한 [faster-whisper](https://github.com/SYSTRAN/faster-whisper)를 설정하고 사용하는 방법을 설명합니다.

---

## 1. Python 가상 환경

```bash
python3 -m venv ~/.venvs/voiceinput
source ~/.venvs/voiceinput/bin/activate
```

---

## 2. PyTorch 및 빠른 위스퍼 설치(CUDA 12)

```bash
pip install torch --extra-index-url https://download.pytorch.org/whl/cu121
pip install faster-whisper
```

---

## 3. 오디오 종속성 설치

```bash
pip install pyaudio webrtcvad
sudo apt install portaudio19-dev python3-pyaudio
```

---

## 4. CUDA 12(우분투 24.04)용 cuDNN 설치

1. NVIDIA 웹사이트에서 우분투 24.04용 cuDNN .deb를 다운로드합니다.
2. 설치합니다:
   ```bash
   wget https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
   sudo apt-get update
   sudo apt-get -y install cudnn cudnn-cuda-12
   ```
3. 3. 확인합니다:
   ```bash
   ls /usr/lib/x86_64-linux-gnu/libcudnn*
   ```

---

## 5. PyTorch GPU 액세스 테스트

```bash
source ~/.venvs/voiceinput/bin/activate
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.__version__)"
```
True`와 버전 번호를 인쇄해야 합니다.

---

## 6. 스크립트 사용 예

- 키보드 단축키를 사용하여 제공된 `voice_input.sh` 스크립트를 음성-텍스트 변환에 사용하세요.
- 스크립트가 상단의 venv를 활성화하는지 확인하세요:
  ```bash
  source ~/.venvs/voiceinput/bin/activate
  ```
- 이 스크립트는 녹음을 위해 PyAudio와 webrtcvad를 사용하고, GPU 트랜스크립션에는 빠른 속삭임(fast-whisper)을 사용합니다.

---

## 7. 키보드 단축키 설정(GNOME 예제)

1. 설정 → 키보드 → 키보드 단축키를 엽니다.
2. 사용자 지정 바로가기를 추가합니다:
   - **이름:** 음성 입력
   - **명령:** `/home/tyler/voice_input.sh &`
   - **바로 가기:** Alt + /

---

## 8. 문제 해결

- **누락된 모듈:** `pip install ...`로 venv에 설치합니다.
- **cuDNN 오류:** CUDA 버전에 맞는 cuDNN이 설치되어 있는지 확인합니다.
- **ALSA/JACK 경고:** 일반적으로 오디오가 작동하면 무시해도 안전합니다.
- **오디오 없음:** 마이크 권한 및 장치 선택을 확인하세요.
- CPU에서 테스트하려면:** 스크립트에서 `device='cuda'`를 `device='cpu'`로 변경하세요.

---

## 9. 도커 컴포즈 통합

*곧 제공 예정: 이 프로젝트의 일부로 Docker Compose에서 FastWhisper를 사용하기 위한 지침*.

---

## 10. 모범 사례

- 모든 Python 종속성에 전용 가상 머신을 사용하세요.
- NVIDIA 드라이버와 CUDA 툴킷을 최신 상태로 유지하세요.
- GPU 메모리가 충분한 경우(예: 48GB 이상) 최상의 정확도를 위해 `large-v3` 모델을 사용하세요.
- tmp/voice_input.log`에서 스크립트 로그와 오류를 확인하세요.

---

질문이나 도움이 필요하면 프로젝트 관리자에게 문의하세요.