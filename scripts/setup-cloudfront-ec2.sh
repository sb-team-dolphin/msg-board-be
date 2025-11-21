#!/bin/bash

# CloudFront + S3 Setup for EC2 Backend (no ALB)
# 간소화된 버전: EC2 직접 연결

set -e

echo "======================================"
echo "CloudFront + S3 Setup (EC2 Direct)"
echo "======================================"

# 설정
AWS_REGION="ap-northeast-2"
BUCKET_PREFIX="feedback-frontend"
COMMENT="feedback-app-frontend"

# Step 1: EC2 정보 입력
echo ""
echo "[1/6] EC2 Backend Information"
echo ""
echo "Enter your EC2 instance details:"
echo ""

# EC2 Public DNS 또는 IP 입력
echo "Enter EC2 Public DNS or IP (e.g., ec2-13-125-123-45.ap-northeast-2.compute.amazonaws.com):"
read EC2_BACKEND

if [ -z "$EC2_BACKEND" ]; then
  echo "❌ EC2 backend address is required!"
  echo ""
  echo "To find your EC2 public DNS:"
  echo "  aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,PublicDnsName,State.Name]' --output table"
  echo ""
  echo "Or use AWS Console:"
  echo "  EC2 → Instances → Select instance → Copy 'Public IPv4 DNS'"
  exit 1
fi

echo ""
echo "Backend: $EC2_BACKEND"
echo ""

# Backend port 입력
echo "Enter backend port (default: 8080):"
read BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-8080}

echo "Port: $BACKEND_PORT"

# Step 2: S3 버킷 생성
echo ""
echo "[2/6] Creating S3 bucket..."
BUCKET_NAME="${BUCKET_PREFIX}-$(date +%s)"
echo "   Bucket name: $BUCKET_NAME"

aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

echo "   ✅ Bucket created"

# Step 3: Origin Access Control (OAC) 생성
echo ""
echo "[3/6] Creating Origin Access Control..."

OAC_CONFIG='{
  "Name": "feedback-s3-oac",
  "Description": "OAC for feedback frontend S3 bucket",
  "SigningProtocol": "sigv4",
  "SigningBehavior": "always",
  "OriginAccessControlOriginType": "s3"
}'

OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config "$OAC_CONFIG" \
  --query "OriginAccessControl.Id" \
  --output text 2>/dev/null || \
  aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='feedback-s3-oac'].Id | [0]" \
    --output text)

echo "   OAC ID: $OAC_ID"

# Step 4: CloudFront Distribution 생성
echo ""
echo "[4/6] Creating CloudFront distribution..."
echo "   This may take 10-15 minutes..."

CALLER_REF="feedback-frontend-$(date +%s)"

# CloudFront 설정 생성
DISTRIBUTION_CONFIG=$(cat <<EOF
{
  "CallerReference": "$CALLER_REF",
  "Comment": "$COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "S3-frontend",
        "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
        "OriginPath": "",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        },
        "OriginAccessControlId": "$OAC_ID",
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10
      },
      {
        "Id": "EC2-backend",
        "DomainName": "$EC2_BACKEND",
        "OriginPath": "",
        "CustomOriginConfig": {
          "HTTPPort": $BACKEND_PORT,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          },
          "OriginReadTimeout": 30,
          "OriginKeepaliveTimeout": 5
        },
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-frontend",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [
      {
        "PathPattern": "/api/*",
        "TargetOriginId": "EC2-backend",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
          "Quantity": 7,
          "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
          "CachedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"]
          }
        },
        "Compress": true,
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3"
      }
    ]
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      {
        "ErrorCode": 403,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      },
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 300
      }
    ]
  },
  "PriceClass": "PriceClass_100",
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true,
    "MinimumProtocolVersion": "TLSv1.2_2021"
  }
}
EOF
)

# Distribution 생성
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --distribution-config "$DISTRIBUTION_CONFIG" \
  --query "Distribution.Id" \
  --output text)

echo "   Distribution ID: $DISTRIBUTION_ID"

# CloudFront 도메인 가져오기
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query "Distribution.DomainName" \
  --output text)

echo "   CloudFront domain: $CLOUDFRONT_DOMAIN"

# Step 5: S3 버킷 정책 업데이트
echo ""
echo "[5/6] Updating S3 bucket policy..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF
)

echo "$BUCKET_POLICY" > /tmp/bucket-policy.json
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/bucket-policy.json

echo "   ✅ Bucket policy updated"

# Step 6: 프론트엔드 파일 업로드
echo ""
echo "[6/6] Uploading frontend files..."

if [ -d "frontend" ]; then
  cd frontend
  aws s3 sync . s3://$BUCKET_NAME/ \
    --exclude "*.sh" \
    --exclude ".git*" \
    --cache-control "public, max-age=31536000" \
    --exclude "index.html"

  aws s3 cp index.html s3://$BUCKET_NAME/index.html \
    --cache-control "public, max-age=300" \
    --content-type "text/html"

  cd ..
  echo "   ✅ Files uploaded"
else
  echo "   ⚠️  frontend/ directory not found, skipping upload"
fi

# Summary
echo ""
echo "======================================"
echo "✅ Setup Complete!"
echo "======================================"
echo ""
echo "Resources:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  CloudFront Distribution: $DISTRIBUTION_ID"
echo "  CloudFront Domain: $CLOUDFRONT_DOMAIN"
echo "  Backend: $EC2_BACKEND:$BACKEND_PORT"
echo ""
echo "URLs:"
echo "  Frontend: https://$CLOUDFRONT_DOMAIN"
echo "  API: https://$CLOUDFRONT_DOMAIN/api/feedbacks"
echo ""
echo "⏳ CloudFront is deploying (10-15 minutes)"
echo ""
echo "Check deployment status:"
echo "  aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status'"
echo ""

# 설정 파일 저장
cat > cloudfront-config.env <<EOF
export CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID
export CLOUDFRONT_DOMAIN=$CLOUDFRONT_DOMAIN
export S3_BUCKET_NAME=$BUCKET_NAME
export EC2_BACKEND=$EC2_BACKEND
export BACKEND_PORT=$BACKEND_PORT
EOF

echo "Configuration saved: cloudfront-config.env"
echo "Load with: source cloudfront-config.env"
echo ""

echo "Next steps:"
echo "  1. Wait for CloudFront deployment (check status above)"
echo "  2. Test frontend: https://$CLOUDFRONT_DOMAIN"
echo "  3. Test API: https://$CLOUDFRONT_DOMAIN/api/feedbacks"
echo "  4. Update frontend: cd frontend && ./deploy.sh"
echo ""
