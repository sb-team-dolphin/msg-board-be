# 🎯 다음 단계 가이드

**현재 상태**: ALB + ASG + MySQL 인프라 구축 완료 준비 ✅

이제 다음 단계를 진행하세요!

---

## 📝 현재까지 완료된 작업

```
✅ application-prod.yml 생성 (MySQL 연결 설정)
✅ build.gradle에 MySQL 의존성 추가
✅ deploy-asg.yml 워크플로우 생성 (ASG 배포용)
✅ rollback-asg.yml 워크플로우 생성 (ASG 롤백용)
✅ STEP_BY_STEP_BUILD.md 실전 가이드 생성
```

---

## 🚀 1단계: 로컬 빌드 및 테스트 (5분)

### 1-1. 빌드 테스트

```bash
# 프로젝트 디렉토리에서
cd C:/2025proj/simple-api

# Gradle 빌드
./gradlew clean build

# 빌드 성공 확인
ls build/libs/
# → simple-api-0.0.1-SNAPSHOT.jar 확인
```

### 1-2. Docker 이미지 빌드 (로컬 테스트)

```bash
# Docker 이미지 빌드
docker build -t ghcr.io/johnhuh619/simple-api:latest .

# 이미지 확인
docker images | grep simple-api
```

**결과**:
```
ghcr.io/johnhuh619/simple-api   latest   xxxxx   2 minutes ago   500MB
```

---

## 🏗️ 2단계: AWS 인프라 구축 (6-8시간)

### Option 1: 직접 구축 (추천)

**실전 가이드 따라하기**:
```bash
# 가이드 파일 열기
code STEP_BY_STEP_BUILD.md
```

**주요 단계**:
1. ✅ **Step 1**: VPC + Public Subnet × 2 (30분)
2. ✅ **Step 2**: Security Groups × 3 (30분)
3. ✅ **Step 3**: MySQL EC2 설치 (20분)
4. ✅ **Step 4**: Application 코드 수정 + 이미지 푸시 (40분)
5. ✅ **Step 5**: Launch Template 생성 (30분)
6. ✅ **Step 6**: Target Group 생성 (40분)
7. ✅ **Step 7**: ALB 생성 (40분)
8. ✅ **Step 8**: Auto Scaling Group 생성 (60분)
9. ✅ **Step 9**: 전체 테스트 (40분)

**총 소요 시간**: 6-8시간

### Option 2: Terraform 사용 (고급)

Terraform 스크립트로 자동화 (선택사항, 별도 작업 필요)

---

## ⚙️ 3단계: application-prod.yml 수정

**중요**: MySQL Private IP를 실제 값으로 변경!

```bash
# Step 3에서 MySQL EC2 설치 후 Private IP 확인
# 예: 10.0.1.234

# application-prod.yml 수정
code src/main/resources/application-prod.yml
```

**변경 전**:
```yaml
url: jdbc:mysql://MYSQL_PRIVATE_IP:3306/feedbackdb?...
```

**변경 후** (예시):
```yaml
url: jdbc:mysql://10.0.1.234:3306/feedbackdb?...
```

---

## 🔧 4단계: GitHub Actions Secrets 설정

### 4-1. AWS Credentials 설정

```
GitHub Repository → Settings → Secrets and variables → Actions
  → New repository secret
```

**필요한 Secrets**:
```
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: xxxxx...
```

**AWS IAM 권한 필요**:
- EC2 (Launch Templates, Auto Scaling)
- ELB (Application Load Balancer, Target Groups)
- CloudWatch (메트릭, 로그)

### 4-2. 최소 권한 정책 예시

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:ModifyLaunchTemplate",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeInstanceRefreshes",
        "autoscaling:StartInstanceRefresh",
        "autoscaling:CancelInstanceRefresh",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🐳 5단계: GitHub Container Registry 설정

### Option 1: Repository를 Public으로 변경 (간단)

```
GitHub Repository → Settings → General
  → Danger Zone → Change visibility → Make public
```

**장점**: 추가 인증 불필요
**단점**: 코드가 공개됨

### Option 2: Personal Access Token 사용 (권장)

```
GitHub → Profile → Settings → Developer settings
  → Personal access tokens → Tokens (classic)
  → Generate new token

Scopes:
  ☑ write:packages
  ☑ read:packages
  ☑ delete:packages
```

**Token 생성 후**:
```
GitHub Repository → Settings → Secrets and variables → Actions
  → New repository secret

Name: GHCR_TOKEN
Value: ghp_xxxxxxxxxxxxx
```

**deploy-asg.yml 수정** (필요시):
```yaml
- name: Log in to GitHub Container Registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GHCR_TOKEN }}  # GITHUB_TOKEN 대신
```

---

## 🚀 6단계: 첫 배포

### 6-1. 코드 커밋 및 푸시

```bash
# 변경사항 확인
git status

# 스테이징
git add .

# 커밋
git commit -m "feat: Add ASG infrastructure support

- Add application-prod.yml for MySQL connection
- Add MySQL dependency to build.gradle
- Add deploy-asg.yml workflow for ASG deployment
- Add rollback-asg.yml workflow for ASG rollback
- Add STEP_BY_STEP_BUILD.md implementation guide

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

# 푸시
git push origin convert
```

### 6-2. Manual Workflow 실행

```
GitHub Repository → Actions → Deploy to ASG
  → Run workflow
    Environment: production
  → Run workflow (초록색 버튼)
```

**대기 시간**: 약 10-15분
- Docker 빌드: 3-5분
- Launch Template 생성: 1분
- Instance Refresh: 5-10분

### 6-3. 배포 모니터링

```
Actions 탭에서 실시간 로그 확인:
  ✓ Build with Gradle
  ✓ Build and push Docker image
  ✓ Create new Launch Template version
  ✓ Start Instance Refresh
  ✓ Wait for Instance Refresh to complete
  ✓ Verify deployment
```

---

## 🧪 7단계: 배포 검증

### 7-1. ALB DNS 확인

```
AWS Console → EC2 → Load Balancers → feedback-alb
  → Description 탭
  → DNS name: feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com
```

### 7-2. Health Check

```bash
ALB_DNS="feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com"

# Health endpoint
curl http://${ALB_DNS}/actuator/health

# 예상 결과:
# {"status":"UP","components":{"db":{"status":"UP"},...}}
```

### 7-3. 기능 테스트

```bash
# 피드백 생성
curl -X POST http://${ALB_DNS}/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "content": "첫 ASG 배포 성공!",
    "author": "테스터"
  }'

# 피드백 조회
curl http://${ALB_DNS}/api/feedbacks

# 예상 결과:
# [{"id":1,"content":"첫 ASG 배포 성공!","author":"테스터",...}]
```

### 7-4. 로드 밸런싱 확인

```bash
# 10번 요청
for i in {1..10}; do
  curl -s http://${ALB_DNS}/actuator/health | jq -r '.status'
done

# 모두 "UP" 출력되면 성공!
```

---

## 🔄 8단계: 롤백 테스트 (Optional)

### 8-1. 문제 발생 시뮬레이션

```bash
# 의도적으로 잘못된 코드 푸시 또는
# 그냥 롤백 기능 테스트
```

### 8-2. Rollback 실행

```
GitHub Repository → Actions → Rollback ASG Deployment
  → Run workflow
    Confirm: rollback
  → Run workflow
```

**대기 시간**: 5-10분

### 8-3. 롤백 확인

```bash
# Health check
curl http://${ALB_DNS}/actuator/health

# 이전 버전으로 돌아갔는지 확인
curl http://${ALB_DNS}/api/feedbacks
```

---

## 📊 9단계: 모니터링 설정 (Optional)

### Option 1: CloudWatch Alarms (간단)

```
CloudWatch → Alarms → Create alarm

Metrics:
  - ApplicationELB > Per-LB Metrics > TargetResponseTime
  - ApplicationELB > Per-LB Metrics > UnHealthyHostCount
  - EC2 > Per-Instance Metrics > CPUUtilization

Thresholds:
  - TargetResponseTime > 1초
  - UnHealthyHostCount > 0
  - CPUUtilization > 80%

Action:
  - SNS Topic (이메일 알림)
```

### Option 2: Prometheus + Grafana (고급)

**시간 있으면 추가 구축** (약 3-4시간):
- Prometheus EC2 설치
- Grafana EC2 설치
- Node Exporter 메트릭 수집 (이미 Launch Template에 포함됨!)
- 대시보드 구성

---

## 🗑️ 10단계: 5일 후 리소스 삭제

### 삭제 순서 (중요!)

```bash
# 1. Auto Scaling Group 삭제 (인스턴스 자동 종료)
AWS Console → EC2 → Auto Scaling Groups
  → feedback-asg 선택 → Delete

# 2. Load Balancer 삭제
EC2 → Load Balancers
  → feedback-alb 선택 → Delete

# 3. Target Group 삭제
EC2 → Target Groups
  → feedback-tg 선택 → Delete

# 4. Launch Template 삭제
EC2 → Launch Templates
  → feedback-app-template 선택 → Delete

# 5. MySQL EC2 종료
EC2 → Instances
  → mysql-server 선택 → Terminate

# 6. Security Groups 삭제
EC2 → Security Groups
  → alb-sg, app-sg, db-sg 선택 → Delete

# 7. VPC 삭제 (모든 종속 리소스 자동 삭제)
VPC → Your VPCs
  → feedback-vpc 선택 → Delete VPC
```

**예상 비용 (5일)**: 약 $12-15

---

## 🎯 체크리스트

### 코드 준비
```
□ build.gradle에 MySQL 의존성 추가됨
□ application-prod.yml 생성됨
□ MySQL Private IP 설정됨 (Step 3 이후)
□ deploy-asg.yml 워크플로우 준비됨
□ rollback-asg.yml 워크플로우 준비됨
```

### AWS 인프라
```
□ VPC + Subnets 생성 완료
□ Security Groups 3개 생성 완료
□ MySQL EC2 실행 중 (feedbackdb 준비)
□ Launch Template 생성 완료
□ Target Group 생성 완료
□ ALB 생성 완료
□ ASG 생성 완료
□ 인스턴스 2개 healthy 상태
```

### GitHub 설정
```
□ AWS_ACCESS_KEY_ID Secret 설정
□ AWS_SECRET_ACCESS_KEY Secret 설정
□ GHCR_TOKEN Secret 설정 (Optional)
□ Repository Public으로 변경 (또는 Token 설정)
```

### 배포 및 테스트
```
□ 첫 배포 성공 (deploy-asg workflow)
□ ALB DNS로 접근 성공
□ Health check 통과
□ 피드백 생성/조회 동작
□ 로드 밸런싱 확인
□ 롤백 테스트 성공 (Optional)
```

---

## 💡 FAQ

### Q1: Launch Template User Data를 수정하려면?

**A**: User Data는 Base64 인코딩되어 있습니다.

```bash
# 새 스크립트 작성
cat > user-data.sh << 'EOF'
#!/bin/bash
IMAGE_TAG="latest"
MYSQL_HOST="10.0.1.234"
# ... 전체 스크립트
EOF

# Base64 인코딩
base64 -w 0 user-data.sh

# 출력된 문자열을 deploy-asg.yml의 UserData 필드에 붙여넣기
```

### Q2: MySQL Private IP를 환경변수로 관리하려면?

**A**: GitHub Secrets에 추가 후 워크플로우에서 사용:

```yaml
# .github/workflows/deploy-asg.yml
env:
  MYSQL_HOST: ${{ secrets.MYSQL_PRIVATE_IP }}

# User Data에서 사용
--launch-template-data '{
  "UserData": "... MYSQL_HOST=${{ secrets.MYSQL_PRIVATE_IP }} ..."
}'
```

### Q3: Auto Scaling이 트리거 안되는데?

**A**: Scaling Policy 확인:

```
Auto Scaling Groups → feedback-asg
  → Automatic scaling 탭
  → cpu-scaling-policy 확인

Target value: 70%
Warmup time: 300 seconds
```

CPU 부하 테스트:
```bash
# 인스턴스 SSH 접속
ssh -i key.pem ec2-user@[Instance-IP]

# stress 설치
sudo dnf install -y stress

# CPU 100% 부하 (5분)
stress --cpu 4 --timeout 300
```

### Q4: Instance Refresh가 실패하는데?

**A**: 원인:
- Launch Template User Data 오류
- Docker 이미지 pull 실패 (GHCR 인증)
- MySQL 연결 실패
- Health check 실패

**디버깅**:
```bash
# 인스턴스 SSH 접속
ssh -i key.pem ec2-user@[Instance-IP]

# User Data 로그 확인
sudo cat /var/log/user-data.log

# Docker 로그 확인
sudo docker logs feedback-api

# MySQL 연결 테스트
mysql -h 10.0.1.234 -u feedbackuser -p'FeedbackPass123!' feedbackdb
```

---

## 📚 참고 문서

- `STEP_BY_STEP_BUILD.md`: 실전 구축 가이드
- `ARCHITECTURE_EXPLAINED.md`: 아키텍처 설명
- `REVISED_15HOUR_PLAN.md`: 시간별 계획
- `ROLLBACK_IN_ASG.md`: 롤백 전략
- `LAUNCH_TEMPLATE_EXPLAINED.md`: Launch Template 개념

---

## 🎉 축하합니다!

모든 단계를 완료하면:
- ✅ Auto Scaling 기반 고가용성 인프라
- ✅ 무중단 배포 가능
- ✅ 자동 롤백 지원
- ✅ 로드 밸런싱
- ✅ MySQL 영구 저장소

**다음 도전 과제**:
1. HTTPS 적용 (ACM + Route53)
2. Prometheus + Grafana 모니터링
3. CloudWatch Logs 중앙화
4. Terraform으로 IaC 전환
5. Multi-AZ MySQL 구성 (Primary-Replica)

**화이팅!** 🚀
