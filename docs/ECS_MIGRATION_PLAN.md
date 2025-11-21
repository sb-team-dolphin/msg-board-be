# ECS 마이그레이션 + 프론트엔드 레포 분리 통합 계획

## 목표

1. **프론트엔드 레포 분리**: `simple-api-frontend` 독립 레포 생성
2. **백엔드 ECS 전환**: EC2 Docker Compose → ECS Fargate
3. **ECR 도입**: GHCR → AWS ECR

---

## 최종 아키텍처 (To-Be)

```
┌─────────────────────────────────────────────────────────┐
│                       사용자                              │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
         ┌──────────────┐
         │  CloudFront  │ (CDN)
         └──────┬───────┘
                │
        ┌───────┴────────┐
        │                │
        ↓                ↓
   ┌─────────┐      ┌─────────┐
   │   S3    │      │   ALB   │ (Application Load Balancer)
   │(프론트) │      │(백엔드)  │
   └─────────┘      └────┬────┘
                         │
                    ┌────┴─────┐
                    │          │
                    ↓          ↓
              ┌──────────┐ ┌──────────┐
              │ ECS Task │ │ ECS Task │ (Fargate)
              │  (API)   │ │  (API)   │
              └────┬─────┘ └────┬─────┘
                   │            │
                   └─────┬──────┘
                         ↓
                   ┌──────────┐
                   │   RDS    │ (MySQL)
                   └──────────┘

레포 구조:
├── simple-api-frontend (프론트엔드)
│   └── GitHub Actions → CloudFront + S3
└── simple-api (백엔드)
    └── GitHub Actions → ECR + ECS
```

---

## Phase 1: 프론트엔드 레포 분리 (1-2시간)

### 목표
- `simple-api-frontend` 독립 레포 생성
- 기존 `simple-api`에서 frontend/ 제거
- 독립적인 배포 파이프라인

### 1.1 새 레포 생성

```bash
# 로컬 작업
cd ~/workspace
mkdir simple-api-frontend
cd simple-api-frontend

# Git 초기화
git init
git branch -M main

# 기존 프로젝트에서 파일 복사
cp -r ../simple-api/frontend/* ./

# 디렉토리 구조:
# simple-api-frontend/
# ├── index.html
# ├── css/
# │   └── style.css
# ├── js/
# │   └── app.js
# ├── .github/
# │   └── workflows/
# │       └── deploy-cloudfront.yml
# ├── .gitignore
# └── README.md
```

### 1.2 GitHub Actions 워크플로우

`.github/workflows/deploy-cloudfront.yml`:
```yaml
name: Deploy Frontend

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  AWS_REGION: ap-northeast-2

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Find CloudFront & S3
        id: resources
        run: |
          DIST_ID=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='feedback-app-frontend'].Id | [0]" \
            --output text)

          BUCKET=$(aws cloudfront get-distribution --id $DIST_ID \
            --query "Distribution.DistributionConfig.Origins.Items[0].DomainName" \
            --output text | cut -d'.' -f1)

          echo "dist_id=$DIST_ID" >> $GITHUB_OUTPUT
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT

      - name: Sync to S3
        run: |
          aws s3 sync . s3://${{ steps.resources.outputs.bucket }}/ \
            --exclude ".git*" \
            --exclude "*.md" \
            --exclude "index.html" \
            --cache-control "public, max-age=31536000" \
            --delete

      - name: Upload index.html
        run: |
          aws s3 cp index.html s3://${{ steps.resources.outputs.bucket }}/ \
            --cache-control "public, max-age=300"

      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.resources.outputs.dist_id }} \
            --paths "/*"
```

### 1.3 백엔드 레포 정리

```bash
# simple-api 레포에서 frontend/ 제거
cd ~/workspace/simple-api
rm -rf frontend/
rm .github/workflows/deploy-frontend-cloudfront.yml
rm .github/workflows/rollback-frontend*.yml

# README 업데이트
# → 프론트엔드 레포 링크 추가
```

**체크리스트:**
- [ ] GitHub에서 `simple-api-frontend` 레포 생성
- [ ] 로컬에서 파일 복사 및 워크플로우 설정
- [ ] GitHub Secrets 설정 (AWS 키)
- [ ] 배포 테스트
- [ ] 백엔드 레포 정리

---

## Phase 2: ECR 레포지토리 생성 (10분)

### 목표
- Docker 이미지 저장소를 GHCR에서 ECR로 전환

### 2.1 ECR 레포지토리 생성

```bash
# ECR 레포지토리 생성
aws ecr create-repository \
  --repository-name simple-api \
  --region ap-northeast-2 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

# 출력 예시:
# {
#   "repository": {
#     "repositoryUri": "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/simple-api"
#   }
# }
```

### 2.2 Lifecycle Policy 설정 (이미지 자동 정리)

```bash
# 최근 10개 이미지만 보관, 나머지 삭제
aws ecr put-lifecycle-policy \
  --repository-name simple-api \
  --lifecycle-policy-text '{
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 10 images",
        "selection": {
          "tagStatus": "any",
          "countType": "imageCountMoreThan",
          "countNumber": 10
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }'
```

**체크리스트:**
- [ ] ECR 레포지토리 생성
- [ ] Repository URI 저장
- [ ] Lifecycle Policy 설정

---

## Phase 3: ECS 클러스터 구성 (30분)

### 목표
- ECS Fargate 클러스터 생성
- Task Definition 작성
- Service 생성

### 3.1 ECS 클러스터 생성

```bash
# ECS 클러스터 생성 (Fargate 타입)
aws ecs create-cluster \
  --cluster-name simple-api-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1 \
    capacityProvider=FARGATE_SPOT,weight=1 \
  --region ap-northeast-2
```

### 3.2 Task Execution Role 생성

ECS Task가 ECR에서 이미지를 pull하고 CloudWatch에 로그를 쓸 수 있도록 IAM Role 필요:

```bash
# Trust Policy
cat > /tmp/ecs-task-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# IAM Role 생성
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file:///tmp/ecs-task-trust-policy.json

# 관리형 정책 연결
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### 3.3 Task Definition 작성

`task-definition.json`:
```json
{
  "family": "simple-api-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "simple-api",
      "image": "ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/simple-api:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "SPRING_PROFILES_ACTIVE",
          "value": "prod"
        },
        {
          "name": "JAVA_OPTS",
          "value": "-Xmx384m -Xms256m"
        }
      ],
      "secrets": [
        {
          "name": "DB_HOST",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:simple-api/db-host"
        },
        {
          "name": "DB_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:simple-api/db-password"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/simple-api",
          "awslogs-region": "ap-northeast-2",
          "awslogs-stream-prefix": "api"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### 3.4 CloudWatch Logs 그룹 생성

```bash
aws logs create-log-group \
  --log-group-name /ecs/simple-api \
  --region ap-northeast-2
```

### 3.5 Secrets Manager 설정

DB 정보를 Secrets Manager에 저장:

```bash
# DB Host
aws secretsmanager create-secret \
  --name simple-api/db-host \
  --secret-string "your-rds-endpoint.rds.amazonaws.com" \
  --region ap-northeast-2

# DB Password
aws secretsmanager create-secret \
  --name simple-api/db-password \
  --secret-string "your-db-password" \
  --region ap-northeast-2

# 기타 필요한 환경 변수들...
```

**체크리스트:**
- [ ] ECS 클러스터 생성
- [ ] Task Execution Role 생성
- [ ] CloudWatch Logs 그룹 생성
- [ ] Secrets Manager에 DB 정보 저장
- [ ] Task Definition 등록

---

## Phase 4: ALB (Application Load Balancer) 생성 (20분)

### 목표
- ALB로 ECS Task에 트래픽 분산
- Health Check 설정

### 4.1 ALB 생성

```bash
# Security Group 생성 (ALB용)
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name simple-api-alb-sg \
  --description "Security group for Simple API ALB" \
  --vpc-id vpc-xxxxx \
  --query 'GroupId' \
  --output text)

# Inbound 규칙 추가 (HTTP)
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# ALB 생성
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name simple-api-alb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# ALB DNS 이름 가져오기
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"
```

### 4.2 Target Group 생성

```bash
# Target Group 생성
TG_ARN=$(aws elbv2 create-target-group \
  --name simple-api-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id vpc-xxxxx \
  --target-type ip \
  --health-check-path /actuator/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)
```

### 4.3 Listener 생성

```bash
# HTTP Listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

**체크리스트:**
- [ ] ALB Security Group 생성
- [ ] ALB 생성
- [ ] Target Group 생성
- [ ] Listener 생성
- [ ] ALB DNS 이름 확인

---

## Phase 5: ECS Service 생성 (15분)

### 목표
- ECS Service로 Task 자동 관리
- Auto Scaling 설정

### 5.1 ECS Task용 Security Group

```bash
# Security Group 생성
ECS_SG_ID=$(aws ec2 create-security-group \
  --group-name simple-api-ecs-sg \
  --description "Security group for Simple API ECS tasks" \
  --vpc-id vpc-xxxxx \
  --query 'GroupId' \
  --output text)

# ALB에서만 접근 허용
aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SG_ID

# RDS 접근 허용 (RDS Security Group에 추가)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $ECS_SG_ID
```

### 5.2 ECS Service 생성

```bash
aws ecs create-service \
  --cluster simple-api-cluster \
  --service-name simple-api-service \
  --task-definition simple-api-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-xxxxx,subnet-yyyyy],
    securityGroups=[$ECS_SG_ID],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=simple-api,containerPort=8080" \
  --health-check-grace-period-seconds 60
```

### 5.3 Auto Scaling 설정

```bash
# Application Auto Scaling 등록
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/simple-api-cluster/simple-api-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 4

# CPU 기반 스케일링 정책
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/simple-api-cluster/simple-api-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

**체크리스트:**
- [ ] ECS Task Security Group 생성
- [ ] RDS Security Group 업데이트
- [ ] ECS Service 생성
- [ ] Auto Scaling 설정

---

## Phase 6: GitHub Actions 업데이트 (30분)

### 목표
- GHCR → ECR로 전환
- ECS 배포 자동화

### 6.1 새 워크플로우

`.github/workflows/deploy-ecs.yml`:
```yaml
name: Deploy to ECS

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'build.gradle'
      - 'Dockerfile'
  workflow_dispatch:

env:
  AWS_REGION: ap-northeast-2
  ECR_REPOSITORY: simple-api
  ECS_CLUSTER: simple-api-cluster
  ECS_SERVICE: simple-api-service
  CONTAINER_NAME: simple-api

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'

      - name: Build with Gradle
        run: ./gradlew bootJar --no-daemon

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        id: build-image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Update ECS service
        run: |
          aws ecs update-service \
            --cluster ${{ env.ECS_CLUSTER }} \
            --service ${{ env.ECS_SERVICE }} \
            --force-new-deployment

      - name: Wait for deployment
        run: |
          aws ecs wait services-stable \
            --cluster ${{ env.ECS_CLUSTER }} \
            --services ${{ env.ECS_SERVICE }}

      - name: Deployment summary
        run: |
          echo "✅ Deployment complete!"
          echo "Image: ${{ steps.build-image.outputs.image }}"
          echo "Cluster: ${{ env.ECS_CLUSTER }}"
          echo "Service: ${{ env.ECS_SERVICE }}"
```

### 6.2 GitHub Secrets 추가

필요한 Secrets:
- `AWS_ACCESS_KEY_ID` (IAM 사용자 Access Key)
- `AWS_SECRET_ACCESS_KEY` (IAM 사용자 Secret Key)

**체크리스트:**
- [ ] 기존 `deploy.yml` 제거 또는 비활성화
- [ ] `deploy-ecs.yml` 생성
- [ ] GitHub Secrets 설정
- [ ] 배포 테스트

---

## Phase 7: CloudFront Origin 변경 (10분)

### 목표
- CloudFront에서 백엔드 Origin을 ALB로 변경

### 7.1 CloudFront Origin 업데이트

AWS 콘솔:
1. CloudFront → Distribution 선택
2. Origins 탭
3. 백엔드 Origin (기존 EC2) → Edit
4. Origin domain: ALB DNS로 변경
   - 예: `simple-api-alb-123456.ap-northeast-2.elb.amazonaws.com`
5. Protocol: HTTP only (ALB가 HTTP 80 리스닝)
6. Save changes

### 7.2 테스트

```bash
# CloudFront를 통한 API 호출
curl https://your-cloudfront-domain.cloudfront.net/api/feedback

# 직접 ALB 호출
curl http://simple-api-alb-123456.ap-northeast-2.elb.amazonaws.com/api/feedback
```

**체크리스트:**
- [ ] CloudFront Origin 변경
- [ ] API 정상 작동 확인
- [ ] ECS Task 로그 확인

---

## Phase 8: 기존 EC2 정리 (5분)

### 목표
- 구 EC2 인스턴스 종료
- 불필요한 리소스 정리

```bash
# EC2 인스턴스 종료
aws ec2 terminate-instances --instance-ids i-xxxxx

# 기존 Security Group 정리 (사용 중이 아닌 경우)
# 수동으로 확인 후 삭제
```

**체크리스트:**
- [ ] ECS로 정상 작동 확인 후 EC2 종료
- [ ] 불필요한 Security Group 정리
- [ ] 기존 SSH Key 백업

---

## 비용 비교

### 현재 (EC2 + GHCR)
- EC2 t3.micro: $7/월
- RDS db.t3.micro: $15/월
- CloudFront + S3: $1/월
- **총합: ~$23/월**

### ECS + ECR 후
- ECS Fargate (2 Task, 0.25 vCPU, 0.5GB): ~$15/월
- ALB: $16/월
- RDS db.t3.micro: $15/월
- ECR: $0.10/GB/월 (~$0.50)
- CloudFront + S3: $1/월
- **총합: ~$47/월**

**증가: +$24/월 (약 2배)**

### 비용 최적화 방안
1. Fargate Spot 사용: 70% 할인
2. Savings Plans: 20-40% 할인
3. 개발 환경은 Desired Count 1로 설정
4. CloudWatch Logs 보관 기간 단축

---

## 롤백 계획

### ECS → EC2 롤백

1. **CloudFront Origin 되돌리기**
   - Origin을 기존 EC2 IP로 변경

2. **기존 EC2 재시작**
   ```bash
   aws ec2 start-instances --instance-ids i-xxxxx
   ```

3. **ECS Service 중지**
   ```bash
   aws ecs update-service \
     --cluster simple-api-cluster \
     --service simple-api-service \
     --desired-count 0
   ```

---

## 전체 타임라인

| Phase | 작업 | 소요 시간 | 의존성 |
|-------|------|----------|--------|
| 1 | 프론트엔드 레포 분리 | 1-2시간 | - |
| 2 | ECR 레포지토리 생성 | 10분 | - |
| 3 | ECS 클러스터 구성 | 30분 | Phase 2 |
| 4 | ALB 생성 | 20분 | - |
| 5 | ECS Service 생성 | 15분 | Phase 3, 4 |
| 6 | GitHub Actions 업데이트 | 30분 | Phase 2, 5 |
| 7 | CloudFront Origin 변경 | 10분 | Phase 5 |
| 8 | 기존 EC2 정리 | 5분 | Phase 7 |

**총 소요 시간: 3-4시간**

---

## 최종 체크리스트

### 프론트엔드 레포 분리
- [ ] GitHub 레포 생성
- [ ] 파일 이동 및 워크플로우 설정
- [ ] 배포 테스트
- [ ] 백엔드 레포 정리

### ECS 마이그레이션
- [ ] ECR 레포지토리 생성
- [ ] ECS 클러스터 생성
- [ ] Task Definition 등록
- [ ] ALB + Target Group 생성
- [ ] ECS Service 생성
- [ ] Auto Scaling 설정
- [ ] GitHub Actions 워크플로우 업데이트
- [ ] CloudFront Origin 변경
- [ ] 배포 테스트
- [ ] 기존 EC2 종료

### 문서화
- [ ] 새 아키텍처 다이어그램 업데이트
- [ ] README.md 업데이트
- [ ] 롤백 절차 문서화
- [ ] 팀원 교육

---

**작성일**: 2025-11-20
**관련 문서**:
- `FRONTEND_REPO_SEPARATION.md`
- `ALB_MIGRATION_PLAN.md`
- `FRONTEND_ROLLBACK_GUIDE.md`
