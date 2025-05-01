# 레니 디지털 휴먼

이 가이드에서는 인간과 유사한 상호 작용을 위한 시각적 인터페이스를 제공하는 미니프렘 플랫폼의 레니 디지털 휴먼 구성 요소에 대해 설명합니다.

## 개요

레니는 UneeQ의 기술로 구동되는 디지털 휴먼 아바타로, AI 상호 작용을 위한 시각적 인터페이스를 제공합니다. 얼굴 애니메이션, 입술 동기화, 제스처 기능을 결합하여 더욱 매력적인 대화 경험을 제공합니다.

## 레니에 액세스하기

- **헬스 엔드포인트**: http://localhost:8081/health
- **컨테이너 이름**: `renny`

## 아키텍처

Renny 컴포넌트는 다른 여러 서비스와 상호작용합니다:

1. **오디오투페이스 통합**: 오디오를 얼굴 애니메이션으로 변환
2. **유니큐 플랫폼**: 디지털 휴먼 렌더링 관리
3. **Azure 음성 서비스**: 텍스트 음성 변환 기능 제공

## 구성

### 기본 구성 파일

Renny의 기본 구성은 `docker/configuration.dat`에 저장되며, 여기에는 다음이 포함됩니다:

- 서버**: UneeQ 서버 엔드포인트
- 테넌트아이디**: UneeQ 테넌트 식별자
- **JWSSecret**: UneeQ 서비스를 위한 인증 토큰

### 환경 변수

docker/docker-compose.env`의 주요 환경 변수:

- a2f_address**: 오디오투페이스 서비스 주소
- dhop_address**: UneeQ 플랫폼 주소
- **dhop_apikey**: UneeQ 플랫폼 API 키
- **dhop_tenantid**: UneeQ 테넌트 ID
- **azure_region**: 음성 서비스를 위한 Azure 리전
- **azure_speech**: Azure 음성 서비스 키

## 상태 모니터링

다음을 사용하여 Renny의 건강 상태를 확인할 수 있습니다:

```bash
curl -f http://localhost:8081/health
```

이 엔드포인트는 서비스의 현재 상태 및 종속 서비스에 대한 연결에 대한 정보를 반환합니다.

## 네트워크 구성

Renny는 최적의 성능을 보장하기 위해 호스트 네트워킹 모드를 사용합니다:

```yaml
network_mode: "host"
```

이를 통해 Renny는 Docker 네트워크 격리 없이 시스템 네트워크 인터페이스에 직접 액세스할 수 있습니다.

## GPU 가속

Renny는 렌더링에 NVIDIA GPU 가속을 활용합니다:

```yaml
runtime: nvidia
```

이를 통해 애니메이션과 표정을 부드럽게 표현할 수 있습니다.

## LLM과의 통합

Flowise를 통한 Renny와 LLM의 통합은 다음과 같이 작동합니다:

1. 사용자 입력(텍스트 또는 오디오)을 캡처합니다.
2. 입력은 Flowise/vLLM 파이프라인에 의해 처리됩니다.
3. 응답은 Azure TTS를 통해 음성으로 변환됩니다.
4. Audio2Face가 음성과 동기화된 얼굴 애니메이션을 생성합니다.
5. Renny가 애니메이션 아바타가 응답을 말하도록 렌더링합니다.

## 고급 사용자 지정

### 렌더링 옵션

Renny는 명령줄 파라미터를 통해 다양한 렌더링 구성을 지원합니다:

```
-RenderOffScreen  # Headless rendering
-ResX=1920        # Horizontal resolution
-ResY=1080        # Vertical resolution
```

그래픽 디스플레이(헤드리스가 아닌)의 경우 Docker 구성을 수정할 수 있습니다:

```yaml
# Uncomment for visual rendering
environment:
  - DISPLAY=$DISPLAY
volumes:
  - /tmp/.X11-unix:/tmp/.X11-unix
  - ~/.Xauthority:/home/ue4/.Xauthority
```

### 애니메이션 설정

Audio2Face 애니메이션 파라미터는 A2F 구성 파일에서 조정할 수 있습니다:

- 입술 동기화**: 입 움직임 정확도 제어
- **표정 강도**: 얼굴 표정의 강도를 조절합니다.
- 눈 깜박임 매개변수**: 눈 깜박임 빈도 및 스타일 제어

## 문제 해결

### 일반적인 문제

1. **시각적 출력 없음**:
   - '렌더링 오프 스크린'이 활성화되어 있는지 확인하세요.
   - GPU 드라이버 및 렌더링 기능 확인

2. **애니메이션 품질 불량**:
   - A2F 서비스 상태 확인
   - 오디오 품질 및 처리 확인

3. **연결 문제**:
   - UneeQ 플랫폼 연결 확인
   - 네트워크 설정 및 방화벽 규칙 확인

4. **오디오-비주얼 동기화 문제**:
   - A2F_AUDIO_DELAY_TIME_MS` 파라미터 조정
   - 렌더링 지연에 대한 시스템 성능 확인