#!/bin/bash

# EC2에서 실행하는 스크립트
# RDS와 함께 백엔드 Docker 컨테이너 배포

set -e

echo "======================================"
echo "Deploy Backend to EC2 with RDS"
echo "======================================"

# RDS 정보 입력
echo ""
echo "Enter RDS connection details:"
echo ""

read -p "RDS Endpoint (e.g., feedback-db.xxxxx.rds.amazonaws.com): " DB_HOST
read -p "Database Port (default: 3306): " DB_PORT
DB_PORT=${DB_PORT:-3306}
read -p "Database Name (default: feedbackdb): " DB_NAME
DB_NAME=${DB_NAME:-feedbackdb}
read -p "Database Username (default: feedbackuser): " DB_USER
DB_USER=${DB_USER:-feedbackuser}
read -sp "Database Password: " DB_PASSWORD
echo ""

# Docker 이미지
read -p "Docker Image (default: ghcr.io/johnhuh619/simple-api:latest): " DOCKER_IMAGE
DOCKER_IMAGE=${DOCKER_IMAGE:-ghcr.io/johnhuh619/simple-api:latest}

echo ""
echo "Configuration:"
echo "  RDS Host: $DB_HOST"
echo "  RDS Port: $DB_PORT"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USER"
echo "  Docker Image: $DOCKER_IMAGE"
echo ""

# 확인
read -p "Continue with deployment? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 0
fi

# Step 1: 기존 컨테이너 중지
echo ""
echo "[1/5] Stopping existing container..."
sudo docker stop feedback-api 2>/dev/null || echo "   No running container found"
sudo docker rm feedback-api 2>/dev/null || echo "   No container to remove"

# Step 2: 최신 이미지 pull
echo ""
echo "[2/5] Pulling latest Docker image..."
sudo docker pull $DOCKER_IMAGE

# Step 3: 새 컨테이너 시작
echo ""
echo "[3/5] Starting new container..."
sudo docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  $DOCKER_IMAGE

echo "   ✅ Container started"

# Step 4: 헬스 체크 대기
echo ""
echo "[4/5] Waiting for application to be ready..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo "   ✅ Application is healthy!"
    break
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "   Waiting... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "   ⚠️  Health check timeout. Checking logs..."
  sudo docker logs --tail 50 feedback-api
  exit 1
fi

# Step 5: 테스트
echo ""
echo "[5/5] Testing endpoints..."

# Health check
echo "   Testing /actuator/health..."
curl -s http://localhost:8080/actuator/health | head -5

# API check
echo ""
echo "   Testing /api/feedbacks..."
curl -s http://localhost:8080/api/feedbacks | head -10

echo ""
echo ""
echo "======================================"
echo "✅ Deployment Complete!"
echo "======================================"
echo ""
echo "Application is running on:"
echo "  Health: http://localhost:8080/actuator/health"
echo "  API: http://localhost:8080/api/feedbacks"
echo ""
echo "View logs:"
echo "  sudo docker logs -f feedback-api"
echo ""
echo "Stop application:"
echo "  sudo docker stop feedback-api"
echo ""
