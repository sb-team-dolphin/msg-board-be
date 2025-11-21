# 변경사항 요약 - EC2 + RDS + CloudFront

**날짜**: 2025-11-19
**작업**: 백엔드 RDS 연결 + 프론트엔드 CloudFront 분리 (EC2 직접 연결)

---

## ✅ 핵심 변경사항

### 1. **application-prod.yml** - RDS 환경 변수 설정

**변경 전**:
```yaml
datasource:
  url: jdbc:mysql://MYSQL_PRIVATE_IP:3306/feedbackdb?...
  username: feedbackuser
  password: FeedbackPass123!
```

**변경 후**:
```yaml
datasource:
  url: jdbc:mysql://${DB_HOST:localhost}:${DB_PORT:3306}/${DB_NAME:feedbackdb}?...
  username: ${DB_USER:feedbackuser}
  password: ${DB_PASSWORD:FeedbackPass123!}
```

**장점**:
- ✅ Docker 환경 변수로 주입 가능
- ✅ 코드 변경 없이 DB 변경 가능
- ✅ 개발/프로덕션 환경 분리 용이

### 2. **정적 리소스 비활성화** (이미 적용됨)

```yaml
spring:
  web:
    resources:
      add-mappings: false  # CloudFront가 서빙
```

---

## 🆕 신규 스크립트

### 1. `scripts/setup-rds-quick.sh` ⭐

**기능**: RDS MySQL 인스턴스 자동 생성

```bash
./scripts/setup-rds-quick.sh
```

**수행 작업**:
- DB Subnet Group 생성 (기본 VPC)
- Security Group 생성 (EC2 → RDS 접근 허용)
- RDS MySQL 인스턴스 생성 (db.t3.micro, Free Tier)
- 엔드포인트 정보 출력
- `rds-config.env` 파일 생성

**소요 시간**: 10-15분

### 2. `scripts/setup-cloudfront-ec2.sh` ⭐

**기능**: CloudFront + S3 배포 (EC2 직접 연결, ALB 없음)

```bash
./scripts/setup-cloudfront-ec2.sh
```

**수행 작업**:
- S3 버킷 생성
- Origin Access Control (OAC) 생성
- CloudFront Distribution 생성:
  - Origin 1: S3 (프론트엔드)
  - Origin 2: EC2 Public DNS (백엔드)
- S3 버킷 정책 설정
- 프론트엔드 파일 업로드
- `cloudfront-config.env` 파일 생성

**입력 필요**:
- EC2 Public DNS
- Backend Port (기본 8080)

**소요 시간**: 15-20분

### 3. `scripts/deploy-to-ec2-with-rds.sh`

**기능**: EC2에서 실행하는 배포 스크립트

```bash
# EC2에서 실행
./scripts/deploy-to-ec2-with-rds.sh
```

**수행 작업**:
- RDS 연결 정보 입력
- 기존 컨테이너 중지/삭제
- 최신 Docker 이미지 pull
- 환경 변수와 함께 컨테이너 시작
- Health check 대기
- 엔드포인트 테스트

**소요 시간**: 2-3분

---

## 📖 신규 문서

### `QUICK_EC2_DEPLOYMENT.md` ⭐⭐⭐

**주요 내용**:
- EC2 + RDS + CloudFront 빠른 배포 가이드
- 3단계 배포 프로세스:
  1. RDS 생성 (10-15분)
  2. 백엔드 재배포 (5-10분)
  3. CloudFront 배포 (15-20분)
- 트러블슈팅 섹션
- 체크리스트

**총 소요 시간**: 30-40분

---

## 🎯 배포 프로세스

### Step 1: RDS 생성

```bash
cd C:/2025proj/simple-api
./scripts/setup-rds-quick.sh

# EC2 Instance ID 입력 (보안 강화)
# 10-15분 대기
# rds-config.env 파일 생성됨
```

### Step 2: 백엔드 재배포 (EC2에서)

```bash
# 로컬에서 스크립트를 EC2로 복사
scp -i your-key.pem scripts/deploy-to-ec2-with-rds.sh ec2-user@<EC2-IP>:~

# EC2에 SSH 접속
ssh -i your-key.pem ec2-user@<EC2-IP>

# 배포 스크립트 실행
chmod +x deploy-to-ec2-with-rds.sh
./deploy-to-ec2-with-rds.sh

# RDS 엔드포인트 입력
# 2-3분 대기
# Health check 통과 확인
```

### Step 3: CloudFront 배포

```bash
# 로컬에서
cd C:/2025proj/simple-api
./scripts/setup-cloudfront-ec2.sh

# EC2 Public DNS 입력
# 15-20분 대기
# cloudfront-config.env 파일 생성됨
```

### Step 4: 테스트

```bash
# 환경 변수 로드
source cloudfront-config.env

# 브라우저에서 확인
start https://$CLOUDFRONT_DOMAIN

# API 테스트
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks
```

---

## 🏗️ 최종 아키텍처

```
사용자
  ↓ HTTPS
CloudFront Distribution
  ├─ /              → S3 Bucket (프론트엔드)
  │  ├─ index.html
  │  ├─ js/app.js
  │  └─ css/style.css
  │
  └─ /api/*         → EC2 Instance (백엔드)
                      └─ Docker Container
                         └─ Spring Boot
                            ↓
                          RDS MySQL
                            └─ feedbackdb

✅ CORS 없음 (같은 도메인)
✅ HTTPS 자동
✅ RDS 자동 백업
✅ 프론트엔드 독립 배포
```

---

## 📦 Docker 실행 명령어 (참고)

### 로컬 빌드 (선택사항)

```bash
# Gradle 빌드
./gradlew clean build

# Docker 이미지 빌드
docker build -t ghcr.io/johnhuh619/simple-api:latest .

# GitHub Container Registry 푸시
docker push ghcr.io/johnhuh619/simple-api:latest
```

### EC2에서 실행

```bash
# 환경 변수 설정
export DB_HOST="feedback-db.xxxxx.rds.amazonaws.com"
export DB_PORT="3306"
export DB_NAME="feedbackdb"
export DB_USER="feedbackuser"
export DB_PASSWORD="FeedbackPass123!"

# Docker 실행
sudo docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_HOST=$DB_HOST \
  -e DB_PORT=$DB_PORT \
  -e DB_NAME=$DB_NAME \
  -e DB_USER=$DB_USER \
  -e DB_PASSWORD=$DB_PASSWORD \
  ghcr.io/johnhuh619/simple-api:latest

# 로그 확인
sudo docker logs -f feedback-api

# Health check
curl http://localhost:8080/actuator/health
```

---

## 🔐 보안 고려사항

### RDS Security Group

- ✅ EC2 Security Group에서만 접근 허용
- ✅ Public 접근 비활성화
- ✅ VPC 내부 통신만 허용

### CloudFront → EC2

- ⚠️ EC2 Security Group에서 8080 포트 개방 필요
- ✅ CloudFront HTTPS 강제

**권장 설정**:
```bash
# EC2 Security Group: 8080 포트 개방 (전체 또는 CloudFront IP)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

---

## 💾 생성된 환경 설정 파일

### `rds-config.env` (RDS 생성 후)

```bash
export RDS_ENDPOINT=feedback-db.xxxxx.rds.amazonaws.com
export RDS_PORT=3306
export RDS_DATABASE=feedbackdb
export RDS_USERNAME=feedbackuser
export RDS_PASSWORD=FeedbackPass123!
export JDBC_URL=jdbc:mysql://...
```

### `cloudfront-config.env` (CloudFront 생성 후)

```bash
export CLOUDFRONT_DISTRIBUTION_ID=E1A2B3C4D5E6F7
export CLOUDFRONT_DOMAIN=d1234567890abc.cloudfront.net
export S3_BUCKET_NAME=feedback-frontend-1732012345
export EC2_BACKEND=ec2-13-125-xxx-xxx.ap-northeast-2.compute.amazonaws.com
export BACKEND_PORT=8080
```

**사용법**:
```bash
source rds-config.env
source cloudfront-config.env

echo $CLOUDFRONT_DOMAIN
```

---

## ✅ 테스트 체크리스트

### 백엔드 (RDS)
- [ ] RDS 인스턴스 생성 완료
- [ ] Security Group 설정 완료 (EC2 → RDS)
- [ ] EC2에서 Docker 재시작
- [ ] `curl http://localhost:8080/actuator/health` → 200 OK
- [ ] `curl http://localhost:8080/api/feedbacks` → JSON 응답

### 프론트엔드 (CloudFront)
- [ ] CloudFront Distribution 생성 완료
- [ ] Status: "Deployed"
- [ ] S3 버킷 파일 업로드 확인
- [ ] `curl https://$CLOUDFRONT_DOMAIN/` → HTML 응답
- [ ] `curl https://$CLOUDFRONT_DOMAIN/api/feedbacks` → JSON 응답

### 통합 테스트
- [ ] 브라우저에서 프론트엔드 접속
- [ ] 개발자 도구에서 CORS 에러 없음 확인
- [ ] 피드백 생성 테스트
- [ ] RDS에서 데이터 확인

---

## 🚀 다음 단계

### 프론트엔드 업데이트

```bash
cd frontend
vim css/style.css  # 수정

./deploy.sh  # 배포 (1-2분)
```

### 백엔드 업데이트

```bash
# 로컬에서
./gradlew clean build
docker build -t ghcr.io/johnhuh619/simple-api:latest .
docker push ghcr.io/johnhuh619/simple-api:latest

# EC2에서
sudo docker pull ghcr.io/johnhuh619/simple-api:latest
sudo docker restart feedback-api
```

---

## 📊 비용 예상

```
RDS (db.t3.micro):
  - Free Tier (1년): 무료
  - 이후: ~$15-20/월

CloudFront:
  - Free Tier: 1TB, 10M requests/월
  - 초과 시: ~$0.85/10GB

S3:
  - ~$0.01/월 (거의 무료)

총: Free Tier 사용 시 ~$0-1/월, 이후 ~$15-20/월
```

---

## 📚 관련 문서

1. **QUICK_EC2_DEPLOYMENT.md** ⭐ - 빠른 배포 가이드 (여기서 시작!)
2. **DEPLOYMENT_STATUS_SUMMARY.md** - 전체 현황
3. **frontend/README.md** - 프론트엔드 운영 가이드

---

**🎉 모든 준비 완료!**

**다음 명령어로 시작**:
```bash
./scripts/setup-rds-quick.sh
```

그 다음 `QUICK_EC2_DEPLOYMENT.md` 참조하여 단계별 진행!
