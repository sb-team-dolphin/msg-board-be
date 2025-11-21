# Infrastructure Upgrade Plan: Production-Ready Architecture

**목표**: 단일 EC2 → High Availability + Monitoring
**핵심**: ALB + Auto Scaling + Prometheus/Grafana + MySQL on EC2
**제약**: RDS 제외 (비용 절감), EC2 베이스

---

## 📊 Executive Summary

### 현재 → 목표

| 항목 | 현재 (Phase 0) | 목표 (Phase 3) |
|------|---------------|---------------|
| **가용성** | 99% (SPOF) | 99.9%+ (Multi-AZ) |
| **확장성** | 수동 | 자동 (Auto Scaling) |
| **모니터링** | CloudWatch Logs | Grafana + Prometheus |
| **데이터베이스** | H2 (파일) | MySQL (EC2) |
| **서버 수** | 1대 | 2-4대 (자동 증감) |
| **로드 밸런싱** | 없음 | ALB |
| **비용** | $0/월 | ~$80-100/월 |

---

## 🏗️ 목표 아키텍처

```
                          Internet
                             │
                             ▼
                    ┌────────────────┐
                    │   Route 53     │ (선택)
                    │   (DNS)        │
                    └────────┬───────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                         VPC                                  │
│                   (10.0.0.0/16)                             │
│                                                              │
│  ┌──────────────── Public Subnets ─────────────────────┐   │
│  │                                                       │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │   Application Load Balancer (ALB)             │ │   │
│  │  │   - SSL/TLS Termination                       │ │   │
│  │  │   - Health Check                              │ │   │
│  │  │   - Port 80/443                               │ │   │
│  │  └──────────────┬─────────────────────────────────┘ │   │
│  │                 │                                    │   │
│  │  AZ-A           │           AZ-C                     │   │
│  │  10.0.1.0/24    │           10.0.2.0/24             │   │
│  └─────────────────┼────────────────────────────────────┘   │
│                    │                                         │
│  ┌─────────────────┼────────── Private Subnets ──────────┐  │
│  │                 │                                      │  │
│  │  AZ-A           │           AZ-C                       │  │
│  │  10.0.11.0/24   ▼           10.0.12.0/24              │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │     Auto Scaling Group (ASG)                   │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌─────────────┐       ┌─────────────┐        │  │  │
│  │  │  │   API       │       │   API       │        │  │  │
│  │  │  │  Server 1   │       │  Server 2   │        │  │  │
│  │  │  │  (EC2)      │       │  (EC2)      │        │  │  │
│  │  │  │  - Docker   │       │  - Docker   │        │  │  │
│  │  │  │  - App      │       │  - App      │        │  │  │
│  │  │  └──────┬──────┘       └──────┬──────┘        │  │  │
│  │  │         │                     │                │  │  │
│  │  │         └──────────┬──────────┘                │  │  │
│  │  └────────────────────┼───────────────────────────┘  │  │
│  │                       │                              │  │
│  │  ┌────────────────────▼──────────────────────────┐  │  │
│  │  │          MySQL Database Server                │  │  │
│  │  │          (EC2 - t3.small)                     │  │  │
│  │  │          AZ-A: 10.0.11.0/24                   │  │  │
│  │  │          - EBS Volume (100GB, gp3)            │  │  │
│  │  │          - 자동 백업 (S3)                      │  │  │
│  │  └───────────────────────────────────────────────┘  │  │
│  │                                                      │  │
│  │  ┌───────────────────────────────────────────────┐  │  │
│  │  │    Monitoring Server (EC2 - t3.small)        │  │  │
│  │  │    AZ-A: 10.0.11.0/24                        │  │  │
│  │  │    ┌─────────────────────────────────┐       │  │  │
│  │  │    │  Prometheus                     │       │  │  │
│  │  │    │  - Metrics Collection           │       │  │  │
│  │  │    │  - Alerting Rules               │       │  │  │
│  │  │    │  - Port 9090                    │       │  │  │
│  │  │    └─────────────────────────────────┘       │  │  │
│  │  │    ┌─────────────────────────────────┐       │  │  │
│  │  │    │  Grafana                        │       │  │  │
│  │  │    │  - Dashboards                   │       │  │  │
│  │  │    │  - Visualizations               │       │  │  │
│  │  │    │  - Port 3000                    │       │  │  │
│  │  │    └─────────────────────────────────┘       │  │  │
│  │  │    ┌─────────────────────────────────┐       │  │  │
│  │  │    │  Node Exporter                  │       │  │  │
│  │  │    │  - System Metrics               │       │  │  │
│  │  │    └─────────────────────────────────┘       │  │  │
│  │  └───────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                External Services                      │  │
│  │  - S3 (Backups)                                      │  │
│  │  - CloudWatch Logs                                   │  │
│  │  - Slack (Alerts)                                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 컴포넌트 상세 설계

### 1. VPC 및 네트워크 구조

#### VPC 설계
```yaml
VPC:
  CIDR: 10.0.0.0/16
  DNS: Enabled
  Region: ap-northeast-2 (Seoul)

  Availability Zones:
    - ap-northeast-2a
    - ap-northeast-2c
```

#### Subnet 설계
```yaml
Public Subnets (ALB용):
  - Public-AZ-A: 10.0.1.0/24  (ap-northeast-2a)
  - Public-AZ-C: 10.0.2.0/24  (ap-northeast-2c)
  - Internet Gateway 연결
  - Route: 0.0.0.0/0 → IGW

Private Subnets (Application용):
  - Private-App-AZ-A: 10.0.11.0/24 (ap-northeast-2a)
  - Private-App-AZ-C: 10.0.12.0/24 (ap-northeast-2c)
  - NAT Gateway 통해 외부 접근 (패키지 다운로드용)
  - Route: 0.0.0.0/0 → NAT Gateway

Private Subnets (Data/Monitoring용):
  - Private-Data-AZ-A: 10.0.21.0/24 (ap-northeast-2a)
  - MySQL Server
  - Monitoring Server
  - NAT Gateway 통해 외부 접근
```

#### NAT Gateway
```yaml
NAT Gateway:
  Location: Public-AZ-A (10.0.1.0/24)
  Purpose: Private subnet이 인터넷 접근 (outbound only)
  Cost: ~$32/월 + 데이터 전송 비용
```

---

### 2. Application Load Balancer (ALB)

#### 기본 설정
```yaml
Type: Application Load Balancer
Scheme: Internet-facing
IP Address Type: IPv4
Subnets:
  - Public-AZ-A (10.0.1.0/24)
  - Public-AZ-C (10.0.2.0/24)

Listeners:
  - Port: 80 (HTTP)
    Default Action: Forward to Target Group

  # 선택: HTTPS 설정
  - Port: 443 (HTTPS)
    SSL Certificate: ACM
    Default Action: Forward to Target Group

Security Group: alb-sg
```

#### Target Group 설정
```yaml
Target Group:
  Name: feedback-api-tg
  Protocol: HTTP
  Port: 8080
  VPC: feedback-vpc

  Health Check:
    Protocol: HTTP
    Path: /actuator/health
    Interval: 30s
    Timeout: 5s
    Healthy Threshold: 2
    Unhealthy Threshold: 3

  Targets:
    Type: Instance (Auto Scaling Group에서 자동 등록)

  Stickiness:
    Type: Load Balancer Cookie
    Duration: 1 hour (선택)
```

---

### 3. Auto Scaling Group (ASG)

#### Launch Template
```yaml
Launch Template:
  Name: feedback-api-lt
  AMI: Amazon Linux 2023
  Instance Type: t3.small

  User Data:
    #!/bin/bash
    # Docker 설치
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker

    # Docker Compose 설치
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # CloudWatch Agent 설치
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    rpm -U ./amazon-cloudwatch-agent.rpm

    # Prometheus Node Exporter 설치
    wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    tar xvfz node_exporter-*.tar.gz
    cd node_exporter-*/
    nohup ./node_exporter &

    # 애플리케이션 배포 디렉토리 생성
    mkdir -p /opt/feedback-api
    cd /opt/feedback-api

    # GHCR 로그인 (Secrets Manager에서 가져오기)
    aws secretsmanager get-secret-value --secret-id ghcr-credentials --region ap-northeast-2 --query SecretString --output text | jq -r '.password' | docker login ghcr.io -u $(aws secretsmanager get-secret-value --secret-id ghcr-credentials --region ap-northeast-2 --query SecretString --output text | jq -r '.username') --password-stdin

    # 최신 이미지 Pull
    docker pull ghcr.io/johnhuh619/simple-api:latest

    # 컨테이너 실행
    docker run -d \
      --name feedback-api \
      -p 8080:8080 \
      -e SPRING_PROFILES_ACTIVE=prod \
      -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.21.10:3306/feedbackdb \
      -e SPRING_DATASOURCE_USERNAME=feedbackuser \
      -e SPRING_DATASOURCE_PASSWORD=$(aws secretsmanager get-secret-value --secret-id db-password --region ap-northeast-2 --query SecretString --output text) \
      --restart unless-stopped \
      ghcr.io/johnhuh619/simple-api:latest

  IAM Instance Profile: ec2-instance-role
  Security Groups: app-sg

  Monitoring:
    Detailed Monitoring: Enabled
```

#### Auto Scaling Group 설정
```yaml
Auto Scaling Group:
  Name: feedback-api-asg
  Launch Template: feedback-api-lt

  VPC Subnets:
    - Private-App-AZ-A (10.0.11.0/24)
    - Private-App-AZ-C (10.0.12.0/24)

  Capacity:
    Minimum: 2
    Desired: 2
    Maximum: 4

  Health Check:
    Type: ELB
    Grace Period: 300s

  Target Groups:
    - feedback-api-tg

  Scaling Policies:
    # Scale Out (증가)
    - Name: scale-out-cpu
      Type: TargetTrackingScaling
      Metric: Average CPU Utilization
      Target: 70%
      Cooldown: 300s

    # Scale Out (요청 수)
    - Name: scale-out-requests
      Type: TargetTrackingScaling
      Metric: ALB Request Count Per Target
      Target: 1000 requests/target
      Cooldown: 300s

    # Scale In (감소)
    - Name: scale-in
      Type: TargetTrackingScaling
      Metric: Average CPU Utilization
      Target: 70%
      Scale In Cooldown: 600s

  Tags:
    - Key: Name
      Value: feedback-api-instance
      PropagateAtLaunch: true
```

---

### 4. MySQL Database Server (EC2)

#### 인스턴스 설정
```yaml
Instance:
  Type: t3.small
  AMI: Amazon Linux 2023
  Subnet: Private-Data-AZ-A (10.0.21.0/24)
  Private IP: 10.0.21.10 (고정)
  Security Group: db-sg

  EBS Volumes:
    - Root: 20GB (gp3)
    - Data: 100GB (gp3)
      Device: /dev/sdf
      Mount: /var/lib/mysql
      IOPS: 3000
      Throughput: 125 MB/s

  IAM Role: mysql-server-role

  Tags:
    Name: mysql-server
    Type: database
```

#### MySQL 설치 및 설정
```bash
#!/bin/bash

# MySQL 8.0 설치
sudo dnf install -y mysql-community-server

# 데이터 디렉토리 설정
sudo mkfs -t ext4 /dev/sdf
sudo mkdir /var/lib/mysql
sudo mount /dev/sdf /var/lib/mysql
echo '/dev/sdf /var/lib/mysql ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

# MySQL 초기화
sudo systemctl start mysqld
sudo systemctl enable mysqld

# root 비밀번호 설정
TEMP_PASSWORD=$(sudo grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
mysql -u root -p"$TEMP_PASSWORD" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewSecurePassword123!';"

# 데이터베이스 및 사용자 생성
mysql -u root -p"NewSecurePassword123!" << EOF
CREATE DATABASE feedbackdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'feedbackuser'@'10.0.%' IDENTIFIED BY 'SecureUserPassword123!';
GRANT ALL PRIVILEGES ON feedbackdb.* TO 'feedbackuser'@'10.0.%';
FLUSH PRIVILEGES;
EOF

# MySQL 설정 최적화
sudo tee -a /etc/my.cnf << EOF
[mysqld]
# 성능 최적화
max_connections = 200
innodb_buffer_pool_size = 512M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2

# 보안
bind-address = 10.0.21.10

# 로깅
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 2
log_error = /var/log/mysql/error.log

# 백업
log_bin = /var/lib/mysql/mysql-bin
expire_logs_days = 7
binlog_format = ROW
EOF

sudo systemctl restart mysqld
```

#### 자동 백업 스크립트
```bash
#!/bin/bash
# /opt/mysql-backup.sh

BACKUP_DIR="/opt/mysql-backups"
S3_BUCKET="s3://feedback-api-backups-396468676673/mysql"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

# mysqldump 백업
mysqldump -u root -p'NewSecurePassword123!' \
  --all-databases \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --routines \
  --triggers \
  --events \
  | gzip > "$BACKUP_DIR/backup_$TIMESTAMP.sql.gz"

# S3 업로드
aws s3 cp "$BACKUP_DIR/backup_$TIMESTAMP.sql.gz" \
  "$S3_BUCKET/$(date +%Y/%m/%d)/backup_$TIMESTAMP.sql.gz" \
  --storage-class STANDARD_IA

# 로컬 백업 정리 (7일 이상)
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: backup_$TIMESTAMP.sql.gz"
```

#### Cron 설정
```bash
# 매일 새벽 2시 백업
0 2 * * * /opt/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
```

---

### 5. Monitoring Server (Prometheus + Grafana)

#### 인스턴스 설정
```yaml
Instance:
  Type: t3.small
  AMI: Amazon Linux 2023
  Subnet: Private-Data-AZ-A (10.0.21.0/24)
  Private IP: 10.0.21.20 (고정)
  Security Group: monitoring-sg

  EBS Volume:
    - Root: 30GB (gp3)
    - Monitoring Data: 50GB (gp3)
      Device: /dev/sdf
      Mount: /opt/monitoring-data

  Tags:
    Name: monitoring-server
    Type: monitoring
```

#### Prometheus 설치 및 설정
```bash
#!/bin/bash

# Prometheus 설치
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
mv prometheus-* prometheus

# 설정 파일
cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'feedback-api'
    environment: 'production'

# Alertmanager 설정
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Alert Rules
rule_files:
  - "alerts.yml"

scrape_configs:
  # Prometheus 자체 모니터링
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # API 서버들 (Auto Scaling Group)
  - job_name: 'feedback-api'
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 9100
        filters:
          - name: tag:aws:autoscaling:groupName
            values:
              - feedback-api-asg
    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        target_label: instance
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id

  # MySQL Server
  - job_name: 'mysql'
    static_configs:
      - targets: ['10.0.21.10:9104']  # MySQL Exporter

  # Node Exporter (시스템 메트릭)
  - job_name: 'node'
    static_configs:
      - targets:
          - '10.0.21.10:9100'  # MySQL Server
          - '10.0.21.20:9100'  # Monitoring Server

  # Spring Boot Actuator (애플리케이션 메트릭)
  - job_name: 'spring-actuator'
    metrics_path: '/actuator/prometheus'
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 8080
        filters:
          - name: tag:aws:autoscaling:groupName
            values:
              - feedback-api-asg
EOF

# Alert Rules
cat > /opt/prometheus/alerts.yml << 'EOF'
groups:
  - name: instance
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} down"
          description: "{{ $labels.instance }} has been down for more than 5 minutes."

      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for 5 minutes."

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 85%."

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk space is below 20%."

  - name: application
    rules:
      - alert: HighErrorRate
        expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on {{ $labels.instance }}"
          description: "5xx error rate is above 5%."

      - alert: SlowResponseTime
        expr: histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow response time on {{ $labels.instance }}"
          description: "P95 response time is above 1 second."
EOF

# Systemd 서비스
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/monitoring-data/prometheus \
  --web.console.templates=/opt/prometheus/consoles \
  --web.console.libraries=/opt/prometheus/console_libraries \
  --storage.tsdb.retention.time=30d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 사용자 생성 및 권한
useradd -rs /bin/false prometheus
mkdir -p /opt/monitoring-data/prometheus
chown -R prometheus:prometheus /opt/prometheus /opt/monitoring-data/prometheus

# 서비스 시작
systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus
```

#### Grafana 설치 및 설정
```bash
#!/bin/bash

# Grafana 설치
cat > /etc/yum.repos.d/grafana.repo << 'EOF'
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

dnf install -y grafana

# Grafana 설정
cat > /etc/grafana/grafana.ini << 'EOF'
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = monitoring.yourdomain.com
root_url = http://monitoring.yourdomain.com

[security]
admin_user = admin
admin_password = SecureGrafanaPassword123!

[auth.anonymous]
enabled = false

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[session]
provider = file
provider_config = sessions

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info
EOF

# 서비스 시작
systemctl start grafana-server
systemctl enable grafana-server
```

#### Grafana 대시보드 자동 프로비저닝
```bash
# 데이터소스 설정
cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
EOF

# 대시보드 프로비저닝
mkdir -p /var/lib/grafana/dashboards

# Node Exporter Dashboard (ID: 1860)
# Spring Boot Dashboard (ID: 12900)
# MySQL Dashboard (ID: 7362)
```

---

### 6. Security Groups 설계

```yaml
# ALB Security Group
alb-sg:
  Ingress:
    - Port: 80 (HTTP)
      Source: 0.0.0.0/0
      Description: "Allow HTTP from internet"

    - Port: 443 (HTTPS)
      Source: 0.0.0.0/0
      Description: "Allow HTTPS from internet"

  Egress:
    - Port: 8080
      Destination: app-sg
      Description: "Forward to application servers"

# Application Server Security Group
app-sg:
  Ingress:
    - Port: 8080
      Source: alb-sg
      Description: "Allow traffic from ALB"

    - Port: 9100
      Source: monitoring-sg
      Description: "Prometheus Node Exporter"

    - Port: 22
      Source: bastion-sg (또는 특정 IP)
      Description: "SSH access"

  Egress:
    - Port: 3306
      Destination: db-sg
      Description: "MySQL connection"

    - Port: 443
      Destination: 0.0.0.0/0
      Description: "HTTPS outbound (package downloads)"

    - Port: 80
      Destination: 0.0.0.0/0
      Description: "HTTP outbound"

# Database Security Group
db-sg:
  Ingress:
    - Port: 3306
      Source: app-sg
      Description: "MySQL from application servers"

    - Port: 9104
      Source: monitoring-sg
      Description: "MySQL Exporter for Prometheus"

    - Port: 22
      Source: bastion-sg (또는 특정 IP)
      Description: "SSH access"

  Egress:
    - Port: 443
      Destination: 0.0.0.0/0
      Description: "S3 backup upload"

# Monitoring Security Group
monitoring-sg:
  Ingress:
    - Port: 9090
      Source: [Your IP] 또는 VPN
      Description: "Prometheus Web UI"

    - Port: 3000
      Source: [Your IP] 또는 VPN
      Description: "Grafana Web UI"

    - Port: 22
      Source: bastion-sg (또는 특정 IP)
      Description: "SSH access"

  Egress:
    - Port: 8080
      Destination: app-sg
      Description: "Scrape application metrics"

    - Port: 9100
      Destination: app-sg, db-sg
      Description: "Scrape node exporter"

    - Port: 9104
      Destination: db-sg
      Description: "Scrape MySQL exporter"

    - Port: 443
      Destination: 0.0.0.0/0
      Description: "AWS API calls"
```

---

## 💰 비용 분석

### 월간 비용 (ap-northeast-2)

```
┌──────────────────────────────────────────────────────┐
│ 컴포넌트                비용 계산                     │
├──────────────────────────────────────────────────────┤
│ ALB                                                   │
│   - 기본: $22.50/월                                  │
│   - LCU: ~$5/월 (저트래픽 기준)                      │
│   소계: $27.50/월                                    │
├──────────────────────────────────────────────────────┤
│ Auto Scaling Group (API Servers)                     │
│   - t3.small × 2: $30.37/월                         │
│   - EBS (20GB gp3 × 2): $3.20/월                    │
│   소계: $33.57/월                                    │
├──────────────────────────────────────────────────────┤
│ MySQL Server                                         │
│   - t3.small × 1: $15.18/월                         │
│   - EBS Root (20GB gp3): $1.60/월                   │
│   - EBS Data (100GB gp3): $8.00/월                  │
│   소계: $24.78/월                                    │
├──────────────────────────────────────────────────────┤
│ Monitoring Server                                    │
│   - t3.small × 1: $15.18/월                         │
│   - EBS Root (30GB gp3): $2.40/월                   │
│   - EBS Data (50GB gp3): $4.00/월                   │
│   소계: $21.58/월                                    │
├──────────────────────────────────────────────────────┤
│ NAT Gateway                                          │
│   - 기본: $32.85/월                                  │
│   - 데이터 전송: ~$5/월 (추정)                       │
│   소계: $37.85/월                                    │
├──────────────────────────────────────────────────────┤
│ S3 (백업)                                            │
│   - 스토리지: ~$1/월                                 │
│   - 요청: ~$0.10/월                                  │
│   소계: $1.10/월                                     │
├──────────────────────────────────────────────────────┤
│ CloudWatch (선택)                                    │
│   - Logs: $5/월                                     │
│   - Alarms: $1/월                                   │
│   소계: $6/월 (선택)                                │
├──────────────────────────────────────────────────────┤
│ **총계 (최소)**           $146.38/월                │
│ **총계 (CloudWatch 포함)** $152.38/월               │
└──────────────────────────────────────────────────────┘

참고:
- 프리티어는 만료된 것으로 가정
- 데이터 전송 비용은 트래픽에 따라 변동
- 예상 트래픽: 월 100GB 미만
```

### 비용 절감 옵션

```yaml
옵션 1: NAT Gateway 제거
  - Private subnet을 Public으로 변경
  - 보안 저하 (권장하지 않음)
  - 절감: -$37.85/월
  - 총 비용: ~$108/월

옵션 2: Monitoring Server 제거
  - CloudWatch만 사용
  - 기능 제한
  - 절감: -$21.58/월
  - 총 비용: ~$125/월

옵션 3: Auto Scaling 최소화
  - Min: 1, Max: 2로 설정
  - 가용성 저하
  - 절감: -$16.78/월
  - 총 비용: ~$129/월

추천:
  - 처음에는 옵션 3 적용 (Min: 1, Desired: 1, Max: 3)
  - 트래픽 증가 시 Min: 2로 변경
  - 예상 비용: ~$130/월
```

---

## 📋 단계별 구현 계획

### Phase 1: 네트워크 기반 구축 (1주)

#### Week 1-1: VPC 및 Subnet 생성
```bash
# Terraform 또는 AWS Console

# 1. VPC 생성
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=feedback-vpc}]'

# 2. Subnet 생성
# Public Subnets
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.1.0/24 --availability-zone ap-northeast-2a
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.2.0/24 --availability-zone ap-northeast-2c

# Private Subnets
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.11.0/24 --availability-zone ap-northeast-2a
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.12.0/24 --availability-zone ap-northeast-2c
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.21.0/24 --availability-zone ap-northeast-2a

# 3. Internet Gateway
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id vpc-xxx --internet-gateway-id igw-xxx

# 4. NAT Gateway
aws ec2 allocate-address --domain vpc
aws ec2 create-nat-gateway --subnet-id subnet-public-a --allocation-id eipalloc-xxx

# 5. Route Tables
# Public Route Table
aws ec2 create-route-table --vpc-id vpc-xxx
aws ec2 create-route --route-table-id rtb-xxx --destination-cidr-block 0.0.0.0/0 --gateway-id igw-xxx

# Private Route Table
aws ec2 create-route-table --vpc-id vpc-xxx
aws ec2 create-route --route-table-id rtb-xxx --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-xxx
```

#### Week 1-2: Security Groups 생성
```bash
# ALB Security Group
aws ec2 create-security-group --group-name alb-sg --description "ALB Security Group" --vpc-id vpc-xxx
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 443 --cidr 0.0.0.0/0

# Application Security Group
# Database Security Group
# Monitoring Security Group
# (위 Security Groups 설계 참조)
```

### Phase 2: 데이터베이스 마이그레이션 (1-2주)

#### Step 1: MySQL 서버 구축
```bash
# 1. EC2 인스턴스 시작 (Private-Data-AZ-A)
# 2. EBS 볼륨 추가 및 마운트
# 3. MySQL 8.0 설치 및 설정
# 4. 데이터베이스 생성
# 5. 백업 스크립트 설정
```

#### Step 2: H2 → MySQL 마이그레이션
```bash
# 1. H2 데이터 export
java -cp h2-*.jar org.h2.tools.Script \
  -url jdbc:h2:file:/app/data/feedbackdb \
  -user sa \
  -script backup.sql

# 2. SQL 변환 (H2 → MySQL 문법)
# - AUTO_INCREMENT 처리
# - TIMESTAMP 처리
# - 데이터 타입 변환

# 3. MySQL import
mysql -h 10.0.21.10 -u feedbackuser -p feedbackdb < converted.sql

# 4. 데이터 검증
```

#### Step 3: Application 설정 변경
```yaml
# application-prod.yml

spring:
  datasource:
    url: jdbc:mysql://10.0.21.10:3306/feedbackdb?useSSL=false&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
    username: feedbackuser
    password: ${DB_PASSWORD}  # Secrets Manager에서 주입
    driver-class-name: com.mysql.cj.jdbc.Driver

  jpa:
    database-platform: org.hibernate.dialect.MySQL8Dialect
    hibernate:
      ddl-auto: validate  # 프로덕션에서는 validate 또는 none
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.MySQL8Dialect
```

```xml
<!-- pom.xml 또는 build.gradle -->
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
    <scope>runtime</scope>
</dependency>
```

### Phase 3: 모니터링 서버 구축 (1주)

#### Step 1: Monitoring Server 설치
```bash
# 1. EC2 인스턴스 시작 (Private-Data-AZ-A)
# 2. Prometheus 설치 및 설정
# 3. Grafana 설치 및 설정
# 4. Alertmanager 설정 (선택)
```

#### Step 2: Application에 Prometheus Exporter 추가
```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

#### Step 3: 대시보드 구성
```bash
# Grafana에 다음 대시보드 import:
# - Node Exporter (ID: 1860)
# - Spring Boot 2.1 Statistics (ID: 12900)
# - MySQL Overview (ID: 7362)
```

### Phase 4: ALB + Auto Scaling 구축 (1-2주)

#### Step 1: Launch Template 생성
```bash
# User Data 스크립트 작성
# IAM Role 설정 (Secrets Manager, S3, CloudWatch 권한)
# Security Group 연결
```

#### Step 2: Target Group 생성
```bash
aws elbv2 create-target-group \
  --name feedback-api-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id vpc-xxx \
  --health-check-enabled \
  --health-check-path /actuator/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

#### Step 3: ALB 생성
```bash
aws elbv2 create-load-balancer \
  --name feedback-api-alb \
  --subnets subnet-public-a subnet-public-c \
  --security-groups sg-alb \
  --scheme internet-facing \
  --type application
```

#### Step 4: Auto Scaling Group 생성
```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name feedback-api-asg \
  --launch-template LaunchTemplateName=feedback-api-lt \
  --min-size 1 \
  --max-size 3 \
  --desired-capacity 1 \
  --vpc-zone-identifier "subnet-private-app-a,subnet-private-app-c" \
  --target-group-arns arn:aws:elasticloadbalancing:... \
  --health-check-type ELB \
  --health-check-grace-period 300
```

#### Step 5: Scaling Policy 생성
```bash
# CPU 기반 스케일링
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name feedback-api-asg \
  --policy-name cpu-scale-out \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration file://cpu-scaling.json
```

### Phase 5: CI/CD 파이프라인 업데이트 (2-3일)

#### deploy.yml 수정
```yaml
# .github/workflows/deploy.yml

# 기존: EC2에 직접 배포
# 새로: Auto Scaling Group 인스턴스 refresh

jobs:
  deploy:
    steps:
      # ... (빌드 및 이미지 푸시는 동일)

      - name: Update Launch Template
        run: |
          # 최신 이미지로 Launch Template 새 버전 생성
          aws ec2 create-launch-template-version \
            --launch-template-name feedback-api-lt \
            --source-version $Latest \
            --launch-template-data '{"ImageId":"'$NEW_AMI'"}'  # User Data에 이미지 버전 포함

      - name: Start Instance Refresh
        run: |
          aws autoscaling start-instance-refresh \
            --auto-scaling-group-name feedback-api-asg \
            --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'

      - name: Wait for Refresh Complete
        run: |
          # Instance Refresh 완료 대기
          # Health check 확인
```

---

## ⚠️ 주의사항 및 Best Practices

### 1. 데이터베이스 마이그레이션

```yaml
주의사항:
  - ⚠️ H2 → MySQL 마이그레이션 시 데이터 손실 위험
  - ⚠️ 데이터 타입 차이 (TIMESTAMP, AUTO_INCREMENT 등)
  - ⚠️ 트랜잭션 격리 수준 차이

권장 사항:
  ✅ 마이그레이션 전 전체 백업 (H2 파일 + SQL export)
  ✅ 테스트 환경에서 먼저 시도
  ✅ 데이터 검증 스크립트 작성
  ✅ 롤백 계획 수립
```

### 2. MySQL on EC2 운영

```yaml
백업 전략:
  ✅ 매일 자동 백업 (mysqldump + S3)
  ✅ Binary log 활성화 (Point-in-time recovery)
  ✅ 백업 테스트 (복원 가능 여부 확인)

보안:
  ✅ root 계정 비밀번호 강력하게
  ✅ 애플리케이션용 계정 분리
  ✅ bind-address로 private IP만 바인딩
  ✅ Secrets Manager로 비밀번호 관리

모니터링:
  ✅ 디스크 사용률 (자동 증가 설정)
  ✅ Slow query log 활성화
  ✅ Connection pool 모니터링

고가용성 한계:
  ⚠️ 단일 서버 (SPOF)
  ⚠️ 장애 시 수동 복구 필요
  ⚠️ Failover 자동화 없음

  → 향후 RDS로 전환 고려 (Multi-AZ)
```

### 3. Auto Scaling 운영

```yaml
초기 설정:
  - Min: 1, Desired: 1, Max: 3
  - 트래픽 패턴 파악 후 조정

Warm-up 시간:
  - 300초 설정 (애플리케이션 시작 시간 고려)
  - 너무 짧으면 불필요한 스케일링

Health Check:
  - Grace Period: 300초
  - ALB Health Check + Instance Health Check 모두 활용

Rolling Update:
  - MinHealthyPercentage: 50% 이상
  - 무중단 배포 보장
```

### 4. 비용 최적화

```yaml
절감 방안:
  ✅ Reserved Instance (1년 약정 시 ~40% 절감)
  ✅ Savings Plans
  ✅ Spot Instance (개발/테스트 환경)
  ✅ Auto Scaling으로 피크 타임만 증가
  ✅ 불필요한 시간대 Min:0 설정 (선택)

모니터링:
  ✅ AWS Budgets 설정 ($150/월 알림)
  ✅ Cost Explorer로 주간 리뷰
  ✅ 사용하지 않는 리소스 정리
```

### 5. 보안 Best Practices

```yaml
네트워크:
  ✅ Private subnet에 애플리케이션/DB 배치
  ✅ NAT Gateway로 outbound만 허용
  ✅ Security Group을 최소 권한으로

인증/권한:
  ✅ IAM Role 사용 (Access Key 금지)
  ✅ Secrets Manager로 비밀번호 관리
  ✅ 정기적인 비밀번호 rotation

접근 제어:
  ✅ Bastion Host 또는 Session Manager 사용
  ✅ SSH 키 관리
  ✅ CloudTrail로 API 호출 감사
```

---

## 🚀 마이그레이션 체크리스트

### 사전 준비
- [ ] 현재 H2 데이터 전체 백업
- [ ] S3에 백업 업로드
- [ ] 팀원들에게 마이그레이션 일정 공지
- [ ] 롤백 계획 수립

### Phase 1: 네트워크 (1주)
- [ ] VPC 생성
- [ ] Subnet 생성 (Public × 2, Private × 3)
- [ ] Internet Gateway 설정
- [ ] NAT Gateway 설정
- [ ] Route Table 설정
- [ ] Security Group 생성 (4개)

### Phase 2: 데이터베이스 (1-2주)
- [ ] MySQL EC2 인스턴스 시작
- [ ] EBS 볼륨 추가 및 마운트
- [ ] MySQL 8.0 설치
- [ ] 데이터베이스 및 사용자 생성
- [ ] H2 데이터 export
- [ ] MySQL로 데이터 import
- [ ] 데이터 검증
- [ ] 백업 스크립트 설정
- [ ] Cron 백업 자동화

### Phase 3: 모니터링 (1주)
- [ ] Monitoring EC2 인스턴스 시작
- [ ] Prometheus 설치 및 설정
- [ ] Grafana 설치 및 설정
- [ ] Alert Rules 설정
- [ ] Slack 알림 연동
- [ ] 대시보드 구성
- [ ] Application에 Prometheus endpoint 추가

### Phase 4: ALB + ASG (1-2주)
- [ ] Launch Template 작성
- [ ] User Data 스크립트 작성
- [ ] IAM Role 설정
- [ ] Target Group 생성
- [ ] ALB 생성
- [ ] Listener 설정
- [ ] Auto Scaling Group 생성
- [ ] Scaling Policy 설정
- [ ] 테스트 (스케일 in/out)

### Phase 5: CI/CD 업데이트 (2-3일)
- [ ] deploy.yml 수정 (Instance Refresh)
- [ ] rollback.yml 수정
- [ ] 테스트 배포
- [ ] 무중단 배포 검증

### Phase 6: 최종 검증 및 전환
- [ ] 전체 시스템 테스트
- [ ] 성능 테스트
- [ ] 장애 시나리오 테스트
- [ ] 모니터링 대시보드 확인
- [ ] 알람 테스트
- [ ] 팀 교육
- [ ] 운영 문서 작성
- [ ] 기존 단일 EC2 종료

---

## 📖 다음 단계

### 즉시 시작 가능
1. **VPC 설계 리뷰** - 팀과 네트워크 구조 최종 확인
2. **비용 승인** - 월 $130-150 예산 확보
3. **마이그레이션 일정** - 4-6주 일정 수립

### 추가 문서 필요 시
- [ ] Terraform 코드 작성 (IaC)
- [ ] 상세 운영 매뉴얼
- [ ] 장애 대응 가이드
- [ ] 롤백 절차서

---

## 💬 질문 및 답변

### Q1: RDS 없이 MySQL on EC2, 위험하지 않나요?
**A**:
- 적절한 백업 전략이 있으면 괜찮습니다
- 매일 자동 백업 + S3 업로드
- Binary log로 Point-in-time recovery 가능
- 단, 고가용성은 제한적 (수동 failover)
- 트래픽 증가 시 RDS 전환 고려

### Q2: NAT Gateway 비용이 부담스러운데?
**A**:
- NAT Gateway: ~$38/월 (가장 비싼 항목 중 하나)
- 대안: NAT Instance (t3.nano ~$4/월)
  - 관리 부담 증가
  - 성능 제한
- 또는 Public subnet 사용 (보안 저하)

권장: 초기에는 NAT Gateway 사용, 안정화 후 NAT Instance로 전환 고려

### Q3: Auto Scaling Min:1로 시작해도 되나요?
**A**:
- 네, 가능합니다
- 초기 트래픽이 적으면 Min:1, Max:3 권장
- 장점: 비용 절감 (~$16/월)
- 단점: 단일 서버 중단 시 잠깐 다운타임
- 트래픽 증가 시 Min:2로 변경

### Q4: Prometheus/Grafana 대신 CloudWatch만?
**A**:
- CloudWatch는 기본 메트릭만 제공
- Prometheus/Grafana 장점:
  - 애플리케이션 메트릭 (JVM, 응답시간 등)
  - 커스텀 대시보드
  - 더 상세한 쿼리
- 비용: Monitoring Server ~$22/월
- 선택: CloudWatch + Grafana 조합 가능

### Q5: 전체 작업 기간은?
**A**:
```
단계별 소요 시간:
- Phase 1 (네트워크): 1주
- Phase 2 (DB): 1-2주
- Phase 3 (모니터링): 1주
- Phase 4 (ALB+ASG): 1-2주
- Phase 5 (CI/CD): 2-3일

총 예상 기간: 4-6주
병렬 작업 시: 3-4주 가능
```

---

**준비되셨으면 바로 시작하시죠! 🚀**

각 단계별 상세 가이드가 필요하면 말씀해주세요.
