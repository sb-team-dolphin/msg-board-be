#!/bin/bash

# RDS MySQL 빠른 생성 스크립트
# EC2 기반 단순 백엔드용

set -e

echo "======================================"
echo "RDS MySQL Quick Setup"
echo "======================================"

# 설정
DB_INSTANCE_ID="feedback-db"
DB_NAME="feedbackdb"
DB_USERNAME="feedbackuser"
DB_PASSWORD="FeedbackPass123!"  # ⚠️ 실제 운영에서는 안전한 비밀번호 사용!
DB_INSTANCE_CLASS="db.t3.micro"  # Free Tier
ALLOCATED_STORAGE=20  # GB (Free Tier: 20GB)

echo ""
echo "Configuration:"
echo "  Instance ID: $DB_INSTANCE_ID"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USERNAME"
echo "  Instance Class: $DB_INSTANCE_CLASS"
echo ""

# Step 1: 기본 VPC의 Subnet Group 확인/생성
echo "[1/5] Setting up DB Subnet Group..."

# 기본 VPC ID 가져오기
DEFAULT_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

echo "   Default VPC: $DEFAULT_VPC"

# 기본 VPC의 모든 서브넷 가져오기
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
  --query "Subnets[*].SubnetId" \
  --output text)

echo "   Subnets: $SUBNET_IDS"

# DB Subnet Group 생성 (이미 있으면 스킵)
aws rds create-db-subnet-group \
  --db-subnet-group-name feedback-db-subnet \
  --db-subnet-group-description "Feedback app DB subnet group" \
  --subnet-ids $SUBNET_IDS 2>/dev/null || echo "   Subnet group already exists"

echo "   ✅ DB Subnet Group ready"

# Step 2: Security Group 생성
echo ""
echo "[2/5] Creating Security Group for RDS..."

# EC2의 Public IP 가져오기 (선택사항)
echo "   Enter your EC2 instance ID (or press Enter to allow all VPC access):"
read EC2_INSTANCE_ID

if [ -n "$EC2_INSTANCE_ID" ]; then
  EC2_SG=$(aws ec2 describe-instances \
    --instance-ids $EC2_INSTANCE_ID \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "")

  if [ -n "$EC2_SG" ]; then
    echo "   EC2 Security Group: $EC2_SG"
  fi
fi

# RDS Security Group 생성
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name feedback-rds-sg \
  --description "Security group for Feedback RDS instance" \
  --vpc-id $DEFAULT_VPC \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=feedback-rds-sg" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

echo "   RDS Security Group: $RDS_SG_ID"

# MySQL 포트 개방 (3306)
if [ -n "$EC2_SG" ]; then
  # EC2 Security Group에서만 접근 허용
  aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG_ID \
    --protocol tcp \
    --port 3306 \
    --source-group $EC2_SG 2>/dev/null || echo "   Rule already exists"
  echo "   ✅ MySQL access allowed from EC2 security group"
else
  # VPC CIDR에서 접근 허용
  VPC_CIDR=$(aws ec2 describe-vpcs \
    --vpc-ids $DEFAULT_VPC \
    --query "Vpcs[0].CidrBlock" \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG_ID \
    --protocol tcp \
    --port 3306 \
    --cidr $VPC_CIDR 2>/dev/null || echo "   Rule already exists"
  echo "   ✅ MySQL access allowed from VPC ($VPC_CIDR)"
fi

# Step 3: RDS 인스턴스 생성
echo ""
echo "[3/5] Creating RDS MySQL instance..."
echo "   ⏳ This may take 5-10 minutes..."

aws rds create-db-instance \
  --db-instance-identifier $DB_INSTANCE_ID \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username $DB_USERNAME \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage $ALLOCATED_STORAGE \
  --db-name $DB_NAME \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-subnet-group-name feedback-db-subnet \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --storage-encrypted \
  --publicly-accessible false \
  --no-multi-az \
  --storage-type gp3 \
  --tags Key=Name,Value=feedback-database Key=Environment,Value=production 2>/dev/null || echo "   Instance already exists"

# Step 4: RDS 인스턴스 생성 대기
echo ""
echo "[4/5] Waiting for RDS instance to be available..."
echo "   This typically takes 5-10 minutes. You can continue and check back later."
echo ""

aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE_ID \
  --no-cli-pager &

WAIT_PID=$!

# 진행 상황 표시
while kill -0 $WAIT_PID 2>/dev/null; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier $DB_INSTANCE_ID \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null || echo "creating")

  echo "   Status: $STATUS..."
  sleep 15
done

wait $WAIT_PID

echo "   ✅ RDS instance is available!"

# Step 5: Endpoint 정보 가져오기
echo ""
echo "[5/5] Getting RDS endpoint..."

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_ID \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

RDS_PORT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_ID \
  --query "DBInstances[0].Endpoint.Port" \
  --output text)

echo ""
echo "======================================"
echo "✅ RDS Setup Complete!"
echo "======================================"
echo ""
echo "Connection Details:"
echo "  Endpoint: $RDS_ENDPOINT"
echo "  Port: $RDS_PORT"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USERNAME"
echo "  Password: $DB_PASSWORD"
echo ""
echo "JDBC URL:"
echo "  jdbc:mysql://${RDS_ENDPOINT}:${RDS_PORT}/${DB_NAME}?useSSL=false&serverTimezone=Asia/Seoul"
echo ""

# 환경 변수 파일 생성
cat > rds-config.env <<EOF
export RDS_ENDPOINT=$RDS_ENDPOINT
export RDS_PORT=$RDS_PORT
export RDS_DATABASE=$DB_NAME
export RDS_USERNAME=$DB_USERNAME
export RDS_PASSWORD=$DB_PASSWORD
export JDBC_URL=jdbc:mysql://${RDS_ENDPOINT}:${RDS_PORT}/${DB_NAME}?useSSL=false&serverTimezone=Asia/Seoul
EOF

echo "Configuration saved to: rds-config.env"
echo "Load with: source rds-config.env"
echo ""

echo "Next steps:"
echo "  1. Update application-prod.yml with RDS endpoint"
echo "  2. Rebuild and redeploy backend"
echo "  3. Test database connection"
echo ""

# application-prod.yml 업데이트 예시 출력
echo "======================================"
echo "Update application-prod.yml:"
echo "======================================"
cat <<YAML
spring:
  datasource:
    url: jdbc:mysql://${RDS_ENDPOINT}:${RDS_PORT}/${DB_NAME}?useSSL=false&serverTimezone=Asia/Seoul
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
YAML
echo ""
