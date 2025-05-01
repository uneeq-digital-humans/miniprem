# Prometheus 및 Grafana로 모니터링하기

이 가이드에서는 기본 제공 모니터링 도구를 사용하여 MiniPrem 플랫폼의 성능 및 사용량 메트릭을 추적하는 방법을 설명합니다.

## 개요

MiniPrem에는 두 가지 강력한 모니터링 도구가 포함되어 있습니다:

1. **프로메테우스**: 메트릭을 수집하고 저장하는 시계열 데이터베이스
2. **그라파나**: Prometheus 데이터에서 대시보드를 생성하는 시각화 플랫폼

## 모니터링 도구 액세스

| 도구 | URL | 기본 자격 증명 |
|------|-----|---------------------|
| Grafana | http://localhost:3001 | 관리자 / 관리자 |
| 프로메테우스 | http://localhost:9090 | N/A |

## Grafana 대시보드

### 사전 구성된 대시보드

미니프렘 설치에는 플로우이즈 모니터링을 위해 사전 구성된 대시보드가 포함되어 있습니다:

1. **플로우이즈 대시보드**: 플로우이즈 인스턴스의 주요 메트릭을 표시합니다:
   - HTTP 요청 횟수
   - HTTP 요청 지속 시간
   - 메모리 사용량
   - CPU 사용량

대시보드 보기 ###

1. http://localhost:3001 에서 그라파나에 로그인합니다.
2. 왼쪽 사이드바에서 "대시보드"를 클릭합니다.
3. 목록에서 "플로우이즈 대시보드"를 선택합니다.

### 사용자 지정 대시보드 만들기

1. 사이드바에서 "+" 아이콘을 클릭합니다.
2. "대시보드"를 선택합니다.
3. "새 패널 추가"를 클릭합니다.
4. 시각화 유형(그래프, 게이지, 표 등)을 선택합니다.
5. 쿼리 편집기에서 Prometheus 쿼리를 입력합니다.
6. 표시 옵션 구성
7. "저장"을 클릭하여 대시보드에 패널을 추가합니다.

## 프로메테우스 쿼리 예시

### 기본 지표

```promql
# HTTP request count
http_request_total

# Average request duration in the last 5 minutes
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Memory usage
process_resident_memory_bytes

# CPU usage
rate(process_cpu_seconds_total[1m])
```
