# 🎯 인프라 최소화 분석 (CloudWatch 사용 시)

**질문**: Public 서브넷 3개, EC2 3개 쓰는 이유? CloudWatch로 모니터링 대체하면?

---

## 📊 현재 계획 정확한 구성

### 실제 구성 (STEP_BY_STEP_BUILD.md 기준)

```
┌─────────────────────────────────────────────────────┐
│                VPC (10.0.0.0/16)                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Public Subnet × 2 (3개 아님!) ⭐                    │
│   ├─ Public-AZ-A (10.0.1.0/24)                     │
│   └─ Public-AZ-C (10.0.2.0/24)                     │
│                                                     │
│ Private Subnet × 0 (없음!)                          │
│                                                     │
└─────────────────────────────────────────────────────┘

EC2 인스턴스 × 3:
  ├─ App Instance #1 (Public-AZ-A 또는 AZ-C) ⭐
  ├─ App Instance #2 (Public-AZ-A 또는 AZ-C) ⭐
  └─ MySQL Instance (Public-AZ-A)             ⭐

모니터링:
  - CloudWatch (AWS 기본 제공) ✅
  - Prometheus/Grafana 없음 (EC2 추가 불필요)
```

**정정**: Public Subnet은 **2개**입니다! 3개 아닙니다!

---

## ❓ 왜 Public Subnet 2개?

### ALB (Application Load Balancer) 요구사항 ⭐

```
AWS ALB 최소 요구사항:
  ✅ 최소 2개 가용 영역 (Availability Zone)
  ✅ 각 AZ에 최소 1개 Subnet

이유:
  - 고가용성 (High Availability)
  - 한쪽 AZ 장애 시에도 서비스 지속

┌─────────────────────────────────────────────┐
│ 가용 영역 A (ap-northeast-2a)               │
│   - Public-AZ-A (10.0.1.0/24)              │
│   - ALB 배치됨                              │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ 가용 영역 C (ap-northeast-2c)               │
│   - Public-AZ-C (10.0.2.0/24)              │
│   - ALB 배치됨                              │
└─────────────────────────────────────────────┘

만약 Public Subnet 1개만 만들면?
  ❌ ALB 생성 불가!
  Error: "Load balancer requires at least 2 subnets"
```

### 1개로 줄일 수 없을까?

```
❌ 불가능합니다!

ALB 없이 단일 EC2만:
  - 가능은 함
  - 하지만 이 프로젝트 목표가:
    ✅ ALB를 통한 로드밸런싱
    ✅ Auto Scaling 데모
    → ALB 필수 → Subnet 2개 필수!
```

---

## ❓ 왜 EC2 3개? (CloudWatch 사용 시)

### 현재 구성

```
EC2 × 3:
  1. App Instance #1  (ASG 관리)
  2. App Instance #2  (ASG 관리)
  3. MySQL Instance   (단독)

각각의 이유:
```

### 1. App Instance × 2 (Auto Scaling Group)

```
왜 2개?
  ✅ Auto Scaling 데모
  ✅ 로드 밸런싱 확인
  ✅ 고가용성 (1개 죽어도 서비스 지속)
  ✅ 무중단 배포 테스트 (Instance Refresh)

만약 1개만 쓴다면?
  ⚠️ 로드 밸런싱 의미 없음 (ALB → 1개 인스턴스)
  ⚠️ Auto Scaling 의미 없음 (확장할 곳 없음)
  ⚠️ 배포 중 다운타임 발생 (1개 종료 → 0개 → 서비스 중단!)
  ⚠️ 팀 요구사항 미충족:
     "alb를 통한 오토 스케일링을 하자고 하더라"

→ 최소 2개 필요!
```

### 2. MySQL Instance × 1

```
왜 1개?
  ✅ 데이터베이스 서버 필요
  ✅ App에서 연결 필요

0개로 줄일 수 없을까?
  Option 1: RDS 사용
    - 비용 증가 ($15/월 → $30/월)
    - 팀이 "rds는 비용 문제로 빼보려고"
    → ❌ 불가

  Option 2: App 내장 H2
    - 현재 상태로 돌아감
    - 팀이 "mysql로 바꾸자고"
    → ❌ 불가

  Option 3: App 인스턴스에 MySQL 같이 설치
    - 가능은 함
    - 하지만 안티패턴:
      · App 재시작 시 DB도 재시작
      · Auto Scaling 시 DB 데이터 분산
      · 운영 리스크 높음
    → ❌ 비추천

→ 별도 MySQL EC2 1개 필수!
```

### 3. 모니터링 (Prometheus/Grafana) - 제거 가능! ⭐

```
원래 계획 (3DAY_RAPID_DEPLOYMENT.md):
  - Prometheus EC2 × 1
  - Grafana EC2 × 1
  총 EC2 5개 (App × 2 + MySQL × 1 + Prom × 1 + Graf × 1)

CloudWatch로 대체 시:
  ✅ Prometheus EC2 제거
  ✅ Grafana EC2 제거
  총 EC2 3개 (App × 2 + MySQL × 1)

절약:
  비용: $5/월 (t3.small × 2)
  설정 시간: 3-4시간
```

---

## 📊 최소 구성 vs 현재 구성

### Option A: 절대 최소 (ALB 포기)

```
┌─────────────────────────────────────────┐
│ 불가능한 이유                           │
├─────────────────────────────────────────┤
│ Subnet: 1개 (Public-AZ-A)              │
│ EC2: 2개 (App × 1 + MySQL × 1)         │
│                                         │
│ ❌ ALB 생성 불가 (최소 2개 AZ 필요)    │
│ ❌ Auto Scaling 의미 없음               │
│ ❌ 팀 요구사항 미충족                   │
│ ❌ 고가용성 없음                        │
└─────────────────────────────────────────┘

비용: ~$7 (5일)
→ 하지만 프로젝트 목표 달성 불가!
```

### Option B: ALB 최소 (현재 계획!) ⭐

```
┌─────────────────────────────────────────┐
│ 현재 계획 (CloudWatch 사용)             │
├─────────────────────────────────────────┤
│ Subnet: 2개 (Public-AZ-A, Public-AZ-C) │
│ EC2: 3개 (App × 2 + MySQL × 1)         │
│ 모니터링: CloudWatch (무료)             │
│                                         │
│ ✅ ALB 생성 가능                        │
│ ✅ Auto Scaling 데모 가능               │
│ ✅ 로드 밸런싱 동작 확인                │
│ ✅ 무중단 배포 테스트                   │
│ ✅ 고가용성 (2개 AZ)                    │
│ ✅ 팀 요구사항 충족                     │
└─────────────────────────────────────────┘

비용: ~$11 (5일)
설정 시간: 6-8시간

→ 이게 최적!
```

### Option C: 프로덕션 풀셋 (오버스펙)

```
┌─────────────────────────────────────────┐
│ 불필요하게 많음                         │
├─────────────────────────────────────────┤
│ Subnet: 3개 (Public × 2 + Private × 1) │
│ EC2: 5개 (App × 2 + MySQL × 1          │
│            + Prom × 1 + Graf × 1)      │
│ 모니터링: Prometheus + Grafana          │
│                                         │
│ ⚠️ 5일 데모에는 과함                   │
│ ⚠️ 비용 증가 ($18)                     │
│ ⚠️ 설정 시간 증가 (12-15시간)          │
└─────────────────────────────────────────┘

비용: ~$18 (5일)
설정 시간: 12-15시간

→ 5일 데모에는 오버스펙!
```

---

## 💰 비용 상세 비교 (5일 기준)

### EC2 인스턴스별 비용

```
t3.small: $0.0208/시간
  → 24시간 × 5일 = 120시간
  → $0.0208 × 120 = $2.50/대

App Instance × 2:
  $2.50 × 2 = $5.00

MySQL Instance × 1:
  $2.50 × 1 = $2.50

Prometheus × 1 (제거!):
  $2.50 × 0 = $0 ✅

Grafana × 1 (제거!):
  $2.50 × 0 = $0 ✅

총 EC2 비용: $7.50
```

### 전체 인프라 비용

```
┌──────────────────────────────────────────┐
│ CloudWatch 사용 시 (현재 계획)           │
├──────────────────────────────────────────┤
│ ALB:              $2.70                  │
│ App EC2 × 2:      $5.00                  │
│ MySQL EC2:        $2.50                  │
│ EBS (30GB):       $0.50                  │
│ CloudWatch:       $0 (기본 무료) ✅       │
│ Data transfer:    $1.00                  │
├──────────────────────────────────────────┤
│ 총:              ~$11.70                 │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ Prometheus + Grafana 사용 시             │
├──────────────────────────────────────────┤
│ ALB:              $2.70                  │
│ App EC2 × 2:      $5.00                  │
│ MySQL EC2:        $2.50                  │
│ Prometheus EC2:   $2.50 ⚠️               │
│ Grafana EC2:      $2.50 ⚠️               │
│ EBS (50GB):       $0.80                  │
│ Data transfer:    $1.50                  │
├──────────────────────────────────────────┤
│ 총:              ~$17.50                 │
└──────────────────────────────────────────┘

절약: $5.80 (33%)
```

---

## 🎯 정리: 왜 이 구성인가?

### Public Subnet 2개 이유

```
1️⃣ ALB 최소 요구사항
   → 최소 2개 가용 영역 필요
   → 각 AZ에 1개 Subnet 필요

2️⃣ 고가용성
   → 한쪽 AZ 장애 시에도 서비스 지속

3️⃣ 줄일 수 없음!
   → 1개로 하면 ALB 생성 불가
   → ALB 없으면 팀 요구사항 미충족
```

### EC2 3개 이유 (CloudWatch 사용 시)

```
1️⃣ App Instance × 2
   → Auto Scaling 데모 필수
   → 로드 밸런싱 확인 필수
   → 무중단 배포 테스트
   → 1개로 줄이면 의미 없음!

2️⃣ MySQL Instance × 1
   → 데이터베이스 필수
   → RDS는 비용 문제로 제외 (팀 결정)
   → App 내장 H2는 팀이 거부 (MySQL 원함)

3️⃣ 모니터링 EC2 × 0
   → CloudWatch로 대체! ✅
   → Prometheus/Grafana 불필요
   → $5.80 절약!
```

---

## 📋 최종 권장 구성

### CloudWatch 모니터링 사용 시 (권장!) ⭐

```
VPC:
  └─ Public Subnet × 2 (AZ-A, AZ-C) ⭐

EC2:
  ├─ App Instance × 2 (ASG 관리) ⭐
  └─ MySQL Instance × 1          ⭐

모니터링:
  └─ CloudWatch (무료) ⭐

총:
  - Public Subnet: 2개
  - EC2: 3개
  - 비용: ~$11 (5일)
  - 설정 시간: 6-8시간

이유:
  ✅ ALB 요구사항 충족 (Subnet 2개)
  ✅ Auto Scaling 데모 가능 (App 2개)
  ✅ MySQL 별도 분리 (안정성)
  ✅ 비용 최소화 (모니터링 CloudWatch)
  ✅ 팀 요구사항 모두 충족
```

### CloudWatch 메트릭 예시

```
기본 제공 (무료):
  - CPUUtilization (EC2)
  - NetworkIn/Out (EC2)
  - TargetResponseTime (ALB)
  - HealthyHostCount (Target Group)
  - RequestCount (ALB)

충분한 모니터링:
  ✅ CPU 사용률 모니터링
  ✅ 네트워크 트래픽
  ✅ ALB 응답 시간
  ✅ 헬시 인스턴스 수
  ✅ 요청 수

Prometheus/Grafana와 비교:
  - 대시보드: CloudWatch Dashboard 사용
  - 알림: CloudWatch Alarms 사용
  - 5일 데모에는 충분! ✅
```

---

## 🚫 불가능한 옵션들

### ❌ Public Subnet 1개

```
AWS ALB 생성 시:
  Error: An Application Load Balancer must be attached
         to at least two subnets in different Availability Zones.

→ 물리적으로 불가능!
```

### ❌ App Instance 1개

```
가능은 하지만:
  - Auto Scaling 의미 없음
  - 로드 밸런싱 의미 없음
  - 배포 중 다운타임 발생
  - 팀 요구사항 미충족

→ 프로젝트 목표 달성 불가!
```

### ❌ MySQL 제거

```
대안 없음:
  - RDS: 비용 문제 (팀이 거부)
  - H2: 팀이 MySQL 원함
  - App 내장: 안티패턴

→ 별도 EC2 필수!
```

---

## 🎓 핵심 정리

### Q: Public Subnet 3개 쓰는 이유?

```
A: 3개 아니고 2개입니다! ⭐

이유:
  - ALB 최소 요구사항 (2개 AZ)
  - 줄일 수 없음 (AWS 제약)
```

### Q: EC2 3개 쓰는 이유?

```
A: CloudWatch 사용 시 3개가 최소입니다!

구성:
  - App × 2: Auto Scaling + 로드밸런싱 데모
  - MySQL × 1: 데이터베이스 서버

Prometheus/Grafana 제거:
  - CloudWatch로 대체 ✅
  - $5.80 절약!
```

### Q: 더 줄일 수 없나?

```
A: 불가능합니다!

Subnet 2개 → 1개?
  ❌ ALB 생성 불가 (AWS 제약)

App 2개 → 1개?
  ⚠️ Auto Scaling 의미 없음
  ⚠️ 팀 요구사항 미충족

MySQL 1개 → 0개?
  ❌ RDS는 비용 문제
  ❌ H2는 팀이 거부

→ 현재 구성이 최소입니다!
```

---

**최종 답변**:
- **Public Subnet: 2개** (3개 아님! ALB 최소 요구사항)
- **EC2: 3개** (App × 2 + MySQL × 1, CloudWatch 사용 시)
- **모니터링: CloudWatch** (Prometheus/Grafana 제거 → $5.80 절약!)
- **비용: ~$11** (5일 기준)

**이게 프로젝트 목표 달성 가능한 최소 구성입니다!** ✅
