#!/bin/bash
# CloudFront 무료 개선 사항 적용 스크립트
# - Origin Access Control (OAC)
# - 보안 헤더 (CloudFront Functions)
# - 캐시 최적화

set -e

echo "======================================"
echo "CloudFront 무료 개선 사항 적용"
echo "======================================"
echo ""

# CloudFront Distribution ID 찾기
echo "🔍 CloudFront Distribution 찾는 중..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='feedback-app-frontend'].Id | [0]" \
  --output text)

if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
  echo "❌ CloudFront distribution을 찾을 수 없습니다!"
  exit 1
fi

echo "✅ Distribution ID: $DISTRIBUTION_ID"
echo ""

# S3 버킷 이름 가져오기
echo "🔍 S3 버킷 이름 가져오는 중..."
BUCKET_DOMAIN=$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query "Distribution.DistributionConfig.Origins.Items[?contains(DomainName, 's3')].DomainName | [0]" \
  --output text)

BUCKET_NAME=${BUCKET_DOMAIN%%.s3.*.amazonaws.com}

if [ -z "$BUCKET_NAME" ]; then
  echo "❌ S3 버킷을 찾을 수 없습니다!"
  exit 1
fi

echo "✅ S3 Bucket: $BUCKET_NAME"
echo ""

# AWS 계정 ID 가져오기
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

echo "======================================"
echo "Step 1: Origin Access Control (OAC) 생성"
echo "======================================"

# OAC 생성
OAC_NAME="feedback-s3-oac-$(date +%s)"
echo "📝 OAC 생성 중: $OAC_NAME"

OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config "{
    \"Name\": \"$OAC_NAME\",
    \"Description\": \"OAC for feedback frontend S3 bucket\",
    \"SigningProtocol\": \"sigv4\",
    \"SigningBehavior\": \"always\",
    \"OriginAccessControlOriginType\": \"s3\"
  }" \
  --query 'OriginAccessControl.Id' \
  --output text)

echo "✅ OAC 생성 완료: $OAC_ID"
echo ""

echo "======================================"
echo "Step 2: S3 버킷 정책 업데이트"
echo "======================================"

# S3 버킷 정책 생성
cat > /tmp/s3-bucket-policy.json << EOF
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
          "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF

echo "📝 S3 버킷 정책 적용 중..."
aws s3api put-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --policy file:///tmp/s3-bucket-policy.json

echo "✅ S3 버킷 정책 업데이트 완료"
echo ""

echo "======================================"
echo "Step 3: S3 Public Access 차단"
echo "======================================"

echo "📝 S3 Public Access 차단 중..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "✅ S3 Public Access 차단 완료 (CloudFront만 접근 가능)"
echo ""

echo "======================================"
echo "Step 4: CloudFront Functions (보안 헤더)"
echo "======================================"

# CloudFront Function 생성
cat > /tmp/cloudfront-function.js << 'JSEOF'
function handler(event) {
    var response = event.response;
    var headers = response.headers;

    // Security Headers
    headers['strict-transport-security'] = {
        value: 'max-age=63072000; includeSubdomains; preload'
    };
    headers['x-content-type-options'] = {
        value: 'nosniff'
    };
    headers['x-frame-options'] = {
        value: 'DENY'
    };
    headers['x-xss-protection'] = {
        value: '1; mode=block'
    };
    headers['referrer-policy'] = {
        value: 'strict-origin-when-cross-origin'
    };
    headers['permissions-policy'] = {
        value: 'geolocation=(), microphone=(), camera=()'
    };

    return response;
}
JSEOF

FUNCTION_NAME="feedback-security-headers-$(date +%s)"
echo "📝 CloudFront Function 생성 중: $FUNCTION_NAME"

FUNCTION_ARN=$(aws cloudfront create-function \
  --name "$FUNCTION_NAME" \
  --function-config "Comment=Add security headers,Runtime=cloudfront-js-1.0" \
  --function-code fileb:///tmp/cloudfront-function.js \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' \
  --output text)

echo "✅ CloudFront Function 생성 완료"
echo "   ARN: $FUNCTION_ARN"
echo ""

# Function 배포
echo "📝 Function 배포 중..."
ETAG=$(aws cloudfront describe-function \
  --name "$FUNCTION_NAME" \
  --query 'ETag' \
  --output text)

aws cloudfront publish-function \
  --name "$FUNCTION_NAME" \
  --if-match "$ETAG" > /dev/null

echo "✅ Function 배포 완료"
echo ""

echo "======================================"
echo "Step 5: CloudFront Distribution 업데이트"
echo "======================================"

echo "⚠️  수동 작업 필요!"
echo ""
echo "다음 단계를 AWS 콘솔에서 수행하세요:"
echo ""
echo "1. CloudFront 콘솔: https://console.aws.amazon.com/cloudfront/"
echo "2. Distribution ID: $DISTRIBUTION_ID 선택"
echo ""
echo "3. Origins 탭:"
echo "   - Origin 선택 → Edit"
echo "   - Origin access: 'Origin access control settings (recommended)' 선택"
echo "   - Origin access control: $OAC_NAME 선택"
echo "   - Save changes"
echo ""
echo "4. Behaviors 탭:"
echo "   - Default (*) 선택 → Edit"
echo "   - Function associations:"
echo "     * Viewer response: $FUNCTION_NAME 선택"
echo "   - Cache key and origin requests:"
echo "     * Cache policy: CachingOptimized (권장)"
echo "   - Compress objects automatically: Yes"
echo "   - Save changes"
echo ""
echo "5. 배포 대기 (5-10분)"
echo ""

echo "======================================"
echo "✅ 설정 완료!"
echo "======================================"
echo ""
echo "📋 적용된 개선 사항:"
echo "  ✅ OAC: S3 버킷을 private으로 보호"
echo "  ✅ 보안 헤더: XSS, Clickjacking 등 방어"
echo "  ✅ Public Access 차단: CloudFront만 S3 접근 가능"
echo ""
echo "📝 다음 단계:"
echo "  1. AWS 콘솔에서 CloudFront 설정 완료 (위 가이드 참고)"
echo "  2. 배포 완료 후 테스트:"
echo "     curl -I https://your-cloudfront-domain.cloudfront.net"
echo "  3. 보안 헤더 확인:"
echo "     https://securityheaders.com"
echo ""
echo "💰 비용: 완전 무료!"
echo ""

# 정리
rm -f /tmp/s3-bucket-policy.json /tmp/cloudfront-function.js

echo "스크립트 완료!"
