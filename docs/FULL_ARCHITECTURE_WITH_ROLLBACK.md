# 🏗️ 전체 아키텍처 구조 (롤백 시나리오 포함)

**핵심**: 배포 파이프라인 + 인프라 + 롤백 메커니즘의 완전한 그림

---

## 📊 전체 아키텍처 Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEPLOYMENT PIPELINE                                 │
│                                                                              │
│  Developer                GitHub Actions              Docker Registry       │
│     │                          │                            │                │
│     │ git push                 │                            │                │
│     ├─────────────────────────>│                            │                │
│     │                          │ 1. Build JAR               │                │
│     │                          │ 2. Build Docker Image      │                │
│     │                          │ 3. Tag: latest → previous  │                │
│     │                          │ 4. Push new latest         │                │
│     │                          ├───────────────────────────>│                │
│     │                          │                            │ GHCR:          │
│     │                          │                            │ ├─ latest      │
│     │                          │                            │ ├─ previous    │
│     │                          │                            │ └─ sha-xxxxx   │
│     │                          │                            │                │
│     │                          │ 5. Create Launch           │                │
│     │                          │    Template Version        │                │
│     │                          │    (IMAGE_TAG="latest")    │                │
│     │                          │                            │                │
│     │                          │ 6. Trigger Instance        │                │
│     │                          │    Refresh                 │                │
│     │                          v                            │                │
│     │                    AWS Auto Scaling                   │                │
│     │                          │                            │                │
│     │                          │ 7. Replace instances       │                │
│     │                          │    gradually               │                │
│     │                          v                            │                │
└─────┼──────────────────────────┼────────────────────────────┼────────────────┘
      │                          │                            │
      │                          v                            v
┌─────┼──────────────────────────────────────────────────────────────────────┐
│     │                    AWS INFRASTRUCTURE                                │
│     │                                                                      │
│     │    Internet                                                          │
│     │       │                                                              │
│     │       v                                                              │
│     │  ┌────────────────┐                                                  │
│     │  │ Internet       │                                                  │
│     │  │ Gateway (IGW)  │                                                  │
│     │  └────────┬───────┘                                                  │
│     │           │                                                          │
│     │           v                                                          │
│     │  ┌─────────────────────────────────────────────────────┐             │
│     │  │  Application Load Balancer (ALB)                   │             │
│     │  │  - Health Check: /actuator/health                  │             │
│     │  │  - Target: feedback-tg (Port 8080)                 │             │
│     │  │  - DNS: feedback-alb-xxxxx.elb.amazonaws.com       │             │
│     │  └────────┬────────────────────────────────┬───────────┘             │
│     │           │                                │                         │
│     │  ┌────────┼────────────────────────────────┼───────────────┐         │
│     │  │ Public-AZ-A (10.0.1.0/24)    Public-AZ-C (10.0.2.0/24) │         │
│     │  │        │                                │               │         │
│     │  │   ┌────v─────┐                    ┌────v─────┐         │         │
│     │  │   │ Instance │                    │ Instance │         │         │
│     │  │   │    #1    │                    │    #2    │         │         │
│     │  │   │          │                    │          │         │         │
│     │  │   │ Docker:  │                    │ Docker:  │         │         │
│     │  │   │ latest   │                    │ latest   │         │         │
│     │  │   │ :8080    │                    │ :8080    │         │         │
│     │  │   └────┬─────┘                    └────┬─────┘         │         │
│     │  │        │                                │               │         │
│     │  │        └────────────┬───────────────────┘               │         │
│     │  └─────────────────────┼─────────────────────────────────┘         │
│     │                        │                                            │
│     │                        v                                            │
│     │               ┌─────────────────┐                                   │
│     │               │  MySQL Server   │                                   │
│     │               │  10.0.1.X:3306  │                                   │
│     │               │                 │                                   │
│     │               │  feedbackdb     │                                   │
│     │               │  /data/mysql    │                                   │
│     │               └─────────────────┘                                   │
│     │                                                                      │
└─────┼──────────────────────────────────────────────────────────────────────┘
      │
      │ ROLLBACK Scenario
      │
┌─────v──────────────────────────────────────────────────────────────────────┐
│                         ROLLBACK PIPELINE                                   │
│                                                                             │
│  Operator                GitHub Actions              Docker Registry       │
│     │                          │                            │               │
│     │ Manual trigger           │                            │               │
│     │ (workflow_dispatch)      │                            │               │
│     ├─────────────────────────>│                            │               │
│     │                          │ 1. NO BUILD!               │               │
│     │                          │ 2. Create Launch Template  │               │
│     │                          │    Version with            │               │
│     │                          │    IMAGE_TAG="previous"    │               │
│     │                          │                            │ GHCR:         │
│     │                          │                            │ ├─ latest ✗   │
│     │                          │<───────────────────────────┤ ├─ previous ✓ │
│     │                          │ 3. Pull 'previous' tag     │ └─ sha-xxxxx  │
│     │                          │                            │               │
│     │                          │ 4. Trigger Instance        │               │
│     │                          │    Refresh                 │               │
│     │                          v                            │               │
│     │                    Replace instances with             │               │
│     │                    'previous' image                   │               │
│     │                          │                            │               │
│     │                          v                            │               │
│     │                    ┌─────────┐                        │               │
│     │                    │Instance │                        │               │
│     │                    │Docker:  │                        │               │
│     │                    │previous │ ← 이전 버전으로 복구!   │               │
│     │                    └─────────┘                        │               │
│     │                                                       │               │
└─────┴───────────────────────────────────────────────────────┴───────────────┘
```

---

## 🔄 배포 프로세스 상세 (정상 배포)

### Phase 1: 코드 변경 및 이미지 빌드

```
┌──────────────────────────────────────────────────────────────┐
│ Step 1-4: GitHub Actions (deploy-asg.yml)                   │
└──────────────────────────────────────────────────────────────┘

1. Developer가 코드 변경 후 git push
   └─> GitHub Actions 트리거 (workflow_dispatch)

2. Gradle 빌드
   ├─> ./gradlew clean build
   └─> build/libs/simple-api-0.0.1-SNAPSHOT.jar 생성

3. 현재 'latest' 이미지를 'previous'로 태그 변경 ⭐
   ├─> docker pull ghcr.io/johnhuh619/simple-api:latest
   ├─> docker tag latest → previous
   └─> docker push ghcr.io/johnhuh619/simple-api:previous

4. 새 Docker 이미지 빌드 및 푸시
   ├─> docker build -t ghcr.io/johnhuh619/simple-api:latest
   ├─> docker tag latest → sha-abcd1234
   └─> docker push (latest + sha-abcd1234)

결과:
┌─────────────────────────────────────────┐
│ GitHub Container Registry (GHCR)        │
├─────────────────────────────────────────┤
│ ✅ latest      ← NEW (방금 빌드한 버전)  │
│ ✅ previous    ← OLD (이전 latest)       │
│ ✅ sha-abcd1234 ← NEW (Git SHA 태그)    │
│ ✅ sha-xyz9876  ← OLD                    │
└─────────────────────────────────────────┘
```

### Phase 2: Launch Template 버전 생성

```
┌──────────────────────────────────────────────────────────────┐
│ Step 5: Create Launch Template Version                      │
└──────────────────────────────────────────────────────────────┘

AWS API 호출:
  aws ec2 create-launch-template-version \
    --launch-template-name feedback-app-template \
    --source-version '$Latest' \
    --launch-template-data '{
      "UserData": "... IMAGE_TAG=\"latest\" ..."  ⭐
    }'

결과:
┌─────────────────────────────────────────────────────┐
│ Launch Template: feedback-app-template              │
├─────────────────────────────────────────────────────┤
│ Version 1 (OLD): IMAGE_TAG="latest"   ← 배포 전    │
│ Version 2 (NEW): IMAGE_TAG="latest"   ← 배포 후 ✅  │
│                                                     │
│ Default Version: 2 ← ASG가 사용                     │
└─────────────────────────────────────────────────────┘

주의: User Data는 Base64 인코딩되어 저장됨
```

### Phase 3: Instance Refresh (무중단 배포)

```
┌──────────────────────────────────────────────────────────────┐
│ Step 6-7: Instance Refresh                                  │
└──────────────────────────────────────────────────────────────┘

AWS API 호출:
  aws autoscaling start-instance-refresh \
    --auto-scaling-group-name feedback-asg \
    --preferences '{
      "MinHealthyPercentage": 50,     ← 최소 50% 헬시 유지
      "InstanceWarmup": 300,           ← 5분 워밍업
      "CheckpointPercentages": [50, 100]
    }'

프로세스:
┌────────────────────────────────────────────────────────┐
│ t=0: 기존 인스턴스                                      │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance1│ │Instance2│  (둘 다 OLD 버전)           │
│   │ healthy │ │ healthy │                             │
│   └─────────┘ └─────────┘                             │
│                                                        │
│ t=1min: 첫 번째 인스턴스 교체 시작                     │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐                │
│   │Instance1│ │Instance2│ │Instance3│                │
│   │ healthy │ │ healthy │ │starting │ (NEW 버전)     │
│   └─────────┘ └─────────┘ └─────────┘                │
│                                                        │
│ t=6min: 첫 번째 교체 완료 (Warmup 5분 대기)            │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance2│ │Instance3│  (50% 완료)                 │
│   │ healthy │ │ healthy │                             │
│   └─────────┘ └─────────┘                             │
│                          ↑ NEW                         │
│ ❌ Instance1 종료됨                                     │
│                                                        │
│ t=7min: 두 번째 인스턴스 교체 시작                     │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐                │
│   │Instance2│ │Instance3│ │Instance4│                │
│   │ healthy │ │ healthy │ │starting │ (NEW 버전)     │
│   └─────────┘ └─────────┘ └─────────┘                │
│              ↑ OLD        ↑ NEW                        │
│                                                        │
│ t=12min: 전체 완료                                     │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance3│ │Instance4│  (100% 완료) ✅              │
│   │ healthy │ │ healthy │                             │
│   └─────────┘ └─────────┘                             │
│              ↑ 모두 NEW 버전                           │
│ ❌ Instance2 종료됨                                     │
└────────────────────────────────────────────────────────┘

핵심:
- ALB가 계속 트래픽 라우팅 (무중단!)
- 헬스 체크 실패 시 자동으로 롤백
- 최소 50% healthy 보장 (MinHealthyPercentage)
```

---

## 🔙 롤백 프로세스 상세

### Scenario: 배포 후 버그 발견!

```
문제 상황:
  - 새 버전(latest)을 배포했는데 API가 500 에러 반환
  - 사용자 불만 접수
  - 긴급하게 이전 버전으로 복구 필요!

해결: 롤백 워크플로우 실행!
```

### Phase 1: 롤백 트리거 (수동)

```
┌──────────────────────────────────────────────────────────────┐
│ Operator Action                                              │
└──────────────────────────────────────────────────────────────┘

1. GitHub → Actions → "Rollback ASG Deployment"
2. Run workflow 클릭
3. Confirm 입력: "rollback"
4. Run workflow 버튼

⚠️ 중요: 롤백은 의도적인 작업이므로 확인 필요!
```

### Phase 2: Rollback Launch Template 버전 생성

```
┌──────────────────────────────────────────────────────────────┐
│ rollback-asg.yml Workflow                                    │
└──────────────────────────────────────────────────────────────┘

AWS API 호출:
  aws ec2 create-launch-template-version \
    --launch-template-name feedback-app-template \
    --launch-template-data '{
      "UserData": "... IMAGE_TAG=\"previous\" ..."  ⭐
    }'

결과:
┌─────────────────────────────────────────────────────┐
│ Launch Template: feedback-app-template              │
├─────────────────────────────────────────────────────┤
│ Version 1: IMAGE_TAG="latest"   (초기 버전)         │
│ Version 2: IMAGE_TAG="latest"   (배포 후 - 버그!)   │
│ Version 3: IMAGE_TAG="previous" (롤백용) ✅          │
│                                                     │
│ Default Version: 3 ← ASG가 이제 이걸 사용!          │
└─────────────────────────────────────────────────────┘

핵심 차이점:
  배포:   IMAGE_TAG="latest"   ← GHCR의 latest 이미지 pull
  롤백:   IMAGE_TAG="previous" ← GHCR의 previous 이미지 pull ⭐
```

### Phase 3: 롤백 Instance Refresh

```
┌────────────────────────────────────────────────────────┐
│ t=0: 현재 상태 (버그 있는 버전)                        │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance3│ │Instance4│                             │
│   │latest ✗ │ │latest ✗ │ ← 500 에러 발생!            │
│   └─────────┘ └─────────┘                             │
│                                                        │
│ t=1min: 롤백 시작                                      │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐                │
│   │Instance3│ │Instance4│ │Instance5│                │
│   │latest ✗ │ │latest ✗ │ │starting │                │
│   └─────────┘ └─────────┘ └─────────┘                │
│                             ↑ previous ✓               │
│                                                        │
│ t=6min: 첫 번째 복구 완료                              │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance4│ │Instance5│                             │
│   │latest ✗ │ │previous ✓│ ← 정상 동작!               │
│   └─────────┘ └─────────┘                             │
│ ❌ Instance3 종료                                       │
│                                                        │
│ t=12min: 롤백 완료! ✅                                  │
│   ┌─────────┐ ┌─────────┐                             │
│   │Instance5│ │Instance6│                             │
│   │previous ✓│ │previous ✓│ ← 모두 정상!              │
│   └─────────┘ └─────────┘                             │
│ ❌ Instance4 종료                                       │
│                                                        │
│ 결과: 5-10분 내 이전 버전으로 완전 복구!               │
└────────────────────────────────────────────────────────┘
```

---

## 🎭 Docker Image Tag 전략

### 배포 전후 이미지 상태

```
═══════════════════════════════════════════════════════════════
시나리오 1: 초기 상태
═══════════════════════════════════════════════════════════════
GHCR:
  latest   → v1.0 (현재 운영 중)

Running Instances:
  Instance1: latest (v1.0)
  Instance2: latest (v1.0)

═══════════════════════════════════════════════════════════════
시나리오 2: 첫 배포 (v1.1 배포)
═══════════════════════════════════════════════════════════════
GHCR (배포 중):
  latest   → v1.1  ⭐ 새로 푸시됨
  previous → v1.0  ⭐ latest를 previous로 태그 변경

Running Instances (Instance Refresh 진행 중):
  Instance1: latest (v1.0) ← 곧 종료될 예정
  Instance2: latest (v1.0) ← 곧 종료될 예정
  Instance3: latest (v1.1) ← 새로 시작! (User Data에서 pull)
  Instance4: latest (v1.1) ← 새로 시작!

Running Instances (배포 완료 후):
  Instance3: latest (v1.1) ✅
  Instance4: latest (v1.1) ✅

═══════════════════════════════════════════════════════════════
시나리오 3: 버그 발견! 롤백 필요
═══════════════════════════════════════════════════════════════
GHCR (변경 없음!):
  latest   → v1.1  (버그 있음 ✗)
  previous → v1.0  (안정 버전 ✓)

Running Instances (롤백 전):
  Instance3: latest (v1.1) ✗
  Instance4: latest (v1.1) ✗

Rollback Launch Template Version 3 생성:
  IMAGE_TAG="previous"  ⭐

Running Instances (Instance Refresh 진행 중):
  Instance3: latest (v1.1) ✗ ← 곧 종료
  Instance4: latest (v1.1) ✗ ← 곧 종료
  Instance5: previous (v1.0) ✓ ← 복구됨!
  Instance6: previous (v1.0) ✓ ← 복구됨!

Running Instances (롤백 완료):
  Instance5: previous (v1.0) ✅
  Instance6: previous (v1.0) ✅

═══════════════════════════════════════════════════════════════
시나리오 4: 버그 수정 후 재배포 (v1.2)
═══════════════════════════════════════════════════════════════
GHCR (재배포):
  latest   → v1.2  ⭐ 버그 수정 버전
  previous → v1.1  ⭐ (이전 latest, 버그 있던 버전)

Running Instances (배포 후):
  Instance7: latest (v1.2) ✅ 버그 수정됨!
  Instance8: latest (v1.2) ✅

⚠️ 주의: previous는 이제 v1.1 (버그 버전)
   만약 또 롤백하면 버그 버전으로 돌아감!
```

---

## 🚨 자동 복구 메커니즘

### Health Check 기반 자동 롤백

```
┌────────────────────────────────────────────────────────┐
│ Instance Refresh 중 헬스 체크 실패 시                  │
└────────────────────────────────────────────────────────┘

시나리오: 새 버전이 시작 실패하는 경우

t=0: 배포 시작
  Instance1 (old): healthy ✓
  Instance2 (old): healthy ✓

t=2min: 첫 번째 교체 시도
  Instance1 (old): healthy ✓
  Instance2 (old): healthy ✓
  Instance3 (new): starting...

t=7min: 헬스 체크 실패!
  Instance1 (old): healthy ✓
  Instance2 (old): healthy ✓
  Instance3 (new): unhealthy ✗  ← 5번 연속 실패

⚠️ AWS Auto Scaling 자동 판단:
  → Instance3 종료
  → Instance Refresh 중단
  → 기존 인스턴스 유지 (자동 롤백!)

결과:
  Instance1 (old): healthy ✓  ← 그대로 유지!
  Instance2 (old): healthy ✓  ← 그대로 유지!

✅ 자동으로 안전한 상태 유지!
```

### ALB Health Check 설정

```
Target Group: feedback-tg
├─ Protocol: HTTP
├─ Port: 8080
├─ Path: /actuator/health
├─ Interval: 30초
├─ Timeout: 5초
├─ Healthy threshold: 2회 연속 성공
├─ Unhealthy threshold: 2회 연속 실패
└─ Success codes: 200

헬스 체크 흐름:
1. ALB가 30초마다 GET /actuator/health 요청
2. 5초 내 응답 없으면 실패
3. 2회 연속 실패 → unhealthy 상태
4. ASG가 unhealthy 인스턴스 종료
5. 새 인스턴스 자동 시작
```

---

## 📦 데이터 흐름 (전체 Request/Response)

### 정상 흐름

```
사용자 요청 → 응답까지의 전체 경로:

1. Client
   │
   │ HTTP GET http://feedback-alb-xxxxx.elb.amazonaws.com/api/feedbacks
   │
   v
2. Internet Gateway (IGW)
   │ VPC 진입점
   v
3. Application Load Balancer (ALB)
   │
   ├─ 헬스 체크: Instance1 (healthy), Instance2 (healthy)
   ├─ 로드 밸런싱 알고리즘: Round Robin
   │
   ├─> 50% 트래픽 → Instance1 (10.0.1.10:8080)
   │                  │
   │                  │ Spring Boot Application
   │                  │   └─> FeedbackController
   │                  │         └─> FeedbackService
   │                  │               └─> FeedbackRepository (JPA)
   │                  │                     │
   │                  v                     v
   │              MySQL (10.0.1.234:3306)
   │                  │
   │                  │ SELECT * FROM feedbacks;
   │                  │
   │                  v
   │              [{"id":1,"content":"..."}]
   │                  │
   │                  v
   │              Response: 200 OK
   │                  │
   │                  v
   └─< ALB <─────────┘
        │
        v
   Client receives JSON
```

### 배포 중 트래픽 흐름 (무중단!)

```
배포 시작 (t=0):
  ALB Target Group
  ├─ Instance1 (old): healthy → 50% 트래픽 ✓
  └─ Instance2 (old): healthy → 50% 트래픽 ✓

배포 진행 중 (t=5min):
  ALB Target Group
  ├─ Instance1 (old): healthy → 33% 트래픽 ✓
  ├─ Instance2 (old): healthy → 33% 트래픽 ✓
  └─ Instance3 (new): healthy → 34% 트래픽 ✓
                      ↑ 5분 워밍업 후 트래픽 받기 시작!

배포 완료 (t=12min):
  ALB Target Group
  ├─ Instance3 (new): healthy → 50% 트래픽 ✓
  └─ Instance4 (new): healthy → 50% 트래픽 ✓

✅ 사용자는 배포 중에도 계속 서비스 이용 가능! (무중단)
```

---

## 🔐 Security Groups 트래픽 제어

```
┌─────────────────────────────────────────────────────────┐
│                    Security Architecture                 │
└─────────────────────────────────────────────────────────┘

Internet (0.0.0.0/0)
   │
   │ HTTP:80, HTTPS:443
   v
┌──────────────────┐
│ alb-sg           │
│ ┌──────────────┐ │
│ │ Inbound:     │ │
│ │ 80 ← 0.0.0.0 │ │
│ │ 443 ← 0.0.0.0│ │
│ └──────────────┘ │
└────────┬─────────┘
         │ :8080
         v
┌──────────────────┐
│ app-sg           │
│ ┌──────────────┐ │
│ │ Inbound:     │ │
│ │ 8080 ← alb-sg│ │ ⭐ ALB에서만 접근 가능
│ │ 9100 ← 0.0.0.0│ │ (Node Exporter)
│ │ 22 ← 0.0.0.0 │ │ (SSH, 디버깅용)
│ └──────────────┘ │
└────────┬─────────┘
         │ :3306
         v
┌──────────────────┐
│ db-sg            │
│ ┌──────────────┐ │
│ │ Inbound:     │ │
│ │ 3306 ← app-sg│ │ ⭐ App에서만 접근 가능
│ │ 22 ← 0.0.0.0 │ │ (SSH, 관리용)
│ └──────────────┘ │
└──────────────────┘
   MySQL Server

보안 계층:
1. Internet → ALB만 공개 (80, 443)
2. ALB → App (8080만 허용)
3. App → MySQL (3306만 허용)
4. 외부 → App/MySQL 직접 접근 불가! ✓
```

---

## 🎯 핵심 포인트 정리

### 1. 무중단 배포 (Zero Downtime)

```
✅ ALB가 헬시한 인스턴스에만 트래픽 전송
✅ MinHealthyPercentage: 50% (최소 절반은 항상 healthy)
✅ Instance Refresh: 점진적 교체 (한 번에 하나씩)
✅ InstanceWarmup: 5분 (새 인스턴스 준비 시간)
```

### 2. 빠른 롤백 (5-10분)

```
✅ Docker Image Tag 전략 (latest/previous)
✅ 빌드 불필요! (이미 GHCR에 previous 존재)
✅ Launch Template Version만 변경
✅ Instance Refresh로 자동 교체
```

### 3. 자동 복구

```
✅ Health Check 실패 → 자동 인스턴스 교체
✅ Instance Refresh 실패 → 자동 롤백 (기존 인스턴스 유지)
✅ Auto Scaling → CPU 70% 이상 시 자동 확장
```

### 4. 데이터 안정성

```
✅ MySQL은 별도 EC2 (ASG 영향 없음)
✅ EBS 볼륨 (/data/mysql) - 영구 저장
⚠️ MySQL 롤백은 별도 수동 작업 필요 (DB 백업 복원)
```

---

## 📊 타임라인 비교

### 배포 타임라인

```
정상 배포 (deploy-asg.yml):

00:00  │ Git push
       │
00:01  ├─> GitHub Actions 시작
       │     ├─ Gradle build (2분)
       │     ├─ Docker build (2분)
       │     └─ Docker push (1분)
       │
00:06  ├─> Launch Template 버전 생성 (30초)
       │
00:07  ├─> Instance Refresh 시작
       │     ├─ Instance3 시작 (3분)
       │     ├─ Warmup (5분)
       │     ├─ Instance1 종료 (1분)
       │     ├─ Instance4 시작 (3분)
       │     ├─ Warmup (5분)
       │     └─ Instance2 종료 (1분)
       │
00:25  └─> 배포 완료 ✅

총 소요 시간: ~25분
```

### 롤백 타임라인

```
긴급 롤백 (rollback-asg.yml):

00:00  │ Manual trigger (GitHub Actions)
       │
00:01  ├─> 빌드 없음! ⭐ (시간 절약)
       │     └─ Launch Template Version 생성 (30초)
       │
00:02  ├─> Instance Refresh 시작
       │     ├─ Instance5 시작 (3분, 'previous' pull)
       │     ├─ Warmup (5분)
       │     ├─ Instance3 종료 (1분)
       │     ├─ Instance6 시작 (3분)
       │     ├─ Warmup (5분)
       │     └─ Instance4 종료 (1분)
       │
00:20  └─> 롤백 완료 ✅

총 소요 시간: ~20분 (빌드 없어서 5분 빠름!)
```

---

## 🎬 실제 사용 시나리오

### Scenario 1: 정상 배포

```
Day 1:
  08:00 - 개발자가 새 기능 개발 완료
  08:30 - git push origin convert
  08:31 - GitHub Actions 자동 트리거
  08:56 - 배포 완료, ALB DNS로 접근하니 새 기능 동작 ✅
  09:00 - 팀원들에게 공유

Result: 성공! 🎉
```

### Scenario 2: 버그 발견 → 롤백

```
Day 2:
  10:00 - 새 버전 배포 (v2.0)
  10:25 - 배포 완료
  10:30 - 사용자가 500 에러 제보!
  10:35 - 로그 확인, NullPointerException 발견
  10:36 - 긴급 롤백 결정!
  10:37 - GitHub Actions → Rollback ASG 실행
  10:57 - 롤백 완료, 이전 버전(v1.9)으로 복구 ✅
  11:00 - 500 에러 사라짐
  11:30 - 버그 수정 후 재배포 (v2.1)
  11:55 - 재배포 완료, 정상 동작 확인 ✅

Result: 20분 만에 복구! 👍
```

### Scenario 3: Auto Scaling 동작

```
Day 3:
  14:00 - 평소 트래픽 (CPU 30%)
         Instance3, Instance4만 운영 중

  15:00 - 이벤트 시작! 트래픽 급증
  15:05 - CPU 80% 도달
  15:10 - Auto Scaling 트리거 ⭐
         Desired: 2 → 3
         Instance5 시작!

  15:15 - Instance5 healthy 상태
         트래픽 3개 인스턴스로 분산
         CPU 50%로 안정화

  16:00 - 이벤트 종료, 트래픽 감소
  16:30 - CPU 40%로 하락
  16:45 - 10분간 낮은 CPU 유지
  16:50 - Auto Scaling 스케일인 트리거
         Desired: 3 → 2
         Instance5 종료!

Result: 자동 확장/축소 성공! 🎯
```

---

## 🏆 이 아키텍처의 장점

```
✅ 무중단 배포       → 사용자 영향 최소화
✅ 빠른 롤백        → 장애 시 20분 내 복구
✅ 자동 복구        → 헬스 체크 기반 자가 치유
✅ 자동 확장        → 트래픽 변화에 대응
✅ 고가용성         → 2개 AZ에 분산
✅ 로드 밸런싱      → 트래픽 균등 분배
✅ 영구 데이터 저장  → MySQL on EBS
✅ 비용 효율적      → 5일 기준 $12 (저렴!)
```

---

## 🚨 주의사항

### 1. Database 롤백 별도 필요

```
⚠️ Application 롤백 != Database 롤백

Application 롤백:
  - Docker 이미지만 previous로 변경
  - 5-10분 내 완료

Database 스키마 변경이 있었다면:
  - 별도 DB 백업 복원 필요!
  - mysqldump로 백업본 복원
  - 수동 작업 필요

권장:
  - 배포 전 DB 백업
  - Flyway/Liquibase로 마이그레이션 관리
```

### 2. previous 태그 관리

```
⚠️ previous는 항상 바로 이전 버전만 유지

v1.0 → v1.1 배포:
  latest = v1.1
  previous = v1.0 ✓

v1.1 → v1.2 배포:
  latest = v1.2
  previous = v1.1 ⚠️ (v1.0 사라짐!)

해결책:
  - SHA 태그도 함께 유지 (sha-xxxxx)
  - 필요시 SHA 태그로 롤백 가능
  - 중요 버전은 별도 태그 (v1.0-stable)
```

### 3. 동시 배포 금지

```
⚠️ Instance Refresh 진행 중에는 새 배포 금지!

이유:
  - 현재 교체 중인데 또 교체하면 충돌
  - MinHealthyPercentage 위반 가능

확인 방법:
  aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name feedback-asg

  Status: InProgress → 대기 필요!
  Status: Successful → 배포 가능!
```

---

## 🎓 학습 포인트

```
이 아키텍처를 통해 배운 개념:

1. Infrastructure as Code (IaC)
   └─> Launch Template으로 인스턴스 정의

2. Immutable Infrastructure
   └─> 인스턴스 수정 ✗, 새로 만들기 ✓

3. Blue-Green Deployment (변형)
   └─> Instance Refresh로 점진적 교체

4. Health Check 기반 자동 복구
   └─> Self-healing infrastructure

5. Container Orchestration (간소화 버전)
   └─> Docker + ASG (Kubernetes 대체)

6. GitOps (부분)
   └─> GitHub Actions로 배포 자동화

7. 로드 밸런싱 + 오토 스케일링
   └─> 클라우드 네이티브 패턴
```

---

**이것이 롤백 시나리오까지 포함한 완전한 아키텍처입니다!** 🎉

핵심은:
- **배포**: latest 이미지로 Instance Refresh
- **롤백**: previous 이미지로 Instance Refresh
- **무중단**: ALB가 헬시한 인스턴스에만 트래픽 전송
- **자동 복구**: 헬스 체크 실패 시 자동 인스턴스 교체

**5일간 운영 후 삭제하면 약 $12 비용!** 💰
