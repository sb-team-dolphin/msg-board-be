# 배포 전 체크리스트

## ✅ GitHub Secrets 확인 (완료)

- [x] AWS_HOST
- [x] AWS_USER
- [x] AWS_SSH_KEY
- [x] GHCR_PAT
- [x] SLACK_WEBHOOK_URL

---

## 🔧 EC2 사전 준비 (필수!)

### 1. EC2 SSH 접속 테스트

```bash
# 로컬에서 SSH 접속 확인
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_EC2_HOST

# 접속되면 OK!
```

**문제 발생 시:**
- PEM 키 권한: `chmod 400 ~/.ssh/your-key.pem`
- 보안 그룹에 내 IP의 22번 포트 허용되어 있는지 확인

---

### 2. EC2에서 Docker 설치 확인

```bash
# EC2에 SSH 접속한 상태에서

# Docker 설치 여부 확인
docker --version

# 없으면 설치
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# 재접속 필요 (그룹 권한 적용)
exit
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_EC2_HOST

# 다시 확인
docker ps  # sudo 없이 실행되어야 함
```

---

### 3. Docker Compose 설치 확인

```bash
# Docker Compose 버전 확인
docker compose version
# 또는
docker-compose --version

# 없으면 설치
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 확인
docker compose version
```

---

### 4. GitHub Container Registry 로그인

```bash
# EC2에서 실행

# GHCR_PAT를 환경 변수로 설정
export GHCR_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"  # 본인의 PAT

# GitHub username 설정
export GITHUB_USERNAME="your-github-username"  # 본인의 GitHub username

# 로그인
echo $GHCR_PAT | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

# 성공 메시지 확인
# Login Succeeded
```

**중요:** 이 단계가 없으면 배포 시 이미지를 pull할 수 없습니다!

---

### 5. 작업 디렉토리 생성

```bash
# EC2에서 실행
mkdir -p ~/feedback-api/{data,logs}
cd ~/feedback-api

# 확인
pwd
# /home/ec2-user/feedback-api

ls -la
# data/
# logs/
```

---

### 6. 보안 그룹 확인

**AWS Console → EC2 → 인스턴스 → 보안 그룹**

#### 인바운드 규칙:

| 타입 | 프로토콜 | 포트 범위 | 소스 | 설명 |
|------|---------|----------|------|------|
| SSH | TCP | 22 | 내 IP (또는 0.0.0.0/0) | SSH 접속 |
| Custom TCP | TCP | 8080 | 0.0.0.0/0 | 웹 애플리케이션 |

**8080 포트가 열려있지 않으면 외부에서 접속 불가!**

---

## 🔍 GHCR PAT 권한 확인

### GitHub Personal Access Token 권한

GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)

**필수 권한:**
- [x] `write:packages` - 이미지 푸시
- [x] `read:packages` - 이미지 풀
- [x] `delete:packages` (선택) - 오래된 이미지 삭제

**권한 없으면:**
1. 새 토큰 생성
2. 위 권한 체크
3. GitHub Secrets에서 `GHCR_PAT` 업데이트

---

## 🚀 첫 배포 테스트

### 방법 1: 작은 변경으로 테스트 (추천)

```bash
# 로컬에서

# 작은 변경 (README 등)
echo "\n# Test deployment" >> README.md

git add .
git commit -m "test: GitHub Actions 배포 테스트"
git push origin main
```

### 방법 2: 직접 main에 푸시

```bash
git add .
git commit -m "deploy: EC2 자동 배포 설정"
git push origin main
```

### 배포 모니터링

1. **GitHub에서 확인**
   ```
   Repository → Actions 탭
   ```

2. **실시간 로그 확인**
   - 실행 중인 워크플로우 클릭
   - 각 단계별 로그 확인

3. **예상 소요 시간**
   - Build JAR: ~1분
   - Build Docker Image: ~2-3분
   - Push to GHCR: ~1분
   - Deploy to EC2: ~1분
   - **총: 약 5-7분**

---

## 🎯 배포 성공 확인

### 1. GitHub Actions 확인

- [x] ✅ 모든 단계 초록색
- [x] ✅ "Deployment succeeded!" 메시지
- [x] ✅ Slack 알림 수신 (설정한 경우)

### 2. 브라우저에서 접속

```
http://YOUR_EC2_IP:8080
```

**피드백 작성 화면이 보이면 성공!**

### 3. 헬스체크 API 확인

```bash
curl http://YOUR_EC2_IP:8080/actuator/health
```

**응답:**
```json
{"status":"UP"}
```

### 4. EC2에서 직접 확인

```bash
# SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_EC2_HOST

# 컨테이너 상태
cd ~/feedback-api
docker compose ps

# 실행 중이면 OK
# NAME              IMAGE                                      STATUS
# feedback-api      ghcr.io/username/repo:latest              Up 2 minutes

# 로그 확인
docker compose logs --tail=50

# 데이터 디렉토리 확인
ls -lh data/
# feedbackdb.mv.db 파일이 생성되어야 함
```

---

## ❌ 문제 발생 시 체크

### 1. Build 단계 실패

**증상:** "Gradle build failed"

**확인:**
```bash
# 로컬에서 빌드 테스트
./gradlew clean build

# 성공하면 OK, 실패하면 에러 수정 후 다시 푸시
```

### 2. Docker Image Push 실패

**증상:** "unauthorized: authentication required"

**해결:**
```bash
# GHCR_PAT 권한 확인
# write:packages 권한 있는지 확인

# 새 PAT 생성 후 GitHub Secrets 업데이트
```

### 3. SSH 접속 실패

**증상:** "Permission denied (publickey)"

**확인:**
- AWS_SSH_KEY에 PEM 키 **전체 내용** 포함되었는지
- `-----BEGIN RSA PRIVATE KEY-----` 포함
- `-----END RSA PRIVATE KEY-----` 포함
- 줄바꿈 제대로 되어있는지

**재설정:**
```bash
# 로컬에서 PEM 키 전체 복사
cat ~/.ssh/your-key.pem

# GitHub Secrets → AWS_SSH_KEY 업데이트
```

### 4. Docker Pull 실패 (EC2에서)

**증상:** "pull access denied"

**해결:**
```bash
# EC2에서 GHCR 로그인 다시 시도
echo YOUR_GHCR_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 배포 재시도
```

### 5. 헬스체크 실패

**증상:** "Deployment failed! Checking logs..."

**확인:**
```bash
# EC2에서
cd ~/feedback-api
docker compose logs

# 메모리 부족 확인
free -h

# 포트 충돌 확인
sudo lsof -i :8080
```

---

## 📊 배포 프로세스 요약

```
┌─────────────────────────────────────────────────────┐
│ 1. git push origin main                             │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ 2. GitHub Actions 자동 실행                          │
│    - JAR 빌드                                        │
│    - Docker 이미지 빌드                               │
│    - ghcr.io에 푸시                                  │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ 3. EC2 SSH 접속                                      │
│    - docker-compose.yml 생성                        │
│    - 이미지 pull                                     │
│    - 기존 컨테이너 중지                               │
│    - 새 컨테이너 시작 (볼륨 마운트)                    │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ 4. 헬스체크                                          │
│    - 40초 대기                                       │
│    - /actuator/health 확인                          │
│    - 성공: Slack 알림                                │
│    - 실패: 롤백 + Slack 알림                         │
└─────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────┐
│ 5. 배포 완료!                                        │
│    http://YOUR_EC2_IP:8080                          │
└─────────────────────────────────────────────────────┘
```

---

## 🎉 배포 성공 후

### 데이터 영속성 테스트

```bash
# 1. 브라우저에서 피드백 몇 개 작성
http://YOUR_EC2_IP:8080

# 2. EC2에서 컨테이너 재시작
ssh -i ~/.ssh/key.pem ec2-user@YOUR_EC2_HOST
cd ~/feedback-api
docker compose restart

# 3. 브라우저에서 다시 확인
# → 작성한 피드백이 그대로 있으면 성공!
```

### 재배포 테스트

```bash
# 로컬에서 코드 수정
# (예: 메시지 최대 길이 변경 등)

git add .
git commit -m "feat: 메시지 길이 제한 변경"
git push origin main

# GitHub Actions 실행 확인
# 배포 완료 후 브라우저에서 확인
# → 기존 데이터는 유지되고 새 기능만 반영되면 성공!
```

---

## 다음 단계

1. ✅ **이 체크리스트 완료**
2. 🚀 **첫 배포 실행**
3. 🧪 **데이터 영속성 테스트**
4. 🔄 **재배포 테스트**
5. 🎯 **프로덕션 사용**

---

**준비되셨나요? 체크리스트를 따라 진행하시면 됩니다!**
