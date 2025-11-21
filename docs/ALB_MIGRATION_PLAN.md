# ALB 도입 계획서

## 현재 상태 (As-Is)
- ✅ CloudFront + S3: 프론트엔드 자동 배포
- ✅ EC2 단일 인스턴스: 백엔드 자동 배포
- ✅ RDS MySQL: 데이터베이스
- ✅ GitHub Actions: CI/CD 파이프라인

## 목표 상태 (To-Be)
- ✅ CloudFront + S3: 프론트엔드 (변경 없음)
- 🆕 ALB + Auto Scaling Group: 백엔드 고가용성
- ✅ RDS MySQL: 데이터베이스 (변경 없음)
- 🔄 GitHub Actions: 배포 방식 변경

---

## 1. 인프라 변경 사항

### 1.1 새로 생성할 AWS 리소스

#### A. Application Load Balancer (ALB)
```
이름: feedback-api-alb
리전: ap-northeast-2
스키마: internet-facing (외부 접근)
리스너:
  - HTTP:80 → Target Group (feedback-api-tg)
  - (선택) HTTPS:443 → Target Group (SSL 인증서 필요)
```

**왜 필요한가?**
- 여러 EC2 인스턴스에 트래픽 분산
- Health Check로 비정상 인스턴스 제외
- CloudFront Origin으로 사용 (현재 EC2 Public IP 대체)

#### B. Target Group
```
이름: feedback-api-tg
프로토콜: HTTP
포트: 8080
VPC: 기존 EC2와 동일
Health Check:
  - Path: /actuator/health
  - Interval: 30초
  - Timeout: 5초
  - Healthy threshold: 2
  - Unhealthy threshold: 2
```

**왜 필요한가?**
- ALB가 트래픽을 보낼 EC2 인스턴스 그룹 정의
- Health Check로 정상 인스턴스만 트래픽 수신

#### C. Launch Template
```
이름: feedback-api-launch-template
AMI: Amazon Linux 2023
인스턴스 타입: t3.micro (또는 t3.small)
키 페어: 기존 키 사용
보안 그룹: feedback-api-sg
User Data: (EC2 초기화 스크립트)
  - Docker 설치
  - Docker Compose 설치
  - GHCR 로그인
  - 컨테이너 실행
```

**왜 필요한가?**
- Auto Scaling 시 새 EC2 인스턴스를 동일하게 구성
- 수동 설정 없이 자동으로 애플리케이션 실행

#### D. Auto Scaling Group (ASG)
```
이름: feedback-api-asg
최소 용량: 2 (고가용성)
희망 용량: 2
최대 용량: 4 (트래픽 폭증 대비)
가용 영역: ap-northeast-2a, ap-northeast-2c (Multi-AZ)
Launch Template: feedback-api-launch-template
Target Group: feedback-api-tg

스케일링 정책:
  - CPU 사용률 > 70% → 인스턴스 추가
  - CPU 사용률 < 30% → 인스턴스 제거
```

**왜 필요한가?**
- 트래픽에 따라 EC2 자동 증감
- 항상 최소 2대 유지로 고가용성 보장

---

### 1.2 수정할 AWS 리소스

#### A. CloudFront Distribution
**변경 사항:**
```yaml
Origin 설정 변경:
  현재:
    - /api/* → EC2 Public IP:8080

  변경 후:
    - /api/* → ALB DNS (feedback-api-alb-xxxxx.ap-northeast-2.elb.amazonaws.com)
```

**왜 변경하나?**
- EC2 Public IP는 인스턴스 교체 시 변경됨
- ALB DNS는 고정되어 있고, 자동으로 정상 인스턴스로 라우팅

#### B. Security Group 구조 변경

**현재:**
```
EC2 Security Group (launch-wizard-2):
  - Inbound: 8080 (0.0.0.0/0)  ← 전체 공개
  - Outbound: All
```

**변경 후:**
```
1. ALB Security Group (feedback-api-alb-sg):
   - Inbound:
     * 80 (HTTP) from 0.0.0.0/0
     * 443 (HTTPS) from 0.0.0.0/0
   - Outbound: All

2. EC2 Security Group (feedback-api-ec2-sg):
   - Inbound:
     * 8080 from ALB Security Group ONLY  ← 보안 강화!
     * 22 (SSH) from My IP (관리용)
   - Outbound: All

3. RDS Security Group (변경 없음):
   - Inbound:
     * 3306 from EC2 Security Group
```

**왜 변경하나?**
- EC2를 외부에서 직접 접근 불가하게 막음 (보안 강화)
- ALB를 통해서만 트래픽 수신

---

## 2. 배포 방식 변경

### 2.1 현재 배포 방식 (deploy.yml)

```yaml
배포 흐름:
1. Gradle 빌드 → JAR 생성
2. Docker 이미지 빌드 → GHCR push
3. EC2 1대에 SSH 접속
4. docker-compose로 컨테이너 재시작
5. Health check 실패 시 롤백
```

**문제점:**
- EC2 1대만 업데이트 (다른 인스턴스는 수동 업데이트 필요)
- SSH 접속 방식은 Auto Scaling 환경에 부적합

### 2.2 ALB 환경 배포 방식 (deploy-asg.yml)

```yaml
배포 흐름:
1. Gradle 빌드 → JAR 생성
2. Docker 이미지 빌드 → GHCR push (태그: SHA + latest)
3. Launch Template 새 버전 생성:
   - User Data에 최신 이미지 태그 포함
4. Auto Scaling Group Instance Refresh 시작:
   - 기존 인스턴스 하나씩 교체
   - 새 인스턴스 Health Check 통과 확인
   - 이전 인스턴스 종료
   - 반복 (Rolling Update)
5. 모든 인스턴스 교체 완료
```

**장점:**
- 무중단 배포 (항상 최소 1대 이상 실행 중)
- SSH 접속 불필요
- 모든 인스턴스 자동 업데이트

**Instance Refresh 설정:**
```yaml
MinHealthyPercentage: 50  # 최소 50% 인스턴스는 항상 실행 중
InstanceWarmup: 60초      # 새 인스턴스 준비 시간
```

**예시 (인스턴스 2대 → 2대 업데이트):**
```
시간: 0초
  EC2-old-1 (실행 중) ✅
  EC2-old-2 (실행 중) ✅

시간: 30초
  EC2-old-1 (종료 중)
  EC2-old-2 (실행 중) ✅
  EC2-new-1 (시작 중) ⏳

시간: 60초
  EC2-old-2 (실행 중) ✅
  EC2-new-1 (실행 중) ✅ ← Health Check 통과

시간: 90초
  EC2-old-2 (종료 중)
  EC2-new-1 (실행 중) ✅
  EC2-new-2 (시작 중) ⏳

시간: 120초
  EC2-new-1 (실행 중) ✅
  EC2-new-2 (실행 중) ✅ ← 배포 완료!
```

---

## 3. 코드/설정 변경 사항

### 3.1 GitHub Actions 워크플로우

#### 현재 사용 중:
- ✅ `deploy.yml` - EC2 단일 인스턴스 배포
- ✅ `deploy-frontend-cloudfront.yml` - 프론트엔드 배포
- ❌ `deploy-asg.yml` - **사용 안 함** (ALB/ASG 없음)

#### ALB 도입 후:
- ❌ `deploy.yml` - **비활성화** (또는 삭제)
- ✅ `deploy-frontend-cloudfront.yml` - 변경 없음
- ✅ `deploy-asg.yml` - **활성화** (메인 배포 방식)

### 3.2 docker-compose.yml 변경

**현재:**
```yaml
# EC2에서 직접 실행
services:
  feedback-api:
    image: ghcr.io/johnhuh619/simple-api:latest
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=...
      - DB_PASSWORD=...
```

**변경 후:**
```yaml
# Launch Template User Data에서 실행
# 환경 변수는 GitHub Secrets에서 주입
services:
  feedback-api:
    image: ghcr.io/johnhuh619/simple-api:latest
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=${DB_HOST}
      - DB_PASSWORD=${DB_PASSWORD}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

**주의:** User Data에서 환경 변수를 어떻게 주입할지 고민 필요
- 방법 1: AWS Systems Manager Parameter Store 사용
- 방법 2: AWS Secrets Manager 사용
- 방법 3: Launch Template에 직접 하드코딩 (비권장)

---

## 4. 배포 흐름 비교

### 현재 (EC2 단일 인스턴스)

```
개발자 코드 수정
  ↓ git push
GitHub Actions (deploy.yml) 실행
  ↓
1. Gradle 빌드
2. Docker 이미지 생성 → GHCR
3. EC2에 SSH 접속
4. docker-compose up -d
5. Health check
  ↓
배포 완료 (30초 다운타임 발생)
```

**다운타임:** ✅ 30초 정도 (컨테이너 재시작 시간)

### ALB 환경 (Auto Scaling Group)

```
개발자 코드 수정
  ↓ git push
GitHub Actions (deploy-asg.yml) 실행
  ↓
1. Gradle 빌드
2. Docker 이미지 생성 → GHCR
3. Launch Template 새 버전 생성
4. Instance Refresh 시작
  ↓
Auto Scaling Group이 자동으로:
  - 새 EC2 인스턴스 생성
  - Health Check 통과 대기
  - 이전 EC2 인스턴스 종료
  - 반복
  ↓
배포 완료 (무중단)
```

**다운타임:** ❌ 없음 (Rolling Update)

---

## 5. 비용 영향

### 현재 비용
- EC2 t3.micro 1대: ~$7/월
- RDS db.t3.micro 1대: ~$15/월
- CloudFront + S3: ~$1/월 (트래픽 적음)
- **총합: ~$23/월**

### ALB 도입 후 비용
- ALB: ~$16/월 (시간당 $0.0225)
- EC2 t3.micro 2대: ~$14/월 (최소 2대)
- RDS db.t3.micro 1대: ~$15/월
- CloudFront + S3: ~$1/월
- **총합: ~$46/월** (약 2배 증가)

**비용 절감 방안:**
- 개발/테스트 환경: ASG 최소 용량 1대로 설정
- 프로덕션 환경: 최소 2대 유지
- 야간/주말: Scheduled Scaling으로 인스턴스 축소

---

## 6. 마이그레이션 단계별 계획

### Phase 1: 준비 (1일)
- [ ] ALB, Target Group 생성
- [ ] Launch Template 생성
- [ ] Auto Scaling Group 생성 (최소 2대)
- [ ] Security Group 재구성
- [ ] User Data 스크립트 작성 및 테스트

### Phase 2: 테스트 (1일)
- [ ] 새 ASG 인스턴스가 정상 실행되는지 확인
- [ ] ALB Health Check 통과 확인
- [ ] CloudFront Origin을 ALB로 변경
- [ ] API 요청 정상 작동 확인
- [ ] deploy-asg.yml 워크플로우 테스트

### Phase 3: 전환 (1일)
- [ ] deploy.yml 비활성화
- [ ] deploy-asg.yml 활성화
- [ ] 실제 배포 테스트
- [ ] Instance Refresh 동작 확인
- [ ] 무중단 배포 검증

### Phase 4: 정리 (0.5일)
- [ ] 기존 단일 EC2 인스턴스 종료
- [ ] 불필요한 Security Group 정리
- [ ] 문서 업데이트 (README, WORKFLOWS_GUIDE 등)
- [ ] 모니터링 대시보드 구성 (CloudWatch)

**총 소요 시간: 3.5일**

---

## 7. 주요 변경 파일 목록

### AWS 콘솔에서 작업
- [ ] ALB 생성
- [ ] Target Group 생성
- [ ] Launch Template 생성
- [ ] Auto Scaling Group 생성
- [ ] Security Group 수정
- [ ] CloudFront Origin 변경

### Git 저장소 파일 변경
- [ ] `.github/workflows/deploy.yml` - 비활성화 또는 삭제
- [ ] `.github/workflows/deploy-asg.yml` - 활성화 및 수정
- [ ] `scripts/setup-alb-asg.sh` - 신규 생성 (인프라 자동 구축)
- [ ] `user-data.sh` - 신규 생성 (EC2 초기화 스크립트)
- [ ] `WORKFLOWS_GUIDE.md` - 업데이트
- [ ] `README.md` - 아키텍처 다이어그램 업데이트

---

## 8. 롤백 계획

ALB 전환 후 문제 발생 시:

### 즉시 롤백 (5분 이내)
1. CloudFront Origin을 기존 EC2 IP로 되돌리기
2. 기존 EC2 인스턴스 재시작 (백업해둔 상태)
3. 서비스 복구 확인

### 완전 롤백 (1시간 이내)
1. ASG 삭제
2. ALB, Target Group 삭제
3. deploy.yml 재활성화
4. 기존 배포 방식으로 복귀

---

## 9. 리스크 및 대응 방안

### 리스크 1: Instance Refresh 중 전체 인스턴스 다운
**원인:** Health Check 실패로 새 인스턴스가 계속 실패
**대응:**
- MinHealthyPercentage를 50%로 설정 (최소 1대는 항상 실행)
- Health Check 경로 확인: `/actuator/health`
- 로그 모니터링 (CloudWatch Logs)

### 리스크 2: RDS 연결 실패
**원인:** Security Group 설정 오류
**대응:**
- RDS Security Group에 새 EC2 Security Group 추가
- 연결 테스트 스크립트 작성

### 리스크 3: 환경 변수 누락
**원인:** User Data에서 환경 변수 주입 실패
**대응:**
- AWS Systems Manager Parameter Store 사용
- Launch Template User Data에서 환경 변수 자동 로드

### 리스크 4: 비용 초과
**원인:** ASG가 과도하게 스케일 아웃
**대응:**
- 최대 용량 제한 (4대)
- CloudWatch Alarm 설정 (비용 알림)
- 스케일링 정책 조정

---

## 10. 다음 단계 (ALB 도입 이후)

### 단기 (1개월)
- [ ] CloudWatch 대시보드 구성
- [ ] 로그 중앙 집중화 (CloudWatch Logs)
- [ ] 알람 설정 (CPU, 메모리, Health Check 실패)
- [ ] 백업 자동화 (RDS 스냅샷)

### 중기 (3개월)
- [ ] HTTPS 적용 (ACM 인증서 + ALB 리스너)
- [ ] WAF 적용 (보안 강화)
- [ ] 성능 모니터링 및 최적화
- [ ] 비용 최적화 (Reserved Instance 검토)

### 장기 (6개월)
- [ ] Multi-Region 배포 검토
- [ ] CDN 캐싱 전략 고도화
- [ ] Database Read Replica 추가 (읽기 부하 분산)
- [ ] Container Orchestration (ECS/EKS) 검토

---

## 요약

### ALB 도입으로 달라지는 핵심 사항

| 항목 | 현재 (EC2 단일) | ALB 도입 후 |
|------|----------------|------------|
| 가용성 | ❌ 단일 장애점 | ✅ 고가용성 (Multi-AZ) |
| 확장성 | ❌ 수동 확장 | ✅ 자동 확장 (ASG) |
| 배포 방식 | SSH 접속 | Instance Refresh |
| 다운타임 | 30초 | 0초 (무중단) |
| 비용 | $23/월 | $46/월 |
| 복잡도 | 낮음 | 중간 |
| 보안 | EC2 직접 노출 | ALB 뒤에 숨김 |

### 결론
ALB 도입은 **고가용성과 확장성**을 위한 필수 단계이지만, **비용 2배 증가**와 **복잡도 상승**을 동반합니다.

**권장 시나리오:**
- 트래픽이 적은 초기 단계: 현재 구조 유지
- 사용자 증가 예상 시점: ALB 도입
- 서비스 안정성이 중요한 경우: 즉시 ALB 도입
