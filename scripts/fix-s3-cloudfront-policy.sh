#!/bin/bash

# S3 버킷 정책 수정 스크립트 (CloudFront OAC 접근 허용)

set -e

echo "======================================"
echo "Fix S3 Bucket Policy for CloudFront"
echo "======================================"

# 입력
read -p "Enter S3 bucket name (e.g., feedback-frontend-1234567890): " BUCKET_NAME
read -p "Enter CloudFront Distribution ID (e.g., E1234567890ABC): " DISTRIBUTION_ID

if [ -z "$BUCKET_NAME" ] || [ -z "$DISTRIBUTION_ID" ]; then
  echo "❌ Bucket name and Distribution ID are required!"
  exit 1
fi

echo ""
echo "Configuration:"
echo "  Bucket: $BUCKET_NAME"
echo "  Distribution: $DISTRIBUTION_ID"
echo ""

# AWS Account ID 가져오기
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  Account ID: $ACCOUNT_ID"

# S3 버킷 정책 생성
echo ""
echo "Creating bucket policy..."

cat > /tmp/s3-cloudfront-policy.json <<EOF
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

echo "Policy created:"
cat /tmp/s3-cloudfront-policy.json

# 버킷 정책 적용
echo ""
echo "Applying bucket policy..."
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/s3-cloudfront-policy.json

echo ""
echo "✅ Bucket policy updated successfully!"
echo ""

# Public Access Block 확인
echo "Checking Public Access Block settings..."
aws s3api get-public-access-block --bucket $BUCKET_NAME 2>/dev/null || echo "No public access block configured"

echo ""
echo "======================================"
echo "Next Steps:"
echo "======================================"
echo "1. Wait 1-2 minutes for policy to propagate"
echo "2. Test CloudFront URL: https://d1234...cloudfront.net"
echo "3. If still Access Denied, check CloudFront OAC settings"
echo ""
