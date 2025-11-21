#!/bin/bash
# ECS 인프라 자동 구축 스크립트 (Phase 2-5)

set -e

echo "======================================"
echo "ECS 인프라 자동 구축"
echo "======================================"
echo ""

# 변수 설정
CLUSTER_NAME="simple-api-cluster"
SERVICE_NAME="simple-api-service"
TASK_FAMILY="simple-api-task"
ECR_REPO="simple-api"
REGION="ap-northeast-2"

# VPC 정보 (수동 입력 필요)
read -p "VPC ID 입력: " VPC_ID
read -p "Subnet ID 1 입력: " SUBNET_1
read -p "Subnet ID 2 입력: " SUBNET_2
read -p "RDS Security Group ID 입력: " RDS_SG_ID

echo ""
echo "======================================"
echo "Phase 2: ECR 레포지토리 생성"
echo "======================================"

# ECR 레포지토리 생성
echo "📦 ECR 레포지토리 생성 중..."
ECR_URI=$(aws ecr create-repository \
  --repository-name $ECR_REPO \
  --region $REGION \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --query 'repository.repositoryUri' \
  --output text 2>/dev/null || \
  aws ecr describe-repositories \
    --repository-names $ECR_REPO \
    --region $REGION \
    --query 'repositories[0].repositoryUri' \
    --output text)

echo "✅ ECR Repository: $ECR_URI"

# Lifecycle Policy
echo "📝 Lifecycle Policy 설정 중..."
aws ecr put-lifecycle-policy \
  --repository-name $ECR_REPO \
  --region $REGION \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {"type": "expire"}
    }]
  }' > /dev/null

echo "✅ Lifecycle Policy 설정 완료"
echo ""

echo "======================================"
echo "Phase 3: ECS 클러스터 구성"
echo "======================================"

# ECS 클러스터 생성
echo "🏗️  ECS 클러스터 생성 중..."
aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --capacity-providers FARGATE FARGATE_SPOT \
  --region $REGION \
  > /dev/null 2>&1 || echo "클러스터가 이미 존재합니다"

echo "✅ ECS Cluster: $CLUSTER_NAME"

# Task Execution Role
echo "📝 Task Execution Role 생성 중..."
ROLE_NAME="ecsTaskExecutionRole"

cat > /tmp/ecs-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
  > /dev/null 2>&1 || echo "Role이 이미 존재합니다"

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  > /dev/null 2>&1 || true

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EXECUTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "✅ Execution Role: $EXECUTION_ROLE_ARN"

# CloudWatch Logs
echo "📝 CloudWatch Logs 그룹 생성 중..."
aws logs create-log-group \
  --log-group-name /ecs/$TASK_FAMILY \
  --region $REGION \
  > /dev/null 2>&1 || echo "Log Group이 이미 존재합니다"

echo "✅ CloudWatch Logs: /ecs/$TASK_FAMILY"
echo ""

echo "======================================"
echo "Phase 4: ALB 생성"
echo "======================================"

# ALB Security Group
echo "🔒 ALB Security Group 생성 중..."
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name simple-api-alb-sg \
  --description "Simple API ALB Security Group" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=simple-api-alb-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# ALB Inbound 규칙
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  > /dev/null 2>&1 || true

echo "✅ ALB Security Group: $ALB_SG_ID"

# ALB 생성
echo "🌐 ALB 생성 중..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name simple-api-alb \
  --subnets $SUBNET_1 $SUBNET_2 \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || \
  aws elbv2 describe-load-balancers \
    --names simple-api-alb \
    --region $REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "✅ ALB DNS: $ALB_DNS"

# Target Group
echo "🎯 Target Group 생성 중..."
TG_ARN=$(aws elbv2 create-target-group \
  --name simple-api-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path /actuator/health \
  --health-check-interval-seconds 30 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null || \
  aws elbv2 describe-target-groups \
    --names simple-api-tg \
    --region $REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "✅ Target Group: $TG_ARN"

# Listener
echo "👂 Listener 생성 중..."
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION \
  > /dev/null 2>&1 || echo "Listener가 이미 존재합니다"

echo "✅ Listener 생성 완료"
echo ""

echo "======================================"
echo "Phase 5: ECS Service 생성"
echo "======================================"

# ECS Task Security Group
echo "🔒 ECS Task Security Group 생성 중..."
ECS_SG_ID=$(aws ec2 create-security-group \
  --group-name simple-api-ecs-sg \
  --description "Simple API ECS Tasks Security Group" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=simple-api-ecs-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# ECS Task Inbound (from ALB)
aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SG_ID \
  > /dev/null 2>&1 || true

# RDS Inbound (from ECS)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $ECS_SG_ID \
  > /dev/null 2>&1 || true

echo "✅ ECS Security Group: $ECS_SG_ID"
echo ""

echo "======================================"
echo "✅ 인프라 구축 완료!"
echo "======================================"
echo ""
echo "📋 생성된 리소스:"
echo "  - ECR Repository: $ECR_URI"
echo "  - ECS Cluster: $CLUSTER_NAME"
echo "  - ALB DNS: $ALB_DNS"
echo "  - Target Group: $TG_ARN"
echo "  - ECS Security Group: $ECS_SG_ID"
echo "  - ALB Security Group: $ALB_SG_ID"
echo ""
echo "📝 다음 단계:"
echo "1. Secrets Manager에 DB 정보 저장:"
echo "   aws secretsmanager create-secret --name simple-api/db-host --secret-string 'your-rds-endpoint'"
echo "   aws secretsmanager create-secret --name simple-api/db-password --secret-string 'your-password'"
echo ""
echo "2. Task Definition 등록:"
echo "   aws ecs register-task-definition --cli-input-json file://task-definition.json"
echo ""
echo "3. ECS Service 생성:"
echo "   aws ecs create-service --cli-input-json file://service-definition.json"
echo ""
echo "4. GitHub Actions 워크플로우 업데이트"
echo ""
echo "5. CloudFront Origin을 ALB DNS로 변경:"
echo "   Origin: $ALB_DNS"
echo ""

# 정리
rm -f /tmp/ecs-trust-policy.json

echo "스크립트 완료!"
