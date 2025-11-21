#!/bin/bash

# AWS Permissions Setup Script
# Sets up IAM permissions for CloudFront deployment

set -e

echo "======================================"
echo "AWS Permissions Setup"
echo "======================================"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Get current IAM user
CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
echo "Current IAM User: $CURRENT_USER"

# Policy name
POLICY_NAME="CloudFrontDeploymentPolicy"
POLICY_FILE="scripts/cloudfront-deployment-policy.json"

# Check if policy file exists
if [ ! -f "$POLICY_FILE" ]; then
  echo "❌ Policy file not found: $POLICY_FILE"
  echo "Please ensure you're running this script from the project root directory"
  exit 1
fi

echo ""
echo "===================================="
echo "Step 1: Creating IAM Policy"
echo "===================================="

# Check if policy already exists
EXISTING_POLICY_ARN=$(aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='$POLICY_NAME'].Arn | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_POLICY_ARN" ] && [ "$EXISTING_POLICY_ARN" != "None" ]; then
  echo "⚠️  Policy already exists: $EXISTING_POLICY_ARN"
  POLICY_ARN=$EXISTING_POLICY_ARN

  # Ask user if they want to update the policy
  echo ""
  echo "Do you want to create a new version? (y/n)"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Creating new policy version..."
    aws iam create-policy-version \
      --policy-arn $POLICY_ARN \
      --policy-document file://$POLICY_FILE \
      --set-as-default
    echo "✅ Policy updated to new version"
  else
    echo "Using existing policy version"
  fi
else
  echo "Creating new policy..."
  POLICY_ARN=$(aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://$POLICY_FILE \
    --description "CloudFront + S3 deployment permissions for feedback app" \
    --query 'Policy.Arn' \
    --output text)
  echo "✅ Policy created: $POLICY_ARN"
fi

echo ""
echo "===================================="
echo "Step 2: Attaching Policy to User"
echo "===================================="

# Check if policy is already attached
ATTACHED=$(aws iam list-attached-user-policies \
  --user-name $CURRENT_USER \
  --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyName | [0]" \
  --output text 2>/dev/null || echo "")

if [ -n "$ATTACHED" ] && [ "$ATTACHED" != "None" ]; then
  echo "✅ Policy already attached to user: $CURRENT_USER"
else
  echo "Attaching policy to user: $CURRENT_USER"
  aws iam attach-user-policy \
    --user-name $CURRENT_USER \
    --policy-arn $POLICY_ARN
  echo "✅ Policy attached successfully"
fi

echo ""
echo "===================================="
echo "Step 3: Verifying Permissions"
echo "===================================="

echo "Testing S3 permissions..."
if aws s3 ls > /dev/null 2>&1; then
  echo "  ✅ S3 access verified"
else
  echo "  ❌ S3 access failed"
fi

echo "Testing CloudFront permissions..."
if aws cloudfront list-distributions > /dev/null 2>&1; then
  echo "  ✅ CloudFront access verified"
else
  echo "  ❌ CloudFront access failed"
fi

echo "Testing ELB permissions..."
if aws elbv2 describe-load-balancers > /dev/null 2>&1; then
  echo "  ✅ ELB access verified"
else
  echo "  ❌ ELB access failed"
fi

echo ""
echo "===================================="
echo "✅ Setup Complete!"
echo "===================================="
echo ""
echo "Policy ARN: $POLICY_ARN"
echo "User: $CURRENT_USER"
echo ""
echo "You can now run:"
echo "  ./scripts/setup-cloudfront.sh"
echo ""
echo "Note: If you're using GitHub Actions, make sure the"
echo "AWS credentials in GitHub Secrets have the same permissions!"
echo ""

# Save policy ARN for reference
echo "export CLOUDFRONT_POLICY_ARN=$POLICY_ARN" > .aws-policy-arn
echo "Configuration saved to: .aws-policy-arn"
