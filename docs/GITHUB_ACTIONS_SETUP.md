# GitHub Actions 자동 배포 설정 가이드

## 개요

`main` 브랜치에 푸시하면 자동으로 EC2에 배포되는 CI/CD 파이프라인입니다.

## 배포 흐름

```
Push to main
    ↓
Build JAR with Gradle
    ↓
Build Docker Image
    ↓
Push to GitHub Container Registry (ghcr.io)
    ↓
SSH to EC2
    ↓
Pull latest image
    ↓
Deploy with docker-compose
    ↓
Health check
    ↓
Slack notification
```

## 필수 설정

### 1. GitHub Secrets 설정

Repository → Settings → Secrets and variables → Actions에서 추가:

#### 필수 Secrets

| Secret 이름 | 설명 | 예시 |
|-------------|------|------|
| `AWS_HOST` | EC2 퍼블릭 호스트 또는 IP | `ec2-13-124-123-123.ap-northeast-2.compute.amazonaws.com` |
| `AWS_USER` | EC2 SSH 사용자명 | `ec2-user` (Amazon Linux) 또는 `ubuntu` |
| `AWS_SSH_KEY` | EC2 PEM 키 전체 내용 | `-----BEGIN RSA PRIVATE KEY-----\n...` |
| `GHCR_PAT` | GitHub Personal Access Token | `ghp_xxxxxxxxxxxxx` |

#### 선택 Secrets (Slack 알림용)

| Secret 이름 | 설명 |
|-------------|------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL |

### 2. GitHub Personal Access Token (PAT) 생성

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" 클릭
3. 권한 선택:
   - `write:packages` - 컨테이너 레지스트리에 푸시
   - `read:packages` - 컨테이너 레지스트리에서 풀
   - `delete:packages` - 오래된 이미지 삭제 (선택)
4. 생성된 토큰을 `GHCR_PAT` Secret에 저장

### 3. EC2 PEM 키 Secret에 추가하기

**로컬에서:**

```bash
# PEM 키 내용 복사 (macOS/Linux)
cat ~/.ssh/your-key.pem | pbcopy

# 또는 (Windows Git Bash)
cat ~/.ssh/your-key.pem | clip
```

**GitHub에서:**
1. Repository Settings → Secrets → New repository secret
2. Name: `AWS_SSH_KEY`
3. Value: PEM 키 전체 내용 붙여넣기
   ```
   -----BEGIN RSA PRIVATE KEY-----
   MIIEpAIBAAKCAQEA...
   ...
   -----END RSA PRIVATE KEY-----
   ```

### 4. EC2 사전 준비

#### Docker 설치

```bash
# Amazon Linux 2/2023
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# 재접속 필요
exit
```

#### Docker Compose 설치

```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 확인
docker --version
docker-compose --version
```

#### GitHub Container Registry 로그인

```bash
# Personal Access Token으로 로그인
echo $GHCR_PAT | docker login ghcr.io -u USERNAME --password-stdin

# 또는 수동 입력
docker login ghcr.io
Username: your-github-username
Password: ghp_xxxxxxxxxxxxx (PAT)
```

#### 디렉토리 생성

```bash
mkdir -p ~/feedback-api/{data,logs}
cd ~/feedback-api
```

### 5. EC2 보안 그룹 설정

**인바운드 규칙:**

| 타입 | 프로토콜 | 포트 | 소스 | 설명 |
|------|---------|------|------|------|
| SSH | TCP | 22 | 내 IP | SSH 접속 |
| Custom TCP | TCP | 8080 | 0.0.0.0/0 | 웹 애플리케이션 |

## 사용 방법

### 1. 자동 배포 (main 브랜치 푸시)

```bash
# 코드 수정 후
git add .
git commit -m "feat: 새 기능 추가"
git push origin main
```

**자동으로:**
1. JAR 빌드
2. Docker 이미지 빌드
3. ghcr.io에 푸시
4. EC2에 SSH 접속
5. 이미지 풀
6. docker-compose로 배포
7. 헬스체크
8. Slack 알림 (설정한 경우)

### 2. GitHub Actions 모니터링

1. Repository → Actions 탭
2. 실행 중인 워크플로우 확인
3. 로그 실시간 확인 가능

### 3. 배포 확인

```bash
# 브라우저에서
http://your-ec2-ip:8080

# curl로 헬스체크
curl http://your-ec2-ip:8080/actuator/health
```

## 배포 후 EC2에서 확인

```bash
# SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host

# 컨테이너 상태
cd ~/feedback-api
docker compose ps

# 로그 확인
docker compose logs -f

# 데이터 확인 (H2 DB)
ls -lh data/

# 로그 파일 확인
tail -f logs/feedback-api.log
```

## Slack 알림 설정 (선택사항)

### 1. Slack Incoming Webhook 생성

1. Slack 워크스페이스에서 Apps → Incoming Webhooks 검색
2. "Add to Slack" 클릭
3. 채널 선택 (예: #deployments)
4. Webhook URL 복사
   ```
   https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXX
   ```

### 2. GitHub Secret에 추가

- Name: `SLACK_WEBHOOK_URL`
- Value: Webhook URL

### 3. 알림 예시

```
🚀 Deploy Started by username
🟩⬜️⬜️⬜️ Build Complete

🐳 Docker Image Pushed
🟩🟩⬜️⬜️ Deploying...

🚢 Deploying to EC2
🟩🟩🟩⬜️ Running health check...

✅ Deploy Complete
🟩🟩🟩🟩 Live on Production
```

## 트러블슈팅

### 1. Docker 이미지 푸시 실패

**증상:** `unauthorized: authentication required`

**해결:**
```bash
# PAT 권한 확인
- write:packages 권한 있는지 확인
- 새 PAT 생성 후 GHCR_PAT Secret 업데이트
```

### 2. SSH 접속 실패

**증상:** `Permission denied (publickey)`

**해결:**
```bash
# PEM 키 확인
- AWS_SSH_KEY Secret에 전체 내용이 들어갔는지 확인
- -----BEGIN RSA PRIVATE KEY----- 포함되었는지 확인
- 줄바꿈이 제대로 되어있는지 확인
```

### 3. 헬스체크 실패

**증상:** `Deployment failed! Checking logs...`

**해결:**
```bash
# EC2에서 직접 확인
ssh -i ~/.ssh/key.pem ec2-user@your-ec2
cd ~/feedback-api
docker compose logs

# 메모리 부족 확인
free -h
docker stats

# 포트 충돌 확인
sudo lsof -i :8080
```

### 4. 데이터 휘발 문제

**증상:** 재배포 시 데이터 사라짐

**확인:**
```bash
# 볼륨 마운트 확인
docker inspect feedback-api | grep -A 10 Mounts

# 데이터 디렉토리 확인
ls -la ~/feedback-api/data/

# 정상적으로 마운트되면:
# /home/ec2-user/feedback-api/data → /app/data
```

### 5. Docker Compose 명령어 없음

**증상:** `docker-compose: command not found`

**해결:**
```bash
# Docker Compose V2 설치 (docker compose)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 또는 Docker Compose V2 플러그인 사용
sudo yum install docker-compose-plugin
```

## 고급 설정

### 1. 승인 프로세스 추가

현재 deploy.yml에서 주석 처리된 승인 단계 활성화:

```yaml
# Line 110-161 주석 해제
- name: Request deploy approval
  # ...승인 버튼 전송

- name: Wait for approval
  # ...승인 대기
```

### 2. 다중 환경 배포

```yaml
# dev, staging, prod 환경별 배포
on:
  push:
    branches:
      - main          # prod
      - develop       # staging
      - feature/*     # dev
```

### 3. 롤백 전략

```bash
# EC2에서 이전 버전으로 롤백
cd ~/feedback-api

# 이전 이미지 태그로 변경
docker compose down
docker run -d \
  --name feedback-api \
  -p 8080:8080 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/logs:/app/logs \
  ghcr.io/username/repo:previous-sha
```

## 비용 최적화

### 1. GitHub Container Registry 정리

```bash
# 로컬에서 오래된 이미지 삭제
# GitHub → Packages → feedback-api → Package settings
# Delete old versions
```

### 2. EC2 자동 중지/시작 (개발 환경)

Lambda + CloudWatch Events로 야간/주말 자동 중지

## 체크리스트

배포 전 확인사항:

- [ ] EC2 인스턴스 실행 중
- [ ] 보안 그룹 8080 포트 오픈
- [ ] Docker 설치됨
- [ ] Docker Compose 설치됨
- [ ] GitHub Secrets 모두 설정
  - [ ] AWS_HOST
  - [ ] AWS_USER
  - [ ] AWS_SSH_KEY
  - [ ] GHCR_PAT
- [ ] ghcr.io 로그인 성공
- [ ] ~/feedback-api 디렉토리 생성

## 참고 자료

- [GitHub Actions 문서](https://docs.github.com/en/actions)
- [GitHub Container Registry 문서](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Compose 문서](https://docs.docker.com/compose/)
- [EC2 사용자 가이드](https://docs.aws.amazon.com/ec2/)
