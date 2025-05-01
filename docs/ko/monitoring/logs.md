# 라이브 컨테이너 로그

MiniPrem 스택의 다양한 서비스에서 발생하는 실시간 로그를 확인하세요.

## 컨테이너 로그

드롭다운에서 서비스를 선택하면 해당 로그를 볼 수 있습니다:

```terminal
```컨테이너 로그
flowise
vllm
redis
prometheus
grafana
uneeq
```

## 작동 방식

위의 터미널은 각 서비스에 대한 Docker 컨테이너 로그에 연결합니다. 이를 통해 다음을 수행할 수 있습니다:

1. 실시간으로 문제 디버그
2. 애플리케이션 활동 모니터링
3. 시스템 성능 추적

## 로그 수집

로그는 Docker의 로깅 시스템을 사용하여 수집되고 이 인터페이스로 스트리밍됩니다. 프로덕션 환경에서는 다음과 같은 보다 강력한 로깅 솔루션을 고려할 수 있습니다:

- ELK Stack(Elasticsearch, Logstash, Kibana)
- Loki(Grafana 스택의 일부)
- Datadog 또는 기타 클라우드 모니터링 솔루션