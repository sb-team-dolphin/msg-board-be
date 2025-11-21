# 프론트엔드 레포 분리 가이드

## 목표
`simple-api` 레포에서 프론트엔드를 분리하여 `simple-api-frontend` 레포로 독립

---

## 단계별 가이드

### Step 1: GitHub에서 새 레포 생성

1. https://github.com/new 접속
2. 레포 이름: `simple-api-frontend`
3. Public 선택
4. **"Add a README file" 체크 해제** (나중에 직접 생성)
5. **Create repository** 클릭

### Step 2: 로컬에서 프론트엔드 레포 생성

Windows PowerShell 또는 Git Bash에서:

```bash
# 1. 새 디렉토리 생성 및 이동
cd C:/2025proj
mkdir simple-api-frontend
cd simple-api-frontend

# 2. Git 초기화
git init
git branch -M main

# 3. 기존 프로젝트에서 프론트엔드 파일 복사
cp -r ../simple-api/frontend/* ./

# 4. 디렉토리 구조 확인
ls
# 예상 출력:
# css/
# js/
# index.html
```

### Step 3: GitHub Actions 워크플로우 생성

```bash
# .github/workflows 디렉토리 생성
mkdir -p .github/workflows
```

`.github/workflows/deploy-cloudfront.yml` 파일 생성:

```yaml
name: Deploy to CloudFront

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  AWS_REGION: ap-northeast-2

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Find CloudFront distribution
        id: find-cf
        run: |
          DISTRIBUTION_ID=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='feedback-app-frontend'].Id | [0]" \
            --output text)

          if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
            echo "❌ CloudFront distribution not found!"
            exit 1
          fi

          echo "distribution_id=$DISTRIBUTION_ID" >> $GITHUB_OUTPUT
          echo "✅ Found distribution: $DISTRIBUTION_ID"

      - name: Get S3 bucket
        id: get-bucket
        run: |
          BUCKET_DOMAIN=$(aws cloudfront get-distribution \
            --id ${{ steps.find-cf.outputs.distribution_id }} \
            --query "Distribution.DistributionConfig.Origins.Items[?contains(DomainName, 's3')].DomainName | [0]" \
            --output text)

          BUCKET_NAME=${BUCKET_DOMAIN%%.s3.*.amazonaws.com}

          echo "bucket=$BUCKET_NAME" >> $GITHUB_OUTPUT
          echo "✅ S3 Bucket: $BUCKET_NAME"

      - name: Sync static assets to S3 (long cache)
        run: |
          aws s3 sync . s3://${{ steps.get-bucket.outputs.bucket }}/ \
            --exclude ".git*" \
            --exclude "*.sh" \
            --exclude "README.md" \
            --exclude "index.html" \
            --delete \
            --cache-control "public, max-age=31536000"

      - name: Upload index.html (short cache)
        run: |
          aws s3 cp index.html s3://${{ steps.get-bucket.outputs.bucket }}/index.html \
            --cache-control "public, max-age=300" \
            --content-type "text/html"

      - name: Invalidate CloudFront cache
        id: invalidate
        run: |
          INVALIDATION_ID=$(aws cloudfront create-invalidation \
            --distribution-id ${{ steps.find-cf.outputs.distribution_id }} \
            --paths "/*" \
            --query "Invalidation.Id" \
            --output text)

          echo "invalidation_id=$INVALIDATION_ID" >> $GITHUB_OUTPUT
          echo "✅ Cache invalidation created: $INVALIDATION_ID"

      - name: Get CloudFront domain
        id: get-domain
        run: |
          DOMAIN=$(aws cloudfront get-distribution \
            --id ${{ steps.find-cf.outputs.distribution_id }} \
            --query "Distribution.DomainName" \
            --output text)

          echo "domain=$DOMAIN" >> $GITHUB_OUTPUT

      - name: Deployment summary
        run: |
          echo "======================================"
          echo "✅ Frontend Deployment Complete"
          echo "======================================"
          echo "CloudFront URL: https://${{ steps.get-domain.outputs.domain }}"
          echo "Distribution ID: ${{ steps.find-cf.outputs.distribution_id }}"
          echo "S3 Bucket: ${{ steps.get-bucket.outputs.bucket }}"
          echo "Invalidation ID: ${{ steps.invalidate.outputs.invalidation_id }}"
          echo ""
          echo "⏳ Cache invalidation in progress (1-3 minutes)"
```

### Step 4: README.md 생성

`README.md` 파일 생성:

```markdown
# Simple API Frontend

피드백 보드 프론트엔드 애플리케이션

## 아키텍처
- **호스팅**: AWS CloudFront + S3
- **배포**: GitHub Actions (자동)
- **스타일**: Tailwind CSS (CDN)
- **JavaScript**: Vanilla JS

## 배포 방식
- `main` 브랜치에 push → 자동으로 CloudFront + S3 배포
- CloudFront 캐시 무효화 자동 실행 (1-3분 소요)

## 로컬 개발

### 1. 간단한 HTTP 서버 실행
```bash
# Python 3
python -m http.server 8000

# Node.js
npx serve .

# PHP
php -S localhost:8000
```

### 2. 브라우저에서 확인
http://localhost:8000

## 프로젝트 구조
```
simple-api-frontend/
├── index.html          # 메인 HTML
├── css/
│   └── style.css       # 커스텀 스타일
├── js/
│   └── app.js          # 메인 JavaScript
├── .github/
│   └── workflows/
│       └── deploy-cloudfront.yml  # 배포 워크플로우
└── README.md
```

## 백엔드 API 연동
백엔드 레포: https://github.com/johnhuh619/simple-api

## 환경 변수 (GitHub Secrets)
- `AWS_ACCESS_KEY_ID` - AWS 액세스 키
- `AWS_SECRET_ACCESS_KEY` - AWS 시크릿 키

## 배포 확인
GitHub Actions: https://github.com/johnhuh619/simple-api-frontend/actions
```

### Step 5: .gitignore 생성

`.gitignore` 파일 생성:

```
.DS_Store
*.log
node_modules/
.env
.vscode/
.idea/
```

### Step 6: Git 커밋 및 푸시

```bash
# 모든 파일 추가
git add .

# 커밋
git commit -m "Initial commit: Frontend separation from simple-api"

# 원격 레포 연결
git remote add origin https://github.com/johnhuh619/simple-api-frontend.git

# 푸시
git push -u origin main
```

### Step 7: GitHub Secrets 설정

1. https://github.com/johnhuh619/simple-api-frontend/settings/secrets/actions
2. **New repository secret** 클릭
3. 다음 2개 추가:
   - `AWS_ACCESS_KEY_ID`: (기존 simple-api 레포에서 사용 중인 값)
   - `AWS_SECRET_ACCESS_KEY`: (기존 simple-api 레포에서 사용 중인 값)

### Step 8: 배포 테스트

```bash
# 간단한 변경사항 추가
echo "<!-- Test deployment -->" >> index.html

# 커밋 및 푸시
git add index.html
git commit -m "test: Verify automatic deployment"
git push
```

GitHub Actions에서 자동 배포 확인:
- https://github.com/johnhuh619/simple-api-frontend/actions

---

## Step 9: 백엔드 레포 정리 (simple-api)

프론트엔드가 분리되었으므로 백엔드 레포 정리:

```bash
cd C:/2025proj/simple-api

# 1. frontend/ 디렉토리 삭제
rm -rf frontend/

# 2. 프론트엔드 배포 워크플로우 삭제
rm .github/workflows/deploy-frontend-cloudfront.yml

# 3. deploy.yml에서 paths-ignore 수정 불필요 (frontend가 없으므로)
# 하지만 명시적으로 백엔드 파일만 감지하도록 변경 가능

# 4. Git 커밋
git add .
git commit -m "chore: Remove frontend (separated to simple-api-frontend repo)"
git push
```

### deploy.yml 수정 (선택사항)

`.github/workflows/deploy.yml`의 트리거 부분:

```yaml
on:
  push:
    branches:
      - main
    paths:
      - 'src/**'
      - 'build.gradle'
      - 'Dockerfile'
      - 'docker-compose.yml'
      - '.github/workflows/deploy.yml'
  repository_dispatch:
    types: [deploy_approved]
```

이렇게 하면 백엔드 파일 변경 시에만 배포가 실행됩니다.

---

## README.md 업데이트 (simple-api)

백엔드 레포의 `README.md`에 프론트엔드 레포 링크 추가:

```markdown
# Simple API

## 관련 레포지토리
- 프론트엔드: https://github.com/johnhuh619/simple-api-frontend
```

---

## 최종 구조

### simple-api (백엔드)
```
simple-api/
├── src/
├── build.gradle
├── Dockerfile
├── docker-compose.yml
└── .github/workflows/
    └── deploy.yml          # 백엔드 배포만
```

### simple-api-frontend (프론트엔드)
```
simple-api-frontend/
├── index.html
├── css/
├── js/
└── .github/workflows/
    └── deploy-cloudfront.yml  # 프론트엔드 배포만
```

---

## 장점

### 1. 책임 분리
- 프론트엔드 개발자 ↔ 백엔드 개발자 독립적으로 작업
- 각 레포의 이슈, PR, 브랜치 관리가 명확

### 2. 배포 독립성
- 프론트엔드만 수정 → 백엔드 배포 안 됨
- 백엔드만 수정 → 프론트엔드 배포 안 됨
- 각각 독립적인 배포 히스토리

### 3. 권한 관리
- GitHub Teams 기능으로 권한 분리 가능
- 프론트엔드 개발자에게 백엔드 레포 쓰기 권한 불필요

### 4. CI/CD 속도
- 각 레포의 빌드/배포 시간 단축
- 프론트엔드 배포: ~1분
- 백엔드 배포: ~3분

---

## 주의사항

### 1. API 엔드포인트 관리
`js/app.js`에서 API URL을 환경에 따라 다르게 설정:

```javascript
// 현재
const API_BASE_URL = 'http://your-ec2-ip:8080/api';

// 개선 (환경 자동 감지)
const API_BASE_URL = window.location.hostname === 'localhost'
  ? 'http://localhost:8080/api'  // 로컬 개발
  : 'https://your-cloudfront-domain.cloudfront.net/api';  // 프로덕션
```

### 2. CORS 설정 확인
백엔드에서 프론트엔드 도메인 허용:

```java
@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins(
                    "http://localhost:8000",  // 로컬 개발
                    "https://your-cloudfront-domain.cloudfront.net"  // 프로덕션
                )
                .allowedMethods("GET", "POST", "PUT", "DELETE");
    }
}
```

---

## 다음 단계: ECS + ECR로 마이그레이션

프론트엔드 분리가 완료되면, 백엔드를 ECS로 전환:

1. **ECR 레포지토리 생성**
   - Docker 이미지를 GHCR 대신 ECR에 저장

2. **ECS 클러스터 생성**
   - Fargate 또는 EC2 타입 선택

3. **Task Definition 작성**
   - 컨테이너 스펙 정의 (이미지, 메모리, CPU, 환경 변수)

4. **ECS Service 생성**
   - Auto Scaling, Load Balancer 연동

5. **GitHub Actions 수정**
   - ECR 푸시 + ECS 배포

자세한 내용은 `ECS_MIGRATION_PLAN.md`에서 별도 작성 예정.

---

## 체크리스트

프론트엔드 레포 분리 완료 확인:

- [ ] GitHub에 `simple-api-frontend` 레포 생성
- [ ] 로컬에서 프론트엔드 파일 복사
- [ ] `.github/workflows/deploy-cloudfront.yml` 생성
- [ ] `README.md` 작성
- [ ] `.gitignore` 생성
- [ ] Git 커밋 및 푸시
- [ ] GitHub Secrets 설정 (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- [ ] 자동 배포 테스트 (GitHub Actions)
- [ ] CloudFront에서 변경사항 확인
- [ ] 백엔드 레포에서 `frontend/` 디렉토리 삭제
- [ ] 백엔드 레포에서 프론트엔드 워크플로우 삭제
- [ ] 백엔드 `README.md`에 프론트엔드 레포 링크 추가

---

**작성일**: 2025-11-19
**관련 레포**:
- 백엔드: https://github.com/johnhuh619/simple-api
- 프론트엔드: https://github.com/johnhuh619/simple-api-frontend (생성 예정)
