#!/bin/bash
# S3 버전 관리 활성화 스크립트

set -e

echo "======================================"
echo "S3 버전 관리 활성화"
echo "======================================"
echo ""

# CloudFront Distribution ID 찾기
echo "🔍 CloudFront Distribution 찾는 중..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='feedback-app-frontend'].Id | [0]" \
  --output text)

if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
  echo "❌ CloudFront distribution을 찾을 수 없습니다!"
  echo "Comment가 'feedback-app-frontend'인 distribution이 있는지 확인하세요."
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

# 현재 버전 관리 상태 확인
echo "🔍 현재 버전 관리 상태 확인 중..."
VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --query 'Status' \
  --output text 2>/dev/null || echo "Disabled")

echo "현재 상태: $VERSIONING_STATUS"
echo ""

if [ "$VERSIONING_STATUS" = "Enabled" ]; then
  echo "✅ S3 버전 관리가 이미 활성화되어 있습니다!"
  echo ""

  # 현재 저장된 버전 수 확인
  echo "📊 저장된 버전 통계:"
  echo "======================================"

  TOTAL_VERSIONS=$(aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query 'length(Versions[])' \
    --output text)

  echo "총 버전 수: $TOTAL_VERSIONS"

  # index.html 버전 목록 표시
  echo ""
  echo "📋 index.html 버전 목록 (최근 5개):"
  aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --prefix "index.html" \
    --query 'Versions[:5].[VersionId,LastModified,IsLatest,Size]' \
    --output table

  exit 0
fi

# 버전 관리 활성화
echo "🔄 S3 버전 관리 활성화 중..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "✅ S3 버전 관리 활성화 완료!"
echo ""

# 확인
VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --query 'Status' \
  --output text)

if [ "$VERSIONING_STATUS" = "Enabled" ]; then
  echo "======================================"
  echo "✅ 설정 완료!"
  echo "======================================"
  echo ""
  echo "📦 S3 Bucket: $BUCKET_NAME"
  echo "🔖 버전 관리: 활성화됨"
  echo ""
  echo "📝 다음 단계:"
  echo "1. 이제부터 모든 파일 변경 시 이전 버전이 자동 보관됩니다"
  echo "2. GitHub Actions에서 'Rollback Frontend' 워크플로우로 롤백 가능"
  echo "3. AWS CLI로도 롤백 가능:"
  echo ""
  echo "   # 버전 목록 확인"
  echo "   aws s3api list-object-versions --bucket $BUCKET_NAME --prefix index.html"
  echo ""
  echo "   # 특정 버전으로 롤백"
  echo "   aws s3api copy-object \\"
  echo "     --bucket $BUCKET_NAME \\"
  echo "     --copy-source \"$BUCKET_NAME/index.html?versionId=VERSION_ID\" \\"
  echo "     --key index.html"
  echo ""
  echo "💡 팁: 비용 최적화를 위해 오래된 버전은 자동 삭제 설정 권장"
  echo "   (Lifecycle Policy 사용)"
else
  echo "❌ 버전 관리 활성화 실패!"
  exit 1
fi
