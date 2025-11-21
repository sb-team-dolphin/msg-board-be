# Auto Scaling 환경에서 롤백하기

**핵심 차이**: 단일 EC2 → 여러 인스턴스 (동적 생성/삭제)

---

## 🔄 현재 vs 새 아키텍처 롤백

### 현재 (단일 EC2)

```
롤백 방식:
  1. SSH 접속
  2. docker-compose down
  3. docker pull previous
  4. docker-compose up
  5. DB 복원

특징:
  ✅ 간단 (서버 1대)
  ✅ 직접 제어
  ❌ 다운타임 있음 (40초)
```

### 새 아키텍처 (ALB + ASG)

```
문제:
  ❌ 인스턴스가 여러 개
  ❌ 동적으로 생성/삭제됨
  ❌ 직접 SSH 접속 어려움
  ❌ 어느 서버를 롤백?

해결:
  ✅ Launch Template 버전 관리
  ✅ Instance Refresh (점진적 교체)
  ✅ 무중단 롤백
```

---

## 🎯 3가지 롤백 전략

### 전략 1: Launch Template 버전 롤백 ⭐⭐⭐⭐⭐

**원리**: Launch Template은 버전 관리 기능 내장

```
Launch Template 버전:
  v1: ghcr.io/user/app:sha-abc123
  v2: ghcr.io/user/app:sha-def456  ← 현재 (문제!)
  v3: ghcr.io/user/app:sha-ghi789

롤백:
  ASG가 사용하는 버전을 v2 → v1로 변경
  → Instance Refresh 실행
  → 점진적으로 새 인스턴스(v1) 시작
  → 기존 인스턴스(v2) 종료
```

**장점**:
- ✅ AWS 네이티브 방식
- ✅ 무중단 롤백
- ✅ 점진적 교체
- ✅ 자동 health check

**단점**:
- ⚠️ Launch Template 버전 관리 필요
- ⚠️ 약간 복잡

### 전략 2: Docker 이미지 태그 변경 ⭐⭐⭐⭐☆

**원리**: User Data 스크립트에서 이미지 태그 변경

```
현재 User Data:
  docker pull ghcr.io/user/app:latest

롤백 User Data:
  docker pull ghcr.io/user/app:previous

방법:
  1. Launch Template 새 버전 생성 (latest → previous)
  2. ASG에 적용
  3. Instance Refresh
```

**장점**:
- ✅ 간단한 개념
- ✅ GitHub의 이미지 태그 활용

**단점**:
- ⚠️ 여전히 Launch Template 버전 필요

### 전략 3: ASG 전체 교체 ⭐⭐⭐☆☆

**원리**: 기존 ASG 중단 → 이전 Launch Template로 새 ASG

```
1. 이전 Launch Template 확인
2. 새 ASG 생성 (이전 LT 사용)
3. ALB Target Group에 새 ASG 연결
4. Health check 통과 확인
5. 기존 ASG 삭제
```

**장점**:
- ✅ 완전히 새로운 시작
- ✅ Blue-Green 배포 방식

**단점**:
- ⚠️ 복잡함
- ⚠️ 시간 오래 걸림 (5-10분)

---

## 🚀 추천: 전략 2 (간단 버전)

### 왜?

```
전략 1: 완벽하지만 복잡
전략 2: 충분히 좋고 간단 ← 추천!
전략 3: 너무 복잡
```

---

## 📋 전략 2 상세 가이드

### 사전 준비 (배포 시스템)

#### 1. GitHub Actions: 이미지 태그 전략

**deploy.yml 수정**:

```yaml
# .github/workflows/deploy.yml

jobs:
  build-and-push:
    steps:
      # ... 기존 빌드 단계 ...

      # 1. 현재 latest를 previous로 저장
      - name: Tag current latest as previous
        continue-on-error: true
        run: |
          docker pull ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest || true
          docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest \
                     ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:previous
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:previous

      # 2. 새 이미지를 latest로 푸시
      - name: Build and push Docker image
        uses: docker/build-push-action@v6
        with:
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

      # ... 배포 단계 ...
```

**결과**:
```
배포 전:
  latest:   sha-abc123
  previous: sha-old999

배포 후:
  latest:   sha-def456  (새 버전)
  previous: sha-abc123  (이전 latest)
  sha-def456: sha-def456 (백업용)
```

#### 2. Launch Template: 이미지 태그 파라미터화

**User Data 스크립트 (Launch Template)**:

```bash
#!/bin/bash
set -e

# 환경변수로 이미지 태그 받기 (기본값: latest)
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "🚀 Starting deployment with image tag: $IMAGE_TAG"

# Docker 설치
dnf install -y docker
systemctl start docker

# GHCR 로그인 (Public repo라면 생략 가능)
# echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

# 이미지 pull (태그 사용)
docker pull ghcr.io/johnhuh619/simple-api:$IMAGE_TAG

# 컨테이너 실행
docker run -d \
  --name feedback-api \
  -p 8080:8080 \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.10:3306/feedbackdb \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackPass123! \
  --restart unless-stopped \
  ghcr.io/johnhuh619/simple-api:$IMAGE_TAG

echo "✅ Container started with tag: $IMAGE_TAG"
```

**주의**: User Data에서 환경변수 전달이 어려움
→ 실제로는 **Launch Template 버전**을 여러 개 만드는 것이 더 간단

---

### 실전 롤백 방법 (간단 버전)

#### 방법 A: AWS Console (수동, 5분)

**Step 1: 새 Launch Template 버전 생성**

```
EC2 → Launch Templates → feedback-api-lt

[Actions] → [Modify template (Create new version)]

User data:
  기존: docker pull ghcr.io/johnhuh619/simple-api:latest
  변경: docker pull ghcr.io/johnhuh619/simple-api:previous

[Create template version]

→ Version 3 생성됨
```

**Step 2: Auto Scaling Group 업데이트**

```
EC2 → Auto Scaling Groups → feedback-api-asg

[Edit]

Launch template:
  Version: Latest (3) → 선택

[Update]
```

**Step 3: Instance Refresh**

```
ASG 상세 → [Instance refresh] 탭

[Start instance refresh]

Settings:
  Minimum healthy percentage: 50%
  (1대는 유지하면서 교체)

[Start]

⏱️ 5-10분 대기:
  1. 새 인스턴스(previous) 시작
  2. Health check 통과
  3. 기존 인스턴스(latest) 종료
```

**Step 4: 검증**

```
curl http://<ALB_DNS>/actuator/health
curl http://<ALB_DNS>/api/feedbacks

✅ 이전 버전으로 롤백 완료!
```

#### 방법 B: AWS CLI (자동화, 2분)

```bash
#!/bin/bash
# rollback.sh

set -e

ASG_NAME="feedback-api-asg"
LT_NAME="feedback-api-lt"

echo "🔄 Starting rollback..."

# 1. 현재 Launch Template 버전 확인
CURRENT_VERSION=$(aws ec2 describe-launch-templates \
  --launch-template-names $LT_NAME \
  --query 'LaunchTemplates[0].LatestVersionNumber' \
  --output text)

echo "Current LT version: $CURRENT_VERSION"

# 2. 새 버전 생성 (User Data만 변경)
NEW_VERSION=$(aws ec2 create-launch-template-version \
  --launch-template-name $LT_NAME \
  --source-version $CURRENT_VERSION \
  --launch-template-data '{
    "UserData": "base64_encoded_script_with_previous_tag"
  }' \
  --query 'LaunchTemplateVersion.VersionNumber' \
  --output text)

echo "Created new LT version: $NEW_VERSION"

# 3. ASG에 새 버전 적용
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $ASG_NAME \
  --launch-template LaunchTemplateName=$LT_NAME,Version=$NEW_VERSION

echo "✅ ASG updated to use LT version $NEW_VERSION"

# 4. Instance Refresh 시작
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $ASG_NAME \
  --preferences MinHealthyPercentage=50,InstanceWarmup=300 \
  --query 'InstanceRefreshId' \
  --output text)

echo "🔄 Instance Refresh started: $REFRESH_ID"
echo "⏱️ This will take 5-10 minutes..."

# 5. 진행 상황 모니터링 (선택)
while true; do
  STATUS=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name $ASG_NAME \
    --instance-refresh-ids $REFRESH_ID \
    --query 'InstanceRefreshes[0].Status' \
    --output text)

  echo "Status: $STATUS"

  if [ "$STATUS" = "Successful" ]; then
    echo "✅ Rollback completed!"
    break
  elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ]; then
    echo "❌ Rollback failed!"
    exit 1
  fi

  sleep 30
done
```

#### 방법 C: GitHub Actions (권장!)

**rollback.yml 업데이트**:

```yaml
# .github/workflows/rollback.yml

name: Rollback to Previous Version

on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: 'Type "rollback" to confirm'
        required: true

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Validate confirmation
        run: |
          if [ "${{ github.event.inputs.confirmation }}" != "rollback" ]; then
            echo "❌ Confirmation failed"
            exit 1
          fi

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2

      - name: Get current Launch Template version
        id: get-version
        run: |
          CURRENT=$(aws ec2 describe-launch-templates \
            --launch-template-names feedback-api-lt \
            --query 'LaunchTemplates[0].LatestVersionNumber' \
            --output text)
          echo "current=$CURRENT" >> $GITHUB_OUTPUT

      - name: Create rollback User Data
        run: |
          cat > user-data.sh << 'EOF'
          #!/bin/bash
          set -e
          dnf install -y docker
          systemctl start docker
          docker pull ghcr.io/johnhuh619/simple-api:previous
          docker run -d --name feedback-api -p 8080:8080 \
            -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.10:3306/feedbackdb \
            -e SPRING_DATASOURCE_USERNAME=feedbackuser \
            -e SPRING_DATASOURCE_PASSWORD=FeedbackPass123! \
            --restart unless-stopped \
            ghcr.io/johnhuh619/simple-api:previous
          EOF

          # Base64 인코딩
          USER_DATA=$(base64 -w 0 user-data.sh)
          echo "USER_DATA=$USER_DATA" >> $GITHUB_ENV

      - name: Create new Launch Template version
        id: new-version
        run: |
          NEW_VERSION=$(aws ec2 create-launch-template-version \
            --launch-template-name feedback-api-lt \
            --source-version ${{ steps.get-version.outputs.current }} \
            --launch-template-data "{\"UserData\":\"$USER_DATA\"}" \
            --query 'LaunchTemplateVersion.VersionNumber' \
            --output text)
          echo "new=$NEW_VERSION" >> $GITHUB_OUTPUT

      - name: Update Auto Scaling Group
        run: |
          aws autoscaling update-auto-scaling-group \
            --auto-scaling-group-name feedback-api-asg \
            --launch-template LaunchTemplateName=feedback-api-lt,Version=${{ steps.new-version.outputs.new }}

      - name: Start Instance Refresh
        id: refresh
        run: |
          REFRESH_ID=$(aws autoscaling start-instance-refresh \
            --auto-scaling-group-name feedback-api-asg \
            --preferences MinHealthyPercentage=50,InstanceWarmup=300 \
            --query 'InstanceRefreshId' \
            --output text)
          echo "id=$REFRESH_ID" >> $GITHUB_OUTPUT

      - name: Wait for Instance Refresh
        run: |
          while true; do
            STATUS=$(aws autoscaling describe-instance-refreshes \
              --auto-scaling-group-name feedback-api-asg \
              --instance-refresh-ids ${{ steps.refresh.outputs.id }} \
              --query 'InstanceRefreshes[0].Status' \
              --output text)

            echo "Instance Refresh Status: $STATUS"

            if [ "$STATUS" = "Successful" ]; then
              echo "✅ Rollback completed!"
              break
            elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ]; then
              echo "❌ Rollback failed!"
              exit 1
            fi

            sleep 30
          done

      - name: Verify rollback
        run: |
          ALB_DNS=$(aws elbv2 describe-load-balancers \
            --names feedback-api-alb \
            --query 'LoadBalancers[0].DNSName' \
            --output text)

          echo "Testing ALB: $ALB_DNS"
          curl -f http://$ALB_DNS/actuator/health

      - name: Notify Slack
        if: always()
        run: |
          STATUS="${{ job.status }}"
          if [ "$STATUS" = "success" ]; then
            MESSAGE="✅ Rollback completed successfully"
          else
            MESSAGE="❌ Rollback failed"
          fi

          curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"$MESSAGE\"}"
```

---

## 💾 데이터베이스 롤백

### MySQL은 별도 처리

```
좋은 소식:
  ✅ MySQL은 별도 EC2
  ✅ ASG와 무관
  ✅ 기존 방식 그대로 사용 가능
```

### DB 롤백 방법 (기존과 동일)

```bash
# 1. MySQL 서버 접속
ssh ec2-user@10.0.11.10  # Public IP 또는 Bastion 통해

# 2. S3에서 백업 확인
aws s3 ls s3://feedback-api-backups/2025/11/17/

# 3. 백업 다운로드
aws s3 cp s3://feedback-api-backups/.../backup.sql.gz /tmp/

# 4. 데이터베이스 복원
gunzip /tmp/backup.sql.gz
mysql -u root -p feedbackdb < /tmp/backup.sql

# 5. 검증
mysql -u root -p -e "SELECT COUNT(*) FROM feedbackdb.feedbacks;"
```

---

## 🎯 롤백 시나리오별 대응

### 시나리오 1: 배포 직후 버그 발견

```
상황:
  - 배포 5분 후
  - 심각한 버그 발견
  - 즉시 롤백 필요

대응:
  1. GitHub Actions → Rollback workflow 실행
  2. "rollback" 입력하여 확인
  3. 5-10분 대기
  4. 이전 버전으로 복구 ✅

DB:
  - 데이터 변경 없으면 DB 롤백 불필요
  - 데이터 오염 시 DB도 롤백
```

### 시나리오 2: 데이터베이스 스키마 변경

```
상황:
  - 새 배포에서 테이블 구조 변경
  - 롤백 시 스키마 호환성 문제

대응:
  1. Application 롤백 (GitHub Actions)
  2. DB 스키마도 롤백:
     - 마이그레이션 도구 사용 (Flyway)
     - 또는 백업 복원

⚠️ 주의:
  - 스키마 변경은 항상 Backward Compatible하게!
  - Expand-Migrate-Contract 패턴 사용
```

### 시나리오 3: 일부 인스턴스만 문제

```
상황:
  - Instance 1: 정상 ✅
  - Instance 2: 오류 ❌

대응:
  ALB가 자동 처리:
  - Health check 실패 감지
  - Instance 2를 Target Group에서 제거
  - 트래픽을 Instance 1로만 전달

  추가 조치:
  - Instance Refresh로 모든 인스턴스 재시작
```

---

## ⚡ 빠른 롤백 치트시트

### Console (5분)

```
1. EC2 → Launch Templates → feedback-api-lt
   → Actions → Modify (Create new version)
   → User Data에서 "latest" → "previous"
   → Create

2. EC2 → Auto Scaling Groups → feedback-api-asg
   → Edit → Launch template version 변경
   → Update

3. ASG → Instance refresh 탭
   → Start instance refresh
   → MinHealthyPercentage: 50%

4. ⏱️ 5-10분 대기

5. ✅ 완료!
```

### GitHub Actions (2분)

```
1. GitHub → Actions → Rollback to Previous Version
2. Run workflow
3. Input: "rollback"
4. ⏱️ 5-10분 대기
5. ✅ 완료!
```

### CLI (1분)

```bash
# rollback.sh 실행
./rollback.sh

# 또는
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name feedback-api-asg \
  --preferences MinHealthyPercentage=50
```

---

## 📊 롤백 방법 비교

| 방법 | 시간 | 다운타임 | 난이도 | 추천 |
|------|------|----------|--------|------|
| **GitHub Actions** | 5-10분 | 없음 | ★☆☆ | ⭐⭐⭐⭐⭐ |
| **AWS Console** | 5-10분 | 없음 | ★★☆ | ⭐⭐⭐⭐☆ |
| **AWS CLI** | 5-10분 | 없음 | ★★★ | ⭐⭐⭐☆☆ |

---

## ✅ 핵심 정리

### ASG 환경 롤백 핵심

```
1. Launch Template 버전 관리
   - 배포 시마다 새 버전 생성
   - User Data에 이미지 태그 명시

2. Instance Refresh
   - 무중단 교체 메커니즘
   - MinHealthyPercentage: 50%

3. Docker 이미지 태그
   - latest: 최신
   - previous: 이전 버전
   - sha-xxx: 특정 버전

4. DB 롤백은 별도
   - MySQL은 독립 서버
   - 기존 방식 그대로
```

### 롤백 준비사항

```
✅ Docker 이미지 태그 전략 (latest, previous)
✅ Launch Template 버전 관리
✅ Instance Refresh 이해
✅ DB 백업 (S3)
✅ Rollback workflow (GitHub Actions)
```

### 한 문장 요약

**"Launch Template의 User Data에서 이미지 태그를 `latest`에서 `previous`로 변경하고, Instance Refresh로 점진적으로 교체!"**

---

**롤백 시스템 구축도 도와드릴까요?** 🔄
