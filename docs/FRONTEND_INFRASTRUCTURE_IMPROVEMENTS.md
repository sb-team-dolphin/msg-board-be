# 프론트엔드 인프라 개선 제안

## 현재 구조
```
사용자 → CloudFront → S3
         ↓
    자동 배포 (GitHub Actions)
    롤백 시스템 (S3 Versioning)
```

---

## 우선순위별 개선 사항

### 🔥 Priority 1: 필수 (보안 & 성능)

#### 1. HTTPS + 커스텀 도메인 (SSL/TLS)

**현재 문제:**
- CloudFront 기본 도메인: `d123456.cloudfront.net` (신뢰도 낮음)
- HTTP 사용 시 브라우저 경고

**해결 방안:**
```
사용자 → https://feedback.yourdomain.com (커스텀 도메인)
         ↓
    CloudFront (ACM 인증서)
         ↓
    S3
```

**구축 방법:**

##### Step 1: 도메인 준비
- Route 53에서 도메인 구매 (연 $12~) 또는
- 기존 도메인 사용 (가비아, Cloudflare 등)

##### Step 2: ACM 인증서 발급
```bash
# AWS Certificate Manager (무료!)
# 리전: us-east-1 (CloudFront용은 반드시 버지니아)

aws acm request-certificate \
  --domain-name feedback.yourdomain.com \
  --validation-method DNS \
  --region us-east-1
```

##### Step 3: CloudFront에 연결
- CloudFront → Distribution → Edit
- Alternate Domain Names (CNAMEs): `feedback.yourdomain.com`
- Custom SSL Certificate: ACM 인증서 선택

##### Step 4: DNS 설정
- Route 53 (또는 도메인 제공자)
- A 레코드 생성:
  - Name: `feedback`
  - Type: A - IPv4 address
  - Alias: CloudFront distribution

**장점:**
- ✅ 브라우저 경고 없음
- ✅ SEO 향상
- ✅ 신뢰도 증가
- ✅ 무료 (ACM 인증서)

**비용:** $12/년 (도메인만, 인증서는 무료)

---

#### 2. WAF (Web Application Firewall)

**현재 문제:**
- DDoS 공격에 취약
- Bot 트래픽 차단 불가
- SQL Injection, XSS 공격 방어 없음

**해결 방안:**
```
사용자 → WAF (공격 차단) → CloudFront → S3
         ↓ (차단 규칙)
    - Rate limiting
    - Geo blocking
    - Bot detection
```

**구축 방법:**

##### AWS WAF 생성
```bash
# Web ACL 생성
aws wafv2 create-web-acl \
  --name feedback-frontend-waf \
  --scope CLOUDFRONT \
  --default-action Allow={} \
  --rules file://waf-rules.json \
  --region us-east-1
```

##### 기본 보호 규칙 (waf-rules.json):
```json
[
  {
    "Name": "RateLimitRule",
    "Priority": 1,
    "Statement": {
      "RateBasedStatement": {
        "Limit": 2000,
        "AggregateKeyType": "IP"
      }
    },
    "Action": { "Block": {} }
  },
  {
    "Name": "AWSManagedRulesCommonRuleSet",
    "Priority": 2,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesCommonRuleSet"
      }
    },
    "OverrideAction": { "None": {} }
  }
]
```

**보호 기능:**
- ✅ Rate Limiting: 5분당 2000 요청 제한
- ✅ SQL Injection 차단
- ✅ XSS 공격 차단
- ✅ Known bad inputs 차단

**비용:**
- Web ACL: $5/월
- 규칙: $1/월 per rule
- 요청: $0.60 per 1M requests
- **예상: ~$10/월**

---

#### 3. CloudFront Origin Access Control (OAC)

**현재 문제:**
- S3 버킷이 public으로 설정되어 있다면 누구나 직접 접근 가능
- CloudFront 우회 가능

**해결 방안:**
```
사용자 → CloudFront (유일한 진입점) → S3 (Private)
         ↓ OAC 인증
    S3 버킷 정책으로 CloudFront만 허용
```

**구축 방법:**

##### Step 1: OAC 생성
```bash
aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "feedback-s3-oac",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }'
```

##### Step 2: CloudFront에 연결
- CloudFront → Distribution → Origins → Edit
- Origin access: Origin access control settings (recommended)
- OAC 선택

##### Step 3: S3 버킷 정책 업데이트
```json
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
      "Resource": "arn:aws:s3:::your-bucket-name/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DISTRIBUTION_ID"
        }
      }
    }
  ]
}
```

##### Step 4: S3 Public Access 차단
- S3 → 버킷 → Permissions
- Block all public access: ON

**장점:**
- ✅ S3 직접 접근 불가 (보안 강화)
- ✅ CloudFront만 접근 가능
- ✅ 비용 절감 (S3 트래픽 무료화)

**비용:** 무료

---

### ⚡ Priority 2: 성능 최적화

#### 4. CloudFront Functions (Edge Computing)

**용도:**
- 리다이렉트 (HTTP → HTTPS)
- 헤더 추가 (보안 헤더)
- URL 정규화
- A/B 테스트

**예시: 보안 헤더 추가**

```javascript
// cloudfront-function.js
function handler(event) {
    var response = event.response;
    var headers = response.headers;

    // 보안 헤더 추가
    headers['strict-transport-security'] = {
        value: 'max-age=63072000; includeSubdomains; preload'
    };
    headers['x-content-type-options'] = { value: 'nosniff' };
    headers['x-frame-options'] = { value: 'DENY' };
    headers['x-xss-protection'] = { value: '1; mode=block' };
    headers['referrer-policy'] = { value: 'strict-origin-when-cross-origin' };

    return response;
}
```

**구축:**
```bash
# CloudFront Function 생성
aws cloudfront create-function \
  --name add-security-headers \
  --function-code fileb://cloudfront-function.js \
  --function-config Comment="Add security headers",Runtime="cloudfront-js-1.0"

# CloudFront에 연결
# CloudFront → Distribution → Behaviors → Edit
# Function associations → Viewer response → 함수 선택
```

**장점:**
- ✅ 엣지에서 즉시 실행 (초고속)
- ✅ 보안 점수 향상 (lighthouse, observatory)
- ✅ 저렴한 비용

**비용:** $0.10 per 1M invocations (거의 무료)

---

#### 5. 이미지 최적화 (CloudFront + Lambda@Edge)

**현재 문제:**
- 모든 디바이스에 동일한 크기 이미지 제공
- WebP, AVIF 등 최신 포맷 미지원

**해결 방안:**
```
사용자 → CloudFront → Lambda@Edge (이미지 변환) → S3
         ↓
    자동으로 적절한 크기/포맷 제공
    - 모바일: 작은 이미지
    - 데스크톱: 큰 이미지
    - WebP 지원: WebP 제공
```

**구축 방법:**

##### Lambda@Edge 함수 (예시):
```javascript
// image-optimization.js
const sharp = require('sharp');

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // 디바이스 감지
    const userAgent = headers['user-agent'][0].value;
    const isMobile = /mobile/i.test(userAgent);

    // 이미지 크기 결정
    const width = isMobile ? 640 : 1920;

    // S3에서 원본 이미지 가져오기
    // Sharp로 리사이즈 + WebP 변환
    // 캐싱

    return response;
};
```

**또는 AWS 관리형 서비스:**
- AWS CloudFront + S3 Image Handler (무료 템플릿)

**장점:**
- ✅ 이미지 로딩 속도 2-3배 향상
- ✅ 트래픽 비용 50% 절감
- ✅ 자동 포맷 변환 (WebP, AVIF)

**비용:** Lambda@Edge: $0.60 per 1M requests

---

#### 6. 정적 자산 압축 (Gzip / Brotli)

**현재 상태:**
- CloudFront 기본 Gzip 압축 사용 중 (자동)

**개선 방안:**
- Brotli 압축 활성화 (Gzip보다 15-20% 더 압축)

**구축:**
```bash
# CloudFront 설정
# Distribution → Behaviors → Edit
# Compress objects automatically: Yes (이미 활성화됨)
# CloudFront는 자동으로 Accept-Encoding에 따라 Gzip/Brotli 제공
```

**추가 최적화: 빌드 시 사전 압축**

GitHub Actions에 추가:
```yaml
- name: Pre-compress static files
  run: |
    # Brotli 압축 (.br 파일 생성)
    find . -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) \
      -exec brotli -k {} \;

    # Gzip 압축 (.gz 파일 생성)
    find . -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) \
      -exec gzip -k {} \;

- name: Upload to S3 with proper Content-Encoding
  run: |
    # .br 파일 업로드
    aws s3 sync . s3://bucket/ \
      --exclude "*" \
      --include "*.br" \
      --content-encoding br

    # .gz 파일 업로드
    aws s3 sync . s3://bucket/ \
      --exclude "*" \
      --include "*.gz" \
      --content-encoding gzip
```

**장점:**
- ✅ 빌드 시 압축 (엣지에서 CPU 절약)
- ✅ 전송 크기 50-70% 감소

---

### 📊 Priority 3: 모니터링 & 분석

#### 7. CloudWatch RUM (Real User Monitoring)

**용도:**
- 실제 사용자의 성능 지표 수집
- 페이지 로딩 시간
- JavaScript 에러 추적
- 사용자 경험 분석

**구축:**
```javascript
// index.html에 추가
<script>
(function(n,i,v,r,s,c,x,z){
  // CloudWatch RUM 스크립트
})('YOUR_APP_ID','YOUR_REGION');
</script>
```

**대시보드에서 확인:**
- 페이지 로딩 시간
- JavaScript 에러
- API 호출 성능
- 사용자 지역 분포

**비용:** $1 per 100,000 events

---

#### 8. CloudFront 로그 분석

**현재 상태:**
- 로그 비활성화 (기본값)

**개선:**
```
CloudFront → S3 (로그 저장) → Athena (쿼리) → QuickSight (대시보드)
```

**구축:**
```bash
# CloudFront 로그 활성화
# Distribution → Edit
# Standard Logging: On
# S3 Bucket: logs-bucket
# Log Prefix: cloudfront/feedback/
```

**Athena 쿼리 예시:**
```sql
-- 가장 많이 방문한 페이지
SELECT
  request_uri,
  COUNT(*) as hits
FROM cloudfront_logs
WHERE date = '2025-11-20'
GROUP BY request_uri
ORDER BY hits DESC
LIMIT 10;

-- 국가별 트래픽
SELECT
  country,
  COUNT(*) as requests
FROM cloudfront_logs
GROUP BY country
ORDER BY requests DESC;
```

**장점:**
- ✅ 트래픽 패턴 분석
- ✅ 인기 콘텐츠 파악
- ✅ 캐시 히트율 확인

**비용:** S3 스토리지 ($0.023/GB) + Athena 쿼리 ($5 per TB scanned)

---

### 🚀 Priority 4: 고급 기능

#### 9. CloudFront Geo Restriction (지역 차단)

**용도:**
- 특정 국가만 접근 허용/차단
- 라이선스 제한
- 규정 준수 (GDPR 등)

**구축:**
```bash
# 한국에서만 접근 허용
aws cloudfront update-distribution \
  --id DISTRIBUTION_ID \
  --distribution-config '{
    "GeoRestriction": {
      "RestrictionType": "whitelist",
      "Quantity": 1,
      "Items": ["KR"]
    }
  }'
```

**비용:** 무료

---

#### 10. 다중 환경 배포 (Dev / Staging / Prod)

**현재:**
- main 브랜치 → 프로덕션만 배포

**개선:**
```
dev 브랜치 → dev.feedback.com (개발 환경)
staging 브랜치 → staging.feedback.com (스테이징)
main 브랜치 → feedback.com (프로덕션)
```

**GitHub Actions:**
```yaml
on:
  push:
    branches:
      - dev
      - staging
      - main

jobs:
  deploy:
    steps:
      - name: Determine environment
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            echo "ENV=prod" >> $GITHUB_ENV
            echo "BUCKET=prod-bucket" >> $GITHUB_ENV
          elif [ "${{ github.ref }}" = "refs/heads/staging" ]; then
            echo "ENV=staging" >> $GITHUB_ENV
            echo "BUCKET=staging-bucket" >> $GITHUB_ENV
          else
            echo "ENV=dev" >> $GITHUB_ENV
            echo "BUCKET=dev-bucket" >> $GITHUB_ENV
          fi

      - name: Deploy to S3
        run: aws s3 sync . s3://${{ env.BUCKET }}/
```

**비용:** 추가 S3 버킷 ($1-2/월)

---

## 📊 우선순위별 구축 계획

### 단계별 로드맵

#### Phase 1: 보안 강화 (1-2일)
```
1. ✅ S3 Versioning 활성화 (완료)
2. 🔲 CloudFront OAC 설정 (보안)
3. 🔲 WAF 기본 규칙 적용
4. 🔲 HTTPS + 커스텀 도메인 (선택)
```

**비용:** $10/월 (WAF) + $12/년 (도메인, 선택사항)

#### Phase 2: 성능 최적화 (1일)
```
1. 🔲 CloudFront Functions (보안 헤더)
2. 🔲 Brotli 압축 활성화
3. 🔲 캐시 설정 최적화
```

**비용:** 거의 무료 (~$1/월)

#### Phase 3: 모니터링 (1일)
```
1. 🔲 CloudFront 로그 활성화
2. 🔲 CloudWatch Alarms 설정
3. 🔲 RUM (선택)
```

**비용:** $1-5/월

---

## 💰 비용 요약

### 현재 구조
- CloudFront: $1/월
- S3: $0.50/월
- **총합: ~$1.50/월**

### 개선 후 (최소)
- CloudFront: $1/월
- S3: $0.50/월
- WAF: $10/월
- CloudFront Functions: $0.10/월
- **총합: ~$12/월**

### 개선 후 (최대 - 모든 기능)
- CloudFront: $1/월
- S3: $0.50/월
- 도메인: $1/월 (연 $12)
- WAF: $10/월
- CloudFront Functions: $0.10/월
- RUM: $2/월
- 로그 저장: $1/월
- **총합: ~$15/월**

---

## 🎯 추천 구성 (소규모 프로젝트)

### 필수 (지금 바로)
1. ✅ **OAC (Origin Access Control)** - 무료, 보안 필수
2. ✅ **CloudFront Functions** - 거의 무료, 보안 헤더
3. ✅ **Brotli 압축** - 무료, 성능 향상

### 선택 (트래픽 증가 시)
1. 🔲 **WAF** - $10/월, DDoS 방어
2. 🔲 **커스텀 도메인 + HTTPS** - $12/년, 신뢰도

### 나중에 (스케일 업 시)
1. 🔲 **CloudWatch RUM** - 사용자 모니터링
2. 🔲 **이미지 최적화** - 이미지 많을 때
3. 🔲 **다중 환경** - 팀 규모 커질 때

---

## 🚀 즉시 적용 가능한 개선 사항 (무료)

### 1. OAC 설정 (5분)
S3를 private으로 만들고 CloudFront만 접근 허용

### 2. 보안 헤더 추가 (10분)
CloudFront Functions로 보안 점수 향상

### 3. 캐시 최적화 (5분)
TTL 조정으로 성능/비용 개선

이 3가지부터 시작하시겠어요? 스크립트 만들어드릴까요?
