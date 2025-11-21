# 🚨 3일 (15시간) 급속 구축 가이드

**제약**: 15시간, 초급자 수준
**목표**: 동작하는 프로덕션 인프라 (완벽하진 않아도 OK)
**전략**: MVP → 점진적 개선

---

## ⏱️ 시간 배분 (15시간)

```
Day 1 (5시간):
  ├─ VPC + 네트워크 기본        [1.5시간]
  ├─ MySQL 설치 및 마이그레이션 [3시간]
  └─ 검증                      [0.5시간]

Day 2 (5시간):
  ├─ ALB + Target Group        [1.5시간]
  ├─ Auto Scaling Group 기본   [2시간]
  ├─ 배포 테스트               [1시간]
  └─ 트러블슈팅                [0.5시간]

Day 3 (5시간):
  ├─ Prometheus 기본 설치      [1.5시간]
  ├─ Grafana 기본 설치         [1시간]
  ├─ 대시보드 구성             [1시간]
  ├─ 전체 통합 테스트          [1시간]
  └─ 문서화 및 정리            [0.5시간]
```

---

## 🎯 우선순위 결정

### ✅ 반드시 해야 할 것 (Critical - Day 1-2)

```
1. VPC + Subnet (최소한)          [1.5h]
2. MySQL 마이그레이션              [3h]
3. ALB                            [1.5h]
4. Auto Scaling Group (기본)      [2h]

소계: 8시간
```

### 🟡 해야 할 것 (Important - Day 3)

```
5. Prometheus (기본)              [1.5h]
6. Grafana (기본)                 [1h]
7. 대시보드                       [1h]

소계: 3.5시간
```

### ⏸️ 나중에 할 것 (나중에 개선)

```
- 복잡한 Auto Scaling 정책
- 완벽한 Security Group 세분화
- CI/CD 자동화 업데이트
- Alertmanager 설정
- SSL/TLS 인증서
- 백업 자동화 스크립트
- CloudWatch 통합
```

---

## 📅 Day 1: 네트워크 + 데이터베이스 (5시간)

### 시간표

```
09:00 - 10:30  VPC + 네트워크 기본
10:30 - 11:30  MySQL 서버 설치
11:30 - 13:00  H2 → MySQL 마이그레이션
13:00 - 13:30  검증 및 테스트
```

---

### Step 1.1: VPC 기본 구성 (1.5시간)

**목표**: 최소한의 동작하는 네트워크

#### 간소화 버전 (빠른 구축)
```
VPC: 10.0.0.0/16

Subnets:
  Public-A:  10.0.1.0/24 (ap-northeast-2a)
  Public-C:  10.0.2.0/24 (ap-northeast-2c)
  Private-A: 10.0.11.0/24 (ap-northeast-2a)

# Private-C는 생략 (시간 절약)
# Data subnet도 Private-A에 통합
```

#### AWS Console로 빠르게 (클릭 방식)

**1. VPC 생성 (5분)**
```
AWS Console → VPC → Create VPC
  Name: feedback-vpc
  IPv4 CIDR: 10.0.0.0/16
  [Create VPC]
```

**2. Subnet 생성 (10분)**
```
VPC → Subnets → Create Subnet

Subnet 1:
  Name: Public-AZ-A
  AZ: ap-northeast-2a
  CIDR: 10.0.1.0/24

Subnet 2:
  Name: Public-AZ-C
  AZ: ap-northeast-2c
  CIDR: 10.0.2.0/24

Subnet 3:
  Name: Private-AZ-A
  AZ: ap-northeast-2a
  CIDR: 10.0.11.0/24
```

**3. Internet Gateway (5분)**
```
VPC → Internet Gateways → Create

Name: feedback-igw
[Create]
[Attach to VPC] → feedback-vpc
```

**4. NAT Gateway (10분)**
```
VPC → NAT Gateways → Create

Name: feedback-nat
Subnet: Public-AZ-A
[Allocate Elastic IP]
[Create]

⚠️ 생성에 2-3분 소요 (기다리기)
```

**5. Route Tables (15분)**
```
# Public Route Table
VPC → Route Tables → Create

Name: public-rt
VPC: feedback-vpc
[Create]

Routes 탭:
  [Edit routes]
  Add: 0.0.0.0/0 → feedback-igw
  [Save]

Subnet associations 탭:
  [Edit]
  ✓ Public-AZ-A
  ✓ Public-AZ-C
  [Save]

# Private Route Table
Name: private-rt
VPC: feedback-vpc
[Create]

Routes 탭:
  [Edit routes]
  Add: 0.0.0.0/0 → feedback-nat
  [Save]

Subnet associations 탭:
  [Edit]
  ✓ Private-AZ-A
  [Save]
```

**6. Security Groups (15분)**
```
# ALB Security Group
Name: alb-sg
VPC: feedback-vpc

Inbound:
  HTTP (80)    0.0.0.0/0
  HTTPS (443)  0.0.0.0/0

Outbound:
  All traffic  0.0.0.0/0

---

# App Security Group
Name: app-sg
VPC: feedback-vpc

Inbound:
  Custom TCP (8080)  Source: alb-sg
  Custom TCP (9100)  Source: monitoring-sg
  SSH (22)           Source: [Your IP]

Outbound:
  All traffic  0.0.0.0/0

---

# DB Security Group
Name: db-sg
VPC: feedback-vpc

Inbound:
  MySQL (3306)  Source: app-sg
  SSH (22)      Source: [Your IP]

Outbound:
  All traffic  0.0.0.0/0

---

# Monitoring Security Group
Name: monitoring-sg
VPC: feedback-vpc

Inbound:
  Custom TCP (9090)  Source: [Your IP]  (Prometheus)
  Custom TCP (3000)  Source: [Your IP]  (Grafana)
  SSH (22)           Source: [Your IP]

Outbound:
  All traffic  0.0.0.0/0
```

**체크포인트**: NAT Gateway가 "Available" 상태인지 확인!

---

### Step 1.2: MySQL 서버 구축 (3시간)

#### EC2 인스턴스 시작 (15분)

```
EC2 → Launch Instance

Name: mysql-server
AMI: Amazon Linux 2023
Instance Type: t3.small
Key pair: [기존 키 또는 새로 생성]

Network settings:
  VPC: feedback-vpc
  Subnet: Private-AZ-A (10.0.11.0/24)
  Auto-assign public IP: Disable
  Security Group: db-sg

Storage:
  Root: 20 GiB gp3
  Add volume: 50 GiB gp3 (시간 절약 위해 100GB → 50GB)

Advanced:
  IAM instance profile: [생략 - 나중에 추가]

[Launch instance]
```

#### Bastion Host (임시, 빠른 접속용) (10분)

```
⚠️ 프로덕션에선 권장 안함, 하지만 시간 절약용

EC2 → Launch Instance

Name: bastion
AMI: Amazon Linux 2023
Instance Type: t3.micro (또는 t2.micro 프리티어)
Key pair: [동일한 키]

Network settings:
  VPC: feedback-vpc
  Subnet: Public-AZ-A
  Auto-assign public IP: Enable
  Security Group: 새로 생성
    Inbound: SSH (22) from [Your IP]

[Launch]
```

#### SSH 접속 (5분)

```bash
# 로컬 → Bastion
ssh -i your-key.pem ec2-user@<BASTION_PUBLIC_IP>

# Bastion에서 MySQL 서버 Private IP 확인 (EC2 Console)
# Bastion → MySQL
ssh -i your-key.pem ec2-user@10.0.11.X
```

⚠️ **키 파일을 Bastion에 복사해야 함**:
```bash
# 로컬에서
scp -i your-key.pem your-key.pem ec2-user@<BASTION_PUBLIC_IP>:~/
```

#### MySQL 설치 (30분)

```bash
# MySQL 서버에서 실행

# 1. 시스템 업데이트
sudo dnf update -y

# 2. MySQL 저장소 추가
sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm

# 3. MySQL 서버 설치
sudo dnf install -y mysql-community-server

# 4. 데이터 디렉토리 설정
sudo mkfs -t xfs /dev/nvme1n1  # 두 번째 EBS 볼륨
sudo mkdir /data
sudo mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data xfs defaults,nofail 0 2' | sudo tee -a /etc/fstab

# 5. MySQL 데이터 디렉토리 이동
sudo systemctl stop mysqld || true
sudo mkdir -p /data/mysql
sudo chown -R mysql:mysql /data/mysql
sudo chmod 750 /data/mysql

# 6. MySQL 설정
sudo tee /etc/my.cnf << 'EOF'
[mysqld]
datadir=/data/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

# 네트워크
bind-address = 0.0.0.0
port = 3306

# 성능
max_connections = 150
innodb_buffer_pool_size = 512M

# 문자셋
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[client]
default-character-set = utf8mb4
EOF

# 7. MySQL 초기화 및 시작
sudo mysqld --initialize --user=mysql --datadir=/data/mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld

# 8. 임시 비밀번호 확인
TEMP_PASS=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
echo "임시 비밀번호: $TEMP_PASS"

# 9. root 비밀번호 변경 (강력한 비밀번호 사용!)
mysql -u root -p"$TEMP_PASS" --connect-expired-password << 'EOF'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyNewRootPass123!';
EOF

# 10. 데이터베이스 및 사용자 생성
mysql -u root -p'MyNewRootPass123!' << 'EOF'
CREATE DATABASE feedbackdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'feedbackuser'@'%' IDENTIFIED BY 'FeedbackUserPass123!';
GRANT ALL PRIVILEGES ON feedbackdb.* TO 'feedbackuser'@'%';
FLUSH PRIVILEGES;

SELECT User, Host FROM mysql.user;
SHOW DATABASES;
EOF

echo "✅ MySQL 설치 완료!"
echo "   Host: 10.0.11.X (Private IP)"
echo "   Database: feedbackdb"
echo "   User: feedbackuser"
echo "   Password: FeedbackUserPass123!"
```

#### H2 → MySQL 데이터 마이그레이션 (1.5시간)

**Option 1: 수동 마이그레이션 (간단한 경우)**

```bash
# 1. 기존 EC2에서 H2 데이터 export
ssh ec2-user@<OLD_EC2_IP>

# H2 Console 접속 또는
docker exec feedback-api java -cp /app/h2-*.jar org.h2.tools.Script \
  -url jdbc:h2:file:/app/data/feedbackdb \
  -user sa \
  -script backup.sql

# 2. SQL 파일 다운로드
scp ec2-user@<OLD_EC2_IP>:~/backup.sql ./

# 3. H2 → MySQL 문법 변환 (간단한 sed 치환)
sed -i 's/AUTO_INCREMENT/AUTO_INCREMENT/g' backup.sql
sed -i 's/BIGINT AUTO_INCREMENT/BIGINT AUTO_INCREMENT/g' backup.sql
# (추가 변환 필요 시 수동 수정)

# 4. MySQL에 import
scp backup.sql ec2-user@<BASTION_IP>:~/
ssh ec2-user@<BASTION_IP>
scp backup.sql ec2-user@10.0.11.X:~/

ssh ec2-user@10.0.11.X
mysql -u feedbackuser -p'FeedbackUserPass123!' feedbackdb < backup.sql

# 5. 데이터 확인
mysql -u feedbackuser -p'FeedbackUserPass123!' feedbackdb << 'EOF'
SHOW TABLES;
SELECT COUNT(*) FROM feedbacks;  -- 예시
EOF
```

**Option 2: 애플리케이션으로 마이그레이션 (복잡한 경우)**

```java
// 로컬에서 간단한 마이그레이션 스크립트 작성
// H2에서 읽어서 MySQL에 insert
// (시간이 없으면 Option 1 추천)
```

#### Application 설정 수정 (15분)

```yaml
# src/main/resources/application-prod.yml

spring:
  datasource:
    url: jdbc:mysql://10.0.11.X:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: feedbackuser
    password: FeedbackUserPass123!  # 실제로는 환경변수
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.MySQL8Dialect
```

```gradle
// build.gradle
dependencies {
    // H2 제거 또는 주석
    // runtimeOnly 'com.h2database:h2'

    // MySQL 추가
    runtimeOnly 'com.mysql:mysql-connector-j'
}
```

```bash
# 빌드 및 테스트 (로컬)
./gradlew clean build

# 이미지 빌드
docker build -t feedback-api:mysql .

# 로컬 테스트 (MySQL 연결 확인)
docker run -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.X:3306/feedbackdb \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackUserPass123! \
  -p 8080:8080 \
  feedback-api:mysql

# API 테스트
curl http://localhost:8080/api/feedbacks
```

#### Day 1 체크포인트 ✅

```
□ VPC 생성 완료
□ Subnet 3개 생성 (Public × 2, Private × 1)
□ NAT Gateway 동작
□ Security Groups 4개 생성
□ MySQL 서버 실행 중
□ 데이터 마이그레이션 완료
□ Application이 MySQL 연결 성공
```

---

## 📅 Day 2: ALB + Auto Scaling (5시간)

### 시간표

```
09:00 - 10:30  ALB + Target Group
10:30 - 12:30  Auto Scaling Group
12:30 - 13:30  배포 테스트
13:30 - 14:00  트러블슈팅
```

---

### Step 2.1: Application Load Balancer (1.5시간)

#### Target Group 생성 (15분)

```
EC2 → Target Groups → Create target group

Target type: Instances
Name: feedback-api-tg

Protocol: HTTP
Port: 8080
VPC: feedback-vpc

Health checks:
  Protocol: HTTP
  Path: /actuator/health
  Port: traffic port
  Healthy threshold: 2
  Unhealthy threshold: 3
  Timeout: 5
  Interval: 30

[Next]
[Create target group] (타겟은 아직 등록 안함)
```

#### ALB 생성 (30분)

```
EC2 → Load Balancers → Create load balancer

Type: Application Load Balancer

Basic configuration:
  Name: feedback-api-alb
  Scheme: Internet-facing
  IP address type: IPv4

Network mapping:
  VPC: feedback-vpc
  Mappings:
    ✓ ap-northeast-2a → Public-AZ-A
    ✓ ap-northeast-2c → Public-AZ-C

Security groups:
  alb-sg

Listeners:
  Protocol: HTTP
  Port: 80
  Default action: Forward to feedback-api-tg

[Create load balancer]

⚠️ 생성에 3-5분 소요
```

#### ALB DNS 확인 (5분)

```
Load Balancers → feedback-api-alb

DNS name: feedback-api-alb-xxxxxxxxx.ap-northeast-2.elb.amazonaws.com
Status: Active (확인!)

복사해두기!
```

---

### Step 2.2: Launch Template (30분)

#### IAM Role 생성 (간소화) (10분)

```
IAM → Roles → Create role

Trusted entity: AWS service
Use case: EC2
[Next]

Permissions policies:
  ✓ AmazonEC2ContainerRegistryReadOnly
  ✓ AmazonSSMManagedInstanceCore (선택)
  ✓ CloudWatchAgentServerPolicy (선택)

[Next]

Role name: ec2-instance-role
[Create role]
```

#### Launch Template 생성 (20분)

```
EC2 → Launch Templates → Create launch template

Name: feedback-api-lt

AMI: Amazon Linux 2023
Instance type: t3.small
Key pair: [기존 키]

Network settings:
  ⚠️ Subnet은 여기서 지정하지 않음 (ASG에서 지정)
  Security groups: app-sg

Advanced details:
  IAM instance profile: ec2-instance-role

  User data: (중요!)
```

**User Data 스크립트**:

```bash
#!/bin/bash
set -e

# 로그 파일
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "===== Starting User Data Script ====="

# 1. Docker 설치
echo "[1/6] Installing Docker..."
dnf update -y
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# 2. Docker Compose 설치
echo "[2/6] Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 3. Node Exporter 설치 (Prometheus용)
echo "[3/6] Installing Node Exporter..."
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd -rs /bin/false node_exporter

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

# 4. 애플리케이션 디렉토리
echo "[4/6] Setting up application..."
mkdir -p /opt/feedback-api
cd /opt/feedback-api

# 5. GHCR 로그인 (환경변수로 전달받음)
echo "[5/6] Logging in to GHCR..."
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# 6. 컨테이너 실행
echo "[6/6] Starting application container..."
docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.X:3306/feedbackdb \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackUserPass123! \
  ghcr.io/johnhuh619/simple-api:latest

echo "===== User Data Script Completed ====="
echo "Application should be starting on port 8080"
```

⚠️ **중요**: User Data에서 다음 값들을 실제 값으로 변경:
- `10.0.11.X`: MySQL 서버의 실제 Private IP
- `ghcr.io/johnhuh619/simple-api:latest`: 실제 이미지 경로

**GHCR 인증 문제 해결**:
```
Option 1: Public 이미지로 변경 (GitHub repo를 public으로)
Option 2: User Data에 토큰 하드코딩 (빠르지만 비권장)
Option 3: Secrets Manager 사용 (시간 있으면)
```

시간 절약을 위해 **Option 1 추천** (임시로 repo를 public으로)

---

### Step 2.3: Auto Scaling Group (1시간)

#### ASG 생성 (30분)

```
EC2 → Auto Scaling Groups → Create Auto Scaling group

Name: feedback-api-asg

Launch template: feedback-api-lt (Latest version)
[Next]

Network:
  VPC: feedback-vpc
  Subnets:
    ✓ Private-AZ-A (10.0.11.0/24)
    ⚠️ Private-AZ-C가 없으므로 하나만 선택

[Next]

Load balancing:
  ✓ Attach to an existing load balancer
  ✓ Choose from your load balancer target groups
  Target group: feedback-api-tg

Health checks:
  ✓ ELB
  Grace period: 300 seconds

[Next]

Group size:
  Desired: 1
  Minimum: 1
  Maximum: 2  (시간 절약 위해 작게)

Scaling policies:
  ✓ Target tracking scaling policy
  Metric: Average CPU utilization
  Target value: 70

[Next]
[Next] (Notifications 건너뛰기)

Tags:
  Key: Name
  Value: feedback-api-instance
  ✓ Tag new instances

[Next]
[Create Auto Scaling group]
```

#### 인스턴스 시작 확인 (30분)

```
⚠️ 인스턴스가 시작되고 Health check 통과하는데 5-10분 소요

EC2 → Instances
  - feedback-api-instance 상태 확인
  - Status checks: 2/2 checks passed 대기

EC2 → Target Groups → feedback-api-tg
  - Targets 탭
  - Status: healthy 대기 (5-10분 소요)

⏰ 커피 타임!
```

---

### Step 2.4: 테스트 (1시간)

#### ALB를 통한 접속 테스트 (20분)

```bash
# ALB DNS로 테스트
ALB_DNS="feedback-api-alb-xxxxxxxxx.ap-northeast-2.elb.amazonaws.com"

# Health check
curl http://$ALB_DNS/actuator/health

# API 테스트
curl http://$ALB_DNS/api/feedbacks

# 성공하면 ✅
# 실패하면 트러블슈팅 필요
```

#### 트러블슈팅 체크리스트 (40분)

**문제 1: Target Unhealthy**
```
원인:
  - User Data 실행 실패
  - Docker 컨테이너 시작 안됨
  - Health check 경로 오류

확인:
  ssh ec2-user@<INSTANCE_PRIVATE_IP>  # Bastion 통해

  # User Data 로그 확인
  sudo cat /var/log/user-data.log

  # Docker 상태 확인
  docker ps
  docker logs feedback-api

  # 포트 확인
  curl http://localhost:8080/actuator/health

해결:
  - User Data 수정 후 인스턴스 재시작
  - 또는 수동으로 Docker 실행
```

**문제 2: 502 Bad Gateway**
```
원인:
  - Target Group이 Unhealthy
  - Security Group 막힘

확인:
  EC2 → Target Groups → feedback-api-tg
  - Target 상태 확인
  - Health check 설정 확인

해결:
  - Security Group app-sg에서 8080 포트 확인
  - alb-sg가 app-sg에 접근 가능한지 확인
```

**문제 3: GHCR 로그인 실패**
```
원인:
  - Private registry 인증 실패

빠른 해결:
  1. GitHub repo를 임시로 public으로 변경
  2. GHCR 이미지도 public으로 설정

  GitHub → Repository → Settings → General
    ✓ Change visibility → Public

  GitHub → Repository → Packages
    → 이미지 선택 → Package settings
    ✓ Change visibility → Public
```

#### Day 2 체크포인트 ✅

```
□ Target Group 생성
□ ALB 생성 및 Active 상태
□ Launch Template 작성
□ Auto Scaling Group 생성
□ 인스턴스 1대 실행 중
□ Target healthy 상태
□ ALB DNS로 API 접속 성공
```

---

## 📅 Day 3: 모니터링 (5시간)

### 시간표

```
09:00 - 10:30  Prometheus 설치
10:30 - 11:30  Grafana 설치
11:30 - 12:30  대시보드 구성
12:30 - 13:30  통합 테스트
13:30 - 14:00  정리 및 문서화
```

---

### Step 3.1: Monitoring Server (30분)

#### EC2 인스턴스 시작 (10분)

```
EC2 → Launch Instance

Name: monitoring-server
AMI: Amazon Linux 2023
Instance Type: t3.small
Key pair: [기존 키]

Network:
  VPC: feedback-vpc
  Subnet: Private-AZ-A
  Auto-assign public IP: Disable
  Security Group: monitoring-sg

Storage: 30 GiB gp3

[Launch]
```

#### SSH 접속 (5분)

```bash
# Bastion → Monitoring Server
ssh ec2-user@<BASTION_IP>
ssh ec2-user@10.0.11.Y  # Monitoring Server Private IP
```

---

### Step 3.2: Prometheus 설치 (1시간)

```bash
# Monitoring Server에서 실행

# 1. Prometheus 다운로드
cd /opt
sudo wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
sudo tar xvfz prometheus-*.tar.gz
sudo mv prometheus-* prometheus
sudo useradd -rs /bin/false prometheus
sudo chown -R prometheus:prometheus /opt/prometheus

# 2. 데이터 디렉토리
sudo mkdir -p /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

# 3. 설정 파일 (간소화 버전)
sudo tee /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  # Prometheus 자체
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # API Servers (수동 등록)
  - job_name: 'feedback-api'
    static_configs:
      - targets:
          - '10.0.11.Z:9100'  # API Server Private IP (Auto Scaling으로 시작된 인스턴스)
        labels:
          instance: 'api-1'

  # MySQL Server
  - job_name: 'mysql-server'
    static_configs:
      - targets: ['10.0.11.X:9100']  # MySQL Server Private IP

  # Monitoring Server 자체
  - job_name: 'monitoring-server'
    static_configs:
      - targets: ['localhost:9100']

  # Spring Boot Actuator (있는 경우)
  - job_name: 'spring-actuator'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets:
          - '10.0.11.Z:8080'  # API Server Private IP
EOF

# ⚠️ IP 주소를 실제 값으로 변경!

# 4. Systemd 서비스
sudo tee /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/opt/prometheus/consoles \
  --web.console.libraries=/opt/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

# 5. 서비스 시작
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# 6. 상태 확인
sudo systemctl status prometheus
curl http://localhost:9090/-/healthy

echo "✅ Prometheus 설치 완료!"
echo "   접속: http://10.0.11.Y:9090 (VPN 또는 터널링 필요)"
```

---

### Step 3.3: Grafana 설치 (1시간)

```bash
# Monitoring Server에서 실행

# 1. Grafana 저장소 추가
sudo tee /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

# 2. Grafana 설치
sudo dnf install -y grafana

# 3. 서비스 시작
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# 4. 상태 확인
sudo systemctl status grafana-server
curl http://localhost:3000

echo "✅ Grafana 설치 완료!"
echo "   접속: http://10.0.11.Y:3000"
echo "   초기 계정: admin / admin"
```

---

### Step 3.4: Grafana 설정 (1시간)

#### SSH 터널링으로 Grafana 접속 (5분)

```bash
# 로컬 터미널에서 (새 터미널)
ssh -L 3000:10.0.11.Y:3000 -L 9090:10.0.11.Y:9090 \
  -J ec2-user@<BASTION_IP> \
  ec2-user@10.0.11.Y

# 이제 로컬에서 접속 가능:
# http://localhost:3000  → Grafana
# http://localhost:9090  → Prometheus
```

#### 데이터소스 추가 (5분)

```
브라우저 → http://localhost:3000

로그인: admin / admin
[새 비밀번호 설정]

Left Menu → Connections → Data sources → Add data source

Prometheus 선택:

  URL: http://localhost:9090

  [Save & test]
  ✅ "Data source is working" 확인
```

#### 대시보드 Import (20분)

```
Left Menu → Dashboards → Import

# 1. Node Exporter Dashboard
Dashboard ID: 1860
[Load]

Prometheus: [Select Prometheus]
[Import]

✅ 시스템 메트릭 대시보드 생성됨

# 2. Spring Boot Dashboard (애플리케이션에 Actuator 있는 경우)
Dashboard ID: 12900
[Load]

Prometheus: [Select Prometheus]
[Import]
```

#### 간단한 커스텀 대시보드 (30분)

```
Left Menu → Dashboards → New → New Dashboard

Add visualization:

Panel 1: API Server CPU
  Query: 100 - (avg(irate(node_cpu_seconds_total{mode="idle",job="feedback-api"}[5m])) * 100)
  Title: API Server CPU Usage
  Unit: Percent (0-100)

Panel 2: API Server Memory
  Query: (1 - (node_memory_MemAvailable_bytes{job="feedback-api"} / node_memory_MemTotal_bytes{job="feedback-api"})) * 100
  Title: API Server Memory Usage
  Unit: Percent (0-100)

Panel 3: MySQL Server Status
  Query: up{job="mysql-server"}
  Title: MySQL Server Status
  Visualization: Stat
  Value mapping: 0 = DOWN, 1 = UP

Panel 4: Request Count (Spring Actuator 있는 경우)
  Query: rate(http_server_requests_seconds_count[5m])
  Title: Request Rate
  Unit: reqps

[Save dashboard]
Name: Feedback API Overview
```

---

### Step 3.5: 최종 검증 (1시간)

#### 전체 시스템 테스트 (30분)

```bash
# 1. 네트워크 연결
ping 10.0.11.X  # MySQL
ping 10.0.11.Y  # Monitoring
ping 10.0.11.Z  # API Server

# 2. ALB 접속
curl http://<ALB_DNS>/actuator/health
curl http://<ALB_DNS>/api/feedbacks

# 3. MySQL 연결
mysql -h 10.0.11.X -u feedbackuser -p

# 4. Prometheus Targets
http://localhost:9090/targets
→ 모든 타겟이 UP 상태인지 확인

# 5. Grafana Dashboard
http://localhost:3000
→ 메트릭이 수집되고 있는지 확인
```

#### Auto Scaling 테스트 (선택, 20분)

```bash
# 부하 생성 (간단한 방법)
for i in {1..1000}; do
  curl http://<ALB_DNS>/api/feedbacks &
done

# CloudWatch 또는 Grafana에서 CPU 확인
# CPU > 70% 되면 Auto Scaling 시작 (5분 후)

# ASG 확인
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names feedback-api-asg

# 인스턴스 증가 확인
```

#### 문서화 (10분)

```markdown
# 빠른 참조 가이드

## 접속 정보

ALB: http://<ALB_DNS>
MySQL: 10.0.11.X:3306
Prometheus: http://10.0.11.Y:9090 (터널링 필요)
Grafana: http://10.0.11.Y:3000 (터널링 필요)

## 계정

MySQL:
  - root / MyNewRootPass123!
  - feedbackuser / FeedbackUserPass123!

Grafana:
  - admin / [새 비밀번호]

## SSH 접속

Bastion: ssh ec2-user@<BASTION_PUBLIC_IP>
MySQL: ssh ec2-user@10.0.11.X (via Bastion)
Monitoring: ssh ec2-user@10.0.11.Y (via Bastion)
API Servers: Auto Scaling으로 관리

## 터널링

ssh -L 3000:10.0.11.Y:3000 -L 9090:10.0.11.Y:9090 \
  -J ec2-user@<BASTION_IP> ec2-user@10.0.11.Y

## 모니터링

CloudWatch: EC2 기본 메트릭
Prometheus: http://localhost:9090/targets
Grafana: http://localhost:3000
```

---

## ✅ 최종 체크리스트

### 네트워크 (Day 1)
- [ ] VPC 생성
- [ ] Subnet 3개 (Public × 2, Private × 1)
- [ ] Internet Gateway
- [ ] NAT Gateway
- [ ] Route Tables
- [ ] Security Groups (4개)

### 데이터베이스 (Day 1)
- [ ] MySQL EC2 인스턴스 실행
- [ ] MySQL 8.0 설치
- [ ] 데이터베이스 생성
- [ ] H2 → MySQL 마이그레이션
- [ ] Application MySQL 연결 성공

### ALB + ASG (Day 2)
- [ ] Target Group 생성
- [ ] ALB 생성 및 활성화
- [ ] Launch Template 작성
- [ ] Auto Scaling Group 생성
- [ ] 인스턴스 healthy 상태
- [ ] ALB를 통한 API 접속 성공

### 모니터링 (Day 3)
- [ ] Monitoring Server 시작
- [ ] Prometheus 설치 및 실행
- [ ] Grafana 설치 및 실행
- [ ] 데이터소스 연결
- [ ] 대시보드 구성
- [ ] 메트릭 수집 확인

---

## ⚠️ 알려진 제약사항 (빠른 구축의 한계)

### 보안
- ⚠️ 비밀번호가 하드코딩됨 (User Data, 설정 파일)
- ⚠️ Bastion Host가 Public subnet에 노출
- ⚠️ Security Group이 최소 권한 원칙 미준수

**나중에 개선**:
- AWS Secrets Manager로 비밀번호 관리
- Session Manager로 Bastion 제거
- Security Group 세분화

### 고가용성
- ⚠️ MySQL이 단일 서버 (SPOF)
- ⚠️ Monitoring Server도 단일 서버
- ⚠️ Private Subnet이 단일 AZ

**나중에 개선**:
- RDS Multi-AZ 고려
- Monitoring Server 이중화 또는 Managed Service
- Private Subnet AZ-C 추가

### 백업
- ⚠️ 자동 백업 스크립트 없음
- ⚠️ 재해 복구 계획 미수립

**나중에 개선**:
- Cron으로 자동 백업
- S3 업로드 자동화
- 복구 절차 문서화

### CI/CD
- ⚠️ GitHub Actions가 아직 Auto Scaling 미지원
- ⚠️ 수동 배포 방식

**나중에 개선**:
- deploy.yml 수정 (Instance Refresh)
- Blue-Green 배포 고려

### 모니터링
- ⚠️ Alert Rules 미설정
- ⚠️ Slack 알림 미연동

**나중에 개선**:
- Alertmanager 설정
- Slack Webhook 연동
- On-call 로테이션

---

## 💰 실제 비용 (15시간 버전)

```
간소화된 구성:

ALB: $27.50/월
ASG (t3.small × 1-2): $15-30/월
MySQL (t3.small): $24.78/월
Monitoring (t3.small): $21.58/월
NAT Gateway: $37.85/월
Bastion (t3.micro): $6.07/월 (임시, 나중에 제거 가능)
S3: $1/월

총계: ~$133-148/월

프리티어 만료 고려한 현실적 비용
```

---

## 🚀 15시간 후 결과

**달성한 것**:
- ✅ Multi-AZ ALB
- ✅ Auto Scaling (기본)
- ✅ MySQL on EC2
- ✅ Prometheus + Grafana
- ✅ 동작하는 프로덕션 인프라

**아직 못한 것** (향후 개선):
- ⏸️ 완벽한 보안
- ⏸️ 자동 백업
- ⏸️ CI/CD 자동화
- ⏸️ Alert 시스템
- ⏸️ 완벽한 고가용성

**하지만**: 팀의 요구사항을 충족하는 **동작하는 시스템**을 3일 만에 구축! 🎉

---

## 📚 다음 단계 (15시간 이후)

### Week 2: 보안 강화
- Secrets Manager 적용
- Bastion 제거 (Session Manager)
- Security Group 세분화

### Week 3: 백업 및 복구
- 자동 백업 스크립트
- S3 Lifecycle policy
- 복구 절차 문서화 및 테스트

### Week 4: CI/CD 자동화
- deploy.yml 업데이트 (Instance Refresh)
- rollback.yml 업데이트

### Month 2: 모니터링 고도화
- Alertmanager 설정
- Slack 알림
- 커스텀 메트릭 추가

---

**화이팅! 15시간 안에 해냅시다! 💪**

궁금한 점이나 막히는 부분 있으면 언제든 물어보세요!
