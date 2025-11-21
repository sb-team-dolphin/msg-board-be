# 🚀 실전 구현 가이드 (단계별 검증 포함)

**목표**: ALB + ASG + MySQL 인프라를 순차적으로 구축하고 각 단계마다 검증

**소요 시간**: 6-8시간
**난이도**: ⭐⭐☆☆☆

---

## 📋 사전 준비 체크리스트

### 1. 로컬 환경 확인

```bash
# Git 확인
git --version
# → git version 2.x.x 이상

# Docker 확인
docker --version
# → Docker version 20.x.x 이상

# Java 확인
java -version
# → openjdk version "21" 이상

# Gradle 확인
./gradlew --version
# → Gradle 8.x 이상

# 프로젝트 디렉토리 확인
cd C:/2025proj/simple-api
git status
# → On branch convert
```

### 2. AWS 계정 확인

```bash
# AWS CLI 설치 확인 (Optional)
aws --version

# AWS Console 로그인
# - Region: ap-northeast-2 (서울) 선택 ⭐
# - IAM 권한 확인: EC2, VPC, ELB Full Access
```

### 3. GitHub 설정 확인

```bash
# Repository 상태 확인
# Public으로 설정되어 있거나
# Personal Access Token 준비

# Token 권한 (필요 시):
# - write:packages
# - read:packages
```

---

## 🎯 Phase 1: VPC 및 네트워크 기본 (30분)

### Step 1-1: VPC 생성

```
AWS Console → VPC → Your VPCs → Create VPC

Settings:
  ○ VPC only

Details:
  Name tag: feedback-vpc
  IPv4 CIDR: 10.0.0.0/16
  IPv6 CIDR: No IPv6
  Tenancy: Default

[Create VPC]
```

**✅ 검증**:
```
VPC 목록에서 확인:
  ✓ Name: feedback-vpc
  ✓ State: Available
  ✓ IPv4 CIDR: 10.0.0.0/16
  ✓ VPC ID: vpc-xxxxx (복사해두기!)
```

**⚠️ 주의사항**:
- Region이 **ap-northeast-2 (서울)**인지 재확인!
- VPC ID는 이후 계속 사용되므로 메모장에 복사!

### Step 1-2: Internet Gateway 생성 및 연결

```
VPC → Internet Gateways → Create internet gateway

Name tag: feedback-igw

[Create internet gateway]
```

**생성 후 즉시 연결**:
```
Actions → Attach to VPC
  Available VPCs: feedback-vpc 선택

[Attach internet gateway]
```

**✅ 검증**:
```
Internet Gateways 목록:
  ✓ Name: feedback-igw
  ✓ State: Attached
  ✓ VPC ID: vpc-xxxxx (위에서 만든 VPC)
```

### Step 1-3: Public Subnet 2개 생성

**첫 번째 Subnet**:
```
VPC → Subnets → Create subnet

VPC ID: feedback-vpc 선택 ⭐

Subnet settings:
  Subnet name: Public-AZ-A
  Availability Zone: ap-northeast-2a ⭐
  IPv4 CIDR block: 10.0.1.0/24

[Add new subnet] 클릭
```

**두 번째 Subnet (같은 화면에서 추가)**:
```
Subnet settings:
  Subnet name: Public-AZ-C
  Availability Zone: ap-northeast-2c ⭐
  IPv4 CIDR block: 10.0.2.0/24

[Create subnet]
```

**✅ 검증**:
```
Subnets 목록:
  ✓ Public-AZ-A | 10.0.1.0/24 | ap-northeast-2a | Available
  ✓ Public-AZ-C | 10.0.2.0/24 | ap-northeast-2c | Available
  ✓ Available IPs: 각 251개
```

**⚠️ 주의사항**:
- AZ는 반드시 **2a**와 **2c** (ALB 요구사항!)
- CIDR이 겹치지 않게: 10.0.1.0/24, 10.0.2.0/24

### Step 1-4: Public Subnet 자동 IP 할당 활성화

**각 Subnet마다 실행**:
```
Subnets → Public-AZ-A 선택
  → Actions → Edit subnet settings

Auto-assign IP settings:
  ☑ Enable auto-assign public IPv4 address ⭐

[Save]

→ Public-AZ-C도 동일하게 실행
```

**✅ 검증**:
```
Subnets → 각 Subnet 선택 → Details 탭:
  ✓ Auto-assign public IPv4 address: Yes
```

### Step 1-5: Route Table 생성 및 설정

```
VPC → Route Tables → Create route table

Details:
  Name: public-rt
  VPC: feedback-vpc

[Create route table]
```

**Route 추가**:
```
Route Tables → public-rt 선택
  → Routes 탭 → Edit routes → Add route

Route:
  Destination: 0.0.0.0/0
  Target: Internet Gateway → feedback-igw 선택

[Save changes]
```

**Subnet 연결**:
```
Subnet associations 탭 → Edit subnet associations

Subnets:
  ☑ Public-AZ-A
  ☑ Public-AZ-C

[Save associations]
```

**✅ 검증**:
```
Routes 탭:
  ✓ 10.0.0.0/16    local
  ✓ 0.0.0.0/0      igw-xxxxx

Subnet associations 탭:
  ✓ Public-AZ-A (subnet-xxxxx1)
  ✓ Public-AZ-C (subnet-xxxxx2)
```

**🧪 네트워크 테스트 (Optional)**:
```
임시 EC2 인스턴스 시작:
  - Public-AZ-A에 t2.micro 시작
  - SSH 접속 확인
  - ping 8.8.8.8 (인터넷 연결 확인)
  - 확인 후 인스턴스 종료
```

---

## 🔒 Phase 2: Security Groups 생성 (30분)

### Step 2-1: ALB Security Group

```
EC2 → Security Groups → Create security group

Basic details:
  Security group name: alb-sg
  Description: Security group for ALB
  VPC: feedback-vpc ⭐

Inbound rules:
  [Add rule]
    Type: HTTP
    Port: 80
    Source: 0.0.0.0/0
    Description: Allow HTTP from internet

Outbound rules:
  (기본값 유지: All traffic to 0.0.0.0/0)

[Create security group]
```

**✅ 검증**:
```
Security Groups 목록:
  ✓ Name: alb-sg
  ✓ VPC ID: vpc-xxxxx (feedback-vpc)
  ✓ Inbound: HTTP (80) from 0.0.0.0/0
  ✓ Security Group ID: sg-xxxxx1 (복사!)
```

### Step 2-2: Application Security Group

```
Create security group

Basic details:
  Security group name: app-sg
  Description: Security group for App instances
  VPC: feedback-vpc ⭐

Inbound rules:
  [Add rule]
    Type: Custom TCP
    Port: 8080
    Source: Custom → alb-sg 선택 ⭐
    Description: Allow 8080 from ALB

  [Add rule]
    Type: SSH
    Port: 22
    Source: My IP (또는 0.0.0.0/0)
    Description: SSH for troubleshooting

Outbound rules:
  (기본값 유지)

[Create security group]
```

**✅ 검증**:
```
Security Groups → app-sg:
  ✓ Inbound:
    - 8080 from alb-sg ⭐
    - 22 from My IP
  ✓ Outbound: All traffic
  ✓ Security Group ID: sg-xxxxx2 (복사!)
```

**⚠️ 주의사항**:
- 8080 Source는 반드시 **alb-sg** (IP 아님!)
- 이렇게 해야 ALB에서만 접근 가능!

### Step 2-3: Database Security Group

```
Create security group

Basic details:
  Security group name: db-sg
  Description: Security group for MySQL
  VPC: feedback-vpc ⭐

Inbound rules:
  [Add rule]
    Type: MYSQL/Aurora
    Port: 3306
    Source: Custom → app-sg 선택 ⭐
    Description: Allow MySQL from App

  [Add rule]
    Type: SSH
    Port: 22
    Source: My IP (또는 0.0.0.0/0)
    Description: SSH for management

Outbound rules:
  (기본값 유지)

[Create security group]
```

**✅ 검증**:
```
Security Groups → db-sg:
  ✓ Inbound:
    - 3306 from app-sg ⭐
    - 22 from My IP
  ✓ Security Group ID: sg-xxxxx3 (복사!)
```

**🔍 Security Group 관계 확인**:
```
alb-sg (sg-xxxxx1)
  ↓ (8080)
app-sg (sg-xxxxx2)
  ↓ (3306)
db-sg (sg-xxxxx3)

✅ 올바른 체인!
```

---

## 🗄️ Phase 3: MySQL 설치 및 검증 (40분) ⭐ 중요!

### Step 3-1: MySQL EC2 인스턴스 시작

```
EC2 → Instances → Launch instances

Name: mysql-server

AMI: Amazon Linux 2023 AMI

Instance type: t3.small (또는 t2.small)

Key pair: [기존 키 선택 또는 생성]

Network settings:
  [Edit]
  VPC: feedback-vpc
  Subnet: Public-AZ-A ⭐
  Auto-assign public IP: Enable
  Security group: Select existing → db-sg

Storage:
  Root volume: 10 GiB gp3
  [Add new volume]
    Size: 20 GiB
    Volume type: gp3
    Device: /dev/sdb

[Launch instance]
```

**✅ 검증**:
```
Instances 목록:
  ✓ Name: mysql-server
  ✓ State: Running
  ✓ Instance ID: i-xxxxx (복사!)
  ✓ Public IP: 3.35.X.X (복사!)
  ✓ Private IP: 10.0.1.X (복사! 매우 중요!) ⭐⭐⭐
```

**⚠️ 매우 중요! Private IP 확인**:
```
Instances → mysql-server 선택 → Networking 탭
  Private IPv4 addresses: 10.0.1.234 (예시)

→ 이 IP를 메모장에 복사!
→ 이후 모든 설정에서 사용됨!
```

### Step 3-2: MySQL 설치

**SSH 접속**:
```bash
# 로컬 터미널
ssh -i your-key.pem ec2-user@[MySQL-Public-IP]
```

**MySQL 설치 (한 번에 실행)**:
```bash
# MySQL 8.0 설치
sudo dnf update -y
sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
sudo dnf install -y mysql-community-server

# 데이터 볼륨 마운트
sudo mkfs -t xfs /dev/nvme1n1
sudo mkdir /data
sudo mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data xfs defaults,nofail 0 2' | sudo tee -a /etc/fstab

# MySQL 디렉토리 설정
sudo mkdir -p /data/mysql
sudo chown -R mysql:mysql /data/mysql

# 설정 파일
sudo tee /etc/my.cnf << 'EOF'
[mysqld]
datadir=/data/mysql
socket=/var/lib/mysql/mysql.sock
bind-address = 0.0.0.0
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
max_connections = 100

[client]
default-character-set = utf8mb4
EOF

# MySQL 시작
sudo mysqld --initialize --user=mysql --datadir=/data/mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld
```

**✅ 검증**:
```bash
# MySQL 실행 확인
sudo systemctl status mysqld
# → Active: active (running)

# 포트 확인
sudo netstat -tlnp | grep 3306
# → tcp 0.0.0.0:3306 LISTEN
```

### Step 3-3: 데이터베이스 생성 ⭐

**임시 비밀번호 확인**:
```bash
TEMP_PASS=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
echo "임시 비밀번호: $TEMP_PASS"
# → 임시 비밀번호: xxxx (복사!)
```

**Root 비밀번호 변경 및 DB 생성**:
```bash
# MySQL 접속
mysql -u root -p"$TEMP_PASS" --connect-expired-password

# MySQL 프롬프트에서 실행
ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyRootPass123!';

CREATE DATABASE feedbackdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'feedbackuser'@'%' IDENTIFIED BY 'FeedbackPass123!';
GRANT ALL PRIVILEGES ON feedbackdb.* TO 'feedbackuser'@'%';
FLUSH PRIVILEGES;

SHOW DATABASES;
SELECT user, host FROM mysql.user WHERE user='feedbackuser';

EXIT;
```

**✅ 검증**:
```bash
# 외부 연결 테스트 (로컬에서)
mysql -h [MySQL-Public-IP] -u feedbackuser -p'FeedbackPass123!' feedbackdb

# 접속 성공하면:
mysql> SHOW TABLES;
# → Empty set (정상, 아직 테이블 없음)

mysql> EXIT;
```

**⚠️ 연결 실패 시**:
```
Error: Can't connect to MySQL server

원인 1: Security Group 확인
  → EC2 → Security Groups → db-sg
  → Inbound rules에 3306 from 0.0.0.0/0 임시 추가
  → 테스트 후 다시 app-sg로 변경

원인 2: bind-address 확인
  → /etc/my.cnf에서 bind-address = 0.0.0.0 확인

원인 3: 방화벽 확인
  → sudo systemctl status firewalld
  → sudo systemctl stop firewalld (테스트용)
```

### Step 3-4: Private IP 재확인 및 기록 ⭐⭐⭐

```bash
# MySQL 서버에서 확인
hostname -I | awk '{print $1}'
# → 10.0.1.234 (예시)
```

**📝 중요! 이 IP를 기록**:
```
MySQL Private IP: 10.0.1.234

→ 다음 단계에서 사용:
  1. application-prod.yml
  2. Launch Template User Data
  3. 모든 App 인스턴스 연결

→ 메모장에 복사해두기!
```

---

## 🐳 Phase 4: Application 준비 (40분)

### Step 4-1: application-prod.yml 생성

**파일 위치**: `src/main/resources/application-prod.yml`

```yaml
spring:
  datasource:
    url: jdbc:mysql://10.0.1.234:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    #              ^^^^^^^^^^^ ⭐ MySQL Private IP로 변경!
    username: feedbackuser
    password: FeedbackPass123!
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: update
    properties:
      hibernate:
        format_sql: true
        show_sql: false
    open-in-view: false

logging:
  level:
    root: INFO
    com.feedback.api: DEBUG

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always
```

**⚠️ 필수 수정**:
```
Line 3: url: jdbc:mysql://10.0.1.234:...
         → 10.0.1.234를 실제 MySQL Private IP로 변경!
```

### Step 4-2: build.gradle 확인

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    // MySQL 의존성 ⭐
    runtimeOnly 'com.mysql:mysql-connector-j'

    // H2 (개발용으로 유지)
    runtimeOnly 'com.h2database:h2'

    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
}
```

**✅ 검증**:
```
✓ com.mysql:mysql-connector-j 있음
✓ spring-boot-starter-data-jpa 있음
```

### Step 4-3: 로컬 빌드 테스트

```bash
cd C:/2025proj/simple-api

# 빌드
./gradlew clean build

# 빌드 성공 확인
ls build/libs/
# → simple-api-0.0.1-SNAPSHOT.jar ✓
```

**✅ 검증**:
```
BUILD SUCCESSFUL in Xs

build/libs/simple-api-0.0.1-SNAPSHOT.jar 존재
```

**⚠️ 빌드 실패 시**:
```
원인 1: MySQL 의존성 없음
  → build.gradle 확인

원인 2: 테스트 실패
  → ./gradlew clean build -x test (테스트 스킵)
```

### Step 4-4: Docker 이미지 빌드 및 푸시

**Dockerfile 확인**:
```dockerfile
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY build/libs/*.jar app.jar

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**이미지 빌드**:
```bash
docker build -t ghcr.io/johnhuh619/simple-api:latest .
```

**✅ 검증**:
```bash
docker images | grep simple-api
# → ghcr.io/johnhuh619/simple-api   latest   xxxxx   2 mins ago   500MB
```

**GitHub Container Registry 로그인**:
```bash
# Option 1: Public repo (로그인 불필요)

# Option 2: Private repo
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u johnhuh619 --password-stdin
```

**이미지 푸시**:
```bash
docker push ghcr.io/johnhuh619/simple-api:latest
```

**✅ 검증**:
```
GitHub → Profile → Packages
  → simple-api 패키지 확인
  → latest 태그 존재 확인
```

### Step 4-5: 로컬에서 MySQL 연결 테스트 ⭐ 중요!

**Security Group 임시 수정** (테스트용):
```
EC2 → Security Groups → db-sg
  → Inbound rules → Edit inbound rules
  → Add rule:
    Type: MySQL/Aurora
    Source: 0.0.0.0/0 (임시!)

[Save rules]
```

**Docker로 연결 테스트**:
```bash
docker run --rm \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://[MySQL-Public-IP]:3306/feedbackdb?useSSL=false \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackPass123! \
  -p 8080:8080 \
  ghcr.io/johnhuh619/simple-api:latest
```

**✅ 검증**:
```bash
# 다른 터미널에서
curl http://localhost:8080/actuator/health

# 예상 결과:
{
  "status": "UP",
  "components": {
    "db": {
      "status": "UP",  ⭐ 중요!
      "details": {
        "database": "MySQL",
        "validationQuery": "isValid()"
      }
    },
    ...
  }
}

# ✓ "db": {"status": "UP"} 확인!
```

**MySQL에서 테이블 확인**:
```bash
mysql -h [MySQL-Public-IP] -u feedbackuser -p'FeedbackPass123!' feedbackdb

mysql> SHOW TABLES;
# → feedbacks 테이블 자동 생성됨! (ddl-auto: update)

mysql> DESCRIBE feedbacks;
# → 테이블 구조 확인

mysql> EXIT;
```

**Security Group 원복**:
```
db-sg → Inbound rules → Edit
  → 3306 from 0.0.0.0/0 삭제
  → 3306 from app-sg만 유지

[Save rules]
```

**🎉 Application-MySQL 연결 성공!**

---

## 🚀 Phase 5: Launch Template 생성 (30분)

### Step 5-1: User Data 스크립트 준비

**메모장에서 먼저 작성** (MySQL IP 수정 필요!):

```bash
#!/bin/bash

# 변수 설정
IMAGE_TAG="latest"
MYSQL_HOST="10.0.1.234"  # ⭐⭐⭐ 실제 MySQL Private IP로 변경!
MYSQL_DATABASE="feedbackdb"
MYSQL_USER="feedbackuser"
MYSQL_PASSWORD="FeedbackPass123!"

# 로그
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "========================================="
echo "User Data Started: $(date)"
echo "========================================="

# Docker 설치
echo "[1/3] Installing Docker..."
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Docker 이미지 pull
echo "[2/3] Pulling Docker image..."
sudo docker pull ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

# Application 시작
echo "[3/3] Starting application..."
sudo docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_DATABASE}?useSSL=false&serverTimezone=Asia/Seoul \
  -e SPRING_DATASOURCE_USERNAME=${MYSQL_USER} \
  -e SPRING_DATASOURCE_PASSWORD=${MYSQL_PASSWORD} \
  ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

# 헬스 체크
echo "Waiting for application..."
for i in {1..30}; do
  if curl -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo "✅ Application is healthy!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 10
done

echo "========================================="
echo "User Data Completed: $(date)"
echo "========================================="
```

**⚠️ 필수 수정**:
```
Line 5: MYSQL_HOST="10.0.1.234"
        → 실제 MySQL Private IP로 변경!
```

### Step 5-2: Launch Template 생성

```
EC2 → Launch Templates → Create launch template

Template name: feedback-app-template
Template version description: Initial version
☑ Provide guidance for Auto Scaling

Application and OS Images:
  Amazon Linux 2023 AMI

Instance type:
  t3.small (또는 t2.small)

Key pair:
  [기존 키 선택]

Network settings:
  Subnet: Don't include ⭐ (ASG에서 지정)
  Security groups: app-sg 선택 ⭐

Storage:
  10 GiB gp3

Advanced details:
  [Expand]

  User data:
    [위에서 작성한 스크립트 복붙] ⭐

[Create launch template]
```

**✅ 검증**:
```
Launch Templates 목록:
  ✓ Name: feedback-app-template
  ✓ Latest version: 1
  ✓ AMI: Amazon Linux 2023
  ✓ Instance type: t3.small
  ✓ Security groups: app-sg
```

### Step 5-3: Launch Template 테스트 (Optional but Recommended) ⭐

**테스트 인스턴스 시작**:
```
Launch Templates → feedback-app-template
  → Actions → Launch instance from template

Instance details:
  Subnet: Public-AZ-A ⭐
  Auto-assign public IP: Enable

[Launch instance]
```

**대기 (5분)**:
```
User Data 스크립트 실행 중...
  - Docker 설치: 1분
  - 이미지 pull: 2분
  - 컨테이너 시작: 1분
  - 헬스 체크: 1분
```

**SSH 접속하여 확인**:
```bash
ssh -i your-key.pem ec2-user@[Test-Instance-Public-IP]

# User Data 로그 확인
sudo tail -f /var/log/user-data.log
# → "✅ Application is healthy!" 확인

# Docker 확인
sudo docker ps
# → feedback-api 컨테이너 실행 중

# 헬스 체크
curl http://localhost:8080/actuator/health
# → {"status":"UP","components":{"db":{"status":"UP"}}}

# ✓ db status UP 확인! ⭐
```

**MySQL 연결 확인**:
```bash
# 테스트 데이터 생성
curl -X POST http://localhost:8080/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Launch Template 테스트!",
    "author": "테스터"
  }'

# 조회
curl http://localhost:8080/api/feedbacks
# → [{"id":1,"content":"Launch Template 테스트!",...}]

# MySQL에서 직접 확인
mysql -h 10.0.1.234 -u feedbackuser -p'FeedbackPass123!' feedbackdb

mysql> SELECT * FROM feedbacks;
# → 데이터 확인됨! ✅
```

**테스트 인스턴스 종료**:
```
EC2 → Instances → 테스트 인스턴스 선택
  → Instance state → Terminate instance
```

**🎉 Launch Template 검증 완료!**

---

## ⚖️ Phase 6: Target Group + ALB (80분)

### Step 6-1: Target Group 생성

```
EC2 → Target Groups → Create target group

Target type:
  ○ Instances

Target group name: feedback-tg

Protocol: HTTP
Port: 8080 ⭐
VPC: feedback-vpc

Protocol version: HTTP1

Health checks:
  Protocol: HTTP
  Path: /actuator/health ⭐

Advanced health check:
  Port: Traffic port
  Healthy threshold: 2
  Unhealthy threshold: 2
  Timeout: 5
  Interval: 30
  Success codes: 200

[Next]

Register targets:
  (비워두기 - ASG가 자동 등록)

[Create target group]
```

**✅ 검증**:
```
Target Groups 목록:
  ✓ Name: feedback-tg
  ✓ Protocol: HTTP:8080
  ✓ Health check path: /actuator/health
  ✓ VPC: feedback-vpc
```

**⚠️ 주의사항**:
```
Port: 8080 (80 아님!)
Path: /actuator/health (정확히!)
Success codes: 200
```

### Step 6-2: Application Load Balancer 생성

```
EC2 → Load Balancers → Create load balancer
  → Application Load Balancer [Create]

Name: feedback-alb

Scheme: ○ Internet-facing
IP address type: ○ IPv4

Network mapping:
  VPC: feedback-vpc

  Mappings:
    ☑ ap-northeast-2a → Public-AZ-A ⭐
    ☑ ap-northeast-2c → Public-AZ-C ⭐

Security groups:
  [Remove default]
  ☑ alb-sg ⭐

Listeners and routing:
  Protocol: HTTP
  Port: 80
  Default action: Forward to → feedback-tg

[Create load balancer]
```

**대기 (2-3분)**:
```
Load balancer state: provisioning → active
```

**✅ 검증**:
```
Load Balancers → feedback-alb:
  ✓ State: active
  ✓ DNS name: feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com
    → 복사! ⭐
  ✓ VPC: feedback-vpc
  ✓ AZs: ap-northeast-2a, ap-northeast-2c
  ✓ Security groups: alb-sg
```

**DNS 이름 저장**:
```
ALB_DNS="feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com"

→ 메모장에 복사!
```

### Step 6-3: ALB 헬스 체크 (아직 타겟 없음)

```
Target Groups → feedback-tg → Targets 탭

Registered targets:
  (None - ASG가 추가할 예정)

→ 정상! 아직 인스턴스 없음
```

---

## 🔄 Phase 7: Auto Scaling Group 생성 (60분)

### Step 7-1: Auto Scaling Group 생성

```
EC2 → Auto Scaling Groups → Create Auto Scaling group

Step 1: Choose launch template
  Name: feedback-asg
  Launch template: feedback-app-template ⭐
  Version: Latest

[Next]

Step 2: Choose instance launch options
  VPC: feedback-vpc

  Availability Zones and subnets:
    ☑ Public-AZ-A | 10.0.1.0/24 ⭐
    ☑ Public-AZ-C | 10.0.2.0/24 ⭐

[Next]

Step 3: Configure advanced options
  Load balancing:
    ☑ Attach to an existing load balancer

  Choose from load balancer target groups:
    ☑ feedback-tg ⭐

  Health checks:
    ☑ Turn on Elastic Load Balancing health checks ⭐
    Health check grace period: 300 seconds

[Next]

Step 4: Configure group size and scaling
  Group size:
    Desired: 2 ⭐
    Minimum: 1
    Maximum: 3

  Scaling policies:
    ○ Target tracking scaling policy

    Metric type: Average CPU utilization
    Target value: 70
    Instances need: 300 seconds warm up

[Next]

Step 5: Add notifications
  (Skip)

[Next]

Step 6: Add tags
  [Add tag]
    Key: Name
    Value: feedback-app-asg-instance

[Next]

Step 7: Review
  [Create Auto Scaling group]
```

**✅ 검증**:
```
Auto Scaling Groups 목록:
  ✓ Name: feedback-asg
  ✓ Launch template: feedback-app-template
  ✓ Desired: 2, Min: 1, Max: 3
  ✓ Subnets: Public-AZ-A, Public-AZ-C
```

### Step 7-2: 인스턴스 시작 모니터링 ⭐ 중요!

**Activity 탭 확인**:
```
Auto Scaling Groups → feedback-asg → Activity 탭

Activity history:
  Status: InProgress
    "Launching a new EC2 instance: i-xxxxx1"
    "Launching a new EC2 instance: i-xxxxx2"

대기 (5-7분):
  - EC2 시작: 1분
  - User Data 실행: 5분
  - Health check: 1분
```

**Instance management 탭 확인**:
```
Instances:
  i-xxxxx1 | InService | Healthy | ap-northeast-2a
  i-xxxxx2 | InService | Healthy | ap-northeast-2c

✓ 두 인스턴스 모두 Healthy!
```

**⚠️ InService but Unhealthy 시**:
```
원인: User Data 실행 실패 또는 Health check 실패

해결:
1. EC2 → Instances에서 해당 인스턴스 찾기
2. Public IP로 SSH 접속
3. 로그 확인:
   sudo tail -f /var/log/user-data.log
   sudo docker logs feedback-api

4. 헬스 체크:
   curl http://localhost:8080/actuator/health
```

### Step 7-3: Target Group 헬스 확인 ⭐⭐⭐

```
EC2 → Target Groups → feedback-tg → Targets 탭

Registered targets:
  i-xxxxx1 | 10.0.1.10:8080 | healthy | ap-northeast-2a ✅
  i-xxxxx2 | 10.0.2.20:8080 | healthy | ap-northeast-2c ✅

✓ 두 인스턴스 모두 healthy!
```

**⚠️ unhealthy 시 (매우 중요!)**:
```
Status: unhealthy
  Health check failed

원인 체크:

1. Health check path 확인
   Target Group → Health checks → Edit
   → Path: /actuator/health (정확한지 확인!)

2. Security Group 확인
   app-sg → Inbound rules
   → 8080 from alb-sg 있는지!

3. Application 상태 확인
   SSH 접속:
   curl http://localhost:8080/actuator/health
   → {"status":"UP"} 응답하는지!

4. DB 연결 확인
   curl http://localhost:8080/actuator/health | jq
   → "db": {"status": "UP"} 확인!
```

**🎉 모두 healthy면 성공!**

---

## 🧪 Phase 8: 전체 통합 테스트 (40분)

### Test 1: ALB 헬스 체크

```bash
# 로컬 터미널
ALB_DNS="feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com"

curl http://${ALB_DNS}/actuator/health
```

**예상 결과**:
```json
{
  "status": "UP",
  "components": {
    "db": {
      "status": "UP"  ⭐
    },
    "diskSpace": {
      "status": "UP"
    },
    "ping": {
      "status": "UP"
    }
  }
}
```

**✅ 확인사항**:
```
✓ HTTP 200 응답
✓ "status": "UP"
✓ "db": {"status": "UP"} ⭐ MySQL 연결 성공!
```

### Test 2: 로드 밸런싱 확인 ⭐

**10번 연속 요청**:
```bash
for i in {1..10}; do
  echo "Request $i:"
  curl -s http://${ALB_DNS}/actuator/health | jq -r '.status'
  sleep 1
done
```

**예상 결과**:
```
Request 1: UP
Request 2: UP
Request 3: UP
...
Request 10: UP
```

**인스턴스별 로그 확인**:
```bash
# 인스턴스 1 SSH
ssh -i key.pem ec2-user@[Instance-1-Public-IP]
sudo docker logs -f feedback-api

# 새 터미널, 인스턴스 2 SSH
ssh -i key.pem ec2-user@[Instance-2-Public-IP]
sudo docker logs -f feedback-api

# 원래 터미널에서 요청
for i in {1..20}; do
  curl http://${ALB_DNS}/actuator/health > /dev/null
  sleep 1
done
```

**✅ 확인사항**:
```
✓ 두 인스턴스 모두 요청 로그 보임 (로드밸런싱 동작!)
✓ 대략 50:50 분배
```

### Test 3: 피드백 생성 및 조회 (MySQL 연결) ⭐⭐⭐

**피드백 생성**:
```bash
curl -X POST http://${ALB_DNS}/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "content": "ALB + ASG + MySQL 테스트!",
    "author": "통합테스터"
  }'
```

**예상 결과**:
```json
{
  "id": 1,
  "content": "ALB + ASG + MySQL 테스트!",
  "author": "통합테스터",
  "createdAt": "2025-11-18T12:34:56"
}
```

**피드백 조회**:
```bash
curl http://${ALB_DNS}/api/feedbacks
```

**예상 결과**:
```json
[
  {
    "id": 1,
    "content": "ALB + ASG + MySQL 테스트!",
    "author": "통합테스터",
    "createdAt": "2025-11-18T12:34:56"
  }
]
```

**MySQL에서 직접 확인**:
```bash
# MySQL 서버 SSH
ssh -i key.pem ec2-user@[MySQL-Public-IP]

mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb

mysql> SELECT * FROM feedbacks;
```

**예상 결과**:
```
+----+---------------------------+---------------+---------------------+
| id | content                   | author        | created_at          |
+----+---------------------------+---------------+---------------------+
|  1 | ALB + ASG + MySQL 테스트! | 통합테스터    | 2025-11-18 12:34:56 |
+----+---------------------------+---------------+---------------------+
```

**✅ 확인사항**:
```
✓ 피드백 생성 성공
✓ 피드백 조회 성공
✓ MySQL에 데이터 저장 확인
✓ 두 App 인스턴스 모두 동일한 MySQL 데이터 조회
```

### Test 4: 여러 요청으로 데이터 확인

**10개 피드백 생성**:
```bash
for i in {1..10}; do
  curl -X POST http://${ALB_DNS}/api/feedbacks \
    -H "Content-Type: application/json" \
    -d "{
      \"content\": \"피드백 번호 $i\",
      \"author\": \"사용자$i\"
    }"
  echo ""
  sleep 1
done
```

**조회**:
```bash
curl http://${ALB_DNS}/api/feedbacks | jq
```

**✅ 확인사항**:
```
✓ 10개 피드백 모두 조회됨
✓ ALB를 통해 요청해도 모두 동일한 데이터
✓ MySQL Single Point 정상 동작
```

### Test 5: Auto Scaling 테스트 (Optional)

**CPU 부하 생성**:
```bash
# 인스턴스 1개 SSH
ssh -i key.pem ec2-user@[Instance-Public-IP]

# stress 설치
sudo dnf install -y stress

# CPU 100% 부하 (5분)
stress --cpu 4 --timeout 300
```

**CloudWatch 확인**:
```
EC2 → Auto Scaling Groups → feedback-asg
  → Monitoring 탭

CPUUtilization 그래프:
  → 70% 넘으면 Scale Out 트리거
  → 5분 후 Desired: 2 → 3

Instance management 탭:
  → 새 인스턴스 추가 확인
```

**✅ 확인사항**:
```
✓ CPU 70% 초과
✓ 5분 후 새 인스턴스 시작
✓ Desired capacity: 2 → 3
✓ 새 인스턴스도 healthy
✓ Target Group에 자동 등록
```

---

## 🎉 구축 완료 체크리스트

### Phase 1: 네트워크
```
□ VPC 생성 (feedback-vpc)
□ Internet Gateway 연결
□ Public Subnet × 2 (AZ-A, AZ-C)
□ Route Table 설정 (0.0.0.0/0 → IGW)
□ Auto-assign public IP 활성화
```

### Phase 2: Security Groups
```
□ alb-sg 생성 (80 from 0.0.0.0/0)
□ app-sg 생성 (8080 from alb-sg)
□ db-sg 생성 (3306 from app-sg)
□ Security Group 체인 확인
```

### Phase 3: MySQL
```
□ MySQL EC2 시작 (Public-AZ-A)
□ MySQL 8.0 설치 완료
□ feedbackdb 데이터베이스 생성
□ feedbackuser 사용자 생성
□ Private IP 확인 및 기록 ⭐
□ 외부 연결 테스트 성공
```

### Phase 4: Application
```
□ application-prod.yml 생성 (MySQL IP 수정)
□ build.gradle MySQL 의존성 확인
□ 로컬 빌드 성공
□ Docker 이미지 빌드
□ GHCR 푸시 성공
□ 로컬 Docker MySQL 연결 테스트 성공 ⭐
```

### Phase 5: Launch Template
```
□ User Data 스크립트 작성 (MySQL IP 수정)
□ Launch Template 생성
□ 테스트 인스턴스 시작
□ User Data 로그 확인
□ Docker 컨테이너 실행 확인
□ Health check UP 확인
□ MySQL 연결 확인 ⭐
□ 테스트 인스턴스 종료
```

### Phase 6: ALB
```
□ Target Group 생성 (Port 8080, Path /actuator/health)
□ ALB 생성 (2 AZ, alb-sg)
□ ALB State: active
□ ALB DNS 기록
```

### Phase 7: ASG
```
□ Auto Scaling Group 생성
□ Desired: 2, Min: 1, Max: 3
□ Subnets: Public-AZ-A, Public-AZ-C
□ Target Group 연결
□ 인스턴스 2개 시작 확인
□ Instance management: InService
□ Target Group: healthy × 2 ⭐
```

### Phase 8: 통합 테스트
```
□ ALB 헬스 체크 성공
□ db status UP 확인 ⭐
□ 로드 밸런싱 동작 확인
□ 피드백 생성 성공
□ 피드백 조회 성공
□ MySQL 데이터 확인 ⭐
□ 두 인스턴스 모두 동일한 데이터 조회
□ Auto Scaling 동작 확인 (Optional)
```

---

## 🎯 핵심 주의사항 요약

### 1. MySQL Private IP ⭐⭐⭐ 가장 중요!

```
MySQL Private IP를 정확히 확인하고:
  1. application-prod.yml
  2. Launch Template User Data

두 곳에 동일하게 설정!

확인 방법:
  EC2 → Instances → mysql-server
    → Networking 탭 → Private IPv4: 10.0.1.X
```

### 2. Security Group 체인

```
alb-sg (80 from 0.0.0.0/0)
  ↓
app-sg (8080 from alb-sg) ⭐ IP 아님!
  ↓
db-sg (3306 from app-sg) ⭐ IP 아님!

Security Group ID로 참조!
```

### 3. ALB 2개 AZ 필수

```
ALB Network mapping:
  ☑ ap-northeast-2a → Public-AZ-A
  ☑ ap-northeast-2c → Public-AZ-C

1개만 선택하면 생성 불가!
```

### 4. Target Group Port 8080

```
Target Group:
  Port: 8080 ⭐ (80 아님!)
  Path: /actuator/health ⭐ (정확히!)

Spring Boot는 8080 포트!
```

### 5. ASG Subnet 설정

```
Auto Scaling Group:
  Subnets:
    ☑ Public-AZ-A
    ☑ Public-AZ-C

두 개 모두 선택!
→ AZ 균등 분산
```

### 6. Health Check Grace Period

```
ASG Health checks:
  Grace period: 300 seconds ⭐

User Data 실행 시간 필요:
  - Docker 설치: 1분
  - 이미지 pull: 2분
  - 컨테이너 시작: 1분
  - Health check: 1분
  → 총 5분
```

### 7. User Data는 한 번만 실행

```
User Data는 인스턴스 첫 시작 시에만 실행!

재시작 시 실행 안됨!
→ 테스트는 새 인스턴스 시작으로!
```

---

## 🆘 트러블슈팅 가이드

### 문제 1: Target unhealthy

**증상**:
```
Target Groups → Targets: unhealthy
Health check failed
```

**해결**:
```bash
# 1. 인스턴스 SSH 접속
ssh -i key.pem ec2-user@[Instance-Public-IP]

# 2. Docker 상태 확인
sudo docker ps
# → feedback-api 실행 중인지

# 3. 로그 확인
sudo docker logs feedback-api
# → 에러 로그 확인

# 4. 헬스 체크 직접 테스트
curl http://localhost:8080/actuator/health
# → {"status":"UP"} 응답하는지

# 5. DB 연결 확인
curl http://localhost:8080/actuator/health | jq '.components.db'
# → "status": "UP" 인지
```

**원인별 해결**:
```
원인 1: MySQL IP 오류
  → User Data에서 MYSQL_HOST 확인
  → application-prod.yml IP 확인

원인 2: Security Group
  → app-sg: 8080 from alb-sg 확인
  → db-sg: 3306 from app-sg 확인

원인 3: Docker 이미지 문제
  → ghcr.io/johnhuh619/simple-api:latest 존재 확인
  → 로컬에서 docker pull 테스트

원인 4: MySQL 연결 실패
  → MySQL 서버 실행 확인
  → 3306 포트 열려있는지 확인
  → feedbackuser 권한 확인
```

### 문제 2: ASG 인스턴스 시작 실패

**증상**:
```
Activity: Failed
Instance failed to launch
```

**해결**:
```
# 1. Activity 탭에서 에러 메시지 확인

# 2. Launch Template 확인
  - AMI 올바른지
  - Security Group 선택되었는지
  - User Data 문법 오류 없는지

# 3. 수동 테스트
  Launch Templates → feedback-app-template
    → Actions → Launch instance from template
    → Subnet: Public-AZ-A
    → Launch

  → 수동으로 시작되는지 확인
```

### 문제 3: 로드 밸런싱 안됨

**증상**:
```
요청이 한 인스턴스로만 감
```

**해결**:
```
# 1. Target Group 확인
  Targets 탭:
    - 두 인스턴스 모두 healthy인지
    - Port가 8080인지

# 2. ALB Listener 확인
  ALB → Listeners 탭:
    - HTTP:80 → feedback-tg 연결 확인

# 3. ALB Access Logs (Optional)
  ALB → Attributes → Edit
    - Access logs 활성화
    - S3 버킷 확인
```

### 문제 4: MySQL 연결 실패

**증상**:
```
Application log: Can't connect to MySQL
```

**해결**:
```bash
# 1. MySQL 서버 확인
ssh -i key.pem ec2-user@[MySQL-Public-IP]

sudo systemctl status mysqld
# → Active: active (running)

sudo netstat -tlnp | grep 3306
# → tcp 0.0.0.0:3306 LISTEN

# 2. bind-address 확인
sudo cat /etc/my.cnf | grep bind-address
# → bind-address = 0.0.0.0

# 3. 사용자 권한 확인
mysql -u root -p'MyRootPass123!'

SELECT user, host FROM mysql.user WHERE user='feedbackuser';
# → feedbackuser | %

SHOW GRANTS FOR 'feedbackuser'@'%';
# → GRANT ALL PRIVILEGES ON feedbackdb.*

# 4. App 인스턴스에서 연결 테스트
mysql -h 10.0.1.234 -u feedbackuser -p'FeedbackPass123!' feedbackdb
# → 연결 성공해야 함
```

---

## 🎓 최종 정리

### 구축 완료 상태

```
Internet
  ↓
Internet Gateway
  ↓
ALB (feedback-alb-xxxxx.elb.amazonaws.com)
  ├─→ App Instance #1 (10.0.1.10) AZ-A
  └─→ App Instance #2 (10.0.2.20) AZ-C
       │           │
       └─────┬─────┘ (VPC 내부 통신)
             ↓
        MySQL (10.0.1.234) AZ-A

✅ 로드 밸런싱 동작
✅ Auto Scaling 설정
✅ MySQL 단일 연결
✅ 무중단 배포 준비 (Instance Refresh)
```

### 총 소요 시간

```
Phase 1: 네트워크       30분
Phase 2: Security Groups 30분
Phase 3: MySQL          40분
Phase 4: Application    40분
Phase 5: Launch Template 30분
Phase 6: ALB            80분
Phase 7: ASG            60분
Phase 8: 테스트         40분

총: 약 6시간 (실제 7-8시간 소요 가능)
```

---

## 🔄 Phase 9: GitHub Actions CI/CD 설정 (30분)

### Step 9-1: AWS Credentials 설정

**IAM User 생성** (AWS Console):
```
IAM → Users → Create user

User name: github-actions-deploy
☑ Provide user access to AWS Management Console (Optional)

[Next]

Permissions:
  ○ Attach policies directly

  Filter policies:
    ☑ AmazonEC2FullAccess
    ☑ ElasticLoadBalancingFullAccess
    ☑ AutoScalingFullAccess

[Next] → [Create user]
```

**Access Key 생성**:
```
IAM → Users → github-actions-deploy
  → Security credentials 탭
  → Access keys → Create access key

Use case:
  ○ Command Line Interface (CLI)

[Next]

Access key created:
  Access key ID: AKIA...
  Secret access key: xxxxx...

→ 둘 다 복사! (다시 볼 수 없음!)
```

**✅ 검증**:
```
✓ Access key ID 복사
✓ Secret access key 복사
✓ IAM User에 3개 정책 연결 확인
```

### Step 9-2: GitHub Secrets 설정

```
GitHub Repository → Settings → Secrets and variables → Actions

[New repository secret]

Name: AWS_ACCESS_KEY_ID
Secret: AKIA... (위에서 복사한 값)

[Add secret]

[New repository secret]

Name: AWS_SECRET_ACCESS_KEY
Secret: xxxxx... (위에서 복사한 값)

[Add secret]
```

**✅ 검증**:
```
Actions secrets:
  ✓ AWS_ACCESS_KEY_ID
  ✓ AWS_SECRET_ACCESS_KEY
```

### Step 9-3: Repository 설정 확인

**Public Repository 확인** (간단한 방법):
```
GitHub Repository → Settings → General

Danger Zone:
  Change repository visibility
    → Public 확인

→ Public이면 GHCR 인증 불필요!
```

**또는 GHCR Token 설정** (Private Repository):
```
GitHub → Profile → Settings → Developer settings
  → Personal access tokens → Tokens (classic)
  → Generate new token

Scopes:
  ☑ write:packages
  ☑ read:packages

[Generate token]

→ Token 복사: ghp_xxxxx

GitHub Repository → Settings → Secrets and variables → Actions
  → New repository secret

Name: GHCR_TOKEN
Secret: ghp_xxxxx

[Add secret]
```

### Step 9-4: 워크플로우 파일 확인

**deploy-asg.yml 확인**:
```bash
# 로컬에서
cat .github/workflows/deploy-asg.yml

# 주요 설정 확인:
# - IMAGE_NAME: johnhuh619/simple-api
# - Launch template name: feedback-app-template
# - ASG name: feedback-asg
# - ALB name: feedback-alb
```

**✅ 검증**:
```
✓ .github/workflows/deploy-asg.yml 존재
✓ .github/workflows/rollback-asg.yml 존재
✓ 파일 내 리소스 이름 확인
```

### Step 9-5: 코드 커밋 및 푸시

```bash
# 로컬 터미널
cd C:/2025proj/simple-api

# 변경사항 확인
git status

# 스테이징
git add .

# 커밋
git commit -m "feat: Add ASG infrastructure support

- Add application-prod.yml for MySQL connection
- Update build.gradle with MySQL dependency
- Add deploy-asg.yml workflow for Auto Scaling Group
- Add rollback-asg.yml workflow for rollback
- Add comprehensive implementation guides

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

# 푸시
git push origin convert
```

**✅ 검증**:
```
GitHub Repository → Code 탭:
  ✓ 최신 커밋 확인
  ✓ application-prod.yml 존재
  ✓ .github/workflows/deploy-asg.yml 존재
```

---

## 🚀 Phase 10: 첫 배포 실행 (25분)

### Step 10-1: Manual Workflow 실행

```
GitHub Repository → Actions 탭

Workflows (왼쪽):
  → Deploy to ASG (Auto Scaling Group) 선택

[Run workflow] 버튼 클릭

Use workflow from:
  Branch: convert

Environment:
  production (기본값)

[Run workflow] (초록색 버튼)
```

**대기 시작**:
```
Workflow 실행 시작:
  - Queue: 대기 중
  - In progress: 실행 중
```

### Step 10-2: 배포 모니터링 (실시간)

**GitHub Actions 로그 확인**:
```
Actions 탭 → 최신 workflow 클릭

Jobs:
  build-and-deploy
    ↓
    Steps:
      ✓ Checkout code
      ✓ Set up JDK 21
      ✓ Build with Gradle
      ✓ Run tests
      ✓ Log in to GHCR
      → Tag previous image as 'previous' ⭐
      ✓ Build and push Docker image
      ✓ Configure AWS credentials
      → Get current Launch Template version
      → Create new Launch Template version ⭐
      → Start Instance Refresh ⭐
      → Wait for Instance Refresh (5-10분) ⭐
      → Verify deployment
```

**병렬로 AWS Console 확인**:
```
EC2 → Auto Scaling Groups → feedback-asg
  → Activity 탭

Activity history:
  "Starting instance refresh..."
  "Launching new EC2 instance: i-xxxxx3"
  "Terminating EC2 instance: i-xxxxx1"
  "Launching new EC2 instance: i-xxxxx4"
  "Terminating EC2 instance: i-xxxxx2"
  "Instance refresh completed successfully"
```

**Instance management 탭**:
```
진행 상황:
  Before:
    i-xxxxx1 | InService | Healthy (OLD)
    i-xxxxx2 | InService | Healthy (OLD)

  During (5분 후):
    i-xxxxx1 | InService | Healthy (OLD)
    i-xxxxx2 | InService | Healthy (OLD)
    i-xxxxx3 | Pending | - (NEW, 시작 중)

  During (10분 후):
    i-xxxxx2 | InService | Healthy (OLD)
    i-xxxxx3 | InService | Healthy (NEW) ✅
    i-xxxxx1 | Terminating (OLD 종료 중)

  After (15분):
    i-xxxxx3 | InService | Healthy (NEW) ✅
    i-xxxxx4 | InService | Healthy (NEW) ✅
```

**✅ 검증**:
```
GitHub Actions:
  ✓ All steps completed
  ✓ "Instance Refresh completed successfully"
  ✓ "Verify deployment" 성공

AWS Console:
  ✓ Activity: "Instance refresh completed"
  ✓ Instance management: 2개 InService
  ✓ Target Group: 2개 healthy
```

### Step 10-3: 배포 검증

**헬스 체크**:
```bash
# 로컬 터미널
ALB_DNS="feedback-alb-xxxxx.ap-northeast-2.elb.amazonaws.com"

curl http://${ALB_DNS}/actuator/health

# 예상 결과:
{
  "status": "UP",
  "components": {
    "db": {"status": "UP"}  ⭐
  }
}
```

**기존 데이터 확인** (Phase 8에서 생성한 데이터):
```bash
curl http://${ALB_DNS}/api/feedbacks | jq

# 예상 결과:
[
  {
    "id": 1,
    "content": "ALB + ASG + MySQL 테스트!",
    ...
  },
  ...
  {
    "id": 10,
    "content": "피드백 번호 10",
    ...
  }
]

✓ 기존 데이터 모두 유지됨! (MySQL은 그대로)
```

**새 피드백 생성 (배포 후)**:
```bash
curl -X POST http://${ALB_DNS}/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "content": "GitHub Actions 자동 배포 성공!",
    "author": "자동배포봇"
  }'

curl http://${ALB_DNS}/api/feedbacks | jq '.[] | select(.id == 11)'

# 예상 결과:
{
  "id": 11,
  "content": "GitHub Actions 자동 배포 성공!",
  "author": "자동배포봇",
  ...
}
```

**새 인스턴스 확인**:
```bash
# 새 인스턴스 중 하나에 SSH 접속
ssh -i key.pem ec2-user@[New-Instance-Public-IP]

# User Data 로그 확인
sudo tail -50 /var/log/user-data.log

# Docker 이미지 확인
sudo docker images | grep simple-api
# → ghcr.io/johnhuh619/simple-api   latest   (최신 이미지)

# 컨테이너 로그 확인
sudo docker logs --tail 50 feedback-api
```

**🎉 첫 배포 성공!**

---

## 🔙 Phase 11: 롤백 테스트 (25분)

### Step 11-1: 의도적 버그 생성 (Optional)

**간단한 코드 변경**:
```java
// src/main/java/com/jaewon/practice/simpleapi/controller/FeedbackController.java

@GetMapping
public List<Feedback> getAllFeedbacks() {
    // 의도적 에러 추가
    throw new RuntimeException("테스트 에러!");
    // return feedbackService.getAllFeedbacks();
}
```

**빌드 및 배포**:
```bash
./gradlew clean build
git add .
git commit -m "test: Add intentional error for rollback test"
git push origin convert
```

**GitHub Actions 실행**:
```
Actions → Deploy to ASG → Run workflow
```

**대기 (15분)**:
```
배포 완료 후 확인:
```

**에러 확인**:
```bash
curl http://${ALB_DNS}/api/feedbacks

# 예상 결과:
{
  "timestamp": "2025-11-18T12:34:56",
  "status": 500,
  "error": "Internal Server Error",
  "message": "테스트 에러!",
  ...
}

✓ 버그 배포 완료! (의도적)
```

### Step 11-2: 롤백 실행

**GitHub Actions 롤백 워크플로우 실행**:
```
GitHub → Actions 탭

Workflows:
  → Rollback ASG Deployment 선택

[Run workflow]

Confirm:
  rollback ⭐ (정확히 입력!)

[Run workflow]
```

**롤백 모니터링**:
```
Actions 탭 → Rollback workflow 클릭

Steps:
  ✓ Validate confirmation
  ✓ Configure AWS credentials
  → Get current Launch Template info
  → Create rollback Launch Template version ⭐
    (IMAGE_TAG="previous" 사용)
  → Set rollback version as default
  → Start Instance Refresh
  → Wait for rollback to complete (5-10분)
  → Verify rollback
```

**AWS Console 확인**:
```
Launch Templates → feedback-app-template

Versions:
  Version 1: IMAGE_TAG="latest" (초기)
  Version 2: IMAGE_TAG="latest" (첫 배포)
  Version 3: IMAGE_TAG="latest" (버그 배포)
  Version 4: IMAGE_TAG="previous" (롤백!) ⭐

Default version: 4 ✓
```

**Auto Scaling Group 확인**:
```
Activity 탭:
  "Starting instance refresh for rollback..."
  "Launching new EC2 instance: i-xxxxx5"
  "Terminating EC2 instance: i-xxxxx3"
  "Launching new EC2 instance: i-xxxxx6"
  "Terminating EC2 instance: i-xxxxx4"
  "Instance refresh completed"
```

### Step 11-3: 롤백 검증

**API 동작 확인**:
```bash
curl http://${ALB_DNS}/api/feedbacks

# 예상 결과:
[
  {"id": 1, "content": "ALB + ASG + MySQL 테스트!", ...},
  ...
  {"id": 11, "content": "GitHub Actions 자동 배포 성공!", ...}
]

✓ 에러 사라짐! 정상 동작!
```

**롤백된 인스턴스 확인**:
```bash
ssh -i key.pem ec2-user@[Rollback-Instance-Public-IP]

# Docker 이미지 확인
sudo docker images | grep simple-api
# → simple-api:previous (이전 버전!)

# User Data 로그 확인
sudo tail -50 /var/log/user-data.log
# → "IMAGE_TAG=previous"
# → "ROLLBACK MODE: Using image tag 'previous'"
```

**🎉 롤백 성공! 20분 만에 복구!**

### Step 11-4: 버그 수정 및 재배포

**코드 수정**:
```java
// FeedbackController.java
@GetMapping
public List<Feedback> getAllFeedbacks() {
    // 에러 제거
    return feedbackService.getAllFeedbacks();
}
```

**재배포**:
```bash
git add .
git commit -m "fix: Remove test error"
git push origin convert

# GitHub Actions 자동 트리거
```

**검증**:
```bash
# 배포 완료 후 (15분)
curl http://${ALB_DNS}/api/feedbacks
# → 정상 동작 ✓
```

---

## 📊 Phase 12: CloudWatch 모니터링 설정 (20분, Optional)

### Step 12-1: CloudWatch Dashboard 생성

```
CloudWatch → Dashboards → Create dashboard

Dashboard name: feedback-infrastructure

[Create dashboard]

[Add widget]

Widget type:
  ○ Line

Data source:
  ○ Metrics

[Next]

Metrics:
  All metrics 탭
    → EC2
    → By Auto Scaling Group
    → ☑ CPUUtilization (feedback-asg)

  All metrics 탭
    → ApplicationELB
    → Per AppELB Metrics
    → ☑ TargetResponseTime (feedback-alb)
    → ☑ RequestCount (feedback-alb)

[Create widget]
```

**추가 위젯**:
```
[Add widget] → Number

Metrics:
  ApplicationELB → Per Target Group Metrics
    → ☑ HealthyHostCount (feedback-tg)
    → ☑ UnHealthyHostCount (feedback-tg)

[Create widget]

[Save dashboard]
```

**✅ 검증**:
```
Dashboards → feedback-infrastructure:
  ✓ CPUUtilization 그래프
  ✓ TargetResponseTime 그래프
  ✓ RequestCount 그래프
  ✓ HealthyHostCount 숫자
```

### Step 12-2: CloudWatch Alarms 생성

**CPU 사용률 알람**:
```
CloudWatch → Alarms → Create alarm

[Select metric]
  EC2 → By Auto Scaling Group
    → feedback-asg → CPUUtilization

[Select metric]

Metric:
  Period: 5 minutes
  Statistic: Average

Conditions:
  Threshold type: Static
  Whenever CPUUtilization is: Greater
  than: 80

[Next]

Notification:
  (Optional - SNS Topic 설정)

[Next]

Alarm name: feedback-asg-high-cpu
Description: ASG CPU usage exceeds 80%

[Next]

[Create alarm]
```

**Unhealthy Host 알람**:
```
Create alarm

Metric:
  ApplicationELB → Per Target Group
    → feedback-tg → UnHealthyHostCount

Conditions:
  Whenever UnHealthyHostCount is: Greater
  than: 0

Alarm name: feedback-unhealthy-hosts
Description: Unhealthy hosts detected in target group

[Create alarm]
```

**Target Response Time 알람**:
```
Create alarm

Metric:
  ApplicationELB → Per AppELB
    → feedback-alb → TargetResponseTime

Conditions:
  Period: 1 minute
  Statistic: Average
  Whenever TargetResponseTime is: Greater
  than: 1 (초)

Alarm name: feedback-slow-response
Description: Target response time exceeds 1 second

[Create alarm]
```

**✅ 검증**:
```
Alarms 목록:
  ✓ feedback-asg-high-cpu (OK)
  ✓ feedback-unhealthy-hosts (OK)
  ✓ feedback-slow-response (OK)
```

### Step 12-3: 알람 테스트 (Optional)

**CPU 부하 생성**:
```bash
# 인스턴스 SSH 접속
ssh -i key.pem ec2-user@[Instance-Public-IP]

sudo dnf install -y stress

# CPU 100% (10분)
stress --cpu 4 --timeout 600
```

**CloudWatch 확인**:
```
Alarms → feedback-asg-high-cpu

대기 (5분 후):
  State: OK → In alarm ⚠️

알람 발동 확인! ✓
```

**부하 중단 후**:
```
Ctrl+C (stress 종료)

대기 (5분 후):
  State: In alarm → OK ✓

알람 해제 확인!
```

---

## 🎯 Phase 13: 운영 및 관리 (지속적)

### Step 13-1: 일일 체크리스트

**매일 확인**:
```
□ Target Group Health
  EC2 → Target Groups → feedback-tg
    → Targets: 모두 healthy 확인

□ CloudWatch Alarms
  CloudWatch → Alarms
    → 모두 OK 상태 확인

□ ALB Access
  curl http://[ALB-DNS]/actuator/health
    → 정상 응답 확인

□ MySQL 상태
  ssh mysql-server
  sudo systemctl status mysqld
    → Active 확인
```

### Step 13-2: 정기 백업 (Optional)

**MySQL 백업 스크립트**:
```bash
# MySQL 서버에서
cat > /home/ec2-user/backup-mysql.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/home/ec2-user/mysql-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/feedbackdb_$DATE.sql"

mkdir -p $BACKUP_DIR

mysqldump -u feedbackuser -p'FeedbackPass123!' feedbackdb > $BACKUP_FILE

# 7일 이상 된 백업 삭제
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
EOF

chmod +x /home/ec2-user/backup-mysql.sh

# 수동 백업
./backup-mysql.sh
```

**Cron 설정** (Optional):
```bash
crontab -e

# 매일 새벽 2시 백업
0 2 * * * /home/ec2-user/backup-mysql.sh >> /var/log/mysql-backup.log 2>&1
```

### Step 13-3: 로그 확인

**Application 로그**:
```bash
# 인스턴스 SSH
ssh -i key.pem ec2-user@[Instance-IP]

# 실시간 로그
sudo docker logs -f feedback-api

# 최근 100줄
sudo docker logs --tail 100 feedback-api

# 에러만 필터링
sudo docker logs feedback-api 2>&1 | grep ERROR
```

**User Data 로그**:
```bash
sudo cat /var/log/user-data.log

# 에러 확인
sudo grep -i error /var/log/user-data.log
```

**MySQL 로그**:
```bash
# MySQL 서버에서
sudo tail -f /var/log/mysqld.log

# 슬로우 쿼리 확인 (Optional)
sudo cat /var/log/mysql/slow-query.log
```

### Step 13-4: 성능 모니터링

**CloudWatch Metrics 확인**:
```
CloudWatch → Metrics → All metrics

주요 지표:
  - CPUUtilization (EC2)
    → 평균 30-50% 권장

  - TargetResponseTime (ALB)
    → 평균 < 500ms 권장

  - RequestCount (ALB)
    → 트렌드 확인

  - HealthyHostCount (Target Group)
    → 항상 Desired Capacity와 동일
```

**MySQL 성능**:
```bash
# MySQL 서버에서
mysql -u root -p'MyRootPass123!'

# 슬로우 쿼리 확인
SELECT * FROM mysql.slow_log
ORDER BY start_time DESC
LIMIT 10;

# 연결 수 확인
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Max_used_connections';

# 버퍼 풀 사용률
SHOW STATUS LIKE 'Innodb_buffer_pool%';
```

---

## 🗑️ Phase 14: 리소스 삭제 (5일 후) (30분)

### Step 14-1: 삭제 순서 (매우 중요!) ⭐

**순서를 반드시 지켜야 함!**

```
1. Auto Scaling Group (ASG)
   ↓ (인스턴스 자동 종료)
2. Application Load Balancer (ALB)
   ↓
3. Target Group
   ↓
4. Launch Template
   ↓
5. MySQL EC2 Instance
   ↓
6. Security Groups
   ↓
7. VPC (종속 리소스 자동 삭제)
```

### Step 14-2: 실제 삭제 프로세스

**1. Auto Scaling Group 삭제**:
```
EC2 → Auto Scaling Groups
  → feedback-asg 선택
  → Actions → Delete

Confirmation:
  Type "delete" to confirm

[Delete]

대기 (5분):
  - ASG 삭제
  - 관리 중인 인스턴스 모두 종료
```

**✅ 검증**:
```
EC2 → Instances:
  feedback-app-asg-instance (terminated) ✓
```

**2. Load Balancer 삭제**:
```
EC2 → Load Balancers
  → feedback-alb 선택
  → Actions → Delete load balancer

Confirmation: delete

[Delete]

대기 (2분)
```

**3. Target Group 삭제**:
```
EC2 → Target Groups
  → feedback-tg 선택
  → Actions → Delete

[Yes, delete]
```

**4. Launch Template 삭제**:
```
EC2 → Launch Templates
  → feedback-app-template 선택
  → Actions → Delete template

Confirmation: Delete

[Delete]
```

**5. MySQL EC2 종료**:
```
EC2 → Instances
  → mysql-server 선택
  → Instance state → Terminate instance

[Terminate]

대기 (2분)
```

**6. Security Groups 삭제**:
```
EC2 → Security Groups

삭제 순서 (의존성 역순):
  1. app-sg 선택 → Actions → Delete security groups
  2. alb-sg 선택 → Actions → Delete security groups
  3. db-sg 선택 → Actions → Delete security groups

각각 [Delete] 클릭
```

**⚠️ 에러 발생 시**:
```
Error: "has dependent object"

원인: 아직 사용 중인 리소스 있음

해결:
1. EC2 → Network Interfaces 확인
   → 남은 ENI 삭제
2. 5분 대기 후 재시도
```

**7. VPC 삭제**:
```
VPC → Your VPCs
  → feedback-vpc 선택
  → Actions → Delete VPC

Confirmation:
  Type "delete" to confirm

[Delete]

자동 삭제:
  - Subnets (Public-AZ-A, Public-AZ-C)
  - Route Tables (public-rt)
  - Internet Gateway (feedback-igw)
```

**✅ 최종 검증**:
```
VPC 목록:
  feedback-vpc 없음 ✓

EC2 Instances:
  모두 terminated 또는 없음 ✓

Load Balancers:
  없음 ✓

Auto Scaling Groups:
  없음 ✓
```

### Step 14-3: 비용 확인

**AWS Cost Explorer**:
```
AWS Billing → Cost Explorer

Date range: Last 7 days

Group by: Service

확인:
  - EC2: $XX
  - ELB: $XX
  - Data Transfer: $XX

총 비용: ~$12-15 (5일 기준)
```

### Step 14-4: GitHub 정리 (Optional)

**Docker 이미지 삭제**:
```
GitHub → Profile → Packages
  → simple-api
  → Package settings
  → Delete package (Optional)
```

**Branch 정리**:
```bash
# 로컬에서
git checkout main
git branch -D convert

# 원격 브랜치 삭제 (Optional)
git push origin --delete convert
```

---

## 🎓 최종 완료 체크리스트

### 구축 단계
```
□ Phase 1: VPC + 네트워크 (30분)
□ Phase 2: Security Groups (30분)
□ Phase 3: MySQL 설치 (40분)
□ Phase 4: Application 준비 (40분)
□ Phase 5: Launch Template (30분)
□ Phase 6: ALB (80분)
□ Phase 7: ASG (60분)
□ Phase 8: 통합 테스트 (40분)
□ Phase 9: GitHub Actions 설정 (30분)
□ Phase 10: 첫 배포 (25분)
□ Phase 11: 롤백 테스트 (25분)
□ Phase 12: CloudWatch 모니터링 (20분, Optional)
□ Phase 13: 운영 관리 (지속적)
□ Phase 14: 리소스 삭제 (30분)
```

### 최종 검증
```
□ ALB DNS로 접근 성공
□ 로드 밸런싱 동작 확인
□ MySQL 데이터 CRUD 동작
□ Auto Scaling 정책 동작
□ GitHub Actions 배포 성공
□ 롤백 프로세스 성공
□ CloudWatch 알람 설정 (Optional)
□ 5일 후 리소스 완전 삭제
```

### 학습 목표 달성
```
□ VPC 및 네트워크 이해
□ Security Group 체인 이해
□ ALB + ASG 동작 원리 이해
□ Launch Template 활용
□ Instance Refresh 무중단 배포
□ Docker 이미지 태그 전략 (latest/previous)
□ VPC 내부 통신 이해
□ CI/CD 파이프라인 구축
□ 롤백 전략 및 실행
□ CloudWatch 모니터링
```

---

## 📊 프로젝트 결과

### 구축된 인프라

```
Internet
  ↓
Internet Gateway
  ↓
Application Load Balancer
  ├─→ App Instance #1 (AZ-A) ⎤
  └─→ App Instance #2 (AZ-C) ⎦ Auto Scaling
       │           │
       └─────┬─────┘ VPC 내부 통신
             ↓
        MySQL (AZ-A)

CI/CD:
  GitHub Actions
    ├─ deploy-asg.yml (자동 배포)
    └─ rollback-asg.yml (롤백)

Monitoring:
  CloudWatch
    ├─ Dashboard (Metrics)
    └─ Alarms (CPU, Health, Response Time)
```

### 총 소요 시간

```
인프라 구축:  6-8시간 (Phase 1-8)
CI/CD 설정:   2시간 (Phase 9-11)
모니터링:     0.5시간 (Phase 12, Optional)
리소스 삭제:  0.5시간 (Phase 14)

총: 약 9-11시간
```

### 총 비용 (5일 기준)

```
EC2 × 3 (t3.small):     $7.50
ALB:                     $2.70
EBS (30GB):              $0.50
Data Transfer:           $1.00
CloudWatch (기본):       $0

총: 약 $11.70 (~15,000원)
```

### 달성한 목표

```
✅ 로드 밸런싱 (ALB)
✅ Auto Scaling (CPU 기반)
✅ 무중단 배포 (Instance Refresh)
✅ 롤백 메커니즘 (Docker 이미지 태그)
✅ MySQL 영구 저장소
✅ CI/CD 자동화 (GitHub Actions)
✅ 모니터링 (CloudWatch)
✅ 고가용성 (2 AZ)
✅ VPC 네트워크 보안
```

---

## 💡 추가 개선 방향 (향후)

### 1. 보안 강화
```
□ Private Subnet으로 전환
□ NAT Gateway 또는 VPC Endpoint 추가
□ WAF (Web Application Firewall) 추가
□ SSL/TLS 인증서 적용 (ACM)
□ Secrets Manager로 비밀번호 관리
```

### 2. 데이터베이스 개선
```
□ RDS Multi-AZ로 전환
□ Read Replica 추가
□ 자동 백업 설정
□ Performance Insights 활성화
```

### 3. 모니터링 강화
```
□ Prometheus + Grafana 추가
□ Application Insights (APM)
□ X-Ray 트레이싱
□ CloudWatch Logs Insights
```

### 4. CI/CD 개선
```
□ 블루-그린 배포 전환
□ 카나리 배포 전략
□ 자동 테스트 강화
□ 성능 테스트 자동화
```

### 5. Infrastructure as Code
```
□ Terraform으로 전환
□ CloudFormation Stack
□ GitOps 워크플로우
```

---

## 🎉 축하합니다!

**완전한 프로덕션급 인프라를 구축했습니다!**

이 프로젝트를 통해 다음을 경험했습니다:
- ✅ AWS 핵심 서비스 (VPC, EC2, ALB, ASG)
- ✅ 네트워크 및 보안 설계
- ✅ 컨테이너 기반 배포
- ✅ CI/CD 파이프라인
- ✅ 무중단 배포 및 롤백
- ✅ 모니터링 및 운영

**이제 실무 인프라를 구축할 준비가 되었습니다!** 🚀

---

## 📚 참고 문서

프로젝트 내 문서:
- `ARCHITECTURE_EXPLAINED.md` - 아키텍처 설명
- `FULL_ARCHITECTURE_WITH_ROLLBACK.md` - 롤백 포함 전체 구조
- `EC2_PLACEMENT_EXPLAINED.md` - EC2 배치 상세
- `PUBLIC_VS_PRIVATE_SUBNET.md` - Public vs Private 비교
- `CONTAINER_REGISTRY_COMPARISON.md` - Container Registry 비교
- `MINIMAL_INFRASTRUCTURE.md` - 최소 구성 분석

AWS 공식 문서:
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/)
- [VPC Networking](https://docs.aws.amazon.com/vpc/latest/userguide/)

---

**End of Implementation Guide** 🎯
