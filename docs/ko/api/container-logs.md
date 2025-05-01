# 컨테이너 로그

MiniPrem 스택에서 실행 중인 컨테이너의 실시간 로그를 확인하세요. 이 기능을 사용하면 문서에서 직접 서비스를 모니터링할 수 있습니다.

## 사용 가능한 컨테이너

드롭다운에서 컨테이너를 선택하여 해당 로그를 확인하세요:

```container-logs
flowise
vllm
redis
prometheus
grafana
renny
log-streamer
```

## 작동 방식

이 기능은 포트 8082에서 실행 중인 Log Streamer 서비스에 연결되어 Docker 로그에 대한 WebSocket 인터페이스를 제공합니다. 컨테이너를 선택하면 WebSocket 연결이 다음과 같이 설정됩니다:

```
ws://localhost:8082/logs/{container-name}
```

그런 다음 로그 스트리머 서비스는 Docker에 연결되어 실시간으로 로그를 브라우저로 스트리밍합니다.

## 문제 해결

로그가 표시되지 않는 경우:

1. log-streamer 서비스가 실행 중인지 확인:
   ```bash
   docker ps | grep log-streamer
   ```

2. log-streamer 서비스 로그 확인:
   ```bash
   docker logs log-streamer
   ```

3. 브라우저가 WebSocket을 지원하고 localhost:8082에 액세스할 수 있는지 확인

4. 로그가 여전히 표시되지 않는 경우, 서비스는 시연 목적으로 시뮬레이션된 로그로 자동 전환됩니다.