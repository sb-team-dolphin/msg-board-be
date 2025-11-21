# 🚀 실전 구축 가이드 (Option 1: 극초간단)

**대상**: 인프라 초급자
**목표**: 6-8시간 안에 ALB + ASG + MySQL 구축
**비용**: 5일 기준 약 $12.5
**난이도**: ⭐⭐☆☆☆ (쉬움)

---

## 📋 구축 전 체크리스트

```
□ AWS 계정 로그인 완료
□ ap-northeast-2 (서울) 리전 선택
□ 현재 GitHub repo가 Public으로 변경됨 (또는 GHCR token 준비)
□ 로컬에 Git, Docker 설치 완료
□ SSH 키페어 있음 (없으면 Step 1에서 생성)
□ 시간: 최소 3시간 연속 작업 가능
```

---

## 🗺️ 전체 흐름 (한눈에 보기)

```
Day 1 (3-4시간):
├─ [30분] Step 1: VPC + Public Subnet × 2
├─ [30분] Step 2: Security Groups × 3
├─ [20분] Step 3: MySQL EC2 설치
├─ [40분] Step 4: Application 코드 수정 + Docker 이미지 푸시
├─ [30분] Step 5: Launch Template 생성
└─ [30분] 테스트 및 휴식

Day 2 (3-4시간):
├─ [40분] Step 6: Target Group 생성
├─ [40분] Step 7: ALB 생성
├─ [60분] Step 8: Auto Scaling Group 생성
├─ [40분] Step 9: 전체 테스트
└─ [30분] 정리 및 문서화
```

---

## 📍 Day 1: 네트워크 + 데이터베이스

### ✅ Step 1: VPC + Public Subnet 생성 (30분)

#### 1-1. VPC 생성

```
AWS Console → VPC → Your VPCs → Create VPC

VPC settings:
  ○ VPC only (서브넷은 따로 만듦)

VPC settings:
  Name tag: feedback-vpc
  IPv4 CIDR block: 10.0.0.0/16
  IPv6 CIDR block: No IPv6 CIDR block
  Tenancy: Default

[Create VPC]
```

**결과 확인**:
- VPC ID: `vpc-xxxxx` (복사해두기!)
- State: Available

#### 1-2. Internet Gateway 생성 및 연결

```
VPC → Internet Gateways → Create internet gateway

Name tag: feedback-igw

[Create internet gateway]
```

생성 후 바로:
```
Actions → Attach to VPC
  Available VPCs: feedback-vpc 선택

[Attach internet gateway]
```

**결과 확인**:
- State: Attached
- VPC ID: vpc-xxxxx (위에서 만든 VPC)

#### 1-3. Public Subnet 2개 생성

**첫 번째 Subnet (AZ-A)**:
```
VPC → Subnets → Create subnet

VPC ID: feedback-vpc 선택

Subnet settings:
  Subnet name: Public-AZ-A
  Availability Zone: ap-northeast-2a
  IPv4 CIDR block: 10.0.1.0/24

[Create subnet]
```

**두 번째 Subnet (AZ-C)**:
```
Create subnet (계속)

Subnet settings:
  Subnet name: Public-AZ-C
  Availability Zone: ap-northeast-2c
  IPv4 CIDR block: 10.0.2.0/24

[Create subnet]
```

**결과 확인**:
```
✓ Public-AZ-A  |  10.0.1.0/24  |  ap-northeast-2a  |  Available IPs: 251
✓ Public-AZ-C  |  10.0.2.0/24  |  ap-northeast-2c  |  Available IPs: 251
```

#### 1-4. Public Subnet 자동 Public IP 할당 활성화

**각 Subnet에 대해 실행**:
```
Subnets → Public-AZ-A 선택 → Actions → Edit subnet settings

Auto-assign public IPv4 address:
  ☑ Enable auto-assign public IPv4 address

[Save]
```

**Public-AZ-C도 동일하게 실행**

#### 1-5. Route Table 생성 및 설정

```
VPC → Route Tables → Create route table

Name: public-rt
VPC: feedback-vpc

[Create route table]
```

**생성 후 바로**:
```
Routes 탭 → Edit routes → Add route

Destination: 0.0.0.0/0
Target: Internet Gateway → feedback-igw

[Save changes]
```

**Subnet 연결**:
```
Subnet associations 탭 → Edit subnet associations

☑ Public-AZ-A
☑ Public-AZ-C

[Save associations]
```

**결과 확인**:
```
Routes:
  10.0.0.0/16    local         (VPC 내부 통신)
  0.0.0.0/0      igw-xxxxx     (인터넷 통신)

Subnet associations:
  Public-AZ-A
  Public-AZ-C
```

---

### ✅ Step 2: Security Groups 생성 (30분)

#### 2-1. ALB Security Group

```
EC2 → Security Groups → Create security group

Basic details:
  Security group name: alb-sg
  Description: Security group for Application Load Balancer
  VPC: feedback-vpc

Inbound rules:
  [Add rule]
    Type: HTTP
    Source: 0.0.0.0/0
    Description: Allow HTTP from anywhere

  [Add rule]
    Type: HTTPS
    Source: 0.0.0.0/0
    Description: Allow HTTPS from anywhere (optional)

Outbound rules:
  (기본값 유지: All traffic to 0.0.0.0/0)

[Create security group]
```

**결과**: sg-xxxxx1 (복사!)

#### 2-2. Application Security Group

```
Create security group

Basic details:
  Security group name: app-sg
  Description: Security group for API application instances
  VPC: feedback-vpc

Inbound rules:
  [Add rule]
    Type: Custom TCP
    Port range: 8080
    Source: Custom → alb-sg 선택 (위에서 만든 SG)
    Description: Allow traffic from ALB

  [Add rule]
    Type: Custom TCP
    Port range: 9100
    Source: Custom → 0.0.0.0/0 (CloudWatch 또는 모니터링용)
    Description: Node Exporter metrics

  [Add rule]
    Type: SSH
    Source: Custom → 0.0.0.0/0 (또는 My IP)
    Description: SSH access for troubleshooting

Outbound rules:
  (기본값 유지: All traffic to 0.0.0.0/0)

[Create security group]
```

**결과**: sg-xxxxx2 (복사!)

#### 2-3. MySQL Security Group

```
Create security group

Basic details:
  Security group name: db-sg
  Description: Security group for MySQL database
  VPC: feedback-vpc

Inbound rules:
  [Add rule]
    Type: MYSQL/Aurora (3306)
    Source: Custom → app-sg 선택 (위에서 만든 Application SG)
    Description: Allow MySQL from application instances

  [Add rule]
    Type: SSH
    Source: Custom → 0.0.0.0/0 (또는 My IP)
    Description: SSH access for management

Outbound rules:
  (기본값 유지: All traffic to 0.0.0.0/0)

[Create security group]
```

**결과**: sg-xxxxx3 (복사!)

**전체 Security Group 정리**:
```
alb-sg     → 80, 443 from 0.0.0.0/0
app-sg     → 8080 from alb-sg, 9100 from 0.0.0.0/0, 22 from 0.0.0.0/0
db-sg      → 3306 from app-sg, 22 from 0.0.0.0/0
```

---

### ✅ Step 3: MySQL EC2 설치 (20분)

#### 3-1. EC2 인스턴스 시작

```
EC2 → Instances → Launch instances

Name and tags:
  Name: mysql-server

Application and OS Images:
  Amazon Linux 2023 AMI (기본 선택)

Instance type:
  t3.small (또는 t2.small)

Key pair:
  [기존 키 선택 또는 Create new key pair]

Network settings:
  [Edit]
  VPC: feedback-vpc
  Subnet: Public-AZ-A
  Auto-assign public IP: Enable
  Firewall (security groups): Select existing security group
    → db-sg 선택

Configure storage:
  Root volume: 10 GiB gp3
  [Add new volume]
    → Size: 20 GiB
    → Volume type: gp3
    → Device name: /dev/sdb

[Launch instance]
```

**인스턴스 시작 대기** (2-3분)

#### 3-2. MySQL 설치 및 설정

**로컬 터미널에서**:
```bash
# Public IP 확인 (EC2 콘솔에서)
ssh -i your-key.pem ec2-user@[MySQL-EC2-Public-IP]
```

**접속 후 한 번에 실행** (복붙 가능):
```bash
# MySQL 8.0 설치
sudo dnf update -y
sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
sudo dnf install -y mysql-community-server

# 데이터 볼륨 마운트 (/dev/nvme1n1 = 두 번째 EBS)
sudo mkfs -t xfs /dev/nvme1n1
sudo mkdir /data
sudo mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data xfs defaults,nofail 0 2' | sudo tee -a /etc/fstab

# MySQL 데이터 디렉토리
sudo mkdir -p /data/mysql
sudo chown -R mysql:mysql /data/mysql

# 설정 파일 생성
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

# MySQL 초기화 및 시작
sudo mysqld --initialize --user=mysql --datadir=/data/mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld

# 임시 비밀번호 확인
TEMP_PASS=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
echo "==================================="
echo "임시 비밀번호: $TEMP_PASS"
echo "==================================="
echo ""
echo "다음 명령으로 root 비밀번호 변경:"
echo "mysql -u root -p'$TEMP_PASS' --connect-expired-password"
```

#### 3-3. 데이터베이스 및 사용자 생성

```bash
# root 비밀번호 변경 (위에서 출력된 임시 비밀번호 사용)
mysql -u root -p --connect-expired-password
```

**MySQL 프롬프트에서**:
```sql
-- root 비밀번호 변경
ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyRootPass123!';

-- 데이터베이스 생성
CREATE DATABASE feedbackdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 애플리케이션 사용자 생성
CREATE USER 'feedbackuser'@'%' IDENTIFIED BY 'FeedbackPass123!';
GRANT ALL PRIVILEGES ON feedbackdb.* TO 'feedbackuser'@'%';
FLUSH PRIVILEGES;

-- 확인
SHOW DATABASES;
SELECT user, host FROM mysql.user WHERE user='feedbackuser';

-- 종료
EXIT;
```

#### 3-4. Private IP 확인 및 저장

```bash
# Private IP 확인 (10.0.1.X 형태)
hostname -I | awk '{print $1}'
```

**이 IP를 메모장에 복사**: `10.0.1.X` (예: 10.0.1.234)

**MySQL 설치 완료!** ✅

---

### ✅ Step 4: Application 코드 수정 (40분)

#### 4-1. 로컬 작업 디렉토리로 이동

```bash
cd C:/2025proj/simple-api
git status  # convert 브랜치 확인
```

#### 4-2. application-prod.yml 생성

```bash
# src/main/resources/ 디렉토리 확인
ls src/main/resources/
```

파일 생성:
`src/main/resources/application-prod.yml`

```yaml
spring:
  datasource:
    url: jdbc:mysql://10.0.1.X:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: feedbackuser
    password: FeedbackPass123!
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10
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
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} - %msg%n"

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always
```

**중요**: `10.0.1.X`를 위에서 메모한 MySQL Private IP로 변경!

#### 4-3. build.gradle 수정

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    // MySQL 추가
    runtimeOnly 'com.mysql:mysql-connector-j'

    // H2 주석 처리 (또는 삭제)
    // runtimeOnly 'com.h2database:h2'

    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'

    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
}
```

#### 4-4. Dockerfile 확인/수정

```dockerfile
# 현재 Dockerfile 확인
cat Dockerfile
```

**현재 Dockerfile이 이렇게 되어 있어야 함**:
```dockerfile
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY build/libs/*.jar app.jar

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**만약 SPRING_PROFILES_ACTIVE 설정이 없다면 괜찮음** (환경변수로 전달할 예정)

#### 4-5. 빌드 및 이미지 생성

```bash
# 빌드
./gradlew clean build

# 빌드 성공 확인
ls build/libs/
# → simple-api-0.0.1-SNAPSHOT.jar 있어야 함

# Docker 이미지 빌드
docker build -t ghcr.io/johnhuh619/simple-api:latest .

# 이미지 확인
docker images | grep simple-api
```

#### 4-6. GitHub Container Registry 로그인

```bash
# Personal Access Token 사용 (token은 repo:write, package:write 권한 필요)
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u johnhuh619 --password-stdin
```

**또는 GitHub repo를 Public으로 변경**:
```
GitHub → simple-api → Settings → General
  → Danger Zone → Change visibility → Make public
```

#### 4-7. 이미지 푸시

```bash
# 푸시
docker push ghcr.io/johnhuh619/simple-api:latest

# 성공 확인
# GitHub → Profile → Packages에서 simple-api 패키지 확인
```

**Application 코드 준비 완료!** ✅

---

### ✅ Step 5: Launch Template 생성 (30분)

#### 5-1. Launch Template 생성

```
EC2 → Launch Templates → Create launch template

Launch template name and description:
  Launch template name: feedback-app-template
  Template version description: Initial version with MySQL
  ☑ Provide guidance to help me set up a template that I can use with EC2 Auto Scaling

Application and OS Images (AMI):
  Amazon Linux 2023 AMI (기본값)

Instance type:
  t3.small (또는 t2.small)

Key pair:
  [기존 키 선택]

Network settings:
  Subnet: Don't include in launch template (ASG에서 지정할 예정)
  Firewall (security groups): Select existing security group
    → app-sg 선택

Storage (volumes):
  Volume 1 (Root):
    Size: 10 GiB
    Volume type: gp3
    Delete on termination: Yes

Resource tags:
  [Add tag]
    Key: Name
    Value: feedback-app-instance

Advanced details:
  [Expand]

  IAM instance profile: (없으면 비워두기)

  User data: (아래 스크립트 복붙)
```

#### 5-2. User Data 스크립트

```bash
#!/bin/bash

# 변수 설정
IMAGE_TAG="latest"
MYSQL_HOST="10.0.1.X"  # ← 여기에 MySQL Private IP 입력!
MYSQL_DATABASE="feedbackdb"
MYSQL_USER="feedbackuser"
MYSQL_PASSWORD="FeedbackPass123!"

# 로그 파일
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "========================================="
echo "User Data Script Started: $(date)"
echo "========================================="

# Docker 설치
echo "[1/4] Installing Docker..."
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Node Exporter 설치 (모니터링용 - Optional)
echo "[2/4] Installing Node Exporter..."
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.6.1.linux-amd64.tar.gz
sudo mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

# Node Exporter systemd 서비스
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# Application Docker 이미지 pull
echo "[3/4] Pulling Docker image..."
sudo docker pull ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

# Application 실행
echo "[4/4] Starting application container..."
sudo docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://${MYSQL_HOST}:3306/${MYSQL_DATABASE}?useSSL=false&serverTimezone=Asia/Seoul \
  -e SPRING_DATASOURCE_USERNAME=${MYSQL_USER} \
  -e SPRING_DATASOURCE_PASSWORD=${MYSQL_PASSWORD} \
  ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

# 헬스체크 대기
echo "Waiting for application to be ready..."
for i in {1..30}; do
  if curl -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo "✅ Application is healthy!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 10
done

echo "========================================="
echo "User Data Script Completed: $(date)"
echo "========================================="
```

**중요**: `MYSQL_HOST="10.0.1.X"` 부분을 실제 MySQL Private IP로 변경!

```
[Create launch template]
```

**Launch Template 생성 완료!** ✅

---

### ✅ Day 1 완료 체크

```
□ VPC 생성 (feedback-vpc)
□ Public Subnet × 2 (AZ-A, AZ-C)
□ Internet Gateway 연결
□ Route Table 설정
□ Security Groups × 3 (alb-sg, app-sg, db-sg)
□ MySQL EC2 실행 중 (feedbackdb 생성 완료)
□ Application 코드 MySQL 연결 설정 완료
□ Docker 이미지 빌드 및 푸시 완료
□ Launch Template 생성 완료
```

**Day 1 소요 시간**: 약 3-4시간

**휴식 또는 사전 테스트**: Launch Template이 제대로 작동하는지 테스트용 인스턴스 1개 수동 시작해보기 (Optional)

---

## 📍 Day 2: Load Balancer + Auto Scaling

### ✅ Step 6: Target Group 생성 (40분)

#### 6-1. Target Group 생성

```
EC2 → Target Groups → Create target group

Choose a target type:
  ○ Instances

Target group name: feedback-tg

Protocol: HTTP
Port: 8080
VPC: feedback-vpc

Protocol version: HTTP1

Health checks:
  Health check protocol: HTTP
  Health check path: /actuator/health

Advanced health check settings:
  Port: Traffic port
  Healthy threshold: 2
  Unhealthy threshold: 2
  Timeout: 5 seconds
  Interval: 30 seconds
  Success codes: 200

[Next]
```

#### 6-2. Register targets (지금은 스킵)

```
Available instances:
  (아직 ASG로 만든 인스턴스가 없으므로 비워둠)

[Create target group]
```

**Target Group 생성 완료!** ✅

---

### ✅ Step 7: Application Load Balancer 생성 (40분)

#### 7-1. ALB 생성

```
EC2 → Load Balancers → Create load balancer

Load balancer types:
  [Create] Application Load Balancer

Basic configuration:
  Load balancer name: feedback-alb
  Scheme: ○ Internet-facing
  IP address type: ○ IPv4

Network mapping:
  VPC: feedback-vpc

  Mappings:
    ☑ ap-northeast-2a → Public-AZ-A
    ☑ ap-northeast-2c → Public-AZ-C

Security groups:
  [Remove default]
  ☑ alb-sg

Listeners and routing:
  Protocol: HTTP
  Port: 80
  Default action: Forward to → feedback-tg (위에서 만든 Target Group)

[Create load balancer]
```

**ALB 생성 대기** (2-3분)

#### 7-2. ALB DNS 이름 확인

```
Load Balancers → feedback-alb 선택

Description 탭:
  DNS name: feedback-alb-xxxxxxxxx.ap-northeast-2.elb.amazonaws.com
```

**이 DNS 이름 복사해두기!**

**Application Load Balancer 생성 완료!** ✅

---

### ✅ Step 8: Auto Scaling Group 생성 (60분)

#### 8-1. Auto Scaling Group 생성

```
EC2 → Auto Scaling Groups → Create Auto Scaling group

Step 1: Choose launch template:
  Auto Scaling group name: feedback-asg

  Launch template:
    ☑ feedback-app-template (위에서 만든 Launch Template)
    Version: Latest

  [Next]

Step 2: Choose instance launch options:
  Network:
    VPC: feedback-vpc

    Availability Zones and subnets:
      ☑ Public-AZ-A | 10.0.1.0/24
      ☑ Public-AZ-C | 10.0.2.0/24

  [Next]

Step 3: Configure advanced options:
  Load balancing:
    ☑ Attach to an existing load balancer

    Choose from your load balancer target groups:
      ☑ feedback-tg

  Health checks:
    ☑ Turn on Elastic Load Balancing health checks
    Health check grace period: 300 seconds

  [Next]

Step 4: Configure group size and scaling:
  Group size:
    Desired capacity: 2
    Minimum capacity: 1
    Maximum capacity: 3

  Scaling policies:
    ○ Target tracking scaling policy

    Scaling policy name: cpu-scaling-policy
    Metric type: Average CPU utilization
    Target value: 70
    Instances need: 300 seconds warm up

  [Next]

Step 5: Add notifications:
  (Skip)
  [Next]

Step 6: Add tags:
  [Add tag]
    Key: Name
    Value: feedback-app-asg-instance

  [Next]

Step 7: Review:
  [Create Auto Scaling group]
```

#### 8-2. ASG 인스턴스 시작 확인

```
EC2 → Auto Scaling Groups → feedback-asg

Activity 탭:
  Status: Successful (또는 InProgress)
  Description: Launching a new EC2 instance...
```

**대기 시간**: 약 5분 (User Data 스크립트 실행 포함)

#### 8-3. 인스턴스 상태 확인

```
EC2 → Instances

Name                           | State   | Status Check
-------------------------------|---------|---------------
feedback-app-asg-instance      | Running | 2/2 checks passed
feedback-app-asg-instance      | Running | 2/2 checks passed
mysql-server                   | Running | 2/2 checks passed
```

**2개 인스턴스 Running 확인!**

#### 8-4. Target Group 헬스 체크 확인

```
EC2 → Target Groups → feedback-tg

Targets 탭:
  Instance ID         | Port | Health status
  --------------------|------|---------------
  i-xxxxx1            | 8080 | healthy
  i-xxxxx2            | 8080 | healthy
```

**모두 healthy 상태 대기** (최대 2-3분)

**Auto Scaling Group 생성 완료!** ✅

---

### ✅ Step 9: 전체 테스트 (40분)

#### 9-1. ALB를 통한 접근 테스트

```bash
# 로컬 터미널에서
ALB_DNS="feedback-alb-xxxxxxxxx.ap-northeast-2.elb.amazonaws.com"

# Health check
curl http://${ALB_DNS}/actuator/health

# 예상 결과:
# {"status":"UP"}
```

#### 9-2. 피드백 생성 테스트

```bash
# POST 요청
curl -X POST http://${ALB_DNS}/api/feedbacks \
  -H "Content-Type: application/json" \
  -d '{
    "content": "ALB + ASG 테스트 피드백!",
    "author": "테스터"
  }'

# 예상 결과:
# {"id":1,"content":"ALB + ASG 테스트 피드백!","author":"테스터","createdAt":"2025-11-18T..."}
```

#### 9-3. 피드백 조회 테스트

```bash
# GET 요청
curl http://${ALB_DNS}/api/feedbacks

# 예상 결과:
# [{"id":1,"content":"ALB + ASG 테스트 피드백!","author":"테스터","createdAt":"..."}]
```

#### 9-4. 로드 밸런싱 확인

```bash
# 여러 번 요청하면서 로그 확인
for i in {1..10}; do
  curl -s http://${ALB_DNS}/actuator/health | jq .
  sleep 1
done
```

**각 인스턴스 로그 확인**:
```bash
# 인스턴스 1에 SSH 접속
ssh -i your-key.pem ec2-user@[Instance-1-Public-IP]
sudo docker logs -f feedback-api

# 새 터미널에서 인스턴스 2 접속
ssh -i your-key.pem ec2-user@[Instance-2-Public-IP]
sudo docker logs -f feedback-api
```

**두 인스턴스 모두 요청을 받는지 확인!**

#### 9-5. Auto Scaling 테스트 (Optional)

**CPU 부하 생성**:
```bash
# 인스턴스 1개에 접속
ssh -i your-key.pem ec2-user@[Instance-Public-IP]

# CPU 부하 도구 설치
sudo dnf install -y stress

# CPU 100% 부하 (2분간)
stress --cpu 4 --timeout 120s
```

**CloudWatch에서 확인**:
```
EC2 → Auto Scaling Groups → feedback-asg → Monitoring 탭

CPUUtilization 그래프 확인
  → 70% 넘으면 새 인스턴스 추가됨 (약 5분 소요)
```

#### 9-6. MySQL 데이터 확인

```bash
# MySQL 서버 접속
ssh -i your-key.pem ec2-user@[MySQL-Public-IP]

# MySQL 로그인
mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb

# 데이터 확인
SELECT * FROM feedbacks;
# +----+---------------------------+-----------+---------------------+
# | id | content                   | author    | created_at          |
# +----+---------------------------+-----------+---------------------+
# |  1 | ALB + ASG 테스트 피드백! | 테스터    | 2025-11-18 12:34:56 |
# +----+---------------------------+-----------+---------------------+

EXIT;
```

---

### ✅ Day 2 완료 체크

```
□ Target Group 생성 (feedback-tg)
□ Application Load Balancer 생성 (feedback-alb)
□ Auto Scaling Group 생성 (feedback-asg)
□ 인스턴스 2개 자동 시작 확인
□ Target Group 헬스 체크 healthy 확인
□ ALB DNS로 API 접근 성공
□ 피드백 생성/조회 성공
□ 로드 밸런싱 동작 확인
□ MySQL 데이터 저장 확인
```

**Day 2 소요 시간**: 약 3-4시간

---

## 🎉 구축 완료!

### 📊 최종 인프라 구성

```
Internet
   ↓
Internet Gateway (feedback-igw)
   ↓
Application Load Balancer (feedback-alb)
   ├─ Public-AZ-A (10.0.1.0/24)
   └─ Public-AZ-C (10.0.2.0/24)
   ↓
Auto Scaling Group (feedback-asg)
   ├─ Instance 1 (feedback-api:8080)
   └─ Instance 2 (feedback-api:8080)
   ↓
MySQL Server (10.0.1.X:3306)
```

### 💰 예상 비용 (5일 기준)

```
ALB:              $0.0225/시간 × 120시간 = $2.70
EC2 × 2 (t3.small): $0.0208/시간 × 2 × 120 = $4.99
MySQL (t3.small):   $0.0208/시간 × 120 = $2.50
EBS (30 GiB):       $0.10/GiB/월 × 30 ÷ 6 = $0.50
Data transfer:      $1.00 (예상)

총계: 약 $11.69 (≈ 15,000원)
```

### 🔧 다음 단계 (Optional)

#### 1. GitHub Actions CI/CD 수정

현재 워크플로우는 단일 EC2 기반이므로, ASG + Launch Template 기반으로 수정 필요:

**새 배포 전략**:
1. Docker 이미지 빌드 및 푸시 (현재와 동일)
2. `latest` → `previous` 태그 변경
3. 새 이미지에 `latest` 태그
4. Launch Template 새 버전 생성 (IMAGE_TAG="latest")
5. ASG Instance Refresh 트리거

#### 2. CloudWatch 모니터링 추가

**기본 메트릭**:
- CPUUtilization
- NetworkIn/Out
- TargetResponseTime (ALB)
- HealthyHostCount (Target Group)

**알람 설정**:
- CPU > 80% (2분 이상)
- UnhealthyHostCount > 0
- TargetResponseTime > 1초

#### 3. 롤백 프로세스 준비

**롤백 시나리오**:
1. 새 버전 배포 후 문제 발견
2. Launch Template Version 2 생성 (IMAGE_TAG="previous")
3. ASG 기본 버전 변경 → Version 2
4. Instance Refresh 시작
5. 5-10분 내 이전 버전으로 복구

---

## 🐛 트러블슈팅

### 문제 1: Target Group에서 unhealthy

**증상**:
```
Health status: unhealthy
Health check failed
```

**원인**:
- Application이 8080 포트로 시작 안됨
- `/actuator/health` 경로 없음
- Security Group에서 8080 포트 막힘

**해결**:
```bash
# 1. 인스턴스 SSH 접속
ssh -i your-key.pem ec2-user@[Instance-Public-IP]

# 2. Docker 컨테이너 상태 확인
sudo docker ps -a

# 3. 로그 확인
sudo docker logs feedback-api

# 4. 포트 확인
sudo netstat -tlnp | grep 8080

# 5. 헬스체크 직접 테스트
curl http://localhost:8080/actuator/health

# 6. User Data 로그 확인
sudo cat /var/log/user-data.log
```

### 문제 2: ASG 인스턴스가 시작 안됨

**증상**:
```
Activity history: Failed - Instance failed to launch
```

**원인**:
- Launch Template 설정 오류
- AMI 없음
- Subnet 설정 오류

**해결**:
```
1. Launch Template 확인:
   - AMI ID 올바른지
   - Security Group 선택되었는지
   - User Data 문법 오류 없는지

2. ASG 설정 확인:
   - Subnet이 올바른 VPC에 있는지
   - Desired capacity > 0인지

3. 수동 테스트:
   EC2 → Launch Templates → feedback-app-template
   → Actions → Launch instance from template
   → 수동으로 인스턴스 시작해보기
```

### 문제 3: MySQL 연결 실패

**증상**:
```
docker logs: Cannot connect to MySQL server
```

**원인**:
- MySQL Private IP 잘못됨
- Security Group db-sg에서 3306 포트 안열림
- MySQL 서버 죽음

**해결**:
```bash
# 1. MySQL 서버 확인
ssh -i your-key.pem ec2-user@[MySQL-Public-IP]
sudo systemctl status mysqld

# 2. MySQL 포트 확인
sudo netstat -tlnp | grep 3306

# 3. 외부 연결 테스트 (Application 인스턴스에서)
mysql -h 10.0.1.X -u feedbackuser -p'FeedbackPass123!' feedbackdb

# 4. Security Group 확인
EC2 → Security Groups → db-sg
  Inbound rules: 3306 from app-sg 있는지 확인
```

### 문제 4: ALB DNS로 접근 안됨

**증상**:
```
curl: Could not resolve host
```

**원인**:
- ALB가 아직 프로비저닝 중
- Security Group alb-sg에서 80 포트 안열림
- Target Group에 healthy target 없음

**해결**:
```
1. ALB 상태 확인:
   Load Balancers → feedback-alb
   State: active (provisioning이면 대기)

2. Target Health 확인:
   Target Groups → feedback-tg → Targets 탭
   최소 1개 healthy 있어야 함

3. Security Group 확인:
   alb-sg: 80 from 0.0.0.0/0 있는지
   app-sg: 8080 from alb-sg 있는지

4. Listener 확인:
   ALB → Listeners 탭
   HTTP:80 → feedback-tg 연결되어 있는지
```

---

## 📚 참고 자료

### 관련 문서
- `ARCHITECTURE_EXPLAINED.md`: 전체 아키텍처 설명
- `REVISED_15HOUR_PLAN.md`: 시간별 계획
- `ROLLBACK_IN_ASG.md`: 롤백 전략
- `LAUNCH_TEMPLATE_EXPLAINED.md`: Launch Template 개념

### AWS 공식 문서
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/)
- [Launch Templates](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-templates.html)

---

## ✅ 최종 체크리스트

```
□ VPC + Subnets + IGW 구성 완료
□ Security Groups 3개 생성 완료
□ MySQL 서버 실행 중 (feedbackdb 준비됨)
□ Application 이미지 GHCR에 푸시됨
□ Launch Template 생성 완료
□ Target Group 생성 완료
□ Application Load Balancer 생성 완료
□ Auto Scaling Group 생성 완료
□ 인스턴스 2개 healthy 상태
□ ALB DNS로 API 접근 성공
□ 피드백 생성/조회 동작 확인
□ 로드 밸런싱 동작 확인
□ MySQL 데이터 저장 확인
□ 총 소요 시간: 6-8시간
□ 총 비용: ~$12 (5일 기준)
```

---

## 🎯 축하합니다!

**ALB + Auto Scaling + MySQL 인프라 구축 완료!** 🎉

이제 다음을 할 수 있습니다:
- ✅ 자동 부하 분산 (ALB)
- ✅ 자동 확장/축소 (ASG)
- ✅ 무중단 배포 (Instance Refresh)
- ✅ 헬스체크 기반 자동 복구
- ✅ 고가용성 (2개 AZ)
- ✅ 영구 데이터 저장 (MySQL)

**5일 후 삭제 방법**:
```
1. Auto Scaling Group 삭제 (인스턴스 자동 종료됨)
2. Load Balancer 삭제
3. Target Group 삭제
4. Launch Template 삭제
5. MySQL EC2 종료
6. VPC 삭제 (NAT, IGW, Subnet 자동 삭제)
```

---

**다음 단계**: CI/CD 파이프라인 수정 또는 CloudWatch 모니터링 추가!
