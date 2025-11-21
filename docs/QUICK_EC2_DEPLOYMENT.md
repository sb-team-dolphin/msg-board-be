# ⚡ 빠른 배포 가이드 (EC2 + RDS + CloudFront)

**목표**: 단일 EC2 백엔드 + RDS + CloudFront 프론트엔드 배포
**소요 시간**: 30-40분
**난이도**: ⭐⭐☆☆☆

---

## 🎯 현재 구조

```
현재:
  EC2 1대 (백엔드 실행 중)
  └─ MySQL (로컬 또는 EC2 내부)

목표:
  CloudFront (HTTPS)
    ├─ /          → S3 (프론트엔드)
    └─ /api/*     → EC2 (백엔드) → RDS MySQL

✅ ALB 없이 간단하게!
✅ CORS 문제 없음 (같은 도메인)
```

---

## 📋 사전 준비

### 1. EC2 정보 확인

```bash
# EC2 Public DNS 확인
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicDnsName,State.Name]' \
  --output table

# 또는 AWS Console에서:
# EC2 → Instances → 인스턴스 선택 → "Public IPv4 DNS" 복사
```

**메모장에 저장**:
```
EC2 Public DNS: ec2-13-125-xxx-xxx.ap-northeast-2.compute.amazonaws.com
Backend Port: 8080
```

### 2. EC2 Security Group 확인

```bash
# EC2 인스턴스 ID로 Security Group 확인
aws ec2 describe-instances \
  --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].SecurityGroups[*].[GroupId,GroupName]' \
  --output table
```

필요한 포트:
- ✅ **8080** (백엔드 API)
- ✅ **80** (CloudFront → EC2, 선택사항)

---

## 🚀 Step 1: RDS 생성 (10-15분)

### Option A: 자동 스크립트 (권장)

```bash
cd C:/2025proj/simple-api

# RDS 자동 생성
./scripts/setup-rds-quick.sh
```

**스크립트 실행 중 입력사항**:
```
Enter your EC2 instance ID (or press Enter to allow all VPC access):
i-xxxxxxxxxxxxx  # EC2 인스턴스 ID 입력 (보안 강화)
```

**대기 시간**: 5-10분 (RDS 인스턴스 생성)

**완료 시 출력**:
```
✅ RDS Setup Complete!

Connection Details:
  Endpoint: feedback-db.xxxxx.ap-northeast-2.rds.amazonaws.com
  Port: 3306
  Database: feedbackdb
  Username: feedbackuser
  Password: FeedbackPass123!

Configuration saved to: rds-config.env
```

**rds-config.env 파일 확인**:
```bash
cat rds-config.env

# 출력:
# export RDS_ENDPOINT=feedback-db.xxxxx.rds.amazonaws.com
# export RDS_PORT=3306
# ...
```

### Option B: 수동 생성

AWS Console → RDS → Create database:
1. **Engine**: MySQL 8.0.35
2. **Templates**: Free tier
3. **DB instance identifier**: feedback-db
4. **Master username**: feedbackuser
5. **Master password**: FeedbackPass123!
6. **DB instance class**: db.t3.micro
7. **Storage**: 20 GB
8. **VPC**: Default VPC
9. **Public access**: No
10. **VPC security group**: Create new → feedback-rds-sg
11. **Database name**: feedbackdb

---

## 🔧 Step 2: 백엔드 재배포 (5-10분)

### 2-1. 환경 변수 설정

RDS 엔드포인트를 사용하도록 설정:

```bash
# RDS 설정 로드
source rds-config.env

# 확인
echo $RDS_ENDPOINT
# 출력: feedback-db.xxxxx.ap-northeast-2.rds.amazonaws.com
```

### 2-2. Docker 컨테이너 재시작 (EC2에서 실행)

**SSH로 EC2 접속**:
```bash
ssh -i your-key.pem ec2-user@<EC2-Public-IP>
```

**EC2에서 실행**:
```bash
# 기존 컨테이너 중지 및 제거
sudo docker stop feedback-api || true
sudo docker rm feedback-api || true

# RDS 엔드포인트 설정
export DB_HOST="feedback-db.xxxxx.ap-northeast-2.rds.amazonaws.com"
export DB_PORT="3306"
export DB_NAME="feedbackdb"
export DB_USER="feedbackuser"
export DB_PASSWORD="FeedbackPass123!"

# 새 컨테이너 시작
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
```

**성공 확인**:
```
Started SimpleApiApplication in X.XXX seconds
Tomcat started on port(s): 8080 (http)
```

### 2-3. RDS 연결 테스트

```bash
# Health check
curl http://localhost:8080/actuator/health

# 예상 출력:
# {"status":"UP",...}

# API 테스트
curl http://localhost:8080/api/feedbacks

# 예상 출력:
# {"content":[],"totalElements":0,...}
```

---

## 🌐 Step 3: CloudFront + S3 배포 (15-20분)

### 3-1. CloudFront 인프라 생성

```bash
cd C:/2025proj/simple-api

# CloudFront + S3 설정
./scripts/setup-cloudfront-ec2.sh
```

**스크립트 실행 중 입력사항**:
```
Enter EC2 Public DNS or IP:
ec2-13-125-xxx-xxx.ap-northeast-2.compute.amazonaws.com

Enter backend port (default: 8080):
8080
```

**대기 시간**: 10-15분 (CloudFront 배포)

**완료 시 출력**:
```
✅ Setup Complete!

URLs:
  Frontend: https://d1234567890abc.cloudfront.net
  API: https://d1234567890abc.cloudfront.net/api/feedbacks

⏳ CloudFront is deploying (10-15 minutes)
```

### 3-2. CloudFront 배포 대기

```bash
# 환경 변수 로드
source cloudfront-config.env

# 배포 상태 확인
aws cloudfront get-distribution \
  --id $CLOUDFRONT_DISTRIBUTION_ID \
  --query 'Distribution.Status' \
  --output text

# "Deployed"가 나올 때까지 대기 (10-15분)
```

---

## ✅ Step 4: 통합 테스트 (5분)

### 4-1. API 테스트

```bash
# CloudFront를 통한 API 호출
curl https://$CLOUDFRONT_DOMAIN/api/feedbacks

# 예상 출력:
# {
#   "content": [],
#   "pageable": {...},
#   "totalElements": 0,
#   "totalPages": 0
# }
```

### 4-2. 브라우저 테스트

```bash
# 브라우저에서 열기
start https://$CLOUDFRONT_DOMAIN

# Mac: open https://$CLOUDFRONT_DOMAIN
# Linux: xdg-open https://$CLOUDFRONT_DOMAIN
```

**개발자 도구 확인 (F12)**:

1. **Network 탭**:
   ```
   ✅ index.html - 200 OK (from S3 via CloudFront)
   ✅ app.js - 200 OK (from S3 via CloudFront)
   ✅ api/feedbacks - 200 OK (from EC2 via CloudFront)
   ```

2. **Console 탭**:
   ```
   ❌ CORS 에러 없어야 함!
   ✅ 피드백 목록 로드됨 (빈 배열 또는 기존 데이터)
   ```

### 4-3. 피드백 생성 테스트

브라우저에서:
1. **이름**: "테스터"
2. **메시지**: "RDS + CloudFront 배포 성공!"
3. **[작성하기]** 클릭

→ **목록에 추가되면 성공!** ✅

### 4-4. RDS 데이터 확인

EC2에서:
```bash
# RDS 접속 테스트 (EC2에서 실행)
mysql -h feedback-db.xxxxx.rds.amazonaws.com \
  -u feedbackuser \
  -pFeedbackPass123! \
  feedbackdb

# MySQL에서
mysql> SELECT * FROM feedback;
# 방금 생성한 피드백 확인!

mysql> exit;
```

---

## 🔄 프론트엔드 업데이트 테스트 (2분)

```bash
cd frontend

# CSS 수정
echo "/* Updated $(date) */" >> css/style.css

# 배포
./deploy.sh

# 1-3분 후 브라우저 새로고침 (Ctrl+Shift+R)
# → 변경사항 즉시 반영!
```

---

## 📊 최종 아키텍처

```
사용자
  ↓ HTTPS
CloudFront Distribution
  ├─ /              → S3 Bucket
  │  ├─ index.html
  │  ├─ js/app.js  (API_BASE_URL='/api')
  │  └─ css/style.css
  │
  └─ /api/*         → EC2 Instance
                      ├─ Spring Boot (port 8080)
                      └─ Docker Container
                        ↓
                      RDS MySQL
                        └─ feedbackdb

✅ 같은 도메인 → CORS 없음
✅ HTTPS 자동 적용
✅ RDS 자동 백업 (7일)
✅ 프론트엔드 독립 배포
```

---

## 💰 비용 예상

```
월간 비용 (트래픽 적을 때):

RDS (db.t3.micro):
  - Free Tier: 750시간/월 무료 (1년간)
  - 이후: ~$15-20/월

EC2 (기존 사용 중):
  - 변경 없음

CloudFront:
  - Data Transfer (10GB): ~$0.85
  - Requests (100K): ~$0.01
  - Free Tier: 1TB, 10M requests/월

S3:
  - Storage (10MB): ~$0.0002
  - Requests: ~$0.01

총 예상 비용:
  - Free Tier 사용 시: ~$0-1/월
  - Free Tier 이후: ~$15-20/월 (RDS)
```

---

## 🚨 트러블슈팅

### 문제 1: RDS 연결 실패

**증상**:
```
Communications link failure
```

**원인**: Security Group 설정 오류

**해결**:
```bash
# RDS Security Group 확인
aws ec2 describe-security-groups \
  --group-names feedback-rds-sg \
  --query 'SecurityGroups[0].IpPermissions'

# EC2의 Security Group ID 확인
EC2_SG=$(aws ec2 describe-instances \
  --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

# RDS SG에 EC2 SG 접근 허용
RDS_SG=$(aws ec2 describe-security-groups \
  --group-names feedback-rds-sg \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 3306 \
  --source-group $EC2_SG
```

### 문제 2: CloudFront에서 API 502 에러

**증상**: `/api/feedbacks` 호출 시 502 Bad Gateway

**원인**: EC2 Security Group에서 CloudFront 접근 차단

**해결**:
```bash
# EC2 Security Group에 80/8080 포트 개방
aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

### 문제 3: 프론트엔드 403 Forbidden

**원인**: S3 버킷 정책 오류

**해결**:
```bash
# S3 버킷 정책 확인
aws s3api get-bucket-policy --bucket $S3_BUCKET_NAME

# 재설정 필요 시 스크립트 재실행
./scripts/setup-cloudfront-ec2.sh
```

### 문제 4: Docker 환경 변수 미적용

**증상**: 여전히 로컬 MySQL 연결 시도

**해결**:
```bash
# EC2에서 컨테이너 환경 변수 확인
sudo docker exec feedback-api env | grep DB_

# 환경 변수 재설정 후 재시작
sudo docker restart feedback-api
```

---

## 📂 생성된 파일

```
C:/2025proj/simple-api/
├── src/main/resources/
│   └── application-prod.yml        ✏️ 환경 변수로 수정됨
│
├── scripts/
│   ├── setup-rds-quick.sh          🆕 RDS 자동 생성
│   └── setup-cloudfront-ec2.sh     🆕 CloudFront 설정 (EC2용)
│
├── frontend/                        ✅ 이미 생성됨
│   ├── deploy.sh
│   └── ...
│
├── rds-config.env                   🆕 RDS 설정 (생성됨)
└── cloudfront-config.env            🆕 CloudFront 설정 (생성됨)
```

---

## ✅ 체크리스트

### 백엔드 (RDS)
- [ ] EC2 정보 확인 (Public DNS, Instance ID)
- [ ] `./scripts/setup-rds-quick.sh` 실행
- [ ] RDS 배포 완료 대기 (5-10분)
- [ ] `rds-config.env` 파일 저장
- [ ] EC2에서 Docker 재시작 (환경 변수 주입)
- [ ] RDS 연결 테스트 (health check)

### 프론트엔드 (CloudFront)
- [ ] `./scripts/setup-cloudfront-ec2.sh` 실행
- [ ] EC2 Public DNS 입력
- [ ] CloudFront 배포 대기 (10-15분)
- [ ] `cloudfront-config.env` 파일 저장
- [ ] 통합 테스트 (브라우저)
- [ ] 피드백 생성 테스트
- [ ] 프론트엔드 업데이트 테스트

---

## 🎯 성공 기준

모든 단계 완료 후:

```bash
# 1. RDS 연결 확인
✅ EC2 Docker 로그에 "Started SimpleApiApplication" 표시

# 2. CloudFront 접속 확인
✅ https://d1234...cloudfront.net/ → 프론트엔드 로드

# 3. API 호출 확인
✅ https://d1234...cloudfront.net/api/feedbacks → JSON 응답

# 4. 데이터 생성 확인
✅ 브라우저에서 피드백 생성 → RDS에 저장됨

# 5. CORS 확인
✅ 브라우저 Console에 CORS 에러 없음
```

---

## 📖 참고 문서

- **상세 가이드**: `CLOUDFRONT_DEPLOYMENT_QUICKSTART.md`
- **운영 가이드**: `frontend/README.md`
- **전체 아키텍처**: `FRONTEND_BACKEND_SEPARATION_GUIDE.md`

---

**🎉 완료! EC2 + RDS + CloudFront 배포 성공!**

**Frontend**: https://d1234...cloudfront.net
**Backend API**: https://d1234...cloudfront.net/api
**Database**: RDS MySQL (자동 백업)

이제 프론트엔드는 `./deploy.sh`로 독립 배포 가능! 🚀
