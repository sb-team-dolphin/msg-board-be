#!/bin/bash

# CloudFront + S3 Setup Script
# This script creates the S3 bucket and CloudFront distribution for frontend hosting

set -e

echo "======================================"
echo "CloudFront + S3 Setup"
echo "======================================"

# Configuration
AWS_REGION="ap-northeast-2"
BUCKET_PREFIX="feedback-frontend"
COMMENT="feedback-app-frontend"

# Step 1: Create S3 bucket
echo ""
echo "[1/6] Creating S3 bucket..."
BUCKET_NAME="${BUCKET_PREFIX}-$(date +%s)"
echo "   Bucket name: $BUCKET_NAME"

aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Step 2: Get ALB DNS (for CloudFront origin)
echo ""
echo "[2/6] Getting ALB DNS name..."
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names feedback-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text)

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "None" ]; then
  echo "❌ ALB 'feedback-alb' not found!"
  echo "Please create the backend infrastructure first."
  exit 1
fi

echo "   ALB DNS: $ALB_DNS"

# Step 3: Create Origin Access Control (OAC)
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

# Step 4: Create CloudFront distribution
echo ""
echo "[4/6] Creating CloudFront distribution..."
echo "   This may take 10-15 minutes..."

# Generate unique caller reference
CALLER_REF="feedback-frontend-$(date +%s)"

# Create distribution config
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
        "Id": "ALB-backend",
        "DomainName": "$ALB_DNS",
        "OriginPath": "",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
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
        "TargetOriginId": "ALB-backend",
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

# Create distribution
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
  --distribution-config "$DISTRIBUTION_CONFIG" \
  --query "Distribution.Id" \
  --output text)

echo "   Distribution ID: $DISTRIBUTION_ID"

# Get distribution domain
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query "Distribution.DomainName" \
  --output text)

echo "   CloudFront domain: $CLOUDFRONT_DOMAIN"

# Step 5: Update S3 bucket policy
echo ""
echo "[5/6] Updating S3 bucket policy for CloudFront access..."

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
          "AWS:SourceArn": "arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/${DISTRIBUTION_ID}"
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

# Step 6: Upload frontend files
echo ""
echo "[6/6] Uploading frontend files to S3..."

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
  echo "      Run 'cd frontend && ../scripts/deploy-frontend.sh' to upload later"
fi

# Summary
echo ""
echo "======================================"
echo "✅ Setup Complete!"
echo "======================================"
echo ""
echo "Resources created:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  CloudFront Distribution ID: $DISTRIBUTION_ID"
echo "  CloudFront Domain: $CLOUDFRONT_DOMAIN"
echo "  OAC ID: $OAC_ID"
echo ""
echo "Frontend URL: https://$CLOUDFRONT_DOMAIN"
echo ""
echo "⏳ CloudFront distribution is deploying (10-15 minutes)"
echo "   Check status with:"
echo "   aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status'"
echo ""
echo "Next steps:"
echo "  1. Wait for CloudFront deployment to complete"
echo "  2. Test frontend: https://$CLOUDFRONT_DOMAIN"
echo "  3. Test API: https://$CLOUDFRONT_DOMAIN/api/feedbacks"
echo "  4. Deploy updates: cd frontend && ./deploy.sh"
echo ""

# Save config for later use
cat > cloudfront-config.env <<EOF
export CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID
export CLOUDFRONT_DOMAIN=$CLOUDFRONT_DOMAIN
export S3_BUCKET_NAME=$BUCKET_NAME
export ALB_DNS=$ALB_DNS
EOF

echo "Configuration saved to: cloudfront-config.env"
echo "Load with: source cloudfront-config.env"
echo ""
