# 🚀 프론트엔드/백엔드 분리 구축 가이드

**목표**: S3 + CloudFront + ALB + RDS 아키텍처 구축
**소요 시간**: 3-4시간
**난이도**: ⭐⭐⭐☆☆

---

## 📋 목차

1. [개요 및 아키텍처](#1-개요-및-아키텍처)
2. [사전 준비](#2-사전-준비)
3. [Phase 1: 프로젝트 구조 변경](#phase-1-프로젝트-구조-변경-30분)
4. [Phase 2: RDS 생성](#phase-2-rds-생성-20분)
5. [Phase 3: S3 버킷 설정](#phase-3-s3-버킷-설정-20분)
6. [Phase 4: 백엔드 수정 및 배포](#phase-4-백엔드-수정-및-배포-40분)
7. [Phase 5: CloudFront 배포](#phase-5-cloudfront-배포-40분)
8. [Phase 6: 프론트엔드 배포](#phase-6-프론트엔드-배포-30분)
9. [Phase 7: 통합 테스트](#phase-7-통합-테스트-30분)
10. [Phase 8: 배포 자동화](#phase-8-배포-자동화-30분)
11. [트러블슈팅](#트러블슈팅)

---

## 1. 개요 및 아키텍처

### 최종 아키텍처

```
                        사용자
                          ↓
                 ┌────────────────────┐
                 │   CloudFront CDN   │
                 │  (d123abc.cf.net)  │
                 └──────┬─────────┬───┘
                        │         │
          ┌─────────────┘         └─────────────┐
          │ (정적 파일)                    (API) │
          ↓                                      ↓
  ┌───────────────┐                    ┌─────────────────┐
  │  S3 Bucket    │                    │      ALB        │
  │               │                    │                 │
  │ - index.html  │                    │ ┌─────────────┐ │
  │ - app.js      │                    │ │ API Server1 │ │
  │ - style.css   │                    │ └─────────────┘ │
  └───────────────┘                    │ ┌─────────────┐ │
                                       │ │ API Server2 │ │
                                       │ └──────┬──────┘ │
                                       └────────┼────────┘
                                                │
                                          ┌─────▼─────┐
                                          │    RDS    │
                                          │   MySQL   │
                                          └───────────┘
```

### Request Flow

```
1. 프론트엔드 요청:
   Browser → CloudFront → S3
   GET https://d123abc.cloudfront.net/
   → index.html (캐싱: 5분)

   GET https://d123abc.cloudfront.net/js/app.js
   → app.js (캐싱: 1년)

2. API 요청:
   Browser → CloudFront → ALB → Spring Boot → RDS
   POST https://d123abc.cloudfront.net/api/feedbacks
   → JSON (캐싱 없음)
```

### 장점

```
✅ 독립적 스케일링 (프론트 ∞, 백엔드 Auto Scaling)
✅ 글로벌 CDN 성능
✅ 독립적 배포 (CSS 수정해도 백엔드 재배포 불필요)
✅ 비용 최적화 (S3 + CloudFront 저렴)
✅ 보안 향상 (API 서버 직접 노출 안됨)
```

---

## 2. 사전 준비

### 2-1. 필요한 도구

```bash
✓ AWS CLI 설치 및 설정
✓ Git
✓ 텍스트 에디터 (VS Code 등)
✓ 브라우저
```

### 2-2. AWS CLI 설정 확인

```bash
aws --version
# aws-cli/2.x.x 이상

aws configure list
# access_key, secret_key, region 확인
```

### 2-3. 기존 리소스 확인

```bash
# VPC 확인
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=feedback-vpc"

# ALB 확인
aws elbv2 describe-load-balancers --names feedback-alb

# ASG 확인
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names feedback-asg
```

**⚠️ 중요**: 기존 ALB와 ASG가 있다고 가정합니다. 없으면 먼저 `IMPLEMENTATION_GUIDE.md`를 따라 구축하세요.

---

## Phase 1: 프로젝트 구조 변경 (30분)

### Step 1-1: 프론트엔드 디렉토리 생성

```bash
cd C:/2025proj/simple-api

# 프론트엔드 디렉토리 생성
mkdir frontend
mkdir frontend/js
mkdir frontend/css
```

### Step 1-2: 정적 파일 이동

```bash
# 파일 복사
cp src/main/resources/static/index.html frontend/
cp src/main/resources/static/js/app.js frontend/js/
cp src/main/resources/static/css/style.css frontend/css/

# 복사 확인
ls -la frontend/
# index.html, js/, css/ 확인
```

### Step 1-3: API 엔드포인트 설정 파일 생성

```bash
# frontend/js/config.js 생성
cat > frontend/js/config.js << 'EOF'
// API Configuration
// 프로덕션 환경에서 CloudFront를 통해 API 호출
window.ENV = {
  // CloudFront가 /api/* 요청을 ALB로 프록시
  API_URL: '/api'
};
EOF
```

### Step 1-4: app.js 수정

```javascript
// frontend/js/app.js 파일 수정

// Before (line 2)
const API_BASE_URL = '/api';

// After (line 2-3)
const API_BASE_URL = window.ENV?.API_URL || '/api';
const FEEDBACKS_ENDPOINT = `${API_BASE_URL}/feedbacks`;

// ⚠️ 나머지 코드는 그대로 유지!
```

**수정 방법**:
```bash
# VS Code로 열기
code frontend/js/app.js

# 또는 sed로 수정 (Windows Git Bash)
sed -i '2s|.*|const API_BASE_URL = window.ENV?.API_URL || '"'"'/api'"'"';|' frontend/js/app.js
```

### Step 1-5: index.html 수정 (config.js 추가)

```html
<!-- frontend/index.html -->
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>피드백 보드</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/css/style.css">

    <!-- ✅ config.js 추가 (app.js보다 먼저!) -->
    <script src="/js/config.js"></script>
</head>
<body>
    <!-- body 내용 그대로 -->

    <!-- ✅ app.js는 맨 마지막 -->
    <script src="/js/app.js"></script>
</body>
```

### Step 1-6: 백엔드 static 폴더 정리

```bash
# 백엔드에서 static 폴더 삭제 (충돌 방지)
rm -rf src/main/resources/static/*

# 또는 .gitignore에 추가
echo "src/main/resources/static/" >> .gitignore
```

### Step 1-7: 프론트엔드 .gitignore 생성

```bash
cat > frontend/.gitignore << 'EOF'
# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/

# Logs
*.log
EOF
```

### ✅ 검증

```bash
# 디렉토리 구조 확인
tree frontend/
# frontend/
# ├── index.html
# ├── js/
# │   ├── app.js
# │   └── config.js
# └── css/
#     └── style.css

# 파일 크기 확인
du -sh frontend/
# ~50K
```

---

## Phase 2: RDS 생성 (20분)

### Step 2-1: RDS Subnet Group 생성

```bash
# Private Subnet ID 확인
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=Private-AZ-A" \
  --query "Subnets[0].SubnetId" \
  --output text
# → subnet-abc123 (복사!)

# RDS Subnet Group 생성
aws rds create-db-subnet-group \
  --db-subnet-group-name feedback-db-subnet-group \
  --db-subnet-group-description "Subnet group for Feedback DB" \
  --subnet-ids subnet-abc123 subnet-def456 \
  --tags Key=Name,Value=feedback-db-subnet-group
```

**⚠️ 주의**: subnet-ids는 최소 2개 AZ 필요!

### Step 2-2: RDS Security Group 생성

```bash
# VPC ID 확인
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=feedback-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

# Security Group 생성
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name rds-mysql-sg \
  --description "Security group for RDS MySQL" \
  --vpc-id $VPC_ID \
  --output text)

echo "RDS Security Group: $RDS_SG_ID"

# app-sg ID 확인
APP_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=app-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

echo "App Security Group: $APP_SG_ID"

# Inbound rule 추가 (app-sg에서만 접근)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $APP_SG_ID

# 확인
aws ec2 describe-security-groups --group-ids $RDS_SG_ID
```

### Step 2-3: RDS 인스턴스 생성

```bash
# RDS 생성 (10-15분 소요)
aws rds create-db-instance \
  --db-instance-identifier feedback-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username admin \
  --master-user-password 'YourStrongPassword123!' \
  --allocated-storage 20 \
  --storage-type gp3 \
  --db-subnet-group-name feedback-db-subnet-group \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-name feedbackdb \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --no-publicly-accessible \
  --tags Key=Name,Value=feedback-db

echo "✅ RDS 생성 시작! 10-15분 대기..."
```

### Step 2-4: RDS 생성 대기 및 엔드포인트 확인

```bash
# 상태 확인 (반복 실행)
aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text

# "available" 상태가 되면 계속 진행

# 엔드포인트 확인
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
# → feedback-db.abc123.ap-northeast-2.rds.amazonaws.com

# ⭐ 메모장에 복사!
```

### ✅ 검증

```bash
# RDS 상태 확인
aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port]" \
  --output table

# 예상 결과:
# -----------------------------------------------------------------
# |                    DescribeDBInstances                        |
# +-----------+-------------------------------------------+------+
# | available | feedback-db.abc123.rds.amazonaws.com     | 3306 |
# +-----------+-------------------------------------------+------+
```

---

## Phase 3: S3 버킷 설정 (20분)

### Step 3-1: S3 버킷 생성

```bash
# 버킷 이름 변수 설정 (전역 고유해야 함!)
BUCKET_NAME="feedback-frontend-$(date +%s)"
echo "Bucket Name: $BUCKET_NAME"

# 버킷 생성
aws s3 mb s3://$BUCKET_NAME --region ap-northeast-2

# 확인
aws s3 ls | grep feedback-frontend
```

### Step 3-2: 버킷 버전 관리 활성화 (선택)

```bash
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
```

### Step 3-3: 초기 파일 업로드 (테스트)

```bash
# frontend 디렉토리에서
cd frontend/

# S3 업로드
aws s3 sync . s3://$BUCKET_NAME/ \
  --exclude ".git*" \
  --exclude "*.sh" \
  --region ap-northeast-2

# 확인
aws s3 ls s3://$BUCKET_NAME/ --recursive
```

### Step 3-4: 버킷 정책 설정 (나중에 CloudFront OAC 설정)

**⚠️ 주의**: 버킷 정책은 CloudFront 생성 후 설정합니다 (Step 5에서).

### ✅ 검증

```bash
# 버킷 존재 확인
aws s3api head-bucket --bucket $BUCKET_NAME

# 파일 확인
aws s3 ls s3://$BUCKET_NAME/
# → index.html
# → js/
# → css/

# ⭐ 버킷 이름 저장
echo $BUCKET_NAME > /tmp/bucket_name.txt
```

---

## Phase 4: 백엔드 수정 및 배포 (40분)

### Step 4-1: application-prod.yml 수정

```bash
cd C:/2025proj/simple-api

# RDS 엔드포인트 가져오기
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier feedback-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
```

**수정**: `src/main/resources/application-prod.yml`

```yaml
spring:
  datasource:
    # RDS MySQL 연결
    url: jdbc:mysql://feedback-db.abc123.ap-northeast-2.rds.amazonaws.com:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    #              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 실제 RDS 엔드포인트!
    username: admin
    password: YourStrongPassword123!  # RDS 생성 시 설정한 비밀번호
    driver-class-name: com.mysql.cj.jdbc.Driver

    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: update  # 첫 배포는 update, 이후 validate 권장
    properties:
      hibernate:
        format_sql: true
        show_sql: false
    open-in-view: false

  # 정적 리소스 비활성화 (S3에서 서빙)
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
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
```

### Step 4-2: CORS 설정 추가

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
                .allowedOriginPatterns("*")  // 모든 Origin 허용 (CloudFront 포함)
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
```

**⚠️ 보안**: 프로덕션에서는 `allowedOrigins`에 CloudFront 도메인만 지정하세요.

```java
.allowedOrigins(
    "https://d123abc456def.cloudfront.net",
    "http://localhost:3000"  // 로컬 개발용
)
```

### Step 4-3: 빌드 및 테스트

```bash
# 로컬 빌드
./gradlew clean build

# 빌드 성공 확인
ls -lh build/libs/
# → simple-api-0.0.1-SNAPSHOT.jar
```

### Step 4-4: Git 커밋

```bash
git add .
git commit -m "feat: Separate frontend and backend architecture

- Move static files to frontend/ directory
- Update application-prod.yml for RDS connection
- Add CORS configuration for CloudFront
- Disable static resource serving in Spring Boot

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git push origin main
```

### Step 4-5: GitHub Actions 배포

```bash
# GitHub → Actions 탭
# → Deploy to ASG (Auto Scaling Group)
# → Run workflow

# 또는 로컬에서 트리거
gh workflow run deploy-asg.yml
```

**대기**: 15-20분 (Docker 빌드 + Instance Refresh)

### Step 4-6: ALB 엔드포인트 확인

```bash
# ALB DNS 가져오기
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "ALB DNS: $ALB_DNS"
# → feedback-alb-xxx.ap-northeast-2.elb.amazonaws.com

# ⭐ 메모장에 복사!
```

### ✅ 검증

```bash
# Health Check
curl http://$ALB_DNS/actuator/health

# 예상 응답:
{
  "status": "UP",
  "components": {
    "db": {
      "status": "UP",
      "details": {
        "database": "MySQL",
        "validationQuery": "isValid()"
      }
    }
  }
}

# ⭐ "db": {"status": "UP"} 확인 중요!
```

---

## Phase 5: CloudFront 배포 (40분)

### Step 5-1: CloudFront Origin Access Control (OAC) 생성

```bash
# OAC 생성
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "feedback-s3-oac",
    "Description": "OAC for S3 bucket access",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }' \
  --query 'OriginAccessControl.Id' \
  --output text)

echo "OAC ID: $OAC_ID"
```

### Step 5-2: CloudFront Distribution 설정 파일 준비

```bash
# 버킷 이름 불러오기
BUCKET_NAME=$(cat /tmp/bucket_name.txt)

# ALB DNS 불러오기
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text)

# CloudFront 설정 JSON 생성
cat > /tmp/cloudfront-config.json << EOF
{
  "CallerReference": "feedback-$(date +%s)",
  "Comment": "CloudFront distribution for Feedback App",
  "Enabled": true,
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "S3-feedback-frontend",
        "DomainName": "${BUCKET_NAME}.s3.ap-northeast-2.amazonaws.com",
        "OriginPath": "",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        },
        "OriginAccessControlId": "${OAC_ID}",
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10
      },
      {
        "Id": "ALB-feedback-backend",
        "DomainName": "${ALB_DNS}",
        "OriginPath": "",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          },
          "OriginReadTimeout": 30,
          "OriginKeepaliveTimeout": 5
        },
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-feedback-frontend",
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
    "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [
      {
        "PathPattern": "/api/*",
        "TargetOriginId": "ALB-feedback-backend",
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
        "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3"
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
```

### Step 5-3: CloudFront Distribution 생성

```bash
# Distribution 생성 (5-10분 소요)
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/cloudfront-config.json \
  --query 'Distribution.Id' \
  --output text)

echo "Distribution ID: $DISTRIBUTION_ID"
echo $DISTRIBUTION_ID > /tmp/distribution_id.txt

echo "✅ CloudFront 배포 시작! 10-15분 대기..."
```

### Step 5-4: 배포 상태 확인

```bash
# 상태 확인 (반복 실행)
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.Status' \
  --output text

# "Deployed" 상태가 되면 계속 진행
```

### Step 5-5: CloudFront 도메인 확인

```bash
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' \
  --output text)

echo "CloudFront Domain: $CLOUDFRONT_DOMAIN"
# → d123abc456def.cloudfront.net

# ⭐ 메모장에 복사!
```

### Step 5-6: S3 버킷 정책 업데이트 (OAC 권한)

```bash
# AWS 계정 ID 가져오기
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 버킷 정책 생성
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

echo "✅ S3 버킷 정책 적용 완료!"
```

### ✅ 검증

```bash
# CloudFront 상태 확인
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.[Status,DomainName]' \
  --output table

# 예상 결과:
# -------------------------------------------
# |         GetDistribution                 |
# +-----------+-----------------------------+
# | Deployed  | d123abc.cloudfront.net     |
# +-----------+-----------------------------+
```

---

## Phase 6: 프론트엔드 배포 (30분)

### Step 6-1: config.js 업데이트 (CloudFront 경로)

```bash
cd C:/2025proj/simple-api/frontend

# config.js 수정 (CloudFront를 통한 API 호출)
cat > js/config.js << 'EOF'
// API Configuration
window.ENV = {
  // CloudFront가 /api/* 요청을 ALB로 라우팅
  API_URL: '/api'
};
EOF
```

**설명**: CloudFront 도메인에서 `/api/*` 요청이 자동으로 ALB로 프록시됩니다.

### Step 6-2: S3 업로드 (캐시 설정 포함)

```bash
# 버킷 이름 불러오기
BUCKET_NAME=$(cat /tmp/bucket_name.txt)

# 1. JS/CSS 파일 업로드 (장기 캐싱)
aws s3 sync . s3://$BUCKET_NAME/ \
  --exclude "index.html" \
  --exclude ".git*" \
  --exclude "*.sh" \
  --exclude "*.md" \
  --cache-control "public, max-age=31536000, immutable" \
  --region ap-northeast-2

# 2. index.html 업로드 (단기 캐싱)
aws s3 cp index.html s3://$BUCKET_NAME/index.html \
  --cache-control "public, max-age=300, must-revalidate" \
  --content-type "text/html" \
  --region ap-northeast-2

echo "✅ 프론트엔드 파일 업로드 완료!"
```

**캐싱 전략**:
- `index.html`: 5분 (자주 업데이트)
- `app.js`, `style.css`: 1년 (변경 시 파일명 변경 또는 invalidation)

### Step 6-3: CloudFront 캐시 무효화

```bash
# Distribution ID 불러오기
DISTRIBUTION_ID=$(cat /tmp/distribution_id.txt)

# 캐시 무효화 (모든 파일)
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation ID: $INVALIDATION_ID"

# 무효화 상태 확인
aws cloudfront get-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --id $INVALIDATION_ID \
  --query 'Invalidation.Status'

# "Completed" 상태가 되면 완료
```

### Step 6-4: CORS 응답 헤더 정책 추가 (CloudFront)

**⚠️ 중요**: API 요청에 CORS 헤더가 필요합니다.

```bash
# Response Headers Policy 생성
RESPONSE_HEADERS_POLICY_ID=$(aws cloudfront create-response-headers-policy \
  --response-headers-policy-config '{
    "Name": "API-CORS-Policy",
    "Comment": "CORS policy for API requests",
    "CorsConfig": {
      "AccessControlAllowOrigins": {
        "Quantity": 1,
        "Items": ["*"]
      },
      "AccessControlAllowHeaders": {
        "Quantity": 3,
        "Items": ["Content-Type", "Authorization", "X-Requested-With"]
      },
      "AccessControlAllowMethods": {
        "Quantity": 5,
        "Items": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
      },
      "AccessControlAllowCredentials": true,
      "AccessControlMaxAgeSec": 3600,
      "OriginOverride": false
    }
  }' \
  --query 'ResponseHeadersPolicy.Id' \
  --output text)

echo "Response Headers Policy ID: $RESPONSE_HEADERS_POLICY_ID"
```

**수동 설정 (Console)**:
```
CloudFront → Distributions → [Distribution ID]
  → Behaviors → /api/* → Edit

Response headers policy:
  [Create policy]
  Name: API-CORS-Policy

  CORS:
    Access-Control-Allow-Origin: *
    Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
    Access-Control-Allow-Headers: Content-Type, Authorization
    Access-Control-Max-Age: 3600
```

### ✅ 검증

```bash
# CloudFront 도메인 가져오기
CLOUDFRONT_DOMAIN=$(cat /tmp/cloudfront_domain.txt 2>/dev/null || \
  aws cloudfront get-distribution \
    --id $DISTRIBUTION_ID \
    --query 'Distribution.DomainName' \
    --output text)

echo "CloudFront Domain: $CLOUDFRONT_DOMAIN"

# 프론트엔드 접속 테스트
curl -I https://$CLOUDFRONT_DOMAIN/

# 예상 응답:
# HTTP/2 200
# content-type: text/html
# cache-control: public, max-age=300, must-revalidate
# x-cache: Miss from cloudfront
```

---

## Phase 7: 통합 테스트 (30분)

### Test 1: 프론트엔드 로드

```bash
# CloudFront 도메인
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $(cat /tmp/distribution_id.txt) \
  --query 'Distribution.DomainName' \
  --output text)

echo "Frontend URL: https://$CLOUDFRONT_DOMAIN/"

# 브라우저에서 접속
# Windows:
start https://$CLOUDFRONT_DOMAIN/

# Mac:
open https://$CLOUDFRONT_DOMAIN/

# Linux:
xdg-open https://$CLOUDFRONT_DOMAIN/
```

**확인사항**:
```
✓ 페이지 로드됨
✓ CSS 스타일 적용됨
✓ JavaScript 동작함
✓ "피드백 보드" 헤더 보임
✓ 폼이 정상 표시됨
```

### Test 2: API 연결 (Browser Console)

```javascript
// 브라우저 F12 → Console

// API 엔드포인트 확인
console.log(window.ENV.API_URL);
// → /api

// 직접 API 호출 테스트
fetch('/api/feedbacks?page=0&size=10')
  .then(res => res.json())
  .then(data => console.log(data));

// 예상 응답:
// {
//   "success": true,
//   "data": {
//     "content": [],
//     "totalElements": 0,
//     ...
//   }
// }
```

### Test 3: 피드백 생성

```bash
# 터미널에서 (또는 브라우저 UI 사용)
curl -X POST https://$CLOUDFRONT_DOMAIN/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "username": "테스터",
    "message": "CloudFront + S3 + ALB 테스트!"
  }'

# 예상 응답:
{
  "success": true,
  "data": {
    "id": 1,
    "username": "테스터",
    "message": "CloudFront + S3 + ALB 테스트!",
    "createdAt": "2025-11-19T..."
  }
}
```

### Test 4: 피드백 조회

```bash
# 목록 조회
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks

# 브라우저 UI에서 확인
# → 방금 생성한 피드백이 목록에 표시되어야 함
```

### Test 5: CloudFront 캐싱 확인

```bash
# 정적 파일 (캐싱됨)
curl -I https://$CLOUDFRONT_DOMAIN/js/app.js | grep -i x-cache
# X-Cache: Hit from cloudfront  ← 두 번째 요청부터

# API (캐싱 안됨)
curl -I https://$CLOUDFRONT_DOMAIN/api/feedbacks | grep -i x-cache
# X-Cache: Miss from cloudfront  ← 항상 Miss
```

### Test 6: CORS 확인

```bash
# OPTIONS preflight 요청
curl -X OPTIONS https://$CLOUDFRONT_DOMAIN/api/feedbacks \
  -H "Origin: https://$CLOUDFRONT_DOMAIN" \
  -H "Access-Control-Request-Method: POST" \
  -i

# 예상 헤더:
# Access-Control-Allow-Origin: *
# Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
# Access-Control-Allow-Headers: Content-Type, Authorization
```

### Test 7: 에러 처리 (SPA 라우팅)

```bash
# 존재하지 않는 경로 접속
curl -I https://$CLOUDFRONT_DOMAIN/nonexistent

# 예상:
# HTTP/2 200  ← 404가 아님!
# → index.html이 반환됨 (SPA 라우팅)
```

### ✅ 최종 체크리스트

```
□ 프론트엔드 페이지 로드됨
□ CSS/JS 정상 작동
□ API 호출 성공 (네트워크 탭에서 200 응답)
□ 피드백 생성 가능
□ 피드백 조회 가능
□ 페이지네이션 동작
□ 필터링 동작
□ CloudFront 캐싱 동작 (X-Cache 헤더)
□ CORS 헤더 확인
□ SPA 라우팅 동작 (404 → index.html)
```

---

## Phase 8: 배포 자동화 (30분)

### Step 8-1: 프론트엔드 배포 스크립트 작성

```bash
# frontend/deploy.sh
cat > frontend/deploy.sh << 'EOF'
#!/bin/bash

set -e

echo "====================================="
echo "Frontend Deployment Script"
echo "====================================="

# 환경변수 확인
if [ -z "$S3_BUCKET" ]; then
  echo "❌ Error: S3_BUCKET environment variable not set"
  exit 1
fi

if [ -z "$DISTRIBUTION_ID" ]; then
  echo "❌ Error: DISTRIBUTION_ID environment variable not set"
  exit 1
fi

# 1. JS/CSS 업로드 (장기 캐싱)
echo "[1/4] Uploading JS/CSS files..."
aws s3 sync . s3://$S3_BUCKET/ \
  --exclude "index.html" \
  --exclude "*.sh" \
  --exclude ".git*" \
  --exclude "*.md" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete \
  --region ap-northeast-2

# 2. index.html 업로드 (단기 캐싱)
echo "[2/4] Uploading index.html..."
aws s3 cp index.html s3://$S3_BUCKET/index.html \
  --cache-control "public, max-age=300, must-revalidate" \
  --content-type "text/html" \
  --region ap-northeast-2

# 3. CloudFront 캐시 무효화
echo "[3/4] Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation ID: $INVALIDATION_ID"

# 4. 무효화 완료 대기 (선택)
echo "[4/4] Waiting for invalidation to complete..."
aws cloudfront wait invalidation-completed \
  --distribution-id $DISTRIBUTION_ID \
  --id $INVALIDATION_ID

echo "====================================="
echo "✅ Deployment Completed!"
echo "====================================="
echo "Frontend URL: https://$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' \
  --output text)/"
EOF

chmod +x frontend/deploy.sh
```

### Step 8-2: GitHub Actions 워크플로우 작성

```yaml
# .github/workflows/deploy-frontend.yml
cat > .github/workflows/deploy-frontend.yml << 'EOF'
name: Deploy Frontend to S3 + CloudFront

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
        id: get-resources
        run: |
          # S3 버킷 이름 (태그 기반 검색)
          BUCKET=$(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, 'feedback-frontend-')].Name | [0]" \
            --output text)
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT

          # CloudFront Distribution ID (태그 기반 검색)
          DIST_ID=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='CloudFront distribution for Feedback App'].Id | [0]" \
            --output text)
          echo "distribution=$DIST_ID" >> $GITHUB_OUTPUT

      - name: Sync JS/CSS to S3 (long cache)
        run: |
          aws s3 sync frontend/ s3://${{ steps.get-resources.outputs.bucket }}/ \
            --exclude "index.html" \
            --exclude "*.sh" \
            --exclude ".git*" \
            --exclude "*.md" \
            --cache-control "public, max-age=31536000, immutable" \
            --delete

      - name: Upload index.html (short cache)
        run: |
          aws s3 cp frontend/index.html s3://${{ steps.get-resources.outputs.bucket }}/index.html \
            --cache-control "public, max-age=300, must-revalidate" \
            --content-type "text/html"

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.get-resources.outputs.distribution }} \
            --paths "/*"

      - name: Deployment summary
        run: |
          CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
            --id ${{ steps.get-resources.outputs.distribution }} \
            --query 'Distribution.DomainName' \
            --output text)

          echo "====================================="
          echo "✅ Frontend Deployment Completed!"
          echo "====================================="
          echo "S3 Bucket: ${{ steps.get-resources.outputs.bucket }}"
          echo "CloudFront: https://$CLOUDFRONT_DOMAIN"
          echo "Git SHA: ${{ github.sha }}"
EOF
```

### Step 8-3: GitHub Secrets 확인

```bash
# GitHub Repository → Settings → Secrets and variables → Actions

# 필요한 Secrets:
□ AWS_ACCESS_KEY_ID
□ AWS_SECRET_ACCESS_KEY

# 이미 설정되어 있으면 OK!
```

### Step 8-4: 배포 테스트

```bash
# 파일 수정 (테스트)
cd frontend
echo "/* Updated */" >> css/style.css

# Git 커밋
git add .
git commit -m "test: Update frontend style"
git push origin main

# GitHub Actions 자동 실행 확인
# GitHub → Actions → Deploy Frontend to S3 + CloudFront
```

### ✅ 검증

```bash
# GitHub Actions 로그 확인
# → "✅ Frontend Deployment Completed!" 메시지

# 브라우저에서 확인
# → F5 새로고침
# → 변경사항 반영됨
```

---

## 트러블슈팅

### 문제 1: CloudFront에서 403 Forbidden

**증상**:
```bash
curl https://d123abc.cloudfront.net/
# 403 Forbidden
```

**원인**: S3 버킷 정책 누락 또는 OAC 설정 오류

**해결**:
```bash
# 1. 버킷 정책 확인
aws s3api get-bucket-policy --bucket $BUCKET_NAME

# 2. 버킷 정책 재적용 (Phase 5-6 참조)
# 3. CloudFront Distribution 재배포
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"
```

### 문제 2: API 요청 CORS 에러

**증상**:
```
Access to fetch at 'https://xxx.cloudfront.net/api/feedbacks'
has been blocked by CORS policy
```

**원인**: CloudFront Response Headers Policy 누락 또는 백엔드 CORS 설정 오류

**해결**:
```bash
# 1. 백엔드 CORS 설정 확인 (Phase 4-2)
# WebConfig.java의 allowedOriginPatterns("*") 확인

# 2. CloudFront Response Headers Policy 확인
aws cloudfront list-response-headers-policies \
  --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='API-CORS-Policy']"

# 3. Policy 재생성 (Phase 6-4 참조)
```

### 문제 3: API 요청 시 502 Bad Gateway

**증상**:
```bash
curl https://d123abc.cloudfront.net/api/feedbacks
# 502 Bad Gateway
```

**원인**: ALB Target이 Unhealthy 또는 CloudFront → ALB 연결 오류

**해결**:
```bash
# 1. Target Group 헬스 확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names feedback-tg \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)

# 2. ALB 직접 테스트
curl http://$(aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text)/api/feedbacks

# 3. CloudFront Origin 설정 확인
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.DistributionConfig.Origins.Items[?Id==`ALB-feedback-backend`]'
```

### 문제 4: 프론트엔드 업데이트가 반영 안됨

**증상**: 파일 수정 후 S3 업로드했는데 변경사항이 안 보임

**원인**: CloudFront 캐시

**해결**:
```bash
# 캐시 무효화 (Invalidation)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"

# 또는 특정 파일만
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/index.html" "/js/app.js"

# 완료 대기
aws cloudfront wait invalidation-completed \
  --distribution-id $DISTRIBUTION_ID \
  --id <INVALIDATION_ID>
```

### 문제 5: RDS 연결 실패

**증상**:
```
com.mysql.cj.jdbc.exceptions.CommunicationsException:
Communications link failure
```

**원인**: Security Group 또는 Subnet Group 설정 오류

**해결**:
```bash
# 1. RDS Security Group 확인
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rds-mysql-sg"

# 2. Inbound rule 확인 (3306 from app-sg)
# 3. RDS Subnet Group 확인
aws rds describe-db-subnet-groups \
  --db-subnet-group-name feedback-db-subnet-group

# 4. App 인스턴스에서 연결 테스트
# SSH로 접속 후:
mysql -h <RDS_ENDPOINT> -u admin -p
```

### 문제 6: GitHub Actions 배포 실패

**증상**: GitHub Actions에서 "Access Denied" 에러

**원인**: IAM 권한 부족

**해결**:
```bash
# IAM User에 필요한 권한 추가
# - AmazonS3FullAccess
# - CloudFrontFullAccess
# - 또는 커스텀 정책:

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::feedback-frontend-*",
        "arn:aws:s3:::feedback-frontend-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetDistribution",
        "cloudfront:ListDistributions"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 리소스 정리 (구축 후 5일 뒤)

### Step 1: CloudFront 비활성화 및 삭제

```bash
# 1. Distribution 비활성화
aws cloudfront get-distribution-config \
  --id $DISTRIBUTION_ID \
  --output json > /tmp/dist-config.json

# Enabled를 false로 변경
# (JSON 파일 수동 편집)

aws cloudfront update-distribution \
  --id $DISTRIBUTION_ID \
  --if-match $(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'ETag' --output text) \
  --distribution-config file:///tmp/dist-config.json

# 2. 배포 대기 (5-10분)
aws cloudfront wait distribution-deployed --id $DISTRIBUTION_ID

# 3. 삭제
aws cloudfront delete-distribution \
  --id $DISTRIBUTION_ID \
  --if-match $(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'ETag' --output text)
```

### Step 2: S3 버킷 삭제

```bash
# 버킷 비우기
aws s3 rm s3://$BUCKET_NAME --recursive

# 버킷 삭제
aws s3 rb s3://$BUCKET_NAME
```

### Step 3: RDS 삭제

```bash
# 스냅샷 없이 삭제
aws rds delete-db-instance \
  --db-instance-identifier feedback-db \
  --skip-final-snapshot

# 또는 스냅샷 생성 후 삭제
aws rds delete-db-instance \
  --db-instance-identifier feedback-db \
  --final-db-snapshot-identifier feedback-db-final-snapshot
```

### Step 4: 나머지 리소스 삭제

```bash
# ASG 삭제
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name feedback-asg \
  --force-delete

# ALB 삭제
aws elbv2 delete-load-balancer \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
    --names feedback-alb \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)

# Target Group 삭제
aws elbv2 delete-target-group \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names feedback-tg \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)

# Security Groups 삭제 (의존성 역순)
aws ec2 delete-security-group --group-id <app-sg-id>
aws ec2 delete-security-group --group-id <alb-sg-id>
aws ec2 delete-security-group --group-id <rds-sg-id>

# VPC 삭제
aws ec2 delete-vpc --vpc-id <vpc-id>
```

---

## 비용 요약 (월 기준)

```
CloudFront:
  - 첫 50GB 데이터 전송: 무료
  - 50GB 초과: $0.085/GB
  - 예상: ~$10-15/월

S3:
  - 스토리지: $0.025/GB
  - 요청: $0.0004/1000 PUT, $0.00004/1000 GET
  - 예상: ~$1/월

ALB: ~$27.50/월
EC2 (t3.small × 2): ~$30/월
RDS (db.t3.micro): ~$26/월

총: ~$94.50 - 99.50/월
```

---

## 참고 자료

### AWS 문서
- [CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/s3/latest/userguide/WebsiteHosting.html)
- [RDS MySQL](https://docs.aws.amazon.com/rds/latest/userguide/CHAP_MySQL.html)

### 프로젝트 문서
- `IMPLEMENTATION_GUIDE.md` - 통합 아키텍처 구축 가이드
- `ARCHITECTURE_EXPLAINED.md` - 아키텍처 설명
- `FULL_ARCHITECTURE_WITH_ROLLBACK.md` - 롤백 포함 전체 구조

---

## 최종 체크리스트

```
□ Phase 1: 프로젝트 구조 변경 (frontend/ 디렉토리)
□ Phase 2: RDS 생성 및 엔드포인트 확인
□ Phase 3: S3 버킷 생성 및 파일 업로드
□ Phase 4: 백엔드 CORS 설정 및 배포
□ Phase 5: CloudFront Distribution 생성
□ Phase 6: 프론트엔드 배포 및 캐시 무효화
□ Phase 7: 통합 테스트 (프론트엔드 + API)
□ Phase 8: GitHub Actions 배포 자동화
```

**🎉 완료! 프로덕션급 프론트엔드/백엔드 분리 아키텍처 구축 성공!**

---

**End of Guide** 🚀
