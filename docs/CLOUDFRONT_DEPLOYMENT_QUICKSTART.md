# CloudFront + S3 Frontend Deployment - Quick Start Guide

**목표**: 프론트엔드를 S3 + CloudFront로 분리하여 백엔드와 독립적으로 배포
**소요 시간**: 1-2시간 (CloudFront 생성 대기 시간 포함)
**난이도**: ⭐⭐⭐☆☆

---

## 📊 최종 아키텍처

```
사용자 → CloudFront Distribution (단일 도메인)
         ├─ /                → S3 (Frontend)
         │  ├─ index.html
         │  ├─ js/app.js
         │  └─ css/style.css
         │
         └─ /api/*           → ALB → Spring Boot → RDS

✅ 장점:
- CORS 문제 없음 (같은 도메인)
- 프론트엔드/백엔드 독립 배포
- 글로벌 CDN으로 빠른 로딩
- HTTPS 자동 지원
```

---

## 전제 조건

### 1. 기존 인프라 확인

반드시 아래 리소스가 먼저 생성되어 있어야 합니다:

```bash
# ALB 확인
aws elbv2 describe-load-balancers --names feedback-alb

# ASG 확인
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names feedback-asg

# Target Group 확인
aws elbv2 describe-target-groups --names feedback-tg
```

만약 없다면, 먼저 백엔드 인프라를 배포하세요:
```bash
# GitHub Actions 워크플로우 실행
# .github/workflows/deploy-asg.yml
```

### 2. AWS CLI 설정

```bash
# AWS CLI 설치 확인
aws --version

# 자격 증명 확인
aws sts get-caller-identity
```

### 3. 필요한 AWS 권한 설정 ⚠️

**현재 `test_user` 계정에 권한이 부족합니다!** 아래 권한이 필요합니다:

#### Option A: 관리자 권한 사용 (빠름, 테스트용)

```bash
# 기존 test_user에 AdministratorAccess 추가 (권장하지 않음, 테스트 전용)
aws iam attach-user-policy \
  --user-name test_user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

#### Option B: 최소 권한 정책 생성 (권장)

`cloudfront-deployment-policy.json` 파일 생성:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketOperations",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicy",
        "s3:PutPublicAccessBlock"
      ],
      "Resource": [
        "arn:aws:s3:::feedback-frontend-*",
        "arn:aws:s3:::feedback-frontend-*/*"
      ]
    },
    {
      "Sid": "S3ListBuckets",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Sid": "CloudFrontOperations",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:UpdateDistribution",
        "cloudfront:ListDistributions",
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation",
        "cloudfront:CreateOriginAccessControl",
        "cloudfront:ListOriginAccessControls",
        "cloudfront:GetOriginAccessControl"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ELBDescribe",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

정책 적용:

```bash
# 정책 생성
aws iam create-policy \
  --policy-name CloudFrontDeploymentPolicy \
  --policy-document file://cloudfront-deployment-policy.json

# test_user에 정책 연결
aws iam attach-user-policy \
  --user-name test_user \
  --policy-arn arn:aws:iam::396468676673:policy/CloudFrontDeploymentPolicy
```

권한 확인:

```bash
# S3 권한 테스트
aws s3 ls

# ELB 권한 테스트
aws elbv2 describe-load-balancers

# CloudFront 권한 테스트
aws cloudfront list-distributions
```

---

## 🚀 배포 단계

### Phase 1: Frontend 파일 준비 ✅ (완료됨)

이미 완료된 상태:

```
C:/2025proj/simple-api/
├── frontend/
│   ├── index.html          ✅ 복사됨
│   ├── js/app.js           ✅ 복사됨 (API_BASE_URL='/api')
│   ├── css/style.css       ✅ 복사됨
│   ├── deploy.sh           ✅ 생성됨
│   └── README.md           ✅ 생성됨
└── scripts/
    └── setup-cloudfront.sh ✅ 생성됨
```

확인:
```bash
ls -la frontend/
# index.html, js/app.js, css/style.css 있어야 함
```

### Phase 2: CloudFront 인프라 생성 (15-20분)

**AWS 권한이 설정된 후** 실행:

```bash
cd C:/2025proj/simple-api

# 실행 권한 부여 (이미 완료됨)
chmod +x scripts/setup-cloudfront.sh

# CloudFront 인프라 생성
./scripts/setup-cloudfront.sh
```

**스크립트가 수행하는 작업:**

1. **S3 버킷 생성** (고유 이름: `feedback-frontend-<timestamp>`)
2. **ALB DNS 조회** (기존 `feedback-alb`에서)
3. **Origin Access Control (OAC) 생성** (S3 보안 접근)
4. **CloudFront Distribution 생성**:
   - Origin 1: S3 (프론트엔드)
   - Origin 2: ALB (백엔드 API)
   - Behavior: `/api/*` → ALB
   - Behavior: `/*` → S3
   - Custom Error Responses: 403/404 → index.html (SPA 라우팅)
5. **S3 버킷 정책 설정** (CloudFront만 접근 가능)
6. **프론트엔드 파일 업로드**

**예상 출력:**

```
======================================
✅ Setup Complete!
======================================

Resources created:
  S3 Bucket: feedback-frontend-1732012345
  CloudFront Distribution ID: E1A2B3C4D5E6F7
  CloudFront Domain: d1a2b3c4d5e6f7.cloudfront.net
  OAC ID: E1234567890ABC

Frontend URL: https://d1a2b3c4d5e6f7.cloudfront.net

⏳ CloudFront distribution is deploying (10-15 minutes)
```

**중요**: `cloudfront-config.env` 파일이 생성됩니다. 이 파일을 보관하세요!

```bash
# 환경 변수 로드 (이후 사용)
source cloudfront-config.env
echo $CLOUDFRONT_DOMAIN
```

### Phase 3: CloudFront 배포 대기 (10-15분)

CloudFront 배포는 시간이 걸립니다. 상태 확인:

```bash
# 배포 상태 확인
aws cloudfront get-distribution \
  --id $CLOUDFRONT_DISTRIBUTION_ID \
  --query 'Distribution.Status' \
  --output text

# "Deployed"가 표시될 때까지 대기
# 또는 AWS Console에서 확인: CloudFront → Distributions
```

### Phase 4: 백엔드 재배포 (선택사항)

정적 리소스 서빙을 비활성화하기 위해 백엔드를 재배포합니다.

**이미 적용된 변경사항:**
- `src/main/resources/application-prod.yml`:
  ```yaml
  spring:
    web:
      resources:
        add-mappings: false  # ✅ 추가됨
  ```

**재배포 방법:**

```bash
# 로컬 빌드 테스트
./gradlew clean build

# Git 커밋
git add src/main/resources/application-prod.yml
git commit -m "feat: Disable static resource serving for CloudFront"
git push origin main

# GitHub Actions에서 배포
# GitHub → Actions → Deploy to ASG → Run workflow
```

**또는 수동 배포:**

```bash
# Docker 이미지 빌드
docker build -t ghcr.io/johnhuh619/simple-api:latest .

# GitHub Container Registry에 푸시
docker push ghcr.io/johnhuh619/simple-api:latest

# ASG 인스턴스 갱신 (Instance Refresh)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name feedback-asg
```

### Phase 5: 통합 테스트 (5-10분)

CloudFront 배포가 완료되면 테스트:

```bash
# 1. 프론트엔드 접속 테스트
curl -I https://$CLOUDFRONT_DOMAIN/

# 예상 출력:
# HTTP/2 200
# content-type: text/html
# x-cache: Hit from cloudfront

# 2. API 호출 테스트 (CloudFront를 통해)
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks

# 예상 출력:
# {
#   "content": [...],
#   "totalElements": 10,
#   ...
# }

# 3. 브라우저 테스트
# Windows
start https://$CLOUDFRONT_DOMAIN

# Mac
open https://$CLOUDFRONT_DOMAIN

# Linux
xdg-open https://$CLOUDFRONT_DOMAIN
```

**브라우저 개발자 도구 확인 (F12):**

1. **Network 탭**:
   - `index.html` - 200 OK (from S3 via CloudFront)
   - `js/app.js` - 200 OK (from S3 via CloudFront)
   - `api/feedbacks` - 200 OK (from ALB via CloudFront)

2. **Console 탭**:
   - ❌ CORS 에러 없어야 함!
   - ✅ 피드백 목록 로드됨

3. **피드백 생성 테스트**:
   - 이름: "테스터"
   - 메시지: "CloudFront 배포 성공!"
   - [작성하기] 클릭
   - → 목록에 추가되면 성공! ✅

### Phase 6: 프론트엔드 업데이트 테스트 (2-3분)

```bash
cd frontend

# CSS 수정 (예시)
echo "/* Updated $(date) */" >> css/style.css

# 배포 스크립트 실행
./deploy.sh

# 예상 출력:
# ======================================
# Frontend Deployment Script
# ======================================
# [1/4] Finding CloudFront distribution...
#    Distribution ID: E1A2B3C4D5E6F7
# [2/4] Finding S3 bucket...
#    Bucket: feedback-frontend-1732012345
# [3/4] Uploading files to S3...
#    ✅ Files uploaded successfully
# [4/4] Invalidating CloudFront cache...
#    Invalidation ID: I1234567890ABC
# ======================================
# ✅ Deployment Completed!
# ======================================
```

1-3분 후 브라우저에서 새로고침 (Ctrl+Shift+R) → 변경사항 확인

---

## 🔧 GitHub Actions 자동 배포 설정

### 이미 생성된 워크플로우:

`.github/workflows/deploy-frontend-cloudfront.yml` ✅

### GitHub Secrets 확인:

GitHub Repository → Settings → Secrets and variables → Actions

필요한 시크릿:
- `AWS_ACCESS_KEY_ID` ✅ (이미 설정됨)
- `AWS_SECRET_ACCESS_KEY` ✅ (이미 설정됨)

**중요**: 이 시크릿의 IAM 사용자가 CloudFront/S3 권한을 가지고 있는지 확인!

### 자동 배포 테스트:

```bash
# 프론트엔드 파일 수정
echo "/* Test $(date) */" >> frontend/css/style.css

# Git 커밋 및 푸시
git add frontend/
git commit -m "feat: Update frontend styles"
git push origin main

# GitHub Actions 자동 실행됨!
# GitHub → Actions → "Deploy Frontend to CloudFront" 확인
```

---

## 📋 체크리스트

배포 전:
- [ ] ALB, ASG, Target Group 생성 완료
- [ ] AWS CLI 설정 완료
- [ ] IAM 권한 설정 완료 (S3, CloudFront, ELB)
- [ ] `frontend/` 디렉토리 파일 확인

배포 중:
- [ ] `./scripts/setup-cloudfront.sh` 실행
- [ ] CloudFront Distribution ID 메모
- [ ] `cloudfront-config.env` 파일 백업
- [ ] CloudFront 배포 상태 "Deployed" 확인

배포 후:
- [ ] 프론트엔드 접속 테스트 (https://$CLOUDFRONT_DOMAIN)
- [ ] API 호출 테스트 (/api/feedbacks)
- [ ] 브라우저 개발자 도구 확인 (CORS 에러 없음)
- [ ] 피드백 생성/조회 테스트
- [ ] 프론트엔드 업데이트 테스트 (`./deploy.sh`)
- [ ] GitHub Actions 자동 배포 테스트

---

## 🚨 트러블슈팅

### 문제 1: AWS 권한 에러

**증상:**
```
An error occurred (AccessDenied) when calling the DescribeLoadBalancers operation
```

**해결:**
- 위의 "필요한 AWS 권한 설정" 섹션 참조
- IAM 정책 적용 후 재시도

### 문제 2: ALB not found

**증상:**
```
❌ ALB 'feedback-alb' not found!
```

**해결:**
```bash
# 백엔드 인프라 먼저 배포
# GitHub Actions → Deploy to ASG → Run workflow

# 또는 ALB 이름 확인
aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerName"
```

### 문제 3: CloudFront 403 Forbidden

**증상:** 프론트엔드 접속 시 403 에러

**원인:** S3 버킷 정책 또는 OAC 설정 오류

**해결:**
```bash
# 버킷 정책 확인
aws s3api get-bucket-policy --bucket $S3_BUCKET_NAME

# 정책 재적용 (scripts/setup-cloudfront.sh 스크립트 재실행)
```

### 문제 4: API 호출 502 Bad Gateway

**증상:** `/api/feedbacks` 호출 시 502 에러

**원인:** 백엔드 서버 다운 또는 Target Group 비정상

**해결:**
```bash
# Target Group 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names feedback-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# ASG 인스턴스 확인
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names feedback-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]'

# 인스턴스 로그 확인 (SSH 접속 필요)
ssh ec2-user@<instance-public-ip>
sudo docker logs feedback-api
```

### 문제 5: 변경사항이 반영 안 됨

**원인:** CloudFront 캐시 또는 브라우저 캐시

**해결:**
```bash
# 1. 브라우저 강제 새로고침
# Windows: Ctrl+Shift+R
# Mac: Cmd+Shift+R

# 2. CloudFront 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
  --paths "/*"

# 3. 개발자 도구 → Network → "Disable cache" 체크
```

### 문제 6: deploy.sh에서 "Distribution not found"

**원인:** CloudFront 배포가 안 되어 있거나 Comment가 다름

**해결:**
```bash
# CloudFront 배포 확인
aws cloudfront list-distributions \
  --query "DistributionList.Items[*].[Id,Comment]" \
  --output table

# 수동으로 Distribution ID 설정
export DISTRIBUTION_ID=E1A2B3C4D5E6F7
cd frontend
./deploy.sh
```

---

## 💰 비용 예상

```
CloudFront (월간):
  - Data Transfer (10GB): ~$0.85
  - HTTPS Requests (100,000): ~$0.01
  - Invalidations (1,000 paths): Free

S3 (월간):
  - Storage (10MB): ~$0.0002
  - GET Requests (10,000): ~$0.004
  - PUT Requests (1,000): ~$0.005

총 예상 비용: ~$1-2/월
```

**참고**: AWS Free Tier 사용 시 대부분 무료!

---

## 📚 다음 단계

### 1. 커스텀 도메인 연결

```bash
# Route 53에서 도메인 구매 또는 연결
# ACM에서 SSL 인증서 발급 (us-east-1 리전!)
# CloudFront Distribution에 Alternate Domain Names 추가
```

### 2. HTTPS 강제 적용

이미 적용됨! CloudFront는 기본적으로 HTTP → HTTPS 리다이렉트

### 3. 모니터링 설정

```bash
# CloudWatch 대시보드 생성
# CloudFront 메트릭 확인 (us-east-1 리전)
# 알람 설정 (4xx/5xx 에러율)
```

### 4. WAF 추가 (보안 강화)

```bash
# AWS WAF 웹 ACL 생성
# CloudFront에 연결
# Rate limiting, SQL injection 방어 등
```

---

## 📖 참고 자료

- [CLOUDFRONT_QUICK_DEPLOY.md](./CLOUDFRONT_QUICK_DEPLOY.md) - 상세 가이드
- [frontend/README.md](./frontend/README.md) - Frontend 배포 가이드
- [FRONTEND_BACKEND_SEPARATION_GUIDE.md](./FRONTEND_BACKEND_SEPARATION_GUIDE.md) - 전체 아키텍처 설명

---

## ✅ 성공 확인

모든 단계가 완료되면:

1. ✅ CloudFront URL로 프론트엔드 접속
2. ✅ API 호출이 CloudFront를 통해 ALB로 전달
3. ✅ CORS 에러 없음 (같은 도메인)
4. ✅ 프론트엔드 독립 배포 가능 (`./deploy.sh`)
5. ✅ GitHub Actions 자동 배포 동작
6. ✅ HTTPS 자동 적용
7. ✅ S3 버킷 프라이빗 (보안)

**축하합니다! 🎉**

```
Frontend: https://d1a2b3c4d5e6f7.cloudfront.net
Backend API: https://d1a2b3c4d5e6f7.cloudfront.net/api
```

프론트엔드와 백엔드가 성공적으로 분리되었고, 독립적으로 배포할 수 있습니다!
