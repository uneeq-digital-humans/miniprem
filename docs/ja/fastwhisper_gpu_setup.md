# FastWhisper GPU音声テキスト変換セットアップ (Ubuntu 24.04)

このガイドでは、Ubuntu 24.04の最新のNVIDIA GPUを使用して、高速で正確なGPUアクセラレーション音声テキスト変換を実現するために、[faster-whisper](https://github.com/SYSTRAN/faster-whisper)をセットアップして使用する方法を説明します。

---

## 1. Python仮想環境

```bash
python3 -m venv ~/.venvs/voiceinput
source ~/.venvs/voiceinput/bin/activate
```

---

## 2. PyTorchとfaster-whisperのインストール (CUDA 12)

```bash
pip install torch --extra-index-url https://download.pytorch.org/whl/cu121
pip install faster-whisper
```

---

## 3. 音声依存関係のインストール

```bash
pip install pyaudio webrtcvad
sudo apt install portaudio19-dev python3-pyaudio
```

---

## 4. CUDA 12用のcuDNNのインストール (Ubuntu 24.04)

1. NVIDIAのウェブサイトからUbuntu 24.04用のcuDNN .debをダウンロードします。
2. 以下のコマンドでインストールします。
   ```bash
   wget https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
   sudo cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
   sudo apt-get update
   sudo apt-get -y install cudnn cudnn-cuda-12
   ```
3. 検証:
   ```bash
   ls /usr/lib/x86_64-linux-gnu/libcudnn*
   ```

---

## 5. PyTorch GPUアクセスのテスト

```bash
source ~/.venvs/voiceinput/bin/activate
python3 -c "import torch; print(torch.cuda.is_available()); print(torch.__version__)"
```
`True`とバージョン番号が表示されるはずです。

---

## 6. スクリプトの使用例

- 提供されている`voice_input.sh`スクリプトを使用して、キーボードショートカットで音声テキスト変換を行います。
- スクリプトが仮想環境をアクティブにすることを確認します。
  ```bash
  source ~/.venvs/voiceinput/bin/activate
  ```
- スクリプトはPyAudioとwebrtcvadを使用して録音し、faster-whisperを使用してGPUでテキスト変換を行います。

---

## 7. キーボードショートカットの設定 (GNOME例)

1. 設定 → キーボード → キーボードショートカットを開きます。
2. カスタムショートカットを追加します。
   - **名前:** 音声入力
   - **コマンド:** `/home/tyler/voice_input.sh &`
   - **ショートカット:** Alt + /

---

## 8. トラブルシューティング

- **モジュールが見つからない:** 仮想環境で`pip install ...`を使用してインストールします。
- **cuDNNエラー:** CUDAバージョン用のcuDNNがインストールされていることを確認します。
- **ALSA/JACK警告:** 音声が正常に機能する場合、通常は無視しても安全です。
- **音声が聞こえない:** マイクの権限とデバイスの選択を確認します。
- **CPUでテストする:** スクリプト内の`device='cuda'`を`device='cpu'`に変更します。

---

## 9. Docker Compose統合

*近日公開: このプロジェクトの一部として、FastWhisperをDocker Composeで使用するための手順。*

---

## 10. ベストプラクティス

- すべてのPython依存関係に専用の仮想環境を使用します。
- NVIDIAドライバーとCUDAツールキットを最新の状態に保ちます。
- GPUメモリが十分にある場合（例えば48GB以上）、最高の精度を得るために`large-v3`モデルを使用します。
- スクリプトのログとエラーについては、`/tmp/voice_input.log`を確認します。

---

質問やヘルプが必要な場合は、プロジェクトのメンテナーを連絡してください。