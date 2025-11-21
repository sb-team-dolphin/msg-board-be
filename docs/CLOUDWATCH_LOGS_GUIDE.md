# CloudWatch Logs 활용 가이드

배포된 Feedback API의 로그를 CloudWatch Logs로 수집하고 분석하는 방법을 안내합니다.

## 목차
1. [실시간 로그 모니터링](#1-실시간-로그-모니터링)
2. [에러 추적 및 디버깅](#2-에러-추적-및-디버깅)
3. [CloudWatch Insights 쿼리](#3-cloudwatch-insights---강력한-쿼리)
4. [알람 설정](#4-알람-설정)
5. [로그 분석 자동화](#5-로그-분석-자동화)
6. [비용 최적화](#6-비용-최적화)
7. [실전 활용 시나리오](#7-실전-활용-시나리오)
8. [대시보드 생성](#8-대시보드-생성)

---

## 1. 실시간 로그 모니터링

### AWS Console에서 실시간 확인

```
AWS Console → CloudWatch → Logs → Log groups
→ /ecs/feedback-api → feedback-api (스트림 클릭)
```

**실시간 tail 기능:**
- 새로고침 아이콘 옆 "Tail" 버튼 클릭
- 실시간으로 로그가 스트리밍됩니다

### AWS CLI로 실시간 확인

```bash
# 실시간 로그 스트리밍 (터미널에서)
aws logs tail /ecs/feedback-api --follow --region ap-northeast-2

# 특정 시간대 로그만
aws logs tail /ecs/feedback-api --since 1h --region ap-northeast-2

# 최근 50줄만 보기
aws logs tail /ecs/feedback-api --since 10m --region ap-northeast-2 | tail -n 50
```

---

## 2. 에러 추적 및 디버깅

### 에러 로그만 필터링

**AWS Console에서:**
```
Log groups → /ecs/feedback-api → "Filter events" 입력창에:
ERROR
```

**AWS CLI:**
```bash
# ERROR 키워드 검색
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "ERROR" \
  --region ap-northeast-2

# 결과를 파일로 저장
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "ERROR" \
  --region ap-northeast-2 > error_logs.json
```

### 특정 Exception 추적

```bash
# NullPointerException 검색
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "NullPointerException" \
  --region ap-northeast-2

# 여러 패턴 동시 검색
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "?ERROR ?Exception ?WARN" \
  --region ap-northeast-2

# 특정 시간대의 에러만
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region ap-northeast-2
```

---

## 3. CloudWatch Insights - 강력한 쿼리

### Insights 접근 방법

```
CloudWatch → Logs → Insights
→ Log group 선택: /ecs/feedback-api
→ 쿼리 입력 → Run query
```

### 유용한 쿼리 예제

#### 1) 에러 로그 분석

```sql
fields @timestamp, @message
| filter @message like /ERROR|Exception/
| sort @timestamp desc
| limit 100
```

#### 2) API 응답 시간 분석

```sql
fields @timestamp, @message
| filter @message like /GET|POST/
| parse @message /duration:(?<duration>\d+)ms/
| stats avg(duration), max(duration), min(duration) by bin(5m)
```

#### 3) 시간대별 에러 빈도

```sql
fields @timestamp
| filter @message like /ERROR/
| stats count() as error_count by bin(1h)
| sort @timestamp desc
```

#### 4) 특정 사용자 활동 추적

```sql
fields @timestamp, @message
| filter @message like /userId=12345/
| sort @timestamp desc
| limit 50
```

#### 5) 메모리 사용량 추적

```sql
fields @timestamp, @message
| filter @message like /Memory|Heap/
| parse @message /used:(?<used>\d+)MB/
| display @timestamp, used
```

#### 6) 가장 느린 API 요청 TOP 10

```sql
fields @timestamp, @message
| filter @message like /completed in/
| parse @message /(?<method>GET|POST) (?<path>\/\S+) .* completed in (?<duration>\d+)ms/
| sort duration desc
| limit 10
```

#### 7) HTTP 상태 코드별 통계

```sql
fields @message
| filter @message like /status=/
| parse @message /status=(?<status>\d+)/
| stats count() as request_count by status
| sort request_count desc
```

#### 8) 데이터베이스 쿼리 성능 분석

```sql
fields @timestamp, @message
| filter @message like /Hibernate:|SQL:/
| parse @message /(?<query>SELECT|INSERT|UPDATE|DELETE)/
| stats count() as query_count by query
```

---

## 4. 알람 설정

### 에러 발생 시 알림 받기

#### Step 1: 메트릭 필터 생성

```
CloudWatch → Log groups → /ecs/feedback-api
→ Actions → Create metric filter

Filter pattern: ERROR
Filter name: ErrorFilter

Metric details:
- Metric namespace: FeedbackAPI
- Metric name: ErrorCount
- Metric value: 1
- Default value: 0
```

#### Step 2: 알람 생성

```
CloudWatch → Alarms → Create alarm
→ Select metric → FeedbackAPI → ErrorCount

Conditions:
- Threshold type: Static
- Whenever ErrorCount is: Greater/Equal
- than: 5
- Period: 5 minutes

Actions:
- Create new topic
- Topic name: feedback-api-alerts
- Email: your-email@example.com
```

### 알람 유형별 설정

#### 1) 에러 급증 알람

```
Metric: ErrorCount
Threshold: >= 10 in 5 minutes
Severity: Critical
```

#### 2) 응답 시간 지연 알람

```
Metric: AverageResponseTime
Threshold: >= 1000ms
Period: 5 minutes
Severity: Warning
```

#### 3) 애플리케이션 다운 알람

```
Metric: HealthCheckFailure
Threshold: >= 1
Period: 1 minute
Severity: Critical
```

### Slack 연동

**Option 1: AWS Chatbot 사용 (권장)**

```
AWS Chatbot → Configure new client → Slack
→ Configure new channel
→ SNS topic 연결: feedback-api-alerts
```

**Option 2: Lambda 함수 사용**

```javascript
// Lambda 함수 (Node.js)
const https = require('https');

exports.handler = async (event) => {
    const message = JSON.parse(event.Records[0].Sns.Message);

    const slackMessage = {
        text: `🚨 *${message.AlarmName}*`,
        attachments: [{
            color: 'danger',
            fields: [
                { title: 'Alarm', value: message.AlarmDescription, short: false },
                { title: 'State', value: message.NewStateValue, short: true },
                { title: 'Reason', value: message.NewStateReason, short: false }
            ]
        }]
    };

    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'hooks.slack.com',
            path: '/services/YOUR/WEBHOOK/URL',
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        };

        const req = https.request(options, (res) => {
            resolve('Message sent to Slack');
        });

        req.on('error', (e) => reject(e));
        req.write(JSON.stringify(slackMessage));
        req.end();
    });
};
```

---

## 5. 로그 분석 자동화

### EventBridge로 일일 리포트 자동화

#### Step 1: EventBridge Rule 생성

```
EventBridge → Rules → Create rule

Name: daily-error-report
Schedule: cron(0 9 * * ? *)  # 매일 오전 9시 (UTC)
Target: Lambda function
```

#### Step 2: Lambda 함수 (일일 리포트)

```python
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    client = boto3.client('logs', region_name='ap-northeast-2')

    # 어제 날짜 계산
    yesterday = datetime.now() - timedelta(days=1)
    start_time = int(yesterday.replace(hour=0, minute=0, second=0).timestamp() * 1000)
    end_time = int(yesterday.replace(hour=23, minute=59, second=59).timestamp() * 1000)

    # CloudWatch Insights 쿼리
    query = """
    fields @timestamp, @message
    | filter @message like /ERROR/
    | stats count() as error_count
    """

    # 쿼리 실행
    response = client.start_query(
        logGroupName='/ecs/feedback-api',
        startTime=start_time,
        endTime=end_time,
        queryString=query
    )

    # 결과 가져오기 (실제로는 polling 필요)
    # ... SNS로 결과 전송

    return {
        'statusCode': 200,
        'body': json.dumps('Report sent successfully')
    }
```

### 주간 성능 리포트

```python
# Lambda 함수 - 주간 리포트
query = """
fields @timestamp, @message
| filter @message like /completed in/
| parse @message /completed in (?<duration>\d+)ms/
| stats avg(duration) as avg_time, max(duration) as max_time, count() as total_requests
"""
```

---

## 6. 비용 최적화

### 로그 보존 기간 설정

```bash
# 30일 보관 설정 (권장)
aws logs put-retention-policy \
  --log-group-name /ecs/feedback-api \
  --retention-in-days 30 \
  --region ap-northeast-2

# 다른 옵션들
# 1일, 3일, 5일, 7일, 14일, 30일, 60일, 90일,
# 120일, 150일, 180일, 365일, 400일, 545일,
# 731일, 1827일, 2192일, 2557일, 2922일, 3288일, 3653일

# 현재 설정 확인
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/feedback-api \
  --region ap-northeast-2
```

### 불필요한 로그 레벨 제거

**application.yml 수정 (프로덕션 환경):**

```yaml
logging:
  level:
    root: WARN
    com.jaewon.practice.simpleapi: INFO      # DEBUG 대신 INFO
    org.springframework.web: WARN            # INFO 대신 WARN
    org.hibernate.SQL: WARN                  # DEBUG 끄기
    org.hibernate.type.descriptor: WARN      # 파라미터 로깅 끄기
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} %-5level %logger{36} - %msg%n"
```

### 비용 계산

**예상 로그 발생량:**
- 평균 요청당 로그: 1KB
- 일 10,000 요청 = 10MB
- 월 300MB

**CloudWatch Logs 요금 (서울 리전):**
- 수집: $0.76/GB = 월 $0.23
- 저장 (30일): $0.033/GB/월 = 월 $0.01
- **총 예상 비용: 월 약 $0.24 (300원)**

### 로그 샘플링 (선택사항)

트래픽이 매우 많을 경우 샘플링 고려:

```yaml
# application.yml
logging:
  level:
    org.springframework.web.filter.CommonsRequestLoggingFilter: INFO

# 10% 샘플링 예시
server:
  tomcat:
    accesslog:
      enabled: true
      pattern: '%h %l %u %t "%r" %s %b %D'
      rotate: true
      max-days: 7
      # 샘플링은 애플리케이션 레벨에서 구현 필요
```

---

## 7. 실전 활용 시나리오

### 시나리오 1: 장애 발생 시 대응

**1단계: 알람 수신**
```
Slack/Email: "🚨 ErrorCount >= 10 in 5 minutes"
```

**2단계: CloudWatch Insights로 원인 파악**
```sql
-- 최근 에러 확인
fields @timestamp, @message
| filter @message like /ERROR|Exception/
| sort @timestamp desc
| limit 50
```

**3단계: 영향 범위 분석**
```sql
-- 에러 발생 패턴
fields @timestamp
| filter @message like /ERROR/
| stats count() as error_count by bin(1m)
| sort @timestamp desc
```

**4단계: 특정 에러 상세 추적**
```sql
-- Stack trace 확인
fields @timestamp, @message
| filter @message like /NullPointerException/
| display @timestamp, @message
```

**5단계: 롤백 또는 핫픽스 결정**

### 시나리오 2: 성능 저하 조사

**1단계: 응답 시간 추이 확인**
```sql
fields @timestamp, @message
| filter @message like /completed in/
| parse @message /completed in (?<duration>\d+)ms/
| stats avg(duration) as avg_response_time by bin(5m)
| sort @timestamp desc
```

**2단계: 느린 API 식별**
```sql
fields @message
| filter @message like /completed in/
| parse @message /(?<method>GET|POST) (?<path>\/\S+) .* completed in (?<duration>\d+)ms/
| filter duration > 1000
| stats count() as slow_count by path
| sort slow_count desc
```

**3단계: 데이터베이스 쿼리 확인**
```sql
fields @timestamp, @message
| filter @message like /Hibernate:|took/
| parse @message /took (?<time>\d+)ms/
| filter time > 500
| display @timestamp, @message
```

### 시나리오 3: 사용자 행동 분석

**API 사용 통계**
```sql
fields @message
| filter @message like /GET|POST/
| parse @message /(?<method>GET|POST) (?<path>\/api\/\S+)/
| stats count() as request_count by path, method
| sort request_count desc
```

**시간대별 트래픽 패턴**
```sql
fields @timestamp
| filter @message like /GET|POST/
| stats count() as requests by bin(1h)
| sort @timestamp desc
```

**사용자별 요청 빈도**
```sql
fields @message
| filter @message like /userId=/
| parse @message /userId=(?<userId>\d+)/
| stats count() as request_count by userId
| sort request_count desc
| limit 20
```

---

## 8. 대시보드 생성

### 대시보드 구성

```
CloudWatch → Dashboards → Create dashboard
Name: feedback-api-monitoring
```

### 추천 위젯 구성

#### 1) 에러 발생 추이 (Line graph)

```
Metric: FeedbackAPI/ErrorCount
Period: 5 minutes
Statistic: Sum
```

#### 2) API 호출 수 (Number widget)

```
Metric: AWS/Logs/IncomingLogEvents
Period: 1 hour
Statistic: Sum
```

#### 3) 최근 에러 로그 (Logs table)

```
Log groups: /ecs/feedback-api
Query:
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

#### 4) 응답 시간 분포 (Line graph)

```
Query:
fields @timestamp
| filter @message like /completed in/
| parse @message /completed in (?<duration>\d+)ms/
| stats avg(duration), pct(duration, 95) by bin(5m)
```

### 대시보드 자동 새로고침

```
Dashboard 설정 → Auto refresh → 1 minute
```

---

## 추천 워크플로우

### 일일 모니터링 (5분)

1. **대시보드 확인**
   - 전체 상태 한눈에 파악
   - 에러 발생 추이 확인

2. **Insights 쿼리**
   ```sql
   -- 오늘의 에러 요약
   fields @timestamp, @message
   | filter @message like /ERROR/
   | stats count() as error_count by bin(1h)
   ```

3. **이상 패턴 발견 시 상세 조사**

### 장애 대응 (즉시)

1. **알람 수신 즉시 CloudWatch 접속**
2. **실시간 로그 tail로 현재 상황 파악**
   ```bash
   aws logs tail /ecs/feedback-api --follow
   ```
3. **Insights로 원인 분석**
4. **필요 시 롤백 또는 핫픽스**

### 주간 리뷰 (30분)

1. **주간 에러 통계**
   ```sql
   fields @timestamp
   | filter @message like /ERROR/
   | stats count() as error_count by bin(1d)
   ```

2. **성능 추이 분석**
   ```sql
   fields @timestamp
   | filter @message like /completed in/
   | parse @message /completed in (?<duration>\d+)ms/
   | stats avg(duration) by bin(1d)
   ```

3. **API 사용 패턴 검토**

4. **로그 보존 정책 및 비용 확인**

---

## 유용한 CLI 명령어 모음

### 로그 그룹 관리

```bash
# 모든 로그 그룹 조회
aws logs describe-log-groups --region ap-northeast-2

# 특정 로그 그룹 상세 정보
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/feedback-api \
  --region ap-northeast-2

# 로그 스트림 목록
aws logs describe-log-streams \
  --log-group-name /ecs/feedback-api \
  --region ap-northeast-2
```

### 로그 검색 및 필터링

```bash
# 실시간 tail
aws logs tail /ecs/feedback-api --follow --region ap-northeast-2

# 특정 기간 로그
aws logs tail /ecs/feedback-api \
  --since 2h \
  --until 1h \
  --region ap-northeast-2

# 패턴 필터링
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --filter-pattern "ERROR" \
  --region ap-northeast-2 \
  --output json | jq '.events[].message'
```

### Insights 쿼리 실행

```bash
# 쿼리 시작
QUERY_ID=$(aws logs start-query \
  --log-group-name /ecs/feedback-api \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 20' \
  --region ap-northeast-2 \
  --query 'queryId' \
  --output text)

# 쿼리 결과 확인
aws logs get-query-results \
  --query-id $QUERY_ID \
  --region ap-northeast-2
```

---

## 트러블슈팅

### 로그가 CloudWatch에 안 올라갈 때

1. **IAM Role 권한 확인**
   ```bash
   aws iam get-role --role-name YourEC2Role
   ```

2. **컨테이너 로그 드라이버 확인**
   ```bash
   docker inspect feedback-api | grep -A 10 LogConfig
   ```

3. **수동으로 로그 전송 테스트**
   ```bash
   aws logs create-log-group --log-group-name /test/logs
   aws logs create-log-stream \
     --log-group-name /test/logs \
     --log-stream-name test-stream
   ```

### 비용이 예상보다 높을 때

1. **로그 발생량 확인**
   ```sql
   fields @timestamp
   | stats count() as log_count by bin(1d)
   ```

2. **불필요한 DEBUG 로그 제거**

3. **로그 보존 기간 단축**

---

## 참고 자료

- [CloudWatch Logs 공식 문서](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [CloudWatch Insights 쿼리 문법](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [AWS CLI CloudWatch Logs 명령어](https://docs.aws.amazon.com/cli/latest/reference/logs/)
- [CloudWatch Logs 요금](https://aws.amazon.com/cloudwatch/pricing/)

---

## 다음 단계

- [ ] 대시보드 생성
- [ ] 에러 알람 설정
- [ ] 일일 리포트 자동화
- [ ] Slack 연동
- [ ] 로그 보존 기간 설정 (30일)
- [ ] 프로덕션 로그 레벨 최적화
