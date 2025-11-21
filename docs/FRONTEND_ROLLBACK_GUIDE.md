# 프론트엔드 롤백 가이드 (CloudFront + S3)

## 문제 인식
- 백엔드: Docker 이미지 태그로 롤백 가능 (previous, sha-xxx)
- 프론트엔드: S3는 파일 덮어쓰기 → 이전 버전 사라짐

## 해결 방안: 3가지 전략

---

## 🥇 방법 1: S3 버전 관리 (Versioning) - 권장

### 개념
S3 버킷에서 버전 관리를 활성화하면:
- 모든 파일 변경 시 이전 버전 자동 보관
- 삭제된 파일도 복구 가능
- AWS 콘솔이나 CLI로 롤백

### 1.1 S3 버전 관리 활성화

#### AWS 콘솔에서:
1. S3 콘솔: https://s3.console.aws.amazon.com/
2. 프론트엔드 버킷 선택
3. **Properties** 탭 클릭
4. **Bucket Versioning** 찾기
5. **Edit** → **Enable** → **Save changes**

#### AWS CLI로:
```bash
# 버킷 이름 확인
aws s3 ls

# 버전 관리 활성화
aws s3api put-bucket-versioning \
  --bucket your-frontend-bucket-name \
  --versioning-configuration Status=Enabled

# 확인
aws s3api get-bucket-versioning --bucket your-frontend-bucket-name
# 출력: {"Status": "Enabled"}
```

### 1.2 롤백 방법

#### A. AWS 콘솔에서 수동 롤백

1. S3 버킷 → 파일 클릭 (예: `index.html`)
2. **Versions** 탭 클릭
3. 이전 버전 선택 → **Download** (확인용)
4. 이전 버전 선택 → **Actions** → **Delete**
   - **주의**: 최신 버전을 "삭제"하면 이전 버전이 최신이 됨
5. CloudFront 캐시 무효화:
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

#### B. AWS CLI로 자동 롤백

**롤백 스크립트 (rollback-s3-version.sh):**

```bash
#!/bin/bash
# S3 버전 롤백 스크립트

BUCKET_NAME="your-frontend-bucket"
FILE_PATH="index.html"  # 롤백할 파일
DISTRIBUTION_ID="YOUR_CLOUDFRONT_ID"

echo "📋 현재 버전 목록:"
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --prefix "$FILE_PATH" \
  --query 'Versions[*].[VersionId,LastModified,IsLatest]' \
  --output table

echo ""
read -p "롤백할 VersionId 입력: " VERSION_ID

echo "🔄 버전 $VERSION_ID 로 롤백 중..."

# 이전 버전을 복사해서 최신으로 만들기
aws s3api copy-object \
  --bucket "$BUCKET_NAME" \
  --copy-source "$BUCKET_NAME/$FILE_PATH?versionId=$VERSION_ID" \
  --key "$FILE_PATH" \
  --metadata-directive COPY \
  --cache-control "public, max-age=300"

echo "🔄 CloudFront 캐시 무효화..."
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*"

echo "✅ 롤백 완료!"
```

**사용법:**
```bash
chmod +x rollback-s3-version.sh
./rollback-s3-version.sh
```

### 1.3 GitHub Actions 롤백 워크플로우

`.github/workflows/rollback-frontend.yml`:

```yaml
name: Rollback Frontend

on:
  workflow_dispatch:
    inputs:
      version_id:
        description: 'S3 Version ID to rollback (leave empty to list versions)'
        required: false
        type: string

env:
  AWS_REGION: ap-northeast-2

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
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
          echo "distribution_id=$DISTRIBUTION_ID" >> $GITHUB_OUTPUT

      - name: Get S3 bucket
        id: get-bucket
        run: |
          BUCKET_DOMAIN=$(aws cloudfront get-distribution \
            --id ${{ steps.find-cf.outputs.distribution_id }} \
            --query "Distribution.DistributionConfig.Origins.Items[?contains(DomainName, 's3')].DomainName | [0]" \
            --output text)
          BUCKET_NAME=${BUCKET_DOMAIN%%.s3.*.amazonaws.com}
          echo "bucket=$BUCKET_NAME" >> $GITHUB_OUTPUT

      - name: List versions (if no version_id provided)
        if: ${{ github.event.inputs.version_id == '' }}
        run: |
          echo "======================================"
          echo "📋 index.html 버전 목록:"
          echo "======================================"
          aws s3api list-object-versions \
            --bucket ${{ steps.get-bucket.outputs.bucket }} \
            --prefix "index.html" \
            --query 'Versions[*].[VersionId,LastModified,IsLatest]' \
            --output table

          echo ""
          echo "⚠️  Version ID를 지정하지 않았습니다."
          echo "롤백하려면 워크플로우를 다시 실행하고 Version ID를 입력하세요."
          exit 1

      - name: Rollback to specific version
        if: ${{ github.event.inputs.version_id != '' }}
        run: |
          echo "🔄 버전 ${{ github.event.inputs.version_id }} 로 롤백 중..."

          aws s3api copy-object \
            --bucket ${{ steps.get-bucket.outputs.bucket }} \
            --copy-source "${{ steps.get-bucket.outputs.bucket }}/index.html?versionId=${{ github.event.inputs.version_id }}" \
            --key "index.html" \
            --metadata-directive COPY \
            --cache-control "public, max-age=300" \
            --content-type "text/html"

      - name: Invalidate CloudFront
        if: ${{ github.event.inputs.version_id != '' }}
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.find-cf.outputs.distribution_id }} \
            --paths "/*"

          echo "✅ 롤백 완료!"
          echo "⏳ CloudFront 캐시 무효화 중 (1-3분 소요)"

      - name: Rollback summary
        if: ${{ github.event.inputs.version_id != '' }}
        run: |
          echo "======================================"
          echo "✅ Frontend Rollback Complete"
          echo "======================================"
          echo "Version ID: ${{ github.event.inputs.version_id }}"
          echo "S3 Bucket: ${{ steps.get-bucket.outputs.bucket }}"
          echo "Distribution: ${{ steps.find-cf.outputs.distribution_id }}"
```

**사용법:**
1. GitHub → Actions → "Rollback Frontend"
2. **Run workflow** 클릭
3. Version ID 비워두고 실행 → 버전 목록 확인
4. 다시 실행하고 원하는 Version ID 입력 → 롤백

### 1.4 장단점

**장점:**
- ✅ AWS 네이티브 기능 (별도 도구 불필요)
- ✅ 모든 파일의 모든 버전 자동 보관
- ✅ 삭제된 파일도 복구 가능
- ✅ CloudWatch Events로 자동화 가능

**단점:**
- ❌ 스토리지 비용 증가 (버전마다 과금)
- ❌ 수동으로 Version ID 찾아야 함 (Git SHA와 연결 안 됨)

**비용:**
- 파일 10개, 평균 500KB, 버전 10개씩 보관
- 10 * 500KB * 10 = 50MB → ~$0.001/월 (거의 무료)

---

## 🥈 방법 2: Git 기반 롤백 (Revert)

### 개념
Git 커밋 히스토리를 이용해 이전 버전으로 되돌리고 재배포

### 2.1 롤백 프로세스

```bash
# 1. 커밋 히스토리 확인
git log --oneline -10

# 예시 출력:
# abc1234 feat: Add new button
# def5678 fix: Update styling
# ghi9012 feat: Update homepage  ← 이 버전으로 롤백하고 싶음

# 2. Revert (권장) - 새 커밋으로 되돌리기
git revert abc1234 --no-edit
git push origin main

# 또는 Reset (위험) - 커밋 자체를 제거
git reset --hard ghi9012
git push origin main --force
```

**GitHub Actions가 자동으로 배포**:
- `deploy-cloudfront.yml` 워크플로우 자동 실행
- S3 업로드 + CloudFront 캐시 무효화

### 2.2 GitHub Actions 롤백 워크플로우 (자동화)

`.github/workflows/rollback-frontend-git.yml`:

```yaml
name: Rollback Frontend (Git)

on:
  workflow_dispatch:
    inputs:
      commit_sha:
        description: 'Commit SHA to rollback to (short or full)'
        required: true
        type: string
      rollback_type:
        description: 'Rollback type'
        required: true
        type: choice
        options:
          - revert  # 권장: 되돌리는 새 커밋 생성
          - reset   # 위험: 커밋 히스토리 삭제

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # 전체 히스토리 가져오기

      - name: Configure Git
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"

      - name: Rollback with revert
        if: ${{ github.event.inputs.rollback_type == 'revert' }}
        run: |
          echo "🔄 Reverting to commit ${{ github.event.inputs.commit_sha }}"
          git revert ${{ github.event.inputs.commit_sha }} --no-edit
          git push origin main

      - name: Rollback with reset (force push)
        if: ${{ github.event.inputs.rollback_type == 'reset' }}
        run: |
          echo "⚠️  Force resetting to commit ${{ github.event.inputs.commit_sha }}"
          git reset --hard ${{ github.event.inputs.commit_sha }}
          git push origin main --force

      - name: Trigger deployment
        run: |
          echo "✅ 롤백 완료!"
          echo "📦 deploy-cloudfront.yml 워크플로우가 자동 실행됩니다."
```

**사용법:**
1. GitHub → Actions → "Rollback Frontend (Git)"
2. **Run workflow** 클릭
3. Commit SHA 입력 (예: `ghi9012` 또는 전체 SHA)
4. Rollback type 선택:
   - `revert` (권장): 안전하게 되돌리기
   - `reset` (위험): 커밋 히스토리 삭제

### 2.3 장단점

**장점:**
- ✅ Git 히스토리와 완벽히 동기화
- ✅ 추가 인프라 설정 불필요
- ✅ 롤백 이력이 Git에 남음
- ✅ 무료 (추가 비용 없음)

**단점:**
- ❌ 롤백 = 새 배포 (1-3분 소요)
- ❌ S3 버전 관리 없으면 긴급 복구 불가
- ❌ 실수로 force push 하면 히스토리 손실

---

## 🥉 방법 3: 배포 전 백업 (S3 다른 경로)

### 개념
배포 전에 현재 S3 파일을 백업 경로에 복사

### 3.1 배포 워크플로우 수정

`.github/workflows/deploy-cloudfront.yml`에 백업 단계 추가:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # ... (기존 단계들)

      - name: Backup current version (before deployment)
        run: |
          TIMESTAMP=$(date +%Y%m%d-%H%M%S)
          echo "📦 백업 생성 중: backup/$TIMESTAMP/"

          # 현재 S3 파일을 backup/ 경로로 복사
          aws s3 sync s3://${{ steps.get-bucket.outputs.bucket }}/ \
                       s3://${{ steps.get-bucket.outputs.bucket }}/backup/$TIMESTAMP/ \
            --exclude "backup/*"

          echo "backup_timestamp=$TIMESTAMP" >> $GITHUB_OUTPUT
          echo "✅ 백업 완료: s3://${{ steps.get-bucket.outputs.bucket }}/backup/$TIMESTAMP/"
        id: backup

      - name: Sync to S3 (deployment)
        run: |
          # 기존 배포 로직
          aws s3 sync . s3://${{ steps.get-bucket.outputs.bucket }}/ \
            --exclude "backup/*" \
            --delete

      # ... (나머지 단계들)
```

### 3.2 롤백 워크플로우

`.github/workflows/rollback-frontend-backup.yml`:

```yaml
name: Rollback Frontend (Backup)

on:
  workflow_dispatch:
    inputs:
      backup_timestamp:
        description: 'Backup timestamp (YYYYMMDD-HHMMSS) - leave empty to list'
        required: false
        type: string

env:
  AWS_REGION: ap-northeast-2

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Find CloudFront and S3
        id: find-resources
        run: |
          DISTRIBUTION_ID=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='feedback-app-frontend'].Id | [0]" \
            --output text)

          BUCKET_DOMAIN=$(aws cloudfront get-distribution \
            --id $DISTRIBUTION_ID \
            --query "Distribution.DistributionConfig.Origins.Items[?contains(DomainName, 's3')].DomainName | [0]" \
            --output text)

          BUCKET_NAME=${BUCKET_DOMAIN%%.s3.*.amazonaws.com}

          echo "distribution_id=$DISTRIBUTION_ID" >> $GITHUB_OUTPUT
          echo "bucket=$BUCKET_NAME" >> $GITHUB_OUTPUT

      - name: List available backups
        if: ${{ github.event.inputs.backup_timestamp == '' }}
        run: |
          echo "======================================"
          echo "📋 사용 가능한 백업 목록:"
          echo "======================================"
          aws s3 ls s3://${{ steps.find-resources.outputs.bucket }}/backup/ \
            | grep PRE | awk '{print $2}' | sed 's/\///'

          echo ""
          echo "⚠️  Backup timestamp를 지정하지 않았습니다."
          echo "롤백하려면 워크플로우를 다시 실행하고 timestamp를 입력하세요."
          exit 1

      - name: Restore from backup
        if: ${{ github.event.inputs.backup_timestamp != '' }}
        run: |
          echo "🔄 백업 복원 중: backup/${{ github.event.inputs.backup_timestamp }}/"

          # 백업에서 메인 경로로 복사
          aws s3 sync \
            s3://${{ steps.find-resources.outputs.bucket }}/backup/${{ github.event.inputs.backup_timestamp }}/ \
            s3://${{ steps.find-resources.outputs.bucket }}/ \
            --exclude "backup/*" \
            --delete

      - name: Invalidate CloudFront
        if: ${{ github.event.inputs.backup_timestamp != '' }}
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.find-resources.outputs.distribution_id }} \
            --paths "/*"

          echo "✅ 롤백 완료!"
```

### 3.3 장단점

**장점:**
- ✅ 빠른 복구 (백업에서 즉시 복사)
- ✅ Git 히스토리와 무관하게 롤백 가능
- ✅ 배포 시점 스냅샷 보관

**단점:**
- ❌ 백업 스토리지 비용 (버전마다 전체 파일 복사)
- ❌ 백업 정책 관리 필요 (오래된 백업 삭제)
- ❌ 수동으로 timestamp 입력 필요

**비용 최적화:**
```bash
# S3 Lifecycle 정책으로 30일 이상 된 백업 자동 삭제
aws s3api put-bucket-lifecycle-configuration \
  --bucket your-bucket-name \
  --lifecycle-configuration file://lifecycle.json
```

`lifecycle.json`:
```json
{
  "Rules": [
    {
      "Id": "Delete old backups",
      "Status": "Enabled",
      "Prefix": "backup/",
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
```

---

## 📊 방법 비교표

| 항목 | S3 Versioning | Git Revert | Backup Path |
|------|--------------|------------|-------------|
| **복구 속도** | ⚡ 즉시 | 🐢 1-3분 (재배포) | ⚡ 즉시 |
| **설정 복잡도** | 낮음 | 매우 낮음 | 중간 |
| **추가 비용** | 거의 없음 | 없음 | 중간 |
| **Git 동기화** | ❌ | ✅ | ❌ |
| **자동 백업** | ✅ | ✅ (Git) | ✅ |
| **롤백 이력** | AWS 로그 | Git 히스토리 | S3 로그 |
| **권장 시나리오** | 프로덕션 | 개발/테스트 | 대규모 서비스 |

---

## 🎯 권장 조합

### 소규모 프로젝트 (현재)
**S3 Versioning + Git Revert**
- S3 Versioning 활성화 (긴급 롤백용)
- 일반적인 롤백은 Git Revert 사용

### 중대형 프로젝트
**S3 Versioning + Git Revert + Backup Path**
- S3 Versioning: 긴급 복구
- Git Revert: 일반 롤백
- Backup Path: 특정 시점 스냅샷 (릴리즈 전)

---

## 🚨 긴급 롤백 체크리스트

배포 후 문제 발생 시:

### 1. 문제 확인 (0-5분)
- [ ] CloudFront URL에서 문제 재현
- [ ] 브라우저 캐시 클리어 후 재확인
- [ ] 개발자 도구에서 에러 로그 확인

### 2. 롤백 결정 (5-10분)
- [ ] 핫픽스 가능? → Git 수정 후 재배포
- [ ] 핫픽스 불가? → 이전 버전으로 롤백

### 3. 롤백 실행 (10-15분)

#### 방법 A: S3 Versioning (최빠름)
```bash
# 1. 버전 목록 확인
aws s3api list-object-versions --bucket BUCKET --prefix index.html

# 2. 이전 버전으로 복사
aws s3api copy-object \
  --bucket BUCKET \
  --copy-source "BUCKET/index.html?versionId=VERSION_ID" \
  --key "index.html"

# 3. CloudFront 캐시 무효화
aws cloudfront create-invalidation --distribution-id DIST_ID --paths "/*"
```

#### 방법 B: Git Revert (안전함)
```bash
# 1. 이전 커밋으로 Revert
git revert HEAD --no-edit
git push origin main

# 2. GitHub Actions 자동 배포 (1-3분 대기)
```

### 4. 확인 (15-20분)
- [ ] CloudFront URL에서 정상 작동 확인
- [ ] 모니터링 대시보드 확인 (에러율 감소)
- [ ] 팀에 롤백 완료 알림

---

## 📝 체크리스트: 롤백 시스템 구축

### 기본 설정
- [ ] S3 버전 관리 활성화
- [ ] `.github/workflows/rollback-frontend.yml` 생성
- [ ] CloudFront Distribution ID 확인
- [ ] AWS Secrets 설정 확인

### 문서화
- [ ] README.md에 롤백 절차 추가
- [ ] 팀원에게 롤백 방법 공유
- [ ] 긴급 연락망 정리

### 테스트
- [ ] 개발 환경에서 롤백 테스트
- [ ] S3 Version 복원 테스트
- [ ] CloudFront 캐시 무효화 확인

---

**작성일**: 2025-11-19
**관련 문서**: `FRONTEND_REPO_SEPARATION.md`
