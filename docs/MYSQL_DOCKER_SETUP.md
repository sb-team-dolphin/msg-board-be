# 🐳 MySQL Docker 설치 가이드 (간소화 버전)

**Phase 3 대체**: MySQL을 직접 설치하지 않고 Docker로 실행

**소요 시간**: 40분 → **15분** (25분 절약!) ⭐

---

## 📊 비교: 직접 설치 vs Docker

### 기존 방법 (직접 설치) - 40분

```bash
# MySQL 8.0 리포지토리 추가
sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm

# MySQL 설치
sudo dnf install -y mysql-community-server

# 데이터 볼륨 마운트
sudo mkfs -t xfs /dev/nvme1n1
sudo mount /dev/nvme1n1 /data

# MySQL 설정 파일 작성
sudo tee /etc/my.cnf << 'EOF'
[mysqld]
datadir=/data/mysql
...
EOF

# MySQL 초기화
sudo mysqld --initialize --user=mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld

# 임시 비밀번호 찾기
grep 'temporary password' /var/log/mysqld.log

# 비밀번호 변경 및 DB 생성
mysql -u root -p...

총 소요: 40분
복잡도: ⭐⭐⭐⭐☆
```

### 새 방법 (Docker) - 15분 ⭐

```bash
# Docker 설치
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker

# 데이터 볼륨 마운트
sudo mkfs -t xfs /dev/nvme1n1
sudo mount /dev/nvme1n1 /data
sudo mkdir /data/mysql

# MySQL 컨테이너 실행 (한 줄!)
docker run -d \
  --name mysql \
  --restart unless-stopped \
  -v /data/mysql:/var/lib/mysql \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=MyRootPass123! \
  -e MYSQL_DATABASE=feedbackdb \
  -e MYSQL_USER=feedbackuser \
  -e MYSQL_PASSWORD=FeedbackPass123! \
  mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci

총 소요: 15분
복잡도: ⭐⭐☆☆☆
```

---

## 🚀 Phase 3 (개선): MySQL Docker 설치 (15분)

### Step 3-1: MySQL EC2 인스턴스 시작

**동일** (기존과 같음):
```
EC2 → Instances → Launch instances

Name: mysql-server
AMI: Amazon Linux 2023 AMI
Instance type: t3.small
Key pair: [선택]

Network:
  VPC: feedback-vpc
  Subnet: Public-AZ-A ⭐
  Auto-assign public IP: Enable
  Security group: db-sg

Storage:
  Root: 10 GiB gp3
  [Add volume]:
    Size: 20 GiB
    Volume type: gp3

[Launch instance]
```

**대기** (2-3분):
```
State: Running
Private IP: 10.0.1.X ⭐ (복사!)
```

### Step 3-2: Docker 및 MySQL 설치 (10분)

**SSH 접속**:
```bash
ssh -i your-key.pem ec2-user@[MySQL-Public-IP]
```

**한 번에 실행** (복붙 가능):
```bash
#!/bin/bash

echo "========================================="
echo "MySQL Docker Setup Started: $(date)"
echo "========================================="

# 1. Docker 설치
echo "[1/4] Installing Docker..."
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# 2. 데이터 볼륨 마운트
echo "[2/4] Setting up data volume..."
sudo mkfs -t xfs /dev/nvme1n1
sudo mkdir -p /data
sudo mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data xfs defaults,nofail 0 2' | sudo tee -a /etc/fstab

# MySQL 데이터 디렉토리
sudo mkdir -p /data/mysql
sudo chown -R 999:999 /data/mysql  # MySQL Docker는 UID 999 사용

# 3. MySQL Docker 컨테이너 실행
echo "[3/4] Starting MySQL container..."
sudo docker run -d \
  --name mysql \
  --restart unless-stopped \
  -v /data/mysql:/var/lib/mysql \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=MyRootPass123! \
  -e MYSQL_DATABASE=feedbackdb \
  -e MYSQL_USER=feedbackuser \
  -e MYSQL_PASSWORD=FeedbackPass123! \
  mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --bind-address=0.0.0.0 \
  --max-connections=100

# 4. 대기 (MySQL 초기화 시간)
echo "[4/4] Waiting for MySQL to be ready..."
for i in {1..30}; do
  if sudo docker exec mysql mysqladmin ping -h localhost -u root -p'MyRootPass123!' > /dev/null 2>&1; then
    echo "✅ MySQL is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done

# 5. 검증
echo ""
echo "========================================="
echo "MySQL Docker Setup Completed!"
echo "========================================="
echo ""
echo "Container status:"
sudo docker ps | grep mysql
echo ""
echo "Database info:"
sudo docker exec mysql mysql -u feedbackuser -p'FeedbackPass123!' -e "SHOW DATABASES;"
echo ""
echo "User info:"
sudo docker exec mysql mysql -u root -p'MyRootPass123!' -e "SELECT user, host FROM mysql.user WHERE user='feedbackuser';"
echo ""
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "========================================="
```

**✅ 검증**:
```bash
# 컨테이너 실행 확인
sudo docker ps

# 예상 결과:
CONTAINER ID   IMAGE       STATUS         PORTS                    NAMES
abc123def456   mysql:8.0   Up 2 minutes   0.0.0.0:3306->3306/tcp   mysql

# 데이터베이스 확인
sudo docker exec mysql mysql -u feedbackuser -p'FeedbackPass123!' -e "SHOW DATABASES;"

# 예상 결과:
+--------------------+
| Database           |
+--------------------+
| feedbackdb         |
| information_schema |
| performance_schema |
+--------------------+
```

### Step 3-3: 외부 연결 테스트 (5분)

**Security Group 임시 수정** (테스트용):
```
EC2 → Security Groups → db-sg
  → Inbound rules → Edit
  → Add rule:
    Type: MySQL/Aurora (3306)
    Source: 0.0.0.0/0 (임시!)

[Save rules]
```

**로컬에서 연결 테스트**:
```bash
# 로컬 터미널 (MySQL 클라이언트 필요)
mysql -h [MySQL-Public-IP] -u feedbackuser -p'FeedbackPass123!' feedbackdb

# 또는 Docker 없이 테스트
telnet [MySQL-Public-IP] 3306
# → Connected 뜨면 성공
```

**로컬 Docker로 테스트** (MySQL 클라이언트 없는 경우):
```bash
docker run --rm -it mysql:8.0 \
  mysql -h [MySQL-Public-IP] -u feedbackuser -p'FeedbackPass123!' feedbackdb

# 접속 성공하면:
mysql> SHOW TABLES;
Empty set (0.00 sec)  # 정상 (아직 테이블 없음)

mysql> EXIT;
```

**Security Group 원복**:
```
db-sg → Inbound rules → Edit
  → 3306 from 0.0.0.0/0 삭제
  → 3306 from app-sg만 유지

[Save rules]
```

**Private IP 재확인 및 기록** ⭐⭐⭐:
```bash
# MySQL 서버에서
hostname -I | awk '{print $1}'
# → 10.0.1.234 (예시)

→ 메모장에 복사!
```

**🎉 MySQL Docker 설치 완료! (15분만에!)**

---

## 🔧 Docker MySQL 관리 명령어

### 기본 관리

```bash
# 컨테이너 시작/중지/재시작
sudo docker start mysql
sudo docker stop mysql
sudo docker restart mysql

# 컨테이너 상태 확인
sudo docker ps -a | grep mysql

# 로그 확인
sudo docker logs mysql
sudo docker logs --tail 100 mysql
sudo docker logs -f mysql  # 실시간

# 컨테이너 내부 접속
sudo docker exec -it mysql bash

# MySQL 직접 접속
sudo docker exec -it mysql mysql -u root -p'MyRootPass123!'
```

### 데이터베이스 작업

```bash
# 데이터베이스 목록
sudo docker exec mysql mysql -u root -p'MyRootPass123!' -e "SHOW DATABASES;"

# 테이블 목록
sudo docker exec mysql mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb -e "SHOW TABLES;"

# 테이블 구조 확인
sudo docker exec mysql mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb -e "DESCRIBE feedbacks;"

# 데이터 조회
sudo docker exec mysql mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb -e "SELECT * FROM feedbacks;"
```

### 백업 및 복원

```bash
# 백업 (mysqldump)
sudo docker exec mysql mysqldump -u feedbackuser -p'FeedbackPass123!' feedbackdb > backup.sql

# 복원
sudo docker exec -i mysql mysql -u feedbackuser -p'FeedbackPass123!' feedbackdb < backup.sql

# 자동 백업 스크립트
cat > /home/ec2-user/backup-mysql-docker.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/home/ec2-user/mysql-backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
sudo docker exec mysql mysqldump -u feedbackuser -p'FeedbackPass123!' feedbackdb \
  > $BACKUP_DIR/feedbackdb_$DATE.sql
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
echo "Backup completed: $BACKUP_DIR/feedbackdb_$DATE.sql"
EOF

chmod +x /home/ec2-user/backup-mysql-docker.sh
```

---

## 📊 비교 요약

| 항목 | 직접 설치 | Docker ⭐ |
|------|----------|----------|
| **소요 시간** | 40분 | **15분** |
| **복잡도** | ⭐⭐⭐⭐☆ | **⭐⭐☆☆☆** |
| **설치 단계** | 10단계 | **3단계** |
| **설정 파일** | /etc/my.cnf 수동 작성 | **환경변수로 자동** |
| **초기화** | mysqld --initialize 필요 | **자동 초기화** |
| **DB/사용자 생성** | 수동 (SQL 실행) | **환경변수로 자동** |
| **재시작** | systemctl restart mysqld | **docker restart mysql** |
| **로그 확인** | /var/log/mysqld.log | **docker logs mysql** |
| **백업** | mysqldump 직접 | **docker exec mysqldump** |
| **삭제** | 패키지 제거 필요 | **docker rm -f mysql** |

---

## 🎯 주의사항

### 1. UID 999 권한

```bash
# MySQL Docker는 UID 999로 실행됨
sudo chown -R 999:999 /data/mysql

# 확인
ls -la /data/mysql
# → drwxr-xr-x 999 999
```

### 2. bind-address

```bash
# Docker 실행 시 자동 적용됨
--bind-address=0.0.0.0

# 확인
sudo docker exec mysql mysql -u root -p'MyRootPass123!' \
  -e "SHOW VARIABLES LIKE 'bind_address';"

# 예상 결과:
+---------------+---------+
| Variable_name | Value   |
+---------------+---------+
| bind_address  | 0.0.0.0 |
+---------------+---------+
```

### 3. 자동 재시작

```bash
# --restart unless-stopped 옵션
# → EC2 재부팅 시 자동 시작

# 확인
sudo docker inspect mysql | grep -A 5 RestartPolicy

# 예상 결과:
"RestartPolicy": {
    "Name": "unless-stopped",
    ...
}
```

### 4. 데이터 영구성

```bash
# /data/mysql에 모든 데이터 저장
# → 컨테이너 삭제해도 데이터 유지!

# 테스트
sudo docker stop mysql
sudo docker rm mysql
ls /data/mysql
# → 파일들 그대로 존재 ✓

# 같은 명령으로 다시 시작하면 데이터 복구
sudo docker run -d --name mysql -v /data/mysql:/var/lib/mysql ...
```

---

## 🆘 트러블슈팅

### 문제 1: 컨테이너 시작 실패

```bash
# 로그 확인
sudo docker logs mysql

# 일반적 원인:
# 1. 포트 3306 이미 사용 중
sudo netstat -tlnp | grep 3306
# → 다른 프로세스 종료

# 2. 권한 문제
sudo chown -R 999:999 /data/mysql

# 3. 볼륨 마운트 실패
df -h | grep /data
# → /data 마운트 확인
```

### 문제 2: 외부 연결 실패

```bash
# 1. 컨테이너 포트 확인
sudo docker ps
# → 0.0.0.0:3306->3306/tcp 확인

# 2. 방화벽 확인 (Amazon Linux 2023은 기본 비활성화)
sudo systemctl status firewalld
# → inactive (dead) 확인

# 3. Security Group 확인
# → db-sg에 3306 from app-sg 있는지

# 4. bind-address 확인
sudo docker exec mysql mysql -u root -p'MyRootPass123!' \
  -e "SHOW VARIABLES LIKE 'bind_address';"
# → 0.0.0.0 확인
```

### 문제 3: MySQL 초기화 중

```bash
# 초기화 진행 중일 수 있음 (최대 2분)
sudo docker logs -f mysql

# 다음 메시지 대기:
# "mysqld: ready for connections"

# 또는 ping 테스트
sudo docker exec mysql mysqladmin ping -h localhost -u root -p'MyRootPass123!'
# → mysqld is alive
```

---

## 💡 추가 팁

### 1. docker-compose 사용 (Optional)

```yaml
# /home/ec2-user/docker-compose.yml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: mysql
    restart: unless-stopped
    ports:
      - "3306:3306"
    volumes:
      - /data/mysql:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: MyRootPass123!
      MYSQL_DATABASE: feedbackdb
      MYSQL_USER: feedbackuser
      MYSQL_PASSWORD: FeedbackPass123!
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --bind-address=0.0.0.0
      - --max-connections=100
```

```bash
# docker-compose 설치
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 실행
cd /home/ec2-user
sudo docker-compose up -d

# 중지
sudo docker-compose down
```

### 2. MySQL 설정 파일 마운트 (고급)

```bash
# 커스텀 설정 파일 생성
cat > /home/ec2-user/my.cnf << 'EOF'
[mysqld]
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
bind-address=0.0.0.0
max-connections=100
innodb_buffer_pool_size=256M
EOF

# 설정 파일 마운트하여 실행
sudo docker run -d \
  --name mysql \
  -v /data/mysql:/var/lib/mysql \
  -v /home/ec2-user/my.cnf:/etc/mysql/conf.d/custom.cnf \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=MyRootPass123! \
  mysql:8.0
```

---

## 🎓 Phase 3 완료 체크리스트 (Docker 버전)

```
□ MySQL EC2 인스턴스 시작 (Public-AZ-A)
□ Private IP 확인 및 기록 ⭐⭐⭐
□ Docker 설치 완료
□ 데이터 볼륨 마운트 (/data/mysql)
□ MySQL 컨테이너 실행
□ feedbackdb 데이터베이스 생성 확인
□ feedbackuser 사용자 생성 확인
□ 외부 연결 테스트 성공
□ Security Group 원복 (app-sg만 허용)

총 소요 시간: 15분 (25분 절약!) ⭐
```

---

## 🎉 결론

**Docker 사용의 장점**:
```
✅ 25분 단축 (40분 → 15분)
✅ 설정 자동화 (환경변수)
✅ 간단한 관리 (docker 명령어)
✅ 빠른 백업/복원
✅ 쉬운 삭제 (docker rm -f)
✅ 설정 파일 작성 불필요
✅ 초기화 자동
```

**추천**:
- ✅ 5일 데모: Docker 강력 추천! ⭐⭐⭐
- ⚠️ 프로덕션: 직접 설치 또는 RDS 권장

**IMPLEMENTATION_GUIDE.md의 Phase 3을 이 방법으로 대체하면 됩니다!** 🚀
