# 문제 해결 가이드

이 가이드는 MiniPrem 플랫폼을 실행할 때 발생할 수 있는 일반적인 문제에 대한 해결 방법을 제공합니다.

## 일반 문제 해결 단계

1. **서비스 상태 확인**:
   ```bash
   ./miniprem.sh status
   ```

2. **서비스 로그 보기**:
   ```bash
   ./miniprem.sh logs
   # Or for a specific service
   ./miniprem.sh logs renny
   ```

3. 3. **서비스 다시 시작**:
   ```bash
   ./miniprem.sh restart
   ```

4. **도커 리소스 확인**:
   ```bash
   docker stats
   ```

## vLLM 문제

### vLLM 컨테이너를 시작하지 못함

**증상**: vLLM 컨테이너가 시작 후 즉시 중지됨

**해결 방법**:
1. GPU 가용성을 확인합니다:
   ```bash
   nvidia-smi
   ```

2. NVIDIA 런타임이 올바르게 구성되었는지 확인합니다:
   ```bash
   docker info | grep -i runtime
   ```

3. 포트 충돌을 확인합니다:
   ```bash
   sudo lsof -i :8000
   ```

4. vLLM 로그를 확인합니다:
   ```bash
   docker logs vllm
   ```

### 모델 로딩 문제

**증상**: 모델을 사용하려고 할 때 오류 메시지가 표시됩니다.

**해결 방법**:
1. 모델이 다운로드되었는지 확인합니다:
   ```bash
   docker exec -it vllm ls /root/.cache/huggingface
   ```

2. 모델을 다시 당깁니다:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model facebook/opt-125m
   ```

3. 3. GPU 메모리가 충분한지 확인합니다:
   ```bash
   nvidia-smi
   ```

4. 테스트를 위해 더 작은 모델을 사용해 보세요:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

## 플로우이즈 문제

### 플로우이즈 UI에 액세스할 수 없음

**증상**: http://localhost:3000 에서 플로우이즈에 접속할 수 없습니다.

**해결 방법**:
1. 컨테이너가 실행 중인지 확인하세요:
   ```bash
   docker ps | grep flowise
   ```

2. 컨테이너 로그를 확인합니다:
   ```bash
   docker logs flowise
   ```

3. 포트 가용성을 확인합니다:
   ```bash
   curl -I http://localhost:3000
   ```

### 채팅 플로우 생성 실패

**증상**: 채팅 플로우를 만들거나 저장할 수 없습니다.

**해결방법**:
1. 데이터베이스 연결을 확인하세요:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/database.sqlite
   ```

2. 볼륨 권한을 확인합니다:
   ```bash
   docker exec -it flowise ls -la /usr/src/.flowise/
   ```

3. 3. 설정 스크립트를 수동으로 실행해 보세요:
   ```bash
   ./docker/setup-chatflow-post-deployment-fixed.sh
   ```

### API 인증 문제

**증상**: API 액세스 시 승인되지 않은 오류 발생

**해결 방법**:
1. 올바른 API 키를 사용하고 있는지 확인하세요:
   ```
   Authorization: Bearer miniprem_demo_secret_key
   ```

2. 2. API 키를 재설정합니다:
   ```bash
   docker exec -it flowise node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```
   그런 다음 설치 유형에 따라 적절한 컴포즈 파일(docker-compose.base.yml 또는 docker-compose.extras.yml)에서 `FLOWISE_SECRETKEY_OVERWRITE`를 업데이트하세요.

## 레니 문제

### Renny 상태 확인 실패

**증상**: Renny 컨테이너가 건강하지 않은 상태를 보고합니다.

**해결 방법**:
1. Renny 로그를 확인합니다:
   ```bash
   docker logs renny
   ```

2. UneeQ 플랫폼 연결을 확인합니다:
   ```bash
   curl -I $DHOP_ADDRESS
   ```

3. 오디오투페이스 서비스를 확인합니다:
   ```bash
   docker ps | grep audio2face
   ```

4. configuration.dat 파일을 확인합니다:
   ```bash
   cat docker/configuration.dat
   ```

### Audio2Face 연결 문제

**증상**: 얼굴 애니메이션이 제대로 작동하지 않음

**해결 방법**:
1. Audio2Face 서비스를 확인하세요:
   ```bash
   docker logs audio2face_with_emotion
   docker logs audio2face_controller
   ```

2. 네트워크 구성을 확인합니다:
   ```bash
   docker exec -it renny ping audio2face-gateway
   ```

3. A2F 구성을 확인합니다:
   ```bash
   cat docker/a2f-config.yml
   ```

## 모니터링 문제

### 메트릭을 수집하지 않는 Prometheus

**증상**: Grafana 대시보드에 메트릭이 없습니다.

**해결 방법**:
1. Prometheus가 실행 중인지 확인하세요:
   ```bash
   docker ps | grep prometheus
   ```

2. 프로메테우스 대상을 확인합니다:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Prometheus 구성을 확인합니다:
   ```bash
   cat docker/prometheus.yml
   ```

### Grafana 로그인 문제

**증상**: Grafana에 로그인할 수 없습니다.

**해결방법**:
1. 기본 자격 증명 사용(관리자/관리자)

2. 관리자 비밀번호를 재설정합니다:
   ```bash
   docker exec -it grafana grafana-cli admin reset-admin-password admin
   ```

3. Grafana 로그를 확인합니다:
   ```bash
   docker logs grafana
   ```

네트워크 문제 ## 네트워크 문제

### 포트 충돌

**증상**: 이미 사용 중인 포트로 인해 서비스를 시작하지 못함

**해결 방법**:
1. 포트를 사용하고 있는 프로세스를 찾습니다:
   ```bash
   sudo lsof -i :PORT_NUMBER
   ```

2. 충돌하는 프로세스를 중지하거나 적절한 컴포짓 파일(docker-compose.base.yml 또는 docker-compose.extras.yml)에서 포트를 수정합니다.

3. 방화벽 설정을 확인합니다:
   ```bash
   sudo ufw status
   ```

### 도커 네트워크 문제

**증상**: 서비스가 서로 통신할 수 없음

**해결 방법**:
1. Docker 네트워크를 확인하세요:
   ```bash
   docker network inspect uneeq-miniprem_default
   ```

2. 컨테이너 연결을 확인합니다:
   ```bash
   docker exec -it flowise ping vllm
   ```

3. Docker를 다시 시작합니다:
   ```bash
   sudo systemctl restart docker
   ```

리소스 문제 ## 리소스 문제

### 메모리 부족

**증상**: OOM 오류로 서비스 충돌

**해결 방법**:
1. 메모리 사용량을 확인하세요:
   ```bash
   free -h
   docker stats
   ```

2. 호스트 스왑 공간을 늘립니다:
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. Docker 메모리 제한을 조정합니다:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
   ```

### GPU 메모리 문제

**증상**: GPU 메모리 부족 오류

**해결 방법**:
1. GPU 사용량을 모니터링합니다:
   ```bash
   nvidia-smi -l 1
   ```

2. 더 작은 모델을 사용합니다:
   ```bash
   docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model tinyllama
   ```

3. MiniPrem 작동 중에 다른 애플리케이션이 GPU를 사용하지 못하도록 차단합니다.

서비스를 더 추가하거나 설치 유형을 변경하려면 설치 관리자를 다시 실행하고 원하는 옵션을 선택하세요.
