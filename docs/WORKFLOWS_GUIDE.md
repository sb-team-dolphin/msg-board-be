# GitHub Actions 워크플로우 가이드

**프로젝트**: simple-api
**워크플로우 개수**: 5개

---

## 📊 워크플로우 목록

### 1️⃣ `deploy.yml` - 백엔드 배포 (EC2 단일 서버)

**용도**: EC2 1대에 백엔드 Docker 컨테이너 배포

**트리거**:
```yaml
on:
  push:
    branches: [main]  # main 브랜치에 push하면 자동 실행
  repository_dispatch:
    types: [deploy_approved]
```

**자동 실행 조건**:
- ✅ `git push origin main` 하면 **자동 실행**
- ✅ 백엔드 코드 변경 시 자동 배포

**수동 실행**: ❌ 불가능 (workflow_dispatch 없음)

**작업 내용**:
1. Gradle 빌드
2. Docker 이미지 생성 (GHCR에 push)
3. EC2에 SSH 접속
4. docker-compose로 컨테이너 재시작
5. RDS 환경 변수 주입 (Secrets 사용)

**현재 상태**: ✅ 사용 중 (RDS 설정 완료)

---

### 2️⃣ `deploy-asg.yml` - 백엔드 배포 (Auto Scaling Group)

**용도**: ALB + ASG 환경에 백엔드 배포 (고가용성)

**트리거**:
```yaml
on:
  workflow_dispatch:  # 수동 실행만 가능
    inputs:
      environment:
        - production
        - staging
```

**자동 실행**: ❌ 없음 (수동 실행만)

**수동 실행**: ✅ 가능
- GitHub → Actions → "Deploy to ASG" → **Run workflow** 클릭

**작업 내용**:
1. Gradle 빌드
2. Docker 이미지 생성
3. Launch Template 새 버전 생성
4. Instance Refresh 시작 (롤링 업데이트)
5. Health check 확인

**현재 상태**: ⚠️ 미사용 (ALB/ASG 없음)

---

### 3️⃣ `deploy-frontend-cloudfront.yml` - 프론트엔드 배포 ⭐

**용도**: CloudFront + S3에 프론트엔드 배포

**트리거**:
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'frontend/**'  # frontend 폴더 변경 시만!
  workflow_dispatch:  # 수동 실행도 가능
```

**자동 실행 조건**:
- ✅ `frontend/` 폴더의 파일이 변경되고
- ✅ `git push origin main` 하면 **자동 실행**
- ❌ 백엔드 코드만 변경하면 실행 안 됨

**수동 실행**: ✅ 가능
- GitHub → Actions → "Deploy Frontend to CloudFront" → **Run workflow**

**작업 내용**:
1. CloudFront Distribution 자동 찾기 (Comment='feedback-app-frontend')
2. S3 버킷 이름 가져오기
3. frontend/ 파일 S3에 업로드
4. CloudFront 캐시 무효화

**현재 상태**: ✅ 사용 중 (CloudFront 설정 완료)

**⚠️ 주의**: CloudFront Description에 `feedback-app-frontend` 설정 필요!

---

### 4️⃣ `rollback.yml` - 백엔드 롤백 (EC2)

**용도**: EC2 배포를 이전 버전으로 롤백

**트리거**:
```yaml
on:
  workflow_dispatch:  # 수동 실행만
```

**자동 실행**: ❌ 없음

**수동 실행**: ✅ 가능
- GitHub → Actions → "Rollback" → **Run workflow**

**작업 내용**:
1. 이전 Docker 이미지로 되돌리기 (previous tag)
2. EC2에서 컨테이너 재시작

**현재 상태**: ✅ 사용 가능

---

### 5️⃣ `rollback-asg.yml` - 백엔드 롤백 (ASG)

**용도**: ASG 배포를 이전 Launch Template 버전으로 롤백

**트리거**:
```yaml
on:
  workflow_dispatch:  # 수동 실행만
```

**자동 실행**: ❌ 없음

**수동 실행**: ✅ 가능
- GitHub → Actions → "Rollback ASG" → **Run workflow**

**현재 상태**: ⚠️ 미사용 (ALB/ASG 없음)

---

## 🎯 현재 프로젝트에서 사용하는 워크플로우

### ✅ 활성 워크플로우

| 워크플로우 | 용도 | 자동 실행 | 수동 실행 |
|-----------|------|-----------|----------|
| **deploy.yml** | 백엔드 → EC2 + RDS | ✅ push 시 | ❌ |
| **deploy-frontend-cloudfront.yml** | 프론트엔드 → CloudFront + S3 | ✅ frontend/ 변경 시 | ✅ |
| **rollback.yml** | 백엔드 롤백 | ❌ | ✅ |

### ⚠️ 비활성 워크플로우 (현재 인프라 없음)

| 워크플로우 | 필요 인프라 | 상태 |
|-----------|-------------|------|
| **deploy-asg.yml** | ALB + ASG + Launch Template | 미사용 |
| **rollback-asg.yml** | ALB + ASG | 미사용 |

---

## 🚀 실행 방법

### 1. 자동 실행 (권장)

#### 백엔드 배포:
```bash
# 백엔드 코드 수정
vim src/main/java/.../Controller.java

# 커밋 & 푸시
git add .
git commit -m "feat: Update API endpoint"
git push origin main

# → deploy.yml 자동 실행! (2-3분)
```

#### 프론트엔드 배포:
```bash
# 프론트엔드 코드 수정
vim frontend/css/style.css

# 커밋 & 푸시
git add frontend/
git commit -m "style: Update CSS"
git push origin main

# → deploy-frontend-cloudfront.yml 자동 실행! (1-2분)
```

#### 백엔드 + 프론트엔드 동시 배포:
```bash
# 둘 다 수정
vim src/main/java/.../Controller.java
vim frontend/js/app.js

# 커밋 & 푸시
git add .
git commit -m "feat: Update backend and frontend"
git push origin main

# → deploy.yml 실행 (백엔드)
# → deploy-frontend-cloudfront.yml 실행 (프론트엔드)
# 두 개가 동시에 병렬 실행됨!
```

### 2. 수동 실행 (GitHub UI)

1. **GitHub Repository** → **Actions** 탭
2. 왼쪽에서 워크플로우 선택:
   - "Deploy Frontend to CloudFront"
   - "Rollback"
3. **Run workflow** 버튼 클릭
4. 브랜치 선택 (보통 main)
5. **Run workflow** 확인

---

## 📊 실행 흐름도

### 시나리오 1: 백엔드만 수정

```
개발자가 코드 수정
   ↓
git push origin main
   ↓
deploy.yml 트리거 ✅
   ↓
1. Gradle 빌드
2. Docker 이미지 생성
3. EC2 배포
4. Health check
   ↓
완료! (2-3분)
```

### 시나리오 2: 프론트엔드만 수정

```
개발자가 frontend/ 수정
   ↓
git push origin main
   ↓
deploy-frontend-cloudfront.yml 트리거 ✅
   ↓
1. CloudFront 찾기
2. S3 업로드
3. 캐시 무효화
   ↓
완료! (1-2분)
```

### 시나리오 3: 둘 다 수정

```
개발자가 백엔드 + 프론트엔드 수정
   ↓
git push origin main
   ↓
┌─────────────────┬──────────────────────┐
│  deploy.yml ✅  │  deploy-frontend... ✅│
│  (백엔드 배포)   │  (프론트엔드 배포)     │
└─────────────────┴──────────────────────┘
         ↓                    ↓
    EC2 배포           CloudFront 배포
         ↓                    ↓
        완료                 완료
```

---

## 🔍 워크플로우 실행 확인

### GitHub Actions UI에서:

1. **Repository** → **Actions** 탭
2. 최근 실행 목록 확인:
   ```
   ✅ Deploy to ASG          (deploy-asg.yml)
   ✅ Deploy Frontend        (deploy-frontend-cloudfront.yml)
   ✅ Simple API CI/CD       (deploy.yml)
   ```

3. 클릭해서 상세 로그 확인

### 로컬에서 확인:

```bash
# 최근 워크플로우 실행 확인 (gh CLI 필요)
gh run list

# 특정 워크플로우 로그 확인
gh run view <run-id> --log
```

---

## ⚙️ 워크플로우 비활성화 (필요 시)

현재 사용하지 않는 워크플로우 비활성화:

```bash
# deploy-asg.yml과 rollback-asg.yml을 비활성화하려면:
# 파일 이름 변경 또는 삭제

mv .github/workflows/deploy-asg.yml .github/workflows/deploy-asg.yml.disabled
mv .github/workflows/rollback-asg.yml .github/workflows/rollback-asg.yml.disabled

git add .
git commit -m "chore: Disable ASG workflows (not using ALB/ASG)"
git push
```

---

## 📌 현재 권장 워크플로우

### 일반 개발:

```bash
# 백엔드 수정
git add src/
git commit -m "feat: Add new feature"
git push  # → deploy.yml 자동 실행

# 프론트엔드 수정
git add frontend/
git commit -m "style: Update UI"
git push  # → deploy-frontend-cloudfront.yml 자동 실행
```

### 긴급 롤백:

```bash
# GitHub UI에서:
# Actions → Rollback → Run workflow
```

---

## ✅ 체크리스트

현재 프로젝트 상태:

- [x] deploy.yml - 백엔드 자동 배포 (EC2 + RDS)
- [x] deploy-frontend-cloudfront.yml - 프론트엔드 자동 배포 (CloudFront + S3)
- [x] rollback.yml - 백엔드 수동 롤백
- [ ] deploy-asg.yml - 미사용 (ALB/ASG 없음)
- [ ] rollback-asg.yml - 미사용 (ALB/ASG 없음)

---

## 🎯 요약

| 변경 내용 | 실행되는 워크플로우 | 실행 방법 |
|----------|-------------------|----------|
| 백엔드 코드 수정 | `deploy.yml` | 자동 (push 시) |
| `frontend/` 수정 | `deploy-frontend-cloudfront.yml` | 자동 (push 시) |
| 긴급 롤백 필요 | `rollback.yml` | 수동 (GitHub UI) |

**간단 정리**:
- `git push` → 자동 배포 ✅
- 롤백 필요 → GitHub UI에서 수동 실행 ✅
- ASG 워크플로우 → 현재 미사용 (ALB 없음)

---

**작성일**: 2025-11-19
**프로젝트**: simple-api (EC2 + RDS + CloudFront 구조)
