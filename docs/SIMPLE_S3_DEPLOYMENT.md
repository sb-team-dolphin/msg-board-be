# 🚀 초간단 S3 정적 호스팅 가이드

**목표**: 프론트엔드를 S3에 배포하고 백엔드와 분리
**소요 시간**: 30분
**난이도**: ⭐☆☆☆☆ (매우 쉬움)

---

## 📊 최종 구조

```
프론트엔드 (S3):
  http://feedback-frontend.s3-website.ap-northeast-2.amazonaws.com
  ├─ index.html
  ├─ js/app.js
  └─ css/style.css

백엔드 (ALB + Spring Boot):
  http://feedback-alb-xxx.elb.amazonaws.com
  └─ /api/feedbacks → JSON
```

---

## Step 1: 프론트엔드 파일 준비 (5분)

### 1-1. frontend 디렉토리 생성

```bash
cd C:/2025proj/simple-api

# 디렉토리 생성
mkdir frontend
mkdir frontend/js
mkdir frontend/css
```

### 1-2. 파일 복사

```bash
# 기존 파일 복사
cp src/main/resources/static/index.html frontend/
cp src/main/resources/static/js/app.js frontend/js/
cp src/main/resources/static/css/style.css frontend/css/
```

### 1-3. app.js 수정 (API 엔드포인트)

**파일**: `frontend/js/app.js`

**찾기**:
```javascript
const API_BASE_URL = '/api';
```

**바꾸기**:
```javascript
// ALB 주소로 변경! (실제 ALB DNS로 바꿔야 함)
const API_BASE_URL = 'http://feedback-alb-xxx.ap-northeast-2.elb.amazonaws.com/api';
```

**⚠️ 중요**: `feedback-alb-xxx...`를 실제 ALB DNS로 변경!

**ALB DNS 확인 방법**:
```bash
aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text
```

---

## Step 2: S3 버킷 생성 (5분)

### 2-1. 버킷 생성

```bash
# 버킷 이름 (전역 고유해야 함!)
BUCKET_NAME="feedback-frontend-$(date +%s)"
echo "Bucket Name: $BUCKET_NAME"

# 버킷 생성
aws s3 mb s3://$BUCKET_NAME --region ap-northeast-2
```

### 2-2. 정적 웹사이트 호스팅 활성화

```bash
# 정적 웹사이트 설정
aws s3 website s3://$BUCKET_NAME/ \
  --index-document index.html \
  --error-document index.html
```

### 2-3. 버킷 정책 설정 (Public 읽기 허용)

```bash
cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

# 정책 적용
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/bucket-policy.json

# Public Access Block 해제 (필수!)
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

---

## Step 3: 파일 업로드 (5분)

### 3-1. frontend 파일 업로드

```bash
cd frontend/

# S3 업로드
aws s3 sync . s3://$BUCKET_NAME/ \
  --region ap-northeast-2

# 확인
aws s3 ls s3://$BUCKET_NAME/ --recursive
```

### 3-2. S3 웹사이트 URL 확인

```bash
echo "Frontend URL: http://${BUCKET_NAME}.s3-website.ap-northeast-2.amazonaws.com"
```

**⭐ 이 URL을 메모장에 복사!**

---

## Step 4: 백엔드 CORS 설정 (10분)

### 4-1. WebConfig.java 생성/수정

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
                .allowedOriginPatterns("*")  // 모든 Origin 허용 (개발용)
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
```

**⚠️ 보안**: 실제 운영에서는 S3 URL만 허용하세요:
```java
.allowedOrigins("http://feedback-frontend-123.s3-website.ap-northeast-2.amazonaws.com")
```

### 4-2. 백엔드 재배포

```bash
# 로컬 빌드
./gradlew clean build

# Git 커밋
git add .
git commit -m "feat: Add CORS configuration for S3 frontend"
git push origin main

# GitHub Actions 배포
# GitHub → Actions → Deploy to ASG → Run workflow
```

**대기**: 15분 (Instance Refresh)

---

## Step 5: 테스트 (5분)

### 5-1. 프론트엔드 접속

```bash
# 브라우저에서 열기
S3_URL="http://${BUCKET_NAME}.s3-website.ap-northeast-2.amazonaws.com"

# Windows
start $S3_URL

# Mac
open $S3_URL

# Linux
xdg-open $S3_URL
```

### 5-2. 브라우저 개발자 도구 확인

```
F12 → Network 탭

1. index.html 로드됨 (from S3)
2. app.js 로드됨 (from S3)
3. /api/feedbacks 요청 (to ALB)
4. JSON 응답 받음

✅ 성공!
```

### 5-3. 피드백 생성 테스트

```
1. 브라우저에서 프론트엔드 접속
2. 이름: "테스터"
3. 메시지: "S3 배포 테스트!"
4. [작성하기] 클릭

→ 피드백 목록에 표시되면 성공! ✅
```

### 5-4. CORS 에러 발생 시

**증상**:
```
Access to fetch at 'http://feedback-alb-xxx...' from origin 'http://feedback-frontend-xxx.s3-website...'
has been blocked by CORS policy
```

**해결**:
```bash
# 백엔드 로그 확인
# AWS Console → EC2 → Instances → 인스턴스 선택
# SSH 접속:
ssh -i your-key.pem ec2-user@[Instance-Public-IP]

# Docker 로그 확인
sudo docker logs feedback-api | grep CORS

# WebConfig.java가 적용되었는지 확인
# GitHub Actions 배포가 완료되었는지 확인
```

---

## Step 6: 프론트엔드 업데이트 (2분)

### 6-1. 파일 수정 후 재배포

```bash
cd frontend/

# 파일 수정 (예: CSS)
echo "/* Updated */" >> css/style.css

# S3 재업로드
aws s3 sync . s3://$BUCKET_NAME/ --region ap-northeast-2

# 브라우저 새로고침 (Ctrl+F5)
# → 변경사항 즉시 반영! ✅
```

---

## 배포 스크립트 (선택)

### frontend/deploy.sh

```bash
cat > frontend/deploy.sh << 'EOF'
#!/bin/bash

# S3 버킷 이름 설정
BUCKET_NAME="your-bucket-name"  # ⭐ 실제 버킷 이름으로 변경!

echo "====================================="
echo "Deploying to S3..."
echo "====================================="

# 파일 업로드
aws s3 sync . s3://$BUCKET_NAME/ \
  --exclude "*.sh" \
  --exclude ".git*" \
  --delete \
  --region ap-northeast-2

echo "✅ Deployment completed!"
echo "Frontend URL: http://${BUCKET_NAME}.s3-website.ap-northeast-2.amazonaws.com"
EOF

chmod +x frontend/deploy.sh

# 사용법
cd frontend
./deploy.sh
```

---

## GitHub Actions 자동 배포 (선택)

### .github/workflows/deploy-frontend-s3.yml

```yaml
name: Deploy Frontend to S3

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

      - name: Get S3 bucket name
        id: get-bucket
        run: |
          BUCKET=$(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, 'feedback-frontend-')].Name | [0]" \
            --output text)
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT

      - name: Update API endpoint
        run: |
          # ALB DNS 가져오기
          ALB_DNS=$(aws elbv2 describe-load-balancers \
            --names feedback-alb \
            --query "LoadBalancers[0].DNSName" \
            --output text)

          # app.js 수정
          sed -i "s|const API_BASE_URL = .*|const API_BASE_URL = 'http://${ALB_DNS}/api';|" \
            frontend/js/app.js

      - name: Sync to S3
        run: |
          aws s3 sync frontend/ s3://${{ steps.get-bucket.outputs.bucket }}/ \
            --exclude "*.sh" \
            --exclude ".git*" \
            --delete

      - name: Deployment summary
        run: |
          BUCKET=${{ steps.get-bucket.outputs.bucket }}
          echo "✅ Deployment completed!"
          echo "Frontend URL: http://${BUCKET}.s3-website.ap-northeast-2.amazonaws.com"
```

---

## 트러블슈팅

### 문제 1: S3 URL 접속 시 404 Not Found

**원인**: 정적 웹사이트 호스팅 미설정

**해결**:
```bash
aws s3 website s3://$BUCKET_NAME/ \
  --index-document index.html \
  --error-document index.html
```

### 문제 2: API 호출 시 CORS 에러

**원인**: 백엔드 CORS 설정 누락

**해결**:
1. WebConfig.java 확인
2. 백엔드 재배포 확인
3. 브라우저 캐시 삭제 (Ctrl+Shift+Delete)

### 문제 3: API 호출 시 "net::ERR_CONNECTION_REFUSED"

**원인**: app.js의 ALB DNS가 잘못됨

**해결**:
```bash
# ALB DNS 재확인
aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text

# app.js 수정
# const API_BASE_URL = 'http://[실제-ALB-DNS]/api';
```

### 문제 4: "Access Denied" 에러

**원인**: 버킷 정책 누락

**해결**:
```bash
# Public Access Block 확인
aws s3api get-public-access-block --bucket $BUCKET_NAME

# 모두 false로 설정
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# 버킷 정책 재적용 (Step 2-3 참조)
```

---

## 리소스 정리 (필요 시)

```bash
# S3 버킷 비우기
aws s3 rm s3://$BUCKET_NAME --recursive

# S3 버킷 삭제
aws s3 rb s3://$BUCKET_NAME
```

---

## 비용

```
S3:
  - 스토리지 (50KB): ~$0.001/월
  - GET 요청 (1000회/일): ~$0.01/월

총: ~$1/월 이하 (거의 무료!)
```

---

## 최종 체크리스트

```
□ frontend/ 디렉토리 생성 및 파일 복사
□ app.js API 엔드포인트 수정 (ALB DNS)
□ S3 버킷 생성
□ 정적 웹사이트 호스팅 활성화
□ 버킷 정책 설정 (Public 읽기)
□ 파일 업로드
□ 백엔드 CORS 설정
□ 백엔드 재배포
□ 브라우저 테스트 (프론트엔드 접속)
□ API 호출 테스트 (피드백 생성/조회)
```

---

## 다음 단계 (선택)

만약 더 나은 성능과 보안이 필요하다면:

1. **Option 2: CloudFront 추가**
   - `FRONTEND_BACKEND_SEPARATION_GUIDE.md` 참조
   - HTTPS 지원
   - 글로벌 CDN
   - 단일 도메인

2. **커스텀 도메인 연결**
   - Route 53 설정
   - www.yourdomain.com

3. **CI/CD 자동화**
   - GitHub Actions 워크플로우
   - 자동 배포

---

**🎉 완료! 가장 쉬운 방법으로 프론트엔드/백엔드 분리 성공!**

**Frontend**: http://feedback-frontend-xxx.s3-website.ap-northeast-2.amazonaws.com
**Backend**: http://feedback-alb-xxx.ap-northeast-2.elb.amazonaws.com/api

---

**End of Simple Guide** 🚀
