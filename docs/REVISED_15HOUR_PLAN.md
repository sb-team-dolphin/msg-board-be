# 🚀 수정된 15시간 계획 (DB 마이그레이션 불필요!)

**중요 변경사항**: H2 데이터 유실 OK → MySQL 갈아끼우기만 하면 됨
**시간 절약**: 3시간 → 30분 (2.5시간 절약!)

---

## ⏱️ 수정된 시간 배분

```
Day 1 (5시간):
├─ VPC + 네트워크 기본           [1.5시간]
├─ MySQL 설치 (마이그레이션 X)   [0.5시간] ← 2.5시간 절약!
├─ Application 설정 변경         [0.5시간]
├─ 테스트                        [0.5시간]
└─ 🎉 2시간 여유 생김!          [2시간]

Day 2 (5시간):
├─ ALB + Target Group           [1.5시간]
├─ Launch Template + ASG        [2.5시간]
└─ 배포 테스트                  [1시간]

Day 3 (5시간):
├─ Prometheus 설치              [1.5시간]
├─ Grafana 설치                 [1시간]
├─ 대시보드 구성                [1시간]
└─ 최종 검증                    [1.5시간]
```

---

## 📅 Day 1: 네트워크 + 데이터베이스 (여유있게!)

### 🎯 목표
- VPC 및 네트워크 구성
- MySQL 설치 및 연결 (데이터 없이 깨끗하게 시작)
- Application 설정 변경

### 시간표
```
09:00 - 10:30  VPC + 네트워크
10:30 - 11:00  MySQL 서버 설치 (간단!)
11:00 - 11:30  Application 설정 변경
11:30 - 12:00  테스트 및 검증
12:00 - 14:00  🎉 여유 시간 또는 Day 2 시작
```

---

## 🚀 간소화된 MySQL 설치 (30분!)

### Step 1: EC2 인스턴스 시작 (10분)

```
EC2 → Launch Instance

Name: mysql-server
AMI: Amazon Linux 2023
Instance Type: t3.small
Key pair: [기존 키]

Network:
  VPC: feedback-vpc
  Subnet: Private-AZ-A
  Auto-assign public IP: Disable
  Security Group: db-sg

Storage:
  Root: 20 GiB gp3
  Add volume: 50 GiB gp3

[Launch]
```

### Step 2: MySQL 8.0 빠른 설치 (15분)

```bash
# Bastion → MySQL Server 접속
ssh ec2-user@10.0.11.X

# 한 번에 실행 (복붙 가능)
sudo dnf update -y
sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
sudo dnf install -y mysql-community-server

# 데이터 디렉토리 (두 번째 EBS 볼륨)
sudo mkfs -t xfs /dev/nvme1n1
sudo mkdir /data
sudo mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data xfs defaults,nofail 0 2' | sudo tee -a /etc/fstab

# MySQL 데이터 디렉토리 설정
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
max_connections = 150
innodb_buffer_pool_size = 512M

[client]
default-character-set = utf8mb4
EOF

# MySQL 시작
sudo mysqld --initialize --user=mysql --datadir=/data/mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld

# 임시 비밀번호
TEMP_PASS=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
echo "임시 비밀번호: $TEMP_PASS"

# root 비밀번호 변경
mysql -u root -p"$TEMP_PASS" --connect-expired-password << 'EOF'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyRootPass123!';
EOF

# 데이터베이스 및 사용자 생성 (깨끗한 DB!)
mysql -u root -p'MyRootPass123!' << 'EOF'
CREATE DATABASE feedbackdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'feedbackuser'@'%' IDENTIFIED BY 'FeedbackPass123!';
GRANT ALL PRIVILEGES ON feedbackdb.* TO 'feedbackuser'@'%';
FLUSH PRIVILEGES;
SHOW DATABASES;
EOF

echo "✅ MySQL 설치 완료!"
echo "   Host: $(hostname -I | awk '{print $1}')"
echo "   Database: feedbackdb (빈 데이터베이스)"
echo "   User: feedbackuser"
```

### Step 3: Application 설정 변경 (5분)

**로컬에서 작업**:

```yaml
# src/main/resources/application-prod.yml

spring:
  datasource:
    url: jdbc:mysql://10.0.11.X:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: feedbackuser
    password: FeedbackPass123!  # 실제로는 환경변수로
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: create  # ← 빈 DB이므로 create로 테이블 자동 생성!
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.MySQL8Dialect
```

```gradle
// build.gradle
dependencies {
    // MySQL 추가
    runtimeOnly 'com.mysql:mysql-connector-j'

    // H2 제거 (또는 주석)
    // runtimeOnly 'com.h2database:h2'
}
```

```bash
# 빌드 및 이미지 생성
./gradlew clean build
docker build -t ghcr.io/johnhuh619/simple-api:latest .

# ⚠️ 중요: GitHub repo를 임시로 Public으로 변경!
# GitHub → Repository → Settings → General
#   → Change visibility → Public

# 이미지 푸시
docker push ghcr.io/johnhuh619/simple-api:latest
```

### Step 4: 로컬 테스트 (10분)

```bash
# 로컬에서 MySQL 연결 테스트
docker run --rm \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.X:3306/feedbackdb?useSSL=false \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackPass123! \
  -e SPRING_PROFILES_ACTIVE=prod \
  -p 8080:8080 \
  ghcr.io/johnhuh619/simple-api:latest

# 다른 터미널에서 테스트
curl http://localhost:8080/actuator/health

# 테이블 생성 확인
mysql -h 10.0.11.X -u feedbackuser -p'FeedbackPass123!' feedbackdb << 'EOF'
SHOW TABLES;
DESCRIBE feedbacks;  -- 테이블 구조 확인
EOF
```

### Day 1 완료! ✅

```
□ VPC 생성
□ Subnet 3개 (Public × 2, Private × 1)
□ NAT Gateway
□ Security Groups 4개
□ MySQL 서버 실행 중
□ 빈 데이터베이스 생성 완료
□ Application이 MySQL 연결 성공
□ 테이블 자동 생성 확인
□ 🎉 2시간 여유 생김!
```

**여유 시간 활용**:
1. Day 2 시작 (추천!)
2. 추가 테스트 및 검증
3. 문서 정리
4. 휴식 ☕

---

## 💡 ddl-auto: create 주의사항

### 개발 단계 (지금)
```yaml
hibernate:
  ddl-auto: create  # 테이블 자동 생성 (기존 데이터 삭제!)
```

**장점**:
- ✅ 테이블 자동 생성
- ✅ 스키마 변경 시 자동 반영
- ✅ 개발 속도 빠름

**주의**:
- ⚠️ 서버 재시작 시 데이터 모두 삭제!
- ⚠️ 프로덕션에서는 절대 금지!

### 프로덕션 전환 시
```yaml
hibernate:
  ddl-auto: validate  # 스키마만 검증 (변경 안함)
```

또는

```yaml
hibernate:
  ddl-auto: none  # Hibernate가 스키마 관리 안함
```

**+ Flyway or Liquibase 사용** (DB 마이그레이션 도구)

---

## 📊 수정된 총 시간

### 이전 계획
```
Day 1: 5시간
  - 네트워크: 1.5h
  - MySQL 설치: 1.5h
  - H2 → MySQL 마이그레이션: 2h  ← 불필요!
  - 검증: 0.5h

→ 빡빡함 😰
```

### 새 계획
```
Day 1: 3시간 실제 작업 + 2시간 여유
  - 네트워크: 1.5h
  - MySQL 설치: 0.5h  ← 2.5시간 절약!
  - Application 설정: 0.5h
  - 테스트: 0.5h

→ 여유있음 😊
```

---

## 🎯 새로운 15시간 계획

### 현실적인 배분

**Option 1: 여유있게 (추천!)**
```
Day 1 (3.5시간):
  VPC + MySQL + 테스트

Day 2 (6시간):
  ALB + ASG + 충분한 트러블슈팅 시간

Day 3 (5.5시간):
  Prometheus + Grafana + 최종 검증
```

**Option 2: 빠르게**
```
Day 1 (5시간):
  VPC + MySQL (3h) + ALB 시작 (2h)

Day 2 (5시간):
  ALB 완료 + ASG (전체)

Day 3 (5시간):
  Prometheus + Grafana
```

**Option 3: 가장 빠르게 (경험자용)**
```
Day 1 (7시간):
  VPC + MySQL + ALB + ASG 기본

Day 2 (4시간):
  ASG 완료 + 테스트

Day 3 (4시간):
  Prometheus + Grafana (간소화)
```

---

## 🚀 추천 진행 방식

### Day 1 오전 (3시간)
```
09:00 - 10:30  VPC + 네트워크
10:30 - 11:00  MySQL 설치
11:00 - 11:30  Application 설정
11:30 - 12:00  테스트
```

### Day 1 오후 (2시간)
```
선택 1: Day 2 시작 (ALB)  ← 추천!
선택 2: 추가 검증 및 문서화
선택 3: 모니터링 사전 준비
```

### Day 2 (5시간)
```
09:00 - 10:30  ALB + Target Group
10:30 - 13:00  Launch Template + ASG
13:00 - 14:00  배포 테스트 및 트러블슈팅
```

### Day 3 (5시간)
```
09:00 - 10:30  Prometheus
10:30 - 11:30  Grafana
11:30 - 12:30  대시보드
12:30 - 14:00  최종 검증 및 정리
```

---

## ✅ 핵심 변경사항 요약

### 제거된 것
```
❌ H2 데이터 export (1시간)
❌ SQL 문법 변환 (30분)
❌ MySQL import (30분)
❌ 데이터 검증 (30분)

총 절약: 2.5시간!
```

### 추가된 것
```
✅ ddl-auto: create (자동 테이블 생성)
✅ 깨끗한 DB로 시작
✅ 2시간 여유 시간

→ 훨씬 간단하고 빠름!
```

### 주의사항
```
⚠️ 프로덕션 전환 시:
   ddl-auto: create → validate로 변경 필수!

⚠️ 실제 데이터 있을 때:
   마이그레이션 도구(Flyway) 사용
```

---

## 🎉 결론

**DB 마이그레이션 불필요 = 게임 체인저!**

이전 계획:
- 😰 빡빡한 15시간
- 😓 마이그레이션 스트레스
- 🐛 데이터 유실 위험

새 계획:
- 😊 여유있는 12.5시간 + 2.5시간 예비
- 🎯 깨끗한 시작
- ✅ 더 안정적

**15시간 안에 충분히 가능합니다!** 🚀

---

**다음 단계**: `ARCHITECTURE_EXPLAINED.md`로 큰 그림 이해 → 실제 구축 시작!
