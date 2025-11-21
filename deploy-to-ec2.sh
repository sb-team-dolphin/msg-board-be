#!/bin/bash

# EC2 Deployment Script for Feedback API
# Usage: ./deploy-to-ec2.sh <EC2_HOST> <EC2_USER> <PEM_FILE>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Arguments
EC2_HOST=${1:-""}
EC2_USER=${2:-"ec2-user"}
PEM_FILE=${3:-""}

if [ -z "$EC2_HOST" ] || [ -z "$PEM_FILE" ]; then
    echo -e "${RED}Usage: $0 <EC2_HOST> <EC2_USER> <PEM_FILE>${NC}"
    echo "Example: $0 ec2-13-124-123-123.ap-northeast-2.compute.amazonaws.com ec2-user ~/.ssh/my-key.pem"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Feedback API - EC2 Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Target: $EC2_USER@$EC2_HOST"
echo ""

# Step 1: Build Docker image locally
echo -e "${YELLOW}[1/5] Building Docker image locally...${NC}"
docker build -t feedback-api:latest .

# Step 2: Save Docker image to tar file
echo -e "${YELLOW}[2/5] Saving Docker image to tar file...${NC}"
docker save -o feedback-api.tar feedback-api:latest

# Step 3: Transfer files to EC2
echo -e "${YELLOW}[3/5] Transferring files to EC2...${NC}"
scp -i "$PEM_FILE" feedback-api.tar "$EC2_USER@$EC2_HOST:~/"
scp -i "$PEM_FILE" docker-compose.yml "$EC2_USER@$EC2_HOST:~/"

# Step 4: SSH into EC2 and setup
echo -e "${YELLOW}[4/5] Setting up Docker on EC2...${NC}"
ssh -i "$PEM_FILE" "$EC2_USER@$EC2_HOST" << 'ENDSSH'
    # Install Docker if not installed
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        sudo yum update -y
        sudo yum install -y docker
        sudo service docker start
        sudo usermod -a -G docker ec2-user
    fi

    # Install Docker Compose if not installed
    if ! command -v docker-compose &> /dev/null; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    # Load Docker image
    echo "Loading Docker image..."
    docker load -i feedback-api.tar

    # Create directories for volumes
    mkdir -p data logs

    # Stop existing container if running
    if [ "$(docker ps -q -f name=feedback-api)" ]; then
        echo "Stopping existing container..."
        docker-compose down
    fi

    # Start new container
    echo "Starting new container..."
    docker-compose up -d

    # Cleanup
    rm feedback-api.tar

    echo ""
    echo "Deployment completed!"
    echo "Service is running on http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
ENDSSH

# Step 5: Cleanup local tar file
echo -e "${YELLOW}[5/5] Cleaning up...${NC}"
rm feedback-api.tar

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Deployment Successful!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Your application is now running on EC2!"
echo "Access it at: http://$EC2_HOST:8080"
echo ""
echo "Useful commands:"
echo "  View logs:    ssh -i $PEM_FILE $EC2_USER@$EC2_HOST 'docker-compose logs -f'"
echo "  Stop service: ssh -i $PEM_FILE $EC2_USER@$EC2_HOST 'docker-compose down'"
echo "  Restart:      ssh -i $PEM_FILE $EC2_USER@$EC2_HOST 'docker-compose restart'"
echo ""
