# ⚡ CloudFront 빠른 배포 가이드

**목표**: S3 + CloudFront로 프론트엔드 배포 (CORS 문제 없음!)
**소요 시간**: 1-2시간
**난이도**: ⭐⭐⭐☆☆

---

## 🎯 최종 구조

```
사용자
  ↓
https://d123abc.cloudfront.net/
  ├─ /              → S3 (index.html)
  ├─ /js/app.js     → S3 (JavaScript)
  └─ /api/*         → ALB → Spring Boot → RDS

✅ 같은 도메인 → CORS 문제 없음!
✅ HTTPS 자동 지원
✅ 글로벌 CDN
```

---

## 📋 사전 준비 (5분)

### 필요한 정보 확인

```bash
# 1. ALB DNS 확인
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "ALB DNS: $ALB_DNS"
# ⭐ 복사!

# 2. VPC ID 확인
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=feedback-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

# 3. AWS 계정 ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
```

**⚠️ 환경변수 저장** (터미널 세션 유지):
```bash
export ALB_DNS="<위에서 확인한 ALB DNS>"
export VPC_ID="<위에서 확인한 VPC ID>"
export ACCOUNT_ID="<위에서 확인한 Account ID>"

# 확인
echo "ALB: $ALB_DNS"
echo "VPC: $VPC_ID"
echo "Account: $ACCOUNT_ID"
```

---

## Phase 1: 프론트엔드 파일 준비 (10분)

### Step 1-1: 디렉토리 생성

```bash
cd C:/2025proj/simple-api

mkdir -p frontend/js
mkdir -p frontend/css
```

### Step 1-2: 파일 복사

```bash
# 정적 파일 복사
cp src/main/resources/static/index.html frontend/
cp src/main/resources/static/js/app.js frontend/js/
cp src/main/resources/static/css/style.css frontend/css/

# 확인
ls -la frontend/
ls -la frontend/js/
ls -la frontend/css/
```

### Step 1-3: API 엔드포인트 수정 (중요!)

**frontend/js/app.js** 수정:

```javascript
// ⭐ 파일 맨 위 수정

// Before
const API_BASE_URL = '/api';

// After (CloudFront 사용 시 상대 경로 유지!)
const API_BASE_URL = '/api';  // ← 그대로! CloudFront가 처리
const FEEDBACKS_ENDPOINT = `${API_BASE_URL}/feedbacks`;
```

**설명**: CloudFront가 `/api/*` 요청을 자동으로 ALB로 라우팅하므로 **상대 경로 그대로** 사용!

### Step 1-4: 백엔드 static 폴더 비우기

```bash
# 백엔드에서 정적 파일 제거 (충돌 방지)
rm -rf src/main/resources/static/*

# 확인
ls -la src/main/resources/static/
# → 비어있어야 함
```

### ✅ 검증

```bash
# 파일 확인
tree frontend/
# frontend/
# ├── index.html
# ├── js/
# │   └── app.js
# └── css/
#     └── style.css

# 파일 개수 확인
find frontend/ -type f | wc -l
# → 3
```

---

## Phase 2: RDS 생성 (선택 - 이미 있으면 Skip)

### Step 2-1: RDS가 이미 있는지 확인

```bash
aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].DBInstanceStatus" 2>/dev/null

# "available" → 이미 있음 (Phase 2 전체 Skip)
# Error → 없음 (아래 계속)
```

### Step 2-2: RDS 생성 (없는 경우만)

```bash
# Private Subnet 확인 (최소 2개 필요)
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:Name,Values=Private-*" \
  --query "Subnets[*].SubnetId" \
  --output text)

echo "Subnet IDs: $SUBNET_IDS"

# Subnet Group 생성
aws rds create-db-subnet-group \
  --db-subnet-group-name feedback-db-subnet \
  --db-subnet-group-description "Subnet group for feedback DB" \
  --subnet-ids $SUBNET_IDS

# Security Group 생성
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name rds-mysql-sg \
  --description "RDS MySQL Security Group" \
  --vpc-id $VPC_ID \
  --output text)

echo "RDS SG: $RDS_SG_ID"

# app-sg ID 가져오기
APP_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=group-name,Values=app-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

# Inbound rule (3306 from app-sg)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $APP_SG_ID

# RDS 인스턴스 생성 (10분 소요)
aws rds create-db-instance \
  --db-instance-identifier feedback-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password 'YourStrongPassword123!' \
  --allocated-storage 20 \
  --storage-type gp3 \
  --db-subnet-group-name feedback-db-subnet \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-name feedbackdb \
  --backup-retention-period 7 \
  --no-publicly-accessible

echo "✅ RDS 생성 시작! 10-15분 대기..."
```

### Step 2-3: RDS 엔드포인트 확인 (생성 완료 후)

```bash
# 상태 확인 (반복 실행)
aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text

# "available" 될 때까지 대기

# 엔드포인트 가져오기
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
# ⭐ 복사!

export RDS_ENDPOINT="$RDS_ENDPOINT"
```

---

## Phase 3: S3 버킷 생성 (5분)

### Step 3-1: 버킷 생성

```bash
# 고유한 버킷 이름 생성
BUCKET_NAME="feedback-frontend-$(date +%s)"
echo "Bucket Name: $BUCKET_NAME"

# 버킷 생성
aws s3 mb s3://$BUCKET_NAME --region ap-northeast-2

# 환경변수 저장
export BUCKET_NAME="$BUCKET_NAME"

# 확인
aws s3 ls | grep feedback-frontend
```

### Step 3-2: 버킷 버전 관리 활성화 (선택)

```bash
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
```

### Step 3-3: 파일 업로드

```bash
cd frontend/

# 업로드
aws s3 sync . s3://$BUCKET_NAME/ --region ap-northeast-2

# 확인
aws s3 ls s3://$BUCKET_NAME/ --recursive
```

### ✅ 검증

```bash
# 파일 확인
aws s3 ls s3://$BUCKET_NAME/ --recursive

# 예상 결과:
# index.html
# js/app.js
# css/style.css
```

---

## Phase 4: CloudFront 생성 (핵심! 20분)

### Step 4-1: Origin Access Control (OAC) 생성

```bash
# OAC 생성
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "feedback-s3-oac",
    "Description": "OAC for S3 bucket",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }' \
  --query 'OriginAccessControl.Id' \
  --output text)

echo "OAC ID: $OAC_ID"
export OAC_ID="$OAC_ID"
```

### Step 4-2: CloudFront Distribution 설정 파일 생성

```bash
cat > /tmp/cloudfront-config.json << EOF
{
  "CallerReference": "feedback-$(date +%s)",
  "Comment": "CloudFront for Feedback App",
  "Enabled": true,
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "S3-frontend",
        "DomainName": "${BUCKET_NAME}.s3.ap-northeast-2.amazonaws.com",
        "OriginPath": "",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        },
        "OriginAccessControlId": "${OAC_ID}"
      },
      {
        "Id": "ALB-backend",
        "DomainName": "${ALB_DNS}",
        "OriginPath": "",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-frontend",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["HEAD", "GET"]
      }
    },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    },
    "TrustedKeyGroups": {
      "Enabled": false,
      "Quantity": 0
    }
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [
      {
        "PathPattern": "/api/*",
        "TargetOriginId": "ALB-backend",
        "ViewerProtocolPolicy": "https-only",
        "AllowedMethods": {
          "Quantity": 7,
          "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"],
          "CachedMethods": {
            "Quantity": 2,
            "Items": ["HEAD", "GET"]
          }
        },
        "Compress": true,
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3",
        "TrustedSigners": {
          "Enabled": false,
          "Quantity": 0
        },
        "TrustedKeyGroups": {
          "Enabled": false,
          "Quantity": 0
        }
      }
    ]
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      {
        "ErrorCode": 403,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      },
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      }
    ]
  },
  "PriceClass": "PriceClass_200",
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true,
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "HttpVersion": "http2and3"
}
EOF

echo "✅ CloudFront 설정 파일 생성 완료!"
```

### Step 4-3: CloudFront Distribution 생성 (10분 소요)

```bash
# Distribution 생성
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/cloudfront-config.json \
  --query 'Distribution.Id' \
  --output text)

echo "Distribution ID: $DISTRIBUTION_ID"
export DISTRIBUTION_ID="$DISTRIBUTION_ID"

echo "✅ CloudFront 배포 시작! 10-15분 대기..."
```

### Step 4-4: 배포 상태 확인

```bash
# 상태 확인 (반복 실행)
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.Status' \
  --output text

# "Deployed" 상태가 될 때까지 대기 (10-15분)

# 완료 후 도메인 확인
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' \
  --output text)

echo "CloudFront Domain: $CLOUDFRONT_DOMAIN"
export CLOUDFRONT_DOMAIN="$CLOUDFRONT_DOMAIN"

# ⭐⭐⭐ 이 주소가 프론트엔드 URL!
echo "Frontend URL: https://$CLOUDFRONT_DOMAIN"
```

### Step 4-5: S3 버킷 정책 업데이트 (OAC 권한)

```bash
cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF

# 버킷 정책 적용
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/bucket-policy.json

echo "✅ S3 버킷 정책 업데이트 완료!"
```

### ✅ 검증

```bash
# CloudFront 상태 확인
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.[Status,DomainName]' \
  --output table

# 예상:
# --------------------------------------
# |        GetDistribution             |
# +-----------+------------------------+
# | Deployed  | d123abc.cloudfront.net |
# +-----------+------------------------+

# 프론트엔드 접속 테스트
curl -I https://$CLOUDFRONT_DOMAIN/

# 예상: HTTP/2 200
```

---

## Phase 5: 백엔드 설정 (15분)

### Step 5-1: application-prod.yml 수정

**파일**: `src/main/resources/application-prod.yml`

```yaml
spring:
  datasource:
    # RDS 연결
    url: jdbc:mysql://${RDS_ENDPOINT}:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: admin
    password: YourStrongPassword123!  # RDS 생성 시 설정한 비밀번호
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: update
    properties:
      hibernate:
        format_sql: true
    open-in-view: false

  # 정적 리소스 비활성화 (CloudFront에서 서빙)
  web:
    resources:
      add-mappings: false

logging:
  level:
    root: INFO
    com.jaewon.practice.simpleapi: DEBUG

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always
```

**⚠️ 중요**: `${RDS_ENDPOINT}` 부분을 실제 RDS 엔드포인트로 변경!

```bash
# RDS Endpoint 출력
echo $RDS_ENDPOINT

# 예: feedback-db.abc123.ap-northeast-2.rds.amazonaws.com
```

### Step 5-2: CORS 설정 (CloudFront 사용 시 선택)

CloudFront를 사용하면 같은 도메인이므로 **CORS 설정이 필요 없습니다!**

하지만 안전하게 추가:

**파일**: `src/main/java/com/jaewon/practice/simpleapi/config/WebConfig.java`

```java
package com.jaewon.practice.simpleapi.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns("*")  // 또는 CloudFront 도메인만
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
```

### Step 5-3: 빌드 및 배포

```bash
cd C:/2025proj/simple-api

# 빌드
./gradlew clean build

# Git 커밋
git add .
git commit -m "feat: CloudFront frontend separation

- Remove static resources from backend
- Add RDS connection in application-prod.yml
- Configure CORS for CloudFront
- Separate frontend to S3 + CloudFront

Frontend: https://${CLOUDFRONT_DOMAIN}
Backend: https://${CLOUDFRONT_DOMAIN}/api

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git push origin main
```

### Step 5-4: GitHub Actions 배포

```bash
# GitHub → Actions → Deploy to ASG → Run workflow
# 또는:
gh workflow run deploy-asg.yml

# 대기: 15-20분 (Docker 빌드 + Instance Refresh)
```

### ✅ 검증

```bash
# ALB 헬스 체크
curl http://$ALB_DNS/actuator/health

# 예상:
{
  "status": "UP",
  "components": {
    "db": {
      "status": "UP"  ⭐
    }
  }
}

# db status UP 확인!
```

---

## Phase 6: 통합 테스트 (15분)

### Test 1: 프론트엔드 로드

```bash
# 브라우저에서 CloudFront 도메인 접속
echo "Frontend URL: https://$CLOUDFRONT_DOMAIN"

# Windows
start https://$CLOUDFRONT_DOMAIN

# Mac
open https://$CLOUDFRONT_DOMAIN

# Linux
xdg-open https://$CLOUDFRONT_DOMAIN
```

**확인사항**:
```
✓ 페이지 로드됨
✓ CSS 적용됨
✓ "피드백 보드" 헤더 보임
✓ 폼 정상 표시
✓ HTTPS 주소창에 자물쇠 아이콘 ✅
```

### Test 2: 브라우저 개발자 도구 확인

```
F12 → Network 탭

1. index.html
   → 200 OK
   → from cloudfront

2. js/app.js
   → 200 OK
   → from cloudfront
   → x-cache: Hit from cloudfront (두 번째 접속부터)

3. /api/feedbacks
   → 200 OK
   → 같은 도메인! (CORS 없음!)
   → x-cache: Miss from cloudfront (API는 캐싱 안함)
```

### Test 3: 피드백 생성

```bash
# 터미널에서 테스트
curl -X POST https://$CLOUDFRONT_DOMAIN/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "username": "CloudFront 테스터",
    "message": "S3 + CloudFront + ALB 통합 테스트!"
  }'

# 예상 응답:
{
  "success": true,
  "data": {
    "id": 1,
    "username": "CloudFront 테스터",
    "message": "S3 + CloudFront + ALB 통합 테스트!",
    "createdAt": "2025-11-19T..."
  }
}
```

### Test 4: 브라우저 UI 테스트

```
1. 브라우저에서 https://d123abc.cloudfront.net 접속
2. 피드백 작성:
   - 이름: "UI 테스터"
   - 메시지: "브라우저 UI 테스트"
   - [작성하기] 클릭

3. 확인:
   ✓ 목록에 표시됨
   ✓ CORS 에러 없음
   ✓ 페이지 새로고침 후에도 데이터 유지 (RDS)
```

### Test 5: CORS 확인 (없어야 함!)

```
F12 → Console 탭

→ CORS 에러 없음! ✅
→ 모든 요청이 같은 도메인 (d123abc.cloudfront.net)
```

### ✅ 최종 검증

```bash
# 프론트엔드
curl -I https://$CLOUDFRONT_DOMAIN/
# → 200 OK

# 백엔드 API
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks
# → JSON 응답

# 같은 도메인 확인
echo "Frontend: https://$CLOUDFRONT_DOMAIN/"
echo "Backend:  https://$CLOUDFRONT_DOMAIN/api"
# → 둘 다 같은 도메인! CORS 없음!
```

---

## Phase 7: 배포 자동화 (15분)

### Step 7-1: 프론트엔드 배포 스크립트

```bash
cat > frontend/deploy.sh << 'EOF'
#!/bin/bash
set -e

echo "====================================="
echo "Frontend Deployment"
echo "====================================="

# 환경변수 확인
if [ -z "$BUCKET_NAME" ]; then
  # S3 버킷 자동 검색
  BUCKET_NAME=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, 'feedback-frontend-')].Name | [0]" \
    --output text)
  echo "Auto-detected bucket: $BUCKET_NAME"
fi

if [ -z "$DISTRIBUTION_ID" ]; then
  # CloudFront Distribution 자동 검색
  DISTRIBUTION_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='CloudFront for Feedback App'].Id | [0]" \
    --output text)
  echo "Auto-detected distribution: $DISTRIBUTION_ID"
fi

# 1. S3 업로드
echo "[1/3] Uploading to S3..."
aws s3 sync . s3://$BUCKET_NAME/ \
  --exclude "*.sh" \
  --exclude ".git*" \
  --exclude "*.md" \
  --delete \
  --region ap-northeast-2

# 2. index.html 캐시 설정 (짧게)
echo "[2/3] Updating index.html cache..."
aws s3 cp index.html s3://$BUCKET_NAME/index.html \
  --cache-control "public, max-age=300, must-revalidate" \
  --content-type "text/html" \
  --region ap-northeast-2

# 3. CloudFront 캐시 무효화
echo "[3/3] Invalidating CloudFront cache..."
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text

echo "====================================="
echo "✅ Deployment Completed!"
echo "====================================="

# CloudFront 도메인 출력
DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' \
  --output text)

echo "Frontend URL: https://$DOMAIN"
EOF

chmod +x frontend/deploy.sh
```

### Step 7-2: GitHub Actions 워크플로우

```bash
cat > .github/workflows/deploy-frontend-cf.yml << 'EOF'
name: Deploy Frontend to CloudFront

on:
  push:
    branches: [main]
    paths:
      - 'frontend/**'
  workflow_dispatch:

env:
  AWS_REGION: ap-northeast-2

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Get S3 bucket and CloudFront ID
        id: resources
        run: |
          BUCKET=$(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, 'feedback-frontend-')].Name | [0]" \
            --output text)
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT

          DIST_ID=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='CloudFront for Feedback App'].Id | [0]" \
            --output text)
          echo "distribution=$DIST_ID" >> $GITHUB_OUTPUT

      - name: Sync to S3
        run: |
          aws s3 sync frontend/ s3://${{ steps.resources.outputs.bucket }}/ \
            --exclude "*.sh" \
            --exclude ".git*" \
            --delete

      - name: Update index.html
        run: |
          aws s3 cp frontend/index.html s3://${{ steps.resources.outputs.bucket }}/index.html \
            --cache-control "public, max-age=300, must-revalidate" \
            --content-type "text/html"

      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.resources.outputs.distribution }} \
            --paths "/*"

      - name: Deployment summary
        run: |
          DOMAIN=$(aws cloudfront get-distribution \
            --id ${{ steps.resources.outputs.distribution }} \
            --query 'Distribution.DomainName' \
            --output text)

          echo "====================================="
          echo "✅ Frontend Deployed!"
          echo "====================================="
          echo "URL: https://$DOMAIN"
          echo "SHA: ${{ github.sha }}"
EOF

git add .github/workflows/deploy-frontend-cf.yml
git commit -m "feat: Add CloudFront frontend deployment workflow"
git push origin main
```

### Step 7-3: 배포 테스트

```bash
# 프론트엔드 파일 수정
cd frontend
echo "/* Updated $(date) */" >> css/style.css

# Git 커밋 (frontend/ 변경만)
git add frontend/
git commit -m "test: Update frontend CSS"
git push origin main

# GitHub Actions 자동 실행 확인
# GitHub → Actions → Deploy Frontend to CloudFront
```

---

## 환경변수 저장 (선택)

다음에 사용하기 위해 저장:

```bash
cat > ~/.feedback-env << EOF
export BUCKET_NAME="$BUCKET_NAME"
export DISTRIBUTION_ID="$DISTRIBUTION_ID"
export CLOUDFRONT_DOMAIN="$CLOUDFRONT_DOMAIN"
export ALB_DNS="$ALB_DNS"
export RDS_ENDPOINT="$RDS_ENDPOINT"
export VPC_ID="$VPC_ID"
export ACCOUNT_ID="$ACCOUNT_ID"
EOF

# 다음 세션에서 불러오기:
# source ~/.feedback-env
```

---

## 트러블슈팅

### 문제 1: CloudFront 403 Forbidden

**증상**: `https://d123abc.cloudfront.net/` 접속 시 403

**원인**: S3 버킷 정책 누락

**해결**:
```bash
# Phase 4-5 재실행
# 버킷 정책 재적용

cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/bucket-policy.json
```

### 문제 2: API 요청 502 Bad Gateway

**증상**: `/api/feedbacks` 호출 시 502

**원인**: ALB Target Unhealthy

**해결**:
```bash
# Target Group 확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names feedback-tg \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)

# Unhealthy 원인 확인 후 백엔드 재배포
```

### 문제 3: 프론트엔드 업데이트 반영 안됨

**증상**: 파일 수정했는데 변경 안보임

**원인**: CloudFront 캐시

**해결**:
```bash
# 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"

# 또는 브라우저 강제 새로고침 (Ctrl+Shift+R)
```

### 문제 4: RDS 연결 실패

**증상**: `com.mysql.cj.jdbc.exceptions.CommunicationsException`

**원인**: Security Group 또는 엔드포인트 오류

**해결**:
```bash
# 1. RDS 엔드포인트 재확인
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo $RDS_ENDPOINT

# 2. application-prod.yml에 정확히 입력되었는지 확인

# 3. Security Group 확인
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rds-mysql-sg"
# → 3306 from app-sg 있는지 확인
```

---

## 리소스 정리 (5일 후)

### 순서대로 삭제:

```bash
# 1. CloudFront 비활성화
aws cloudfront get-distribution-config \
  --id $DISTRIBUTION_ID > /tmp/dist-config.json

# Enabled를 false로 수정 후
aws cloudfront update-distribution \
  --id $DISTRIBUTION_ID \
  --if-match <ETag> \
  --distribution-config file:///tmp/dist-config-disabled.json

# 배포 대기 후 삭제
aws cloudfront delete-distribution \
  --id $DISTRIBUTION_ID \
  --if-match <ETag>

# 2. S3 버킷 삭제
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# 3. RDS 삭제
aws rds delete-db-instance \
  --db-instance-identifier feedback-db \
  --skip-final-snapshot

# 4. 나머지 (ALB, ASG 등)
# IMPLEMENTATION_GUIDE.md의 Phase 14 참조
```

---

## 비용 (월 기준)

```
CloudFront:
  - 첫 50GB 무료
  - 50GB 이상: ~$10/월

S3:
  - 스토리지: ~$1/월

ALB: ~$27/월
EC2 (t3.small × 2): ~$30/월
RDS (db.t3.micro): ~$26/월

총: ~$94/월
```

---

## 최종 체크리스트

```
□ Phase 1: 프론트엔드 파일 준비 (frontend/ 디렉토리)
□ Phase 2: RDS 생성 및 엔드포인트 확인 (선택)
□ Phase 3: S3 버킷 생성 및 파일 업로드
□ Phase 4: CloudFront Distribution 생성 (10-15분 대기)
□ Phase 5: 백엔드 설정 및 재배포
□ Phase 6: 통합 테스트 (프론트엔드 + API)
□ Phase 7: 배포 자동화 (GitHub Actions)
```

---

## 성공 확인

```bash
# 최종 URL
echo "✅ 프론트엔드: https://$CLOUDFRONT_DOMAIN"
echo "✅ 백엔드 API: https://$CLOUDFRONT_DOMAIN/api"

# 브라우저 테스트
# 1. https://d123abc.cloudfront.net 접속
# 2. 피드백 작성
# 3. 목록에 표시됨
# 4. F12 → Console → CORS 에러 없음 ✅
```

**🎉 완료! CloudFront 배포 성공!**

**핵심 장점**:
- ✅ CORS 문제 없음 (같은 도메인)
- ✅ HTTPS 자동 지원
- ✅ 글로벌 CDN
- ✅ 프론트/백 독립 배포

---

**End of Quick Deploy Guide** 🚀
