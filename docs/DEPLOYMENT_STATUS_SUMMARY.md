# CloudFront + S3 Frontend Deployment - 현재 상태

**생성 날짜**: 2025-11-19
**작업 상태**: ✅ 준비 완료 (AWS 권한 설정 필요)

---

## 📊 완료된 작업

### ✅ Phase 1: Frontend 파일 준비 (완료)

```
C:/2025proj/simple-api/
├── frontend/                         ✅ 생성됨
│   ├── index.html                    ✅ 복사 완료
│   ├── js/app.js                     ✅ 복사 완료 (API_BASE_URL='/api')
│   ├── css/style.css                 ✅ 복사 완료
│   ├── deploy.sh                     ✅ 생성 완료 (실행 가능)
│   └── README.md                     ✅ 문서 생성
```

**확인 방법:**
```bash
ls -la frontend/
# index.html, js/, css/, deploy.sh, README.md 확인
```

### ✅ Phase 2: 배포 스크립트 생성 (완료)

```
scripts/
├── setup-cloudfront.sh               ✅ CloudFront 인프라 생성 스크립트
├── setup-aws-permissions.sh          ✅ AWS 권한 설정 스크립트
└── cloudfront-deployment-policy.json ✅ IAM 정책 문서
```

**기능:**
- `setup-cloudfront.sh`: S3 버킷, CloudFront Distribution, OAC 자동 생성
- `setup-aws-permissions.sh`: 필요한 IAM 권한 자동 설정
- `deploy.sh`: 프론트엔드 파일 S3 업로드 + CloudFront 캐시 무효화

**실행 권한:**
```bash
ls -l scripts/*.sh frontend/*.sh
# -rwxr-xr-x 확인 (모두 실행 가능)
```

### ✅ Phase 3: GitHub Actions 워크플로우 (완료)

```
.github/workflows/
├── deploy-asg.yml                    ✅ 백엔드 배포 (기존)
├── deploy-frontend-cloudfront.yml    ✅ 프론트엔드 자동 배포 (신규)
└── rollback-asg.yml                  ✅ 롤백 (기존)
```

**deploy-frontend-cloudfront.yml 기능:**
- `frontend/**` 경로 변경 시 자동 트리거
- CloudFront Distribution 자동 감지
- S3 업로드 및 캐시 무효화
- 배포 결과 요약

### ✅ Phase 4: 백엔드 설정 업데이트 (완료)

**변경된 파일:**
```yaml
# src/main/resources/application-prod.yml
spring:
  web:
    resources:
      add-mappings: false  # ✅ 정적 리소스 서빙 비활성화
```

**CORS 설정:**
```java
// src/main/java/com/jaewon/practice/simpleapi/config/WebConfig.java
// ✅ 이미 설정되어 있음
@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("*")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS");
    }
}
```

### ✅ Phase 5: 문서 작성 (완료)

```
문서/
├── CLOUDFRONT_DEPLOYMENT_QUICKSTART.md    ✅ 빠른 시작 가이드 (1-2시간)
├── CLOUDFRONT_QUICK_DEPLOY.md             ✅ 상세 배포 가이드
├── FRONTEND_BACKEND_SEPARATION_GUIDE.md   ✅ 아키텍처 설명
├── SIMPLE_S3_DEPLOYMENT.md                ✅ 간단한 S3 배포 (대안)
└── frontend/README.md                     ✅ Frontend 운영 가이드
```

**각 문서 설명:**
- **CLOUDFRONT_DEPLOYMENT_QUICKSTART.md**: **👈 여기서 시작!**
  - 전체 프로세스 단계별 가이드
  - AWS 권한 설정 방법 포함
  - 트러블슈팅 섹션 포함

- **CLOUDFRONT_QUICK_DEPLOY.md**:
  - 기술적 상세 설명
  - CloudFront 설정 파라미터 설명

- **frontend/README.md**:
  - 일상적인 배포 운영 가이드
  - 트러블슈팅 FAQ

---

## ⚠️ 현재 상태: AWS 권한 필요

### 문제점

현재 IAM 사용자 `test_user`에 다음 권한이 부족합니다:

```
❌ s3:ListAllMyBuckets
❌ s3:CreateBucket
❌ s3:PutObject
❌ elasticloadbalancing:DescribeLoadBalancers
❌ cloudfront:CreateDistribution
```

### 해결 방법

**Option 1: 자동 권한 설정 (권장)**

```bash
cd C:/2025proj/simple-api

# AWS 권한 자동 설정 스크립트 실행
./scripts/setup-aws-permissions.sh
```

이 스크립트는:
1. 현재 IAM 사용자 확인
2. `CloudFrontDeploymentPolicy` 생성
3. 현재 사용자에게 정책 연결
4. 권한 테스트

**Option 2: 수동 권한 설정**

AWS Console에서 수동 설정:

1. IAM → Users → `test_user` 선택
2. Permissions → Add permissions → Attach policies
3. Create policy → JSON 탭
4. `scripts/cloudfront-deployment-policy.json` 내용 붙여넣기
5. Policy name: `CloudFrontDeploymentPolicy`
6. Create policy → Attach to user

**Option 3: 임시 관리자 권한 (테스트 전용, 권장하지 않음)**

```bash
aws iam attach-user-policy \
  --user-name test_user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

---

## 🚀 다음 단계

권한 설정이 완료되면:

### Step 1: AWS 권한 설정

```bash
cd C:/2025proj/simple-api
./scripts/setup-aws-permissions.sh

# 또는 수동으로 IAM 콘솔에서 설정
```

### Step 2: CloudFront 인프라 생성

```bash
./scripts/setup-cloudfront.sh
```

**예상 소요 시간:** 15-20분 (CloudFront 배포 포함)

**예상 출력:**
```
✅ Setup Complete!
Resources created:
  S3 Bucket: feedback-frontend-1732012345
  CloudFront Distribution ID: E1A2B3C4D5E6F7
  CloudFront Domain: d1a2b3c4d5e6f7.cloudfront.net

Frontend URL: https://d1a2b3c4d5e6f7.cloudfront.net
```

### Step 3: 백엔드 재배포

```bash
# Git 커밋 (application-prod.yml 변경 반영)
git add src/main/resources/application-prod.yml
git commit -m "feat: Disable static resource serving for CloudFront"
git push origin main

# GitHub Actions에서 배포
# GitHub → Actions → Deploy to ASG → Run workflow
```

### Step 4: 통합 테스트

```bash
# 환경 변수 로드
source cloudfront-config.env

# 프론트엔드 테스트
curl -I https://$CLOUDFRONT_DOMAIN/

# API 테스트
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks

# 브라우저에서 확인
start https://$CLOUDFRONT_DOMAIN
```

### Step 5: 프론트엔드 업데이트 테스트

```bash
cd frontend

# 파일 수정 (예: CSS)
echo "/* Test $(date) */" >> css/style.css

# 배포
./deploy.sh

# 1-3분 후 브라우저에서 확인
```

---

## 📋 완성된 아키텍처

```
사용자
  ↓
CloudFront Distribution (HTTPS)
  ├─ /              → S3 Bucket
  │  ├─ index.html      (프론트엔드)
  │  ├─ js/app.js
  │  └─ css/style.css
  │
  └─ /api/*         → Application Load Balancer
                      ↓
                    Auto Scaling Group
                      ├─ EC2 Instance 1 (Spring Boot)
                      └─ EC2 Instance 2 (Spring Boot)
                        ↓
                      RDS MySQL

✅ 장점:
- CORS 문제 없음 (같은 도메인)
- 프론트엔드/백엔드 독립 배포
- 글로벌 CDN (빠른 로딩)
- HTTPS 자동 적용
- S3 프라이빗 (보안)
```

---

## 📂 프로젝트 구조 변경 사항

### 신규 파일

```
.
├── frontend/                          🆕 프론트엔드 디렉토리
│   ├── index.html
│   ├── js/app.js
│   ├── css/style.css
│   ├── deploy.sh                      🆕 배포 스크립트
│   └── README.md                      🆕 운영 가이드
│
├── scripts/                           🆕 스크립트 디렉토리
│   ├── setup-cloudfront.sh            🆕 CloudFront 생성
│   ├── setup-aws-permissions.sh       🆕 권한 설정
│   └── cloudfront-deployment-policy.json  🆕 IAM 정책
│
├── .github/workflows/
│   ├── deploy-asg.yml                 (기존)
│   ├── deploy-frontend-cloudfront.yml 🆕 프론트엔드 CI/CD
│   └── rollback-asg.yml               (기존)
│
└── docs/                              🆕 문서
    ├── CLOUDFRONT_DEPLOYMENT_QUICKSTART.md  🆕 빠른 시작
    ├── CLOUDFRONT_QUICK_DEPLOY.md           🆕 상세 가이드
    └── SIMPLE_S3_DEPLOYMENT.md              🆕 S3 대안

```

### 변경된 파일

```
src/main/resources/application-prod.yml  ✏️ 정적 리소스 비활성화 추가
```

### 기존 파일 (변경 없음)

```
src/main/java/.../config/WebConfig.java  ✅ CORS 이미 설정됨
src/main/resources/static/               ⚠️  유지 (로컬 개발용)
```

---

## 💰 예상 비용

```
월간 비용 (트래픽 가정: 10GB, 100K requests):

CloudFront:
  - Data Transfer: ~$0.85
  - HTTPS Requests: ~$0.01
  - Invalidations: Free (first 1,000)

S3:
  - Storage (10MB): ~$0.0002
  - Requests: ~$0.01

합계: ~$1-2/월

💡 AWS Free Tier 사용 시 대부분 무료!
```

---

## 🔒 보안 개선 사항

- ✅ S3 버킷은 프라이빗 (CloudFront OAC로만 접근)
- ✅ HTTPS 강제 (HTTP → HTTPS 자동 리다이렉트)
- ✅ CORS 정책 설정 (백엔드)
- ✅ Origin Access Control (OAC) 사용 (구 OAI 대체)
- ⚠️  추가 권장: WAF, Rate Limiting, 커스텀 도메인 + ACM

---

## 📖 참고 문서

1. **빠른 시작**: `CLOUDFRONT_DEPLOYMENT_QUICKSTART.md` 👈 **여기서 시작**
2. **상세 가이드**: `CLOUDFRONT_QUICK_DEPLOY.md`
3. **운영 가이드**: `frontend/README.md`
4. **아키텍처**: `FRONTEND_BACKEND_SEPARATION_GUIDE.md`
5. **대안 (S3 only)**: `SIMPLE_S3_DEPLOYMENT.md`

---

## ⚙️ GitHub Actions Secrets 확인 필요

프론트엔드 자동 배포를 위해 GitHub Secrets가 올바르게 설정되어 있는지 확인:

```
Repository → Settings → Secrets and variables → Actions

필요한 Secrets:
✅ AWS_ACCESS_KEY_ID
✅ AWS_SECRET_ACCESS_KEY

⚠️ 중요: 이 Secrets의 IAM 사용자도 CloudFront/S3 권한이 있어야 함!
```

**권한 확인 방법:**

1. GitHub Secrets에 사용된 IAM 사용자 이름 확인
2. AWS IAM Console에서 해당 사용자에게 `CloudFrontDeploymentPolicy` 연결
3. 또는 `scripts/cloudfront-deployment-policy.json` 정책 수동 적용

---

## ✅ 체크리스트

### 사전 준비
- [x] Frontend 파일 복사 완료
- [x] 배포 스크립트 생성 완료
- [x] GitHub Actions 워크플로우 생성 완료
- [x] 백엔드 설정 업데이트 완료
- [x] 문서 작성 완료
- [ ] **AWS 권한 설정 필요** 👈 **다음 단계**

### 배포 진행 (권한 설정 후)
- [ ] `./scripts/setup-aws-permissions.sh` 실행
- [ ] `./scripts/setup-cloudfront.sh` 실행
- [ ] CloudFront 배포 완료 대기 (10-15분)
- [ ] `cloudfront-config.env` 파일 백업
- [ ] 백엔드 재배포 (application-prod.yml)
- [ ] 통합 테스트 (프론트엔드 + API)
- [ ] 프론트엔드 업데이트 테스트 (`./deploy.sh`)
- [ ] GitHub Actions 자동 배포 테스트

---

## 🚨 알려진 이슈

### 1. AWS 권한 부족

**증상:**
```
An error occurred (AccessDenied) when calling the DescribeLoadBalancers operation
```

**해결책:**
```bash
./scripts/setup-aws-permissions.sh
```

### 2. ALB 존재 여부 확인 필요

CloudFront 설정 전에 ALB가 존재해야 합니다:

```bash
aws elbv2 describe-load-balancers --names feedback-alb
```

없으면 먼저 백엔드 인프라 배포:
```
GitHub → Actions → Deploy to ASG → Run workflow
```

---

## 🎯 최종 목표

권한 설정 후 스크립트 실행하면:

```bash
./scripts/setup-aws-permissions.sh  # 권한 설정
./scripts/setup-cloudfront.sh       # 인프라 생성 (15분)
# → CloudFront URL 획득

cd frontend
./deploy.sh                          # 배포 (1-2분)
# → 변경사항 즉시 반영!

git add frontend/
git commit -m "Update frontend"
git push origin main
# → GitHub Actions 자동 배포!
```

**결과:**
- ✅ https://d1a2b3c4d5e6f7.cloudfront.net (프론트엔드)
- ✅ https://d1a2b3c4d5e6f7.cloudfront.net/api (백엔드)
- ✅ CORS 문제 없음
- ✅ 독립 배포 가능
- ✅ HTTPS 자동 적용

---

**생성 날짜**: 2025-11-19
**상태**: 모든 파일 및 스크립트 생성 완료, AWS 권한 설정 대기 중

**다음 단계**: `CLOUDFRONT_DEPLOYMENT_QUICKSTART.md` 참조하여 배포 진행
