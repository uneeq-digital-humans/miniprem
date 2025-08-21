시작하기 # 시작하기

이 가이드는 시스템에 MiniPrem 플랫폼을 설치하고 구성하는 데 도움이 됩니다.

## 전제 조건

시작하기 전에 다음이 준비되어 있는지 확인하세요:

- 하드웨어 요구 사항**:
  - 8GB 이상의 VRAM을 갖춘 NVIDIA GPU(16GB 이상 권장)
  - 16GB 이상의 RAM
  - 50GB 이상의 디스크 여유 공간

- 소프트웨어 요구 사항**:
  - 우분투 24.04 LTS 이상 버전
  - NVIDIA 드라이버(최소 버전 550.xx)
  - 도커 및 도커 컴포즈
  - NVIDIA 컨테이너 툴킷

## 설치

### 1. 리포지토리 복제

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### 2. 설치 스크립트 실행

```bash
./install_miniprem.sh
```

설치 프로그램에서 **기본 설치**(Renny + Audio2Face만 해당) 또는 **전체 설치**(모든 서비스) 중 하나를 선택하라는 메시지가 표시됩니다: Renny, 오디오2페이스, 플로우이즈, vLLM, 그라파나, 프로메테우스, RIME 등).
언제든지 설치 프로그램을 다시 실행하여 기본값에서 전체 설치로 업그레이드하거나 선택 사항을 변경할 수 있습니다.

### 3. 구성 값

설치하는 동안 다음 정보가 필요합니다:

Here's the complete Korean table with all the entries:

| 구성 | 설명 | 예제 |
|-----------------------|---------------------------------------------|----------------------------------------------|
| UneeQ 플랫폼 주소 | UneeQ 시그널링 서비스 주소 | api.enterprise.uneeq.io |
| UneeQ 플랫폼 API 키 | UneeQ 플랫폼용 API 키 | your_uneeq_api_key_here |
| 테넌트 ID | UneeQ 테넌트 식별자 | your_tenant_id_here |
| Azure 지역 | 음성 서비스용 Azure 지역 | your_azure_region |
| Azure 음성 키 | Azure 음성 서비스 API 키 | your_azure_speech_key_here |
| 렌니 이미지 | 렌니 디지털 휴먼용 도커 이미지 | facemeproduction/renny:latest |
| RIME API 키 | RIME 텍스트 음성 변환용 도커 이미지 | your_rime_api_key |
| Huggingface 토큰 | Huggingface 접근용 토큰 | your_huggingface_token |
| UneeQ Docker Hub 토큰 | UneeQ 이미지 저장소 접근용 토큰 | your_personal_access_token |

### 4. 설치 확인

설치가 완료되면 모든 서비스가 실행 중인지 확인합니다:

```bash
./miniprem.sh status
```

모든 컨테이너가 실행되고 정상적으로 작동하는 것을 확인해야 합니다.

## 플랫폼 관리하기

### 서비스 시작

```bash
./miniprem.sh start
```

### 서비스 중지

```bash
./miniprem.sh stop
```

### 로그 보기

```bash
./miniprem.sh logs
```

특정 서비스에 대한 로그를 볼 수도 있습니다:

```bash
./miniprem.sh logs renny
./miniprem.sh logs flowise
./miniprem.sh logs vllm
```

### 서비스 다시 시작

```bash
./miniprem.sh restart
```

## 다음 단계

MiniPrem 플랫폼이 실행되면 다음 단계를 진행합니다:

1. [Flowise](flowise.md)를 구성하여 대화 플로우를 설정합니다.
2. Grafana 대시보드를 사용하여 [성능 모니터링](monitoring.md)을 수행합니다.
3. 특정 사용 사례에 맞게 [Renny](renny.md) 사용자 지정하기