#!/bin/bash

# =========================================================================
# AWS DEPLOYMENT AUTOMATION SCRIPT FOR STAYDRIV
# =========================================================================

# Configuration Variables - Customize these as needed
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="123456789012" # Replace with your real AWS Account ID
ECR_REPO_NAME="staydriv-backend"
IMAGE_TAG="latest"
EB_APP_NAME="StayDrivApp"
EB_ENV_NAME="StayDrivEnv-Prod"
EB_PLATFORM="Docker running on 64bit Amazon Linux 2"

echo "=== Starting AWS Integration & Deployment Setup ==="

# 1. Authenticate Docker with AWS ECR
echo "[AWS] Authenticating local Docker daemon to ECR Registry..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Create ECR Repository if it doesn't exist
echo "[AWS] Verifying/creating Elastic Container Registry (ECR) repository..."
aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION || \
aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION

# 3. Build & Tag Production Docker Image
echo "[Docker] Building local production container..."
docker build -t $ECR_REPO_NAME:latest -f Dockerfile .

echo "[Docker] Tagging container image for AWS registry..."
docker tag $ECR_REPO_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

# 4. Push Container Image to AWS ECR
echo "[AWS] Uploading container image to ECR repository..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG

# 5. Create Elastic Beanstalk Application & Environment (if not existing)
echo "[AWS] Verifying Elastic Beanstalk application..."
aws elasticbeanstalk describe-applications --application-names "$EB_APP_NAME" --region $AWS_REGION | grep -q "$EB_APP_NAME" || \
aws elasticbeanstalk create-application --application-name "$EB_APP_NAME" --description "StayDriv Application" --region $AWS_REGION

# Create deployment payload zip containing Dockerrun.aws.json
echo "[AWS] Packaging deployment bundle..."
zip -j deploy-bundle.zip deploy/aws/Dockerrun.aws.json

# 6. Upload Deployment Bundle to S3
S3_BUCKET="elasticbeanstalk-$AWS_REGION-$AWS_ACCOUNT_ID"
VERSION_LABEL="v-$(date +%s)"

echo "[AWS] Uploading deployment archive to S3 bucket $S3_BUCKET..."
aws s3 cp deploy-bundle.zip s3://$S3_BUCKET/$EB_APP_NAME/$VERSION_LABEL.zip

# 7. Create EB Application Version
echo "[AWS] Creating application version $VERSION_LABEL..."
aws elasticbeanstalk create-application-version \
  --application-name "$EB_APP_NAME" \
  --version-label "$VERSION_LABEL" \
  --source-bundle S3Bucket="$S3_BUCKET",S3Key="$EB_APP_NAME/$VERSION_LABEL.zip" \
  --region $AWS_REGION

# 8. Update Environment to deploy new version
echo "[AWS] Deploying new release version to environment $EB_ENV_NAME..."
aws elasticbeanstalk update-environment \
  --environment-name "$EB_ENV_NAME" \
  --version-label "$VERSION_LABEL" \
  --region $AWS_REGION

# Clean up local package
rm deploy-bundle.zip

echo "=== AWS Deployment Initiated Successfully ==="
