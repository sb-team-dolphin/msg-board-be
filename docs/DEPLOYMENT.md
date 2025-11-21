# Feedback API - Docker 배포 가이드

## 목차
1. [로컬 Docker 실행](#로컬-docker-실행)
2. [EC2 배포](#ec2-배포)
3. [트러블슈팅](#트러블슈팅)

---

## 로컬 Docker 실행

### 1. Docker로 빌드 및 실행

```bash
# Docker Compose로 빌드 및 실행 (가장 간단)
docker compose up -d

# 로그 확인
docker compose logs -f

# 중지
docker compose down
```

### 2. Docker만 사용 (Compose 없이)

```bash
# 이미지 빌드
docker build -t feedback-api:latest .

# 컨테이너 실행
docker run -d \
  --name feedback-api \
  -p 8080:8080 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/logs:/app/logs \
  feedback-api:latest

# 로그 확인
docker logs -f feedback-api

# 중지 및 제거
docker stop feedback-api
docker rm feedback-api
```

### 3. 접속 확인

```bash
# 브라우저에서
http://localhost:8080

# curl로 헬스체크
curl http://localhost:8080/actuator/health
```

---

## EC2 배포

### 사전 준비

1. **EC2 인스턴스 생성**
   - AMI: Amazon Linux 2023 또는 Amazon Linux 2
   - 인스턴스 타입: t2.micro 이상 (t2.small 권장)
   - 보안 그룹: 8080 포트 오픈

2. **보안 그룹 설정**
   ```
   인바운드 규칙:
   - SSH (22): 내 IP
   - Custom TCP (8080): 0.0.0.0/0 (또는 특정 IP)
   ```

3. **PEM 키 파일 권한 설정**
   ```bash
   chmod 400 ~/.ssh/your-key.pem
   ```

### 방법 1: 자동 배포 스크립트 사용 (추천)

```bash
# 스크립트 실행
./deploy-to-ec2.sh \
  ec2-13-124-123-123.ap-northeast-2.compute.amazonaws.com \
  ec2-user \
  ~/.ssh/my-key.pem
```

스크립트가 자동으로:
- Docker 이미지 빌드
- EC2로 파일 전송
- Docker 및 Docker Compose 설치
- 컨테이너 실행

### 방법 2: 수동 배포

#### Step 1: 로컬에서 이미지 빌드

```bash
# Docker 이미지 빌드
docker build -t feedback-api:latest .

# 이미지를 tar 파일로 저장
docker save -o feedback-api.tar feedback-api:latest
```

#### Step 2: EC2로 파일 전송

```bash
# tar 파일과 docker-compose.yml 전송
scp -i ~/.ssh/your-key.pem feedback-api.tar ec2-user@your-ec2-host:~/
scp -i ~/.ssh/your-key.pem docker-compose.yml ec2-user@your-ec2-host:~/
```

#### Step 3: EC2에 SSH 접속

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host
```

#### Step 4: EC2에서 Docker 설치 및 실행

```bash
# Docker 설치 (Amazon Linux 2)
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# Docker Compose 설치
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 재접속 (그룹 권한 적용)
exit
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host

# Docker 이미지 로드
docker load -i feedback-api.tar

# 디렉토리 생성
mkdir -p data logs

# 컨테이너 실행
docker compose up -d

# 로그 확인
docker compose logs -f
```

#### Step 5: 접속 확인

```bash
# EC2 퍼블릭 IP 확인
curl http://169.254.169.254/latest/meta-data/public-ipv4

# 브라우저에서 접속
http://<EC2-PUBLIC-IP>:8080
```

### 방법 3: GitHub Actions CI/CD (선택사항)

GitHub Actions로 자동 배포를 설정하려면 `.github/workflows/deploy.yml` 참고

---

## Docker 관리 명령어

### 컨테이너 관리

```bash
# 실행 중인 컨테이너 확인
docker ps

# 모든 컨테이너 확인
docker ps -a

# 로그 확인
docker compose logs -f
docker logs -f feedback-api

# 컨테이너 재시작
docker compose restart
docker restart feedback-api

# 컨테이너 중지
docker compose down
docker stop feedback-api

# 컨테이너 삭제
docker rm feedback-api

# 이미지 삭제
docker rmi feedback-api:latest
```

### 데이터 및 로그 확인

```bash
# H2 데이터베이스 파일
ls -lh data/

# 로그 파일
tail -f logs/feedback-api.log
```

### 리소스 사용량 확인

```bash
# 컨테이너 리소스 사용량
docker stats feedback-api

# 디스크 사용량
docker system df
```

---

## 업데이트 배포

### 로컬에서 테스트 후 EC2 업데이트

```bash
# 1. 코드 수정 후 로컬 테스트
docker compose up --build

# 2. 문제 없으면 EC2에 재배포
./deploy-to-ec2.sh \
  ec2-13-124-123-123.ap-northeast-2.compute.amazonaws.com \
  ec2-user \
  ~/.ssh/my-key.pem
```

### EC2에서 직접 업데이트

```bash
# EC2 SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host

# 컨테이너 중지 및 삭제
docker compose down

# 새 이미지 로드 (전송 받은 경우)
docker load -i feedback-api.tar

# 재시작
docker compose up -d
```

---

## 롤백 (Rollback)

배포 후 문제가 발생했을 때 이전 버전으로 빠르게 되돌리는 방법입니다.

### 이미지 태깅 전략

CI/CD 파이프라인은 다음과 같이 이미지를 태깅합니다:

```
ghcr.io/johnhuh619/simple-api:latest    # 현재 배포된 버전
ghcr.io/johnhuh619/simple-api:previous  # 이전 버전 (롤백용)
ghcr.io/johnhuh619/simple-api:sha-xxxxx # Git SHA 기반 특정 버전
```

### 방법 1: GitHub Actions로 원클릭 롤백 (권장)

**가장 빠르고 안전한 방법입니다.**

#### 단계:

1. **GitHub 레포지토리 → Actions 탭**

2. **"Rollback to Previous Version" 워크플로우 선택**

3. **Run workflow 클릭**
   - Branch: main 선택
   - Confirmation: `rollback` 입력
   - Run workflow 버튼 클릭

4. **진행 상황 모니터링**
   - 실시간으로 로그 확인
   - Slack 알림 수신 (설정한 경우)

5. **완료 확인**
   ```bash
   curl http://<EC2-IP>:8080/actuator/health
   ```

#### 롤백 프로세스:

```
1. ✅ 이전 이미지 존재 확인
2. 🔐 GHCR 로그인
3. 🛑 현재 컨테이너 중지
4. 📦 이전 이미지 Pull
5. 🚀 이전 버전 시작
6. 🩺 Health check
7. ✅ 롤백 완료 알림
```

#### 예상 소요 시간: **약 2-3분**

### 방법 2: EC2에서 수동 롤백

긴급 상황이거나 GitHub Actions를 사용할 수 없을 때 사용합니다.

```bash
# 1. EC2 SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host

# 2. feedback-api 디렉토리로 이동
cd ~/feedback-api

# 3. GHCR 로그인
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# 4. 현재 컨테이너 중지
docker compose down

# 5. 이전 이미지 Pull
docker pull ghcr.io/johnhuh619/simple-api:previous

# 6. docker-compose.yml 임시 수정
sed -i 's/:latest/:previous/g' docker-compose.yml

# 7. 이전 버전 시작
docker compose up -d

# 8. Health check
sleep 40
curl http://localhost:8080/actuator/health

# 9. 성공 확인 후 docker-compose.yml 원복
sed -i 's/:previous/:latest/g' docker-compose.yml

# 10. 로그아웃
docker logout ghcr.io
```

### 방법 3: 특정 SHA 버전으로 롤백

특정 커밋으로 롤백하고 싶을 때:

```bash
# 1. GitHub에서 원하는 커밋의 SHA 확인
# 예: ed51408

# 2. EC2에서 해당 이미지 Pull
docker pull ghcr.io/johnhuh619/simple-api:sha-ed51408

# 3. docker-compose.yml 수정
sed -i 's/:latest/:sha-ed51408/g' docker-compose.yml

# 4. 재배포
docker compose down
docker compose up -d

# 5. 확인 후 원복
sed -i 's/:sha-ed51408/:latest/g' docker-compose.yml
```

### 롤백 후 재배포

롤백 후 문제를 해결했다면 다시 최신 버전으로 배포:

```bash
# 방법 1: main 브랜치에 핫픽스 커밋 후 자동 배포
git commit -m "hotfix: Fix critical bug"
git push origin main
# → GitHub Actions가 자동으로 배포

# 방법 2: EC2에서 수동으로 최신 버전 재배포
cd ~/feedback-api
docker compose down
docker pull ghcr.io/johnhuh619/simple-api:latest
docker compose up -d
```

### 롤백 실패 시 대처

롤백도 실패하는 극단적인 상황:

#### 1. 모든 컨테이너 중지 및 정리

```bash
# 모든 컨테이너 중지
docker stop $(docker ps -aq)

# 컨테이너 삭제
docker rm $(docker ps -aq)

# 네트워크 정리
docker network prune -f
```

#### 2. 알려진 안정 버전으로 강제 배포

```bash
# 특정 SHA 버전 (알려진 안정 버전)
docker pull ghcr.io/johnhuh619/simple-api:sha-2741b1c
docker tag ghcr.io/johnhuh619/simple-api:sha-2741b1c feedback-api:latest

# docker-compose.yml에서 image를 로컬 태그로 변경
# image: feedback-api:latest

docker compose up -d
```

#### 3. 데이터베이스 백업 복원

```bash
# 데이터베이스 손상 시
cd ~/feedback-api
cp -r data data.corrupted
cp -r data.backup data  # 이전 백업 복원
docker compose restart
```

### 롤백 모니터링

#### CloudWatch Logs 확인

```
CloudWatch → Log groups → /ecs/feedback-api
→ 롤백 전후 로그 비교
```

#### 컨테이너 이미지 확인

```bash
# 현재 실행 중인 이미지 확인
docker ps --format "table {{.Image}}\t{{.Status}}\t{{.Names}}"

# 이미지 히스토리
docker images | grep simple-api
```

### 롤백 체크리스트

롤백 전 확인사항:

- [ ] 롤백 사유 명확히 파악
- [ ] CloudWatch Logs에서 에러 확인
- [ ] 이전 버전이 정상 동작했는지 확인
- [ ] 데이터베이스 마이그레이션 없었는지 확인
- [ ] 롤백 후 테스트 계획 수립

롤백 후 확인사항:

- [ ] Health check 통과 확인
- [ ] API 엔드포인트 동작 확인
- [ ] CloudWatch Logs에 에러 없는지 확인
- [ ] 사용자에게 서비스 복구 알림
- [ ] 원인 분석 및 재발 방지 대책 수립

---

## 트러블슈팅

### 1. 포트가 이미 사용 중

```bash
# 8080 포트 사용 중인 프로세스 확인
sudo lsof -i :8080
sudo netstat -tulpn | grep 8080

# 프로세스 종료
sudo kill -9 <PID>
```

### 2. Docker 권한 오류

```bash
# ec2-user를 docker 그룹에 추가
sudo usermod -a -G docker ec2-user

# 재접속 필요
exit
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-host
```

### 3. 메모리 부족

```bash
# docker-compose.yml에 메모리 제한 추가
services:
  feedback-api:
    mem_limit: 512m
    memswap_limit: 512m
```

### 4. 헬스체크 실패

```bash
# 컨테이너 로그 확인
docker logs feedback-api

# 헬스체크 엔드포인트 직접 호출
curl http://localhost:8080/actuator/health

# 컨테이너 내부 접속
docker exec -it feedback-api sh
```

### 5. 데이터베이스 파일 손상

```bash
# 데이터베이스 백업
cp -r data data.backup

# 데이터베이스 초기화 (주의!)
rm -rf data/*
docker compose restart
```

### 6. 로그 파일 너무 큼

```bash
# 로그 파일 크기 확인
du -h logs/

# 오래된 로그 삭제
find logs/ -name "*.log.*" -mtime +30 -delete

# Docker 로그 정리
docker system prune -a
```

---

## 성능 최적화

### JVM 메모리 설정

docker-compose.yml에서 조정:

```yaml
environment:
  - JAVA_OPTS=-Xmx512m -Xms256m
```

### 데이터베이스 최적화

application.yml에서 조정:

```yaml
spring:
  jpa:
    properties:
      hibernate:
        jdbc:
          batch_size: 20
```

---

## 모니터링

### 기본 모니터링

```bash
# 컨테이너 상태
docker ps

# 리소스 사용량
docker stats

# 헬스체크
curl http://localhost:8080/actuator/health
```

### CloudWatch Logs 연동 (프로덕션 권장)

#### 1. EC2 IAM Role 설정

EC2 인스턴스에 CloudWatch Logs 권한 부여:

1. **IAM Role 생성**
   - AWS Console → IAM → Roles → Create role
   - Trusted entity: AWS service → EC2
   - Policy 추가: `CloudWatchLogsFullAccess` (또는 아래 커스텀 정책)

2. **커스텀 IAM Policy** (최소 권한 원칙)
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogGroup",
           "logs:CreateLogStream",
           "logs:PutLogEvents",
           "logs:DescribeLogStreams"
         ],
         "Resource": "arn:aws:logs:ap-northeast-2:*:log-group:/ecs/feedback-api:*"
       }
     ]
   }
   ```

3. **EC2에 Role 연결**
   - EC2 Console → 인스턴스 선택 → Actions → Security → Modify IAM role
   - 생성한 Role 선택

#### 2. Docker Compose 설정

이미 `.github/workflows/deploy.yml`에 CloudWatch 설정이 포함되어 있습니다:

```yaml
logging:
  driver: awslogs
  options:
    awslogs-region: ap-northeast-2
    awslogs-group: /ecs/feedback-api
    awslogs-stream: feedback-api
    awslogs-create-group: "true"
```

#### 3. 로그 확인 방법

**AWS Console에서:**
- CloudWatch → Log groups → `/ecs/feedback-api`
- 실시간 로그 스트림 확인 가능

**AWS CLI로:**
```bash
# 최근 로그 확인
aws logs tail /ecs/feedback-api --follow

# 특정 시간대 로그 검색
aws logs filter-log-events \
  --log-group-name /ecs/feedback-api \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"
```

**로컬에서도 확인 가능:**
```bash
# docker logs 명령어는 여전히 작동
docker logs -f feedback-api
```

#### 4. 로그 보존 기간 설정

```bash
# AWS CLI로 보존 기간 설정 (30일)
aws logs put-retention-policy \
  --log-group-name /ecs/feedback-api \
  --retention-in-days 30
```

#### 5. CloudWatch Insights 쿼리 예제

```sql
-- 에러 로그만 필터링
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- 특정 시간대 요청 분석
fields @timestamp, @message
| filter @message like /GET|POST/
| stats count() by bin(5m)
```

#### 6. 비용 최적화

- **로그 보존 기간**: 30일 권장 (기본값은 무제한)
- **로그 레벨**: 프로덕션에서는 INFO 이상만 (DEBUG 제외)
- **예상 비용**:
  - 수집: $0.76/GB
  - 저장: $0.033/GB/month
  - 일 100MB 로그 기준: 월 $3-5

---

## 보안 권장사항

1. **환경 변수로 민감 정보 관리**
   - docker-compose.yml에 직접 쓰지 말고 .env 파일 사용

2. **HTTPS 적용**
   - Nginx 리버스 프록시 + Let's Encrypt
   - 또는 AWS ALB 사용

3. **방화벽 설정**
   - 보안 그룹에서 필요한 포트만 오픈
   - SSH는 특정 IP만 허용

4. **정기 업데이트**
   - Docker 이미지 정기 재빌드
   - 보안 패치 적용

---

## 참고 링크

- [Docker 공식 문서](https://docs.docker.com/)
- [Docker Compose 문서](https://docs.docker.com/compose/)
- [Spring Boot Docker 가이드](https://spring.io/guides/topicals/spring-boot-docker/)
- [AWS EC2 문서](https://docs.aws.amazon.com/ec2/)
