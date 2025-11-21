# 프론트엔드 롤백 빠른 가이드

## 🚀 빠른 시작

### 1단계: S3 버전 관리 활성화 (최초 1회만)

```bash
cd scripts
chmod +x enable-s3-versioning.sh
./enable-s3-versioning.sh
```

또는 수동으로:
```bash
aws s3api put-bucket-versioning \
  --bucket your-frontend-bucket \
  --versioning-configuration Status=Enabled
```

### 2단계: 롤백 방법 선택

---

## 방법 A: GitHub Actions로 롤백 (추천)

### S3 Versioning 롤백 (가장 빠름)

1. **GitHub Actions 페이지 열기**
   - https://github.com/johnhuh619/simple-api/actions

2. **"Rollback Frontend (S3 Versioning)" 선택**

3. **"Run workflow" 클릭**

4. **첫 실행: 버전 목록 확인**
   - "S3 Version ID" 비워두고 실행
   - 로그에서 사용 가능한 버전 ID 확인

5. **두 번째 실행: 롤백**
   - "S3 Version ID"에 원하는 버전 ID 입력
   - "Run workflow" 클릭
   - 1-2분 대기

6. **확인**
   - CloudFront URL 접속
   - Ctrl+Shift+R로 강력 새로고침

### Git Revert 롤백 (안전함)

1. **로컬에서 커밋 SHA 확인**
   ```bash
   git log --oneline -10
   ```

2. **GitHub Actions 페이지 열기**
   - https://github.com/johnhuh619/simple-api/actions

3. **"Rollback Frontend (Git Revert)" 선택**

4. **"Run workflow" 클릭**
   - "Commit SHA": 되돌릴 커밋 SHA 입력 (예: abc1234)
   - "Rollback type": `revert` 선택 (권장)
   - "Run workflow" 클릭

5. **자동 배포 대기**
   - `deploy-frontend-cloudfront.yml` 자동 실행
   - 2-3분 대기

---

## 방법 B: AWS CLI로 롤백 (고급)

### S3 Versioning 롤백

```bash
# 1. 버전 목록 확인
aws s3api list-object-versions \
  --bucket your-frontend-bucket \
  --prefix index.html \
  --query 'Versions[*].[VersionId,LastModified,IsLatest]' \
  --output table

# 2. 원하는 Version ID 복사 (예: abc123xyz)

# 3. 롤백 실행
aws s3api copy-object \
  --bucket your-frontend-bucket \
  --copy-source "your-frontend-bucket/index.html?versionId=abc123xyz" \
  --key index.html \
  --cache-control "public, max-age=300" \
  --content-type "text/html"

# 4. CloudFront 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"

# 5. 완료! (1-3분 후 반영)
```

### Git Revert 롤백

```bash
# 1. 커밋 히스토리 확인
git log --oneline -10

# 2. 되돌릴 커밋 선택 (예: abc1234)

# 3. Revert 실행
git revert abc1234 --no-edit

# 4. Push
git push origin main

# 5. GitHub Actions 자동 배포 (2-3분 대기)
```

---

## 방법 C: 로컬에서 직접 롤백

### Git Reset (위험: 히스토리 삭제)

```bash
# ⚠️ 경고: 커밋 히스토리가 영구 삭제됩니다!

# 1. 원하는 커밋으로 이동
git reset --hard abc1234

# 2. Force push
git push origin main --force

# 3. GitHub Actions 자동 배포
```

---

## 🚨 긴급 롤백 (프로덕션 장애 시)

### 1분 안에 복구하기

```bash
# S3 Versioning이 활성화되어 있다면:

# 1. 최근 버전 ID 확인 (두 번째 줄이 이전 정상 버전)
aws s3api list-object-versions \
  --bucket BUCKET_NAME \
  --prefix index.html \
  --query 'Versions[:3].[VersionId,LastModified]' \
  --output table

# 2. 이전 버전으로 즉시 복원
aws s3api copy-object \
  --bucket BUCKET_NAME \
  --copy-source "BUCKET_NAME/index.html?versionId=PREVIOUS_VERSION_ID" \
  --key index.html

# 3. 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id DIST_ID \
  --paths "/*"

# 완료! CloudFront 무효화 대기 (1-3분)
```

---

## 📊 롤백 방법 비교

| 방법 | 속도 | 난이도 | 히스토리 보존 | 추천 상황 |
|------|------|--------|--------------|----------|
| **S3 Versioning (GitHub)** | ⚡ 즉시 | ⭐ 쉬움 | ✅ | 긴급 롤백 |
| **Git Revert (GitHub)** | 🐢 2-3분 | ⭐ 쉬움 | ✅ | 일반 롤백 |
| **S3 Versioning (CLI)** | ⚡ 즉시 | ⭐⭐ 보통 | ✅ | CLI 선호 시 |
| **Git Reset (CLI)** | 🐢 2-3분 | ⭐⭐⭐ 어려움 | ❌ | 비권장 |

---

## 🔍 트러블슈팅

### Q1: S3 버전 관리가 비활성화되어 있다고 나옴

**A:** S3 버전 관리를 먼저 활성화하세요:
```bash
./scripts/enable-s3-versioning.sh
```

### Q2: CloudFront 캐시가 갱신되지 않음

**A:** 브라우저 강력 새로고침:
- Windows: `Ctrl + Shift + R`
- Mac: `Cmd + Shift + R`

또는 시크릿 모드에서 테스트

### Q3: Git Revert 시 충돌 발생

**A:** 수동으로 해결 필요:
```bash
# 1. 충돌 파일 확인
git status

# 2. 파일 수정 후
git add .
git revert --continue

# 3. Push
git push origin main
```

### Q4: Version ID를 모르겠음

**A:** GitHub Actions에서 확인:
1. "Rollback Frontend (S3 Versioning)" 실행
2. Version ID 비워두고 실행
3. 로그에서 버전 목록 확인

---

## 📝 체크리스트

### 초기 설정
- [ ] S3 버전 관리 활성화
- [ ] `.github/workflows/rollback-frontend.yml` 커밋
- [ ] `.github/workflows/rollback-frontend-git.yml` 커밋
- [ ] AWS Secrets 설정 확인 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)

### 테스트
- [ ] 개발 환경에서 S3 Versioning 롤백 테스트
- [ ] Git Revert 롤백 테스트
- [ ] CloudFront 캐시 무효화 확인

### 문서화
- [ ] 팀원에게 롤백 절차 공유
- [ ] README.md에 롤백 방법 링크 추가
- [ ] 긴급 연락망 정리

---

## 💡 권장 사항

### 평상시 (일반 롤백)
- Git Revert 사용
- 히스토리 보존
- 안전한 롤백

### 긴급 상황 (프로덕션 장애)
- S3 Versioning 사용
- 즉시 복구
- 나중에 Git으로 정리

### 주기적 관리
- 오래된 S3 버전 정리 (Lifecycle Policy)
- 월 1회 롤백 프로세스 점검
- 비용 모니터링

---

**관련 문서:**
- `FRONTEND_ROLLBACK_GUIDE.md` - 상세 가이드
- `FRONTEND_REPO_SEPARATION.md` - 프론트엔드 분리 가이드
- `WORKFLOWS_GUIDE.md` - GitHub Actions 워크플로우 설명
