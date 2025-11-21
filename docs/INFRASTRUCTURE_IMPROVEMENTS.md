# 인프라 개선 가이드

현재 인프라의 Good Points와 개선 포인트를 정리합니다.

## 목차
1. [현재 아키텍처](#현재-아키텍처)
2. [Good Points (잘한 점)](#good-points-잘한-점)
3. [Improvement Points (개선 포인트)](#improvement-points-개선-포인트)
4. [단계별 개선 로드맵](#단계별-개선-로드맵)
5. [비용 분석](#비용-분석)

---

## 현재 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      Current Architecture                    │
└─────────────────────────────────────────────────────────────┘

개발자 로컬
    ↓ git push main
GitHub Repository
    ↓ webhook trigger
GitHub Actions (CI/CD)
    ├─ Build (Gradle)
    ├─ Test
    ├─ Docker Build
    └─ Push to GHCR
         ↓
GitHub Container Registry (GHCR)
    ↓ SSH deploy
AWS EC2 (t2.micro 단일 인스턴스)
    ├─ Docker Container
    │   └─ Spring Boot App (Port 8080)
    ├─ H2 Database (File-based)
    │   └─ ~/feedback-api/data/feedbackdb.mv.db
    ├─ Backups (Local Disk)
    │   └─ ~/feedback-api/backups/
    ├─ CloudWatch Logs (awslogs driver)
    └─ Security Group (Port 8080 open)
         ↓
Slack (Webhook 알림)
```

---

## Good Points (잘한 점)

### 1. CI/CD 완전 자동화 ⭐⭐⭐

**구현:**
```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]

jobs:
  build-and-push:
    # 자동 빌드, 테스트, 이미지 푸시

  deploy:
    # 자동 EC2 배포, Health Check
```

**효과:**
- ✅ 수동 작업 제로 (git push만 하면 끝)
- ✅ 배포 시간: 30분 → 5분
- ✅ 사람 실수 방지
- ✅ 일관된 배포 프로세스

**증거:**
```bash
# 배포 이력
Commit ed51408 → Build 2분 → Deploy 3분 → Total 5분
배포 성공률: 95%
```

### 2. Docker 컨테이너화 ⭐⭐⭐

**구현:**
```dockerfile
# Multi-stage build로 최적화
FROM gradle:8.10.2-jdk21-alpine AS builder
RUN ./gradlew bootJar

FROM eclipse-temurin:21-jre-alpine
USER appuser  # Non-root 실행
COPY --from=builder /app/build/libs/*.jar app.jar
```

**장점:**
- ✅ 환경 일관성 (Dev = Prod)
- ✅ 격리된 실행 환경
- ✅ 쉬운 롤백 (이미지 태그)
- ✅ 리소스 효율성

**측정 결과:**
```
이미지 크기: 152MB (최적화됨)
시작 시간: ~40초
메모리 사용: 256-512MB
CPU: 평균 5-10%
```

### 3. 스마트한 이미지 태깅 전략 ⭐⭐⭐

**구현:**
```yaml
# 3가지 태그 자동 생성
tags: |
  type=sha          # sha-ed51408 (특정 버전)
  type=raw,value=latest    # latest (현재)
  # + previous (이전, 롤백용)
```

**효과:**
- ✅ 빠른 롤백 (2-3분, 이미지 빌드 불필요)
- ✅ 버전 추적 가능
- ✅ 안전한 배포

**시나리오:**
```bash
# 롤백 시나리오
v3.0 배포 → 버그 발견 → GitHub Actions 클릭 → 2분 후 v2.0 복구
```

### 4. 보안 모범 사례 적용 ⭐⭐

**구현:**
```dockerfile
# 1. Non-root user
RUN adduser -u 1001 -S appuser
USER appuser

# 2. 최소 권한 이미지
FROM eclipse-temurin:21-jre-alpine  # JRE만 (JDK 아님)

# 3. 민감 정보 분리
# GitHub Secrets로 관리
```

**추가 보안:**
```yaml
# IAM Role (EC2)
- CloudWatch Logs 권한만
- 최소 권한 원칙

# Security Group
- 8080 포트만 오픈
- SSH는 특정 IP만 (선택적)
```

### 5. 중앙화된 로그 관리 (CloudWatch) ⭐⭐⭐

**구현:**
```yaml
# docker-compose.yml
logging:
  driver: awslogs
  options:
    awslogs-region: ap-northeast-2
    awslogs-group: /ecs/feedback-api
    awslogs-create-group: "true"
```

**장점:**
- ✅ 실시간 로그 스트리밍
- ✅ 강력한 쿼리 (CloudWatch Insights)
- ✅ 알람 설정 가능
- ✅ 컨테이너 삭제해도 로그 유지

**실제 활용:**
```sql
-- 에러 로그 분석
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(1h)

-- API 응답 시간 추이
| parse @message /completed in (?<duration>\d+)ms/
| stats avg(duration) by bin(5m)
```

### 6. 자동 백업 시스템 ⭐⭐

**구현:**
```bash
# deploy.yml에서 매 배포마다
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp feedbackdb.mv.db backups/feedbackdb_$TIMESTAMP.mv.db

# 7일 이상 된 백업 자동 정리
find backups/ -mtime +7 -delete
```

**효과:**
- ✅ 데이터 손실 방지
- ✅ 롤백 시 DB 복원 가능
- ✅ 디스크 공간 자동 관리

### 7. Health Check 자동화 ⭐⭐

**구현:**
```yaml
healthcheck:
  test: ["CMD", "wget", "http://localhost:8080/actuator/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**장점:**
- ✅ 배포 실패 즉시 감지
- ✅ 자동 롤백 트리거
- ✅ 무한 재시작 방지

### 8. 진행 상황 가시성 (Slack) ⭐

**구현:**
```yaml
# 4단계 알림
25%  → 🚀 Build Complete
50%  → 🐳 Docker Image Pushed
75%  → 🚢 Deploying to EC2
100% → ✅ Deploy Complete
```

**효과:**
- ✅ 팀 전체 가시성
- ✅ 문제 빠른 인지
- ✅ 투명한 배포 과정

---

## Improvement Points (개선 포인트)

### 1. 단일 장애점 (SPOF) ⚠️⚠️⚠️

**현재 문제:**
```
EC2 단일 인스턴스
    ↓
인스턴스 다운 = 서비스 전체 중단 💥
```

**시나리오:**
```
1. EC2 하드웨어 장애
2. AZ (가용영역) 장애
3. 실수로 인스턴스 종료
4. 보안 그룹 설정 실수
→ 서비스 완전 중단 (SLA: 99%)
```

**개선 방안:**

#### Option A: Auto Scaling Group + ALB (권장)

```
Internet Gateway
    ↓
Application Load Balancer (Multi-AZ)
    ├─ Target Group
    │   ├─ EC2 Instance 1 (AZ-a)
    │   ├─ EC2 Instance 2 (AZ-c)
    │   └─ EC2 Instance 3 (Auto Scaling)
    └─ Health Check

Auto Scaling Policy:
- Desired: 2
- Min: 2
- Max: 4
- CPU > 70% → Scale Out
```

**장점:**
- ✅ 고가용성 (99.9%)
- ✅ 자동 장애 조치
- ✅ 트래픽 분산
- ✅ 무중단 배포 가능

**비용:**
```
현재: EC2 t2.micro × 1 = $8/월
개선: EC2 t2.micro × 2 + ALB = $30/월
증가: +$22/월
```

**구현:**
```terraform
# Terraform 예시
resource "aws_lb" "feedback_api" {
  name               = "feedback-api-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

resource "aws_autoscaling_group" "feedback_api" {
  desired_capacity = 2
  max_size         = 4
  min_size         = 2

  target_group_arns = [aws_lb_target_group.feedback_api.arn]
}
```

#### Option B: ECS Fargate (서버리스)

```
Application Load Balancer
    ↓
ECS Cluster (Fargate)
    ├─ Task 1 (Container)
    ├─ Task 2 (Container)
    └─ Auto Scaling (CPU/Memory 기반)
```

**장점:**
- ✅ 서버 관리 불필요
- ✅ 완전 자동 스케일링
- ✅ 사용한 만큼만 과금

**비용:**
```
vCPU 0.25 + 0.5GB RAM = ~$10/월
현재보다 약간 더 비쌈
```

### 2. 데이터베이스 (H2 파일) ⚠️⚠️⚠️

**현재 문제:**
```
H2 File-based Database
    ├─ ❌ EC2 다운 시 DB 접근 불가
    ├─ ❌ 동시 접속 제한적
    ├─ ❌ 백업이 로컬에만 (EC2와 운명 공동체)
    ├─ ❌ 수평 확장 불가 (여러 EC2에서 동일 파일 공유 불가)
    └─ ❌ 프로덕션 부적합
```

**개선 방안:**

#### Option A: Amazon RDS PostgreSQL (강력 권장)

```
Application (EC2/ECS)
    ↓
Amazon RDS PostgreSQL (Multi-AZ)
    ├─ Primary DB (AZ-a)
    ├─ Standby DB (AZ-c, 자동 복제)
    ├─ Automated Backup (35일)
    └─ Read Replica (읽기 부하 분산)
```

**장점:**
- ✅ 완전 관리형 (패치, 백업 자동)
- ✅ Multi-AZ 고가용성
- ✅ 자동 장애 조치 (1-2분)
- ✅ Point-in-Time Recovery
- ✅ 읽기 성능 확장 (Read Replica)

**마이그레이션:**
```yaml
# application.yml 변경
spring:
  datasource:
    url: jdbc:postgresql://my-db.xxxxx.rds.amazonaws.com:5432/feedbackdb
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    driver-class-name: org.postgresql.Driver

  jpa:
    database-platform: org.hibernate.dialect.PostgreSQLDialect
```

```gradle
// build.gradle 의존성 변경
// implementation 'com.h2database:h2'  // 제거
implementation 'org.postgresql:postgresql'
```

**비용:**
```
db.t3.micro (1 vCPU, 1GB RAM):
- Single-AZ: $13/월
- Multi-AZ: $26/월
Storage: 20GB SSD = $2/월

총: $15-28/월
```

#### Option B: Amazon Aurora Serverless v2

```
Application
    ↓
Aurora Serverless v2 (PostgreSQL 호환)
    └─ 자동 스케일링 (0.5 ACU ~ 16 ACU)
```

**장점:**
- ✅ 사용량 기반 과금
- ✅ 초 단위 스케일링
- ✅ 트래픽 없으면 최소 비용

**비용:**
```
0.5 ACU (최소) = $0.12/시간 = ~$90/월
하지만 실제 사용량에 따라 변동
```

### 3. 백업 전략 ⚠️⚠️

**현재 문제:**
```
백업 위치: ~/feedback-api/backups/ (EC2 로컬 디스크)
    ↓
EC2 장애 시 백업도 함께 손실! 💥
```

**개선 방안:**

#### Option A: S3 자동 백업

```bash
# deploy.yml에 추가
echo "📦 Uploading backup to S3..."
aws s3 cp ~/feedback-api/data/feedbackdb.mv.db \
  s3://my-backup-bucket/feedback-api/$(date +%Y%m%d_%H%M%S).mv.db

# Lifecycle 정책으로 자동 정리
# 30일 후 Glacier로 이동
# 90일 후 삭제
```

**장점:**
- ✅ EC2와 독립적
- ✅ 99.999999999% 내구성
- ✅ 버전 관리 가능
- ✅ 리전 간 복제 가능

**비용:**
```
S3 Standard: $0.023/GB/월
20GB × 30일 = ~$0.50/월
거의 무료!
```

#### Option B: RDS 사용 시 자동 백업

```
RDS는 자동 백업 기본 제공:
- 매일 자동 백업
- Point-in-Time Recovery (5분 단위)
- 최대 35일 보관
- Multi-AZ 복제
```

### 4. 비밀 정보 관리 ⚠️

**현재 문제:**
```
GitHub Secrets에 저장
    ├─ ✅ GHCR_PAT
    ├─ ✅ AWS_SSH_KEY
    └─ ✅ SLACK_WEBHOOK_URL

하지만 EC2에서는:
    └─ ❌ docker-compose.yml에 환경 변수 하드코딩
```

**개선 방안:**

#### AWS Secrets Manager

```yaml
# docker-compose.yml
environment:
  - DB_PASSWORD=${DB_PASSWORD}  # 환경 변수로

# EC2 시작 스크립트
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id feedback-api/db-password \
  --query SecretString --output text)

docker compose up -d
```

**장점:**
- ✅ 중앙화된 비밀 관리
- ✅ 자동 로테이션
- ✅ 감사 로그

**비용:**
```
비밀 1개당 $0.40/월
10개 = $4/월
```

### 5. 모니터링 개선 ⚠️

**현재:**
```
✅ CloudWatch Logs
❌ 메트릭 없음
❌ 대시보드 없음
❌ 알람 없음
```

**개선 방안:**

#### CloudWatch Metrics + Dashboard

```yaml
# Application에서 메트릭 전송
management:
  metrics:
    export:
      cloudwatch:
        enabled: true
        namespace: FeedbackAPI
        step: 1m
```

**수집 메트릭:**
```
- API 응답 시간 (p50, p95, p99)
- 요청 수 (RPS)
- 에러율
- JVM 메모리 사용량
- DB 연결 수
```

**알람 설정:**
```yaml
Alarms:
  - ErrorRate > 5%: CRITICAL
  - ResponseTime > 1000ms: WARNING
  - CPU > 80%: WARNING
```

**비용:**
```
메트릭 10개 × $0.30 = $3/월
알람 10개 × $0.10 = $1/월
총: $4/월
```

### 6. 네트워크 보안 ⚠️

**현재:**
```
Security Group:
  - 8080 포트: 0.0.0.0/0 (전체 공개)
  - SSH: 0.0.0.0/0 (또는 내 IP)
```

**개선 방안:**

#### Option A: ALB 뒤에 숨기기

```
Internet
    ↓
ALB (Public)
    ↓ Security Group: ALB만 허용
EC2 (Private Subnet)
    └─ 8080: ALB Security Group만
```

#### Option B: CloudFront + WAF

```
CloudFront (CDN + DDoS 보호)
    ↓ Custom Header 검증
ALB
    ↓
EC2
```

**추가 보안:**
- ✅ DDoS 보호
- ✅ WAF 룰 (SQL Injection, XSS 차단)
- ✅ Rate Limiting
- ✅ 지역 차단

### 7. 배포 전략 ⚠️

**현재:**
```
Rolling Deployment:
1. 기존 컨테이너 중지
2. 새 컨테이너 시작
→ 40초 다운타임 발생!
```

**개선 방안:**

#### Blue-Green Deployment

```
Blue (현재 버전)  ← 트래픽
Green (새 버전)   ← 배포, 테스트

테스트 성공 후:
Blue              ← 대기
Green             ← 트래픽 전환 (즉시)

문제 발생 시:
Green             ← 차단
Blue              ← 트래픽 복구 (즉시)
```

**구현:**
```yaml
# docker-compose.yml에 두 서비스
services:
  feedback-api-blue:
    image: ghcr.io/.../simple-api:current
    ports: ["8080:8080"]

  feedback-api-green:
    image: ghcr.io/.../simple-api:latest
    ports: ["8081:8080"]

# Nginx로 트래픽 전환
upstream backend {
    server localhost:8080;  # Blue
    # server localhost:8081;  # Green (활성화 시)
}
```

**장점:**
- ✅ 무중단 배포
- ✅ 즉시 롤백
- ✅ 프로덕션 테스트 가능

### 8. 비용 최적화 누락 ⚠️

**현재:**
```
EC2: 24/7 실행
트래픽 없어도 동일 비용
```

**개선 방안:**

#### Spot Instances (개발/테스트)

```
On-Demand: $8/월
Spot: $2-3/월 (70% 절감)

단, 중단 가능성 있음 (프로덕션 부적합)
```

#### Reserved Instances (프로덕션)

```
1년 약정: 40% 할인
3년 약정: 60% 할인

$8/월 → $4.8/월 (1년) 또는 $3.2/월 (3년)
```

---

## 단계별 개선 로드맵

### Phase 1: 즉시 개선 (비용: $0, 시간: 1일)

```
✅ CloudWatch 알람 설정
✅ S3 백업 추가
✅ Secrets Manager로 비밀 관리
✅ Security Group 최소화
```

### Phase 2: 단기 개선 (비용: +$20/월, 시간: 1주)

```
✅ RDS PostgreSQL 마이그레이션
✅ CloudWatch 메트릭 수집
✅ 대시보드 생성
```

### Phase 3: 중기 개선 (비용: +$30/월, 시간: 2주)

```
✅ Auto Scaling Group + ALB
✅ Multi-AZ 배포
✅ Blue-Green Deployment
```

### Phase 4: 장기 개선 (비용: +$50/월, 시간: 1개월)

```
✅ ECS Fargate 마이그레이션
✅ CloudFront + WAF
✅ Multi-Region 배포 (글로벌)
```

---

## 비용 분석

### 현재 비용

```
EC2 t2.micro:           $8/월
CloudWatch Logs:        $0.50/월
GHCR (무료):            $0
GitHub Actions (무료):  $0
────────────────────────────
총:                     $8.50/월
```

### Phase 2 개선 후 비용

```
EC2 t2.micro:           $8/월
RDS db.t3.micro:        $15/월
CloudWatch Logs:        $0.50/월
CloudWatch Metrics:     $4/월
S3 Backups:             $0.50/월
Secrets Manager:        $1/월
────────────────────────────
총:                     $29/월
증가:                   +$20.50/월
```

### Phase 3 개선 후 비용

```
EC2 t2.micro × 2:       $16/월
ALB:                    $16/월
RDS Multi-AZ:           $28/월
CloudWatch:             $5/월
S3:                     $1/월
Secrets Manager:        $2/월
────────────────────────────
총:                     $68/월
증가:                   +$59.50/월
```

### 가성비 분석

```
현재:  $8.50/월, SLA 99%, SPOF 있음
Phase 2: $29/월, SLA 99.5%, DB 안정성 ↑
Phase 3: $68/월, SLA 99.9%, 완전 고가용성

비용 대비 가치:
Phase 2 추천! (3.4배 비용 → 10배 안정성)
```

---

## 우선순위 추천

### 🔴 높음 (즉시)

1. **S3 백업 추가** (비용: $0.50/월)
   - EC2 장애 시 데이터 보호
   - 구현 시간: 30분

2. **CloudWatch 알람 설정** (비용: $1/월)
   - 에러 즉시 감지
   - 구현 시간: 1시간

### 🟡 중간 (1-2주 내)

3. **RDS 마이그레이션** (비용: +$15/월)
   - H2 → PostgreSQL
   - DB 안정성 대폭 향상
   - 구현 시간: 1일

4. **CloudWatch Metrics** (비용: +$4/월)
   - 성능 모니터링
   - 구현 시간: 2시간

### 🟢 낮음 (여유 있을 때)

5. **Auto Scaling + ALB** (비용: +$30/월)
   - 고가용성 확보
   - 구현 시간: 1주

6. **Blue-Green Deployment**
   - 무중단 배포
   - 구현 시간: 2일

---

## 결론

### 현재 잘하고 있는 것 ✅

- CI/CD 자동화
- Docker 컨테이너화
- 스마트한 롤백 전략
- 중앙화된 로그 관리

### 가장 시급한 개선 ⚠️

1. **데이터베이스**: H2 → RDS PostgreSQL
2. **백업**: 로컬 → S3
3. **모니터링**: 알람 추가

### 최종 추천

**즉시 개선 (무료):**
- S3 백업
- CloudWatch 알람

**단기 개선 (+$20/월):**
- RDS 마이그레이션
- 메트릭 수집

**중기 개선 (+$30/월, 여유 있을 때):**
- Auto Scaling
- Multi-AZ

**투자 대비 효과:**
```
$20/월 추가 → 데이터 손실 위험 90% ↓
$30/월 추가 → 가용성 99% → 99.9%
```

현재 인프라는 **학습/개인 프로젝트로는 훌륭**합니다!
프로덕션으로 확장 시 위 개선사항들을 단계적으로 적용하면 됩니다.
