# Launch Template 완벽 이해하기

**한 줄 요약**: EC2 인스턴스를 만들 때 사용하는 "설계도" 📋

---

## 🍪 비유로 이해하기

### Launch Template = 쿠키 커터 (틀)

```
쿠키 커터 (Launch Template):
  - 모양: 별 모양
  - 크기: 5cm
  - 재료: 밀가루, 설탕, 버터

쿠키 만들기:
  1. 쿠키 커터로 반죽 찍기
  2. 오븐에 굽기
  3. 똑같은 쿠키 여러 개 생성!

결과:
  🍪 쿠키 1 (별 모양, 5cm)
  🍪 쿠키 2 (별 모양, 5cm)
  🍪 쿠키 3 (별 모양, 5cm)

  → 모두 똑같은 모양!
```

### AWS에 적용하면

```
Launch Template:
  - AMI: Amazon Linux 2023
  - Type: t3.small
  - User Data: Docker 설치 스크립트

Auto Scaling Group:
  1. Launch Template로 인스턴스 생성
  2. 필요한 만큼 자동 생성
  3. 똑같은 서버 여러 대!

결과:
  🖥️ Server 1 (Linux 2023, t3.small, Docker)
  🖥️ Server 2 (Linux 2023, t3.small, Docker)
  🖥️ Server 3 (Linux 2023, t3.small, Docker)

  → 모두 똑같은 설정!
```

---

## 📋 Launch Template이란?

### 정의

```
Launch Template = EC2 인스턴스 생성 설계도

포함 내용:
  ✅ AMI (운영체제)
  ✅ Instance Type (t3.small 등)
  ✅ Key Pair (SSH 키)
  ✅ Security Group (방화벽)
  ✅ User Data (시작 스크립트)
  ✅ IAM Role (권한)
  ✅ Network 설정
  ✅ Storage 설정
```

### 왜 필요한가?

#### 문제: 수동 설정의 악몽

```
Auto Scaling으로 서버 10대 생성할 때:

수동 방식 (Launch Template 없이):
  1. EC2 Console → Launch Instance
  2. AMI 선택
  3. Type 선택
  4. Network 설정
  5. Storage 설정
  6. User Data 입력
  7. Security Group 선택
  8. Launch

  → 10번 반복? 😱
  → 실수 가능성 높음
  → 일관성 없음
```

#### 해결: Launch Template

```
Launch Template 방식:
  1. Launch Template 1번 작성 (설계도)
  2. Auto Scaling Group에 연결
  3. ASG가 자동으로 인스턴스 생성

  → 10대든 100대든 똑같이 생성 ✅
  → 실수 없음
  → 완벽한 일관성
```

---

## 🔨 Launch Template 만들기

### AWS Console 단계별

#### Step 1: 기본 정보

```
EC2 → Launch Templates → Create launch template

Launch template name: feedback-api-lt

Template version description: Initial version with Docker

[체크] Provide guidance to help me set up a template
```

#### Step 2: AMI 선택

```
Application and OS Images (Amazon Machine Image):

  Quick Start:
    → Amazon Linux
    → Amazon Linux 2023 AMI

  AMI ID: ami-0c9c942bd7bf113a2 (예시)
```

#### Step 3: Instance Type

```
Instance type: t3.small

Why?
  - 2 vCPU
  - 2 GiB RAM
  - 적당한 성능/가격
```

#### Step 4: Key Pair

```
Key pair (login):
  → 기존 키 선택 또는 새로 생성

  예: my-keypair
```

#### Step 5: Network Settings

```
Network settings:

⚠️ 여기서는 Subnet 설정 안함!
   (Auto Scaling Group에서 설정)

Security groups:
  → app-sg (미리 만든 것)
```

#### Step 6: Storage

```
Configure storage:

  Volume 1 (Root):
    - Size: 20 GiB
    - Volume type: gp3
    - Delete on termination: Yes
```

#### Step 7: Advanced Details (중요!)

```
Advanced details:

IAM instance profile:
  → ec2-instance-role (미리 만든 것)

Detailed CloudWatch monitoring:
  → Enable (선택)

User data:
  → 여기가 핵심! 👇
```

**User Data 스크립트**:

```bash
#!/bin/bash
set -e

echo "===== Starting User Data Script ====="

# 1. Docker 설치
echo "[1/4] Installing Docker..."
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# 2. Node Exporter 설치 (Prometheus 모니터링용)
echo "[2/4] Installing Node Exporter..."
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd -rs /bin/false node_exporter

cat > /etc/systemd/system/node_exporter.service << 'NODEEOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
NODEEOF

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

# 3. Application 디렉토리
echo "[3/4] Setting up application..."
mkdir -p /opt/feedback-api
cd /opt/feedback-api

# 4. Docker 이미지 Pull 및 실행
echo "[4/4] Starting application..."

# ⭐ 핵심: 여기서 이미지 태그 지정!
IMAGE_TAG="latest"  # 또는 "previous"

docker pull ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

docker run -d \
  --name feedback-api \
  --restart unless-stopped \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:mysql://10.0.11.10:3306/feedbackdb \
  -e SPRING_DATASOURCE_USERNAME=feedbackuser \
  -e SPRING_DATASOURCE_PASSWORD=FeedbackPass123! \
  ghcr.io/johnhuh619/simple-api:${IMAGE_TAG}

echo "===== User Data Script Completed ====="
echo "Application started with image tag: ${IMAGE_TAG}"
```

#### Step 8: 생성!

```
[Create launch template]

✅ Launch template created!
   ID: lt-0123456789abcdef
   Version: 1
```

---

## 🔄 버전 관리

### Launch Template의 강력한 기능!

```
Launch Template은 Git처럼 버전 관리가 됨:

Version 1: latest 이미지 사용
Version 2: previous 이미지 사용 (롤백용)
Version 3: 보안 패치 추가
Version 4: 메모리 증가

각 버전은 독립적으로 유지됨
언제든 원하는 버전으로 전환 가능
```

### 새 버전 만들기

**방법 1: AWS Console**

```
EC2 → Launch Templates → feedback-api-lt

[Actions] → [Modify template (Create new version)]

Description: Rollback to previous image

User data:
  # 변경: IMAGE_TAG="latest" → IMAGE_TAG="previous"
  IMAGE_TAG="previous"
  docker pull ghcr.io/.../app:${IMAGE_TAG}

[Create template version]

✅ Version 2 created!
```

**방법 2: AWS CLI**

```bash
# 현재 버전 확인
aws ec2 describe-launch-templates \
  --launch-template-names feedback-api-lt

# 새 버전 생성 (User Data 변경)
cat > user-data.sh << 'EOF'
#!/bin/bash
IMAGE_TAG="previous"
docker pull ghcr.io/user/app:${IMAGE_TAG}
docker run -d ... ghcr.io/user/app:${IMAGE_TAG}
EOF

# Base64 인코딩
USER_DATA=$(base64 -w 0 user-data.sh)

# 새 버전 생성
aws ec2 create-launch-template-version \
  --launch-template-name feedback-api-lt \
  --launch-template-data "{\"UserData\":\"$USER_DATA\"}" \
  --version-description "Rollback to previous"
```

### 버전 확인

```bash
# 모든 버전 조회
aws ec2 describe-launch-template-versions \
  --launch-template-name feedback-api-lt

# 출력:
LaunchTemplateVersions:
  - VersionNumber: 1
    VersionDescription: Initial version
    CreateTime: 2025-11-17T10:00:00Z

  - VersionNumber: 2
    VersionDescription: Rollback to previous
    CreateTime: 2025-11-17T11:30:00Z
```

---

## 🔗 Auto Scaling Group과 연결

### Launch Template → ASG 연결

```
Auto Scaling Group 생성 시:

[Choose launch template]
  Launch template: feedback-api-lt
  Version:
    ○ Latest  (항상 최신 버전 사용)
    ● Default  (기본 버전 사용)
    ○ Specific version  (특정 버전 지정)

    → Default 선택 (권장)
```

### ASG가 인스턴스 생성하는 과정

```
1. 트리거:
   - Manual: Desired capacity 증가
   - Auto: Scaling policy (CPU > 70%)

2. ASG 동작:
   - Launch Template 확인
   - 설정대로 EC2 인스턴스 생성
   - User Data 실행
   - Target Group에 등록

3. 결과:
   - 똑같은 설정의 서버 생성
   - ALB가 Health Check
   - 트래픽 분산
```

---

## 🎯 롤백에 활용

### 시나리오: 배포 후 롤백

#### 배포 전 상태

```
Launch Template: feedback-api-lt

Version 1 (Default):
  User Data:
    IMAGE_TAG="latest"
    docker pull ghcr.io/.../app:latest

ASG:
  Launch Template: feedback-api-lt (Version 1)
  Instances:
    - Server 1 (latest)
    - Server 2 (latest)
```

#### 새 배포

```
1. GitHub Actions에서 새 이미지 빌드
   - 새 코드 → Docker 이미지
   - ghcr.io/.../app:latest (업데이트)

2. ASG Instance Refresh
   - 기존 인스턴스 종료
   - 새 인스턴스 생성 (새 latest 이미지)

결과:
  - Server 3 (새 latest) ✅
  - Server 4 (새 latest) ✅
```

#### 롤백 필요!

```
1. Launch Template Version 2 생성
   User Data:
     IMAGE_TAG="previous"  # ← 변경!
     docker pull ghcr.io/.../app:previous

2. ASG 업데이트
   Launch Template: feedback-api-lt (Version 2)

3. Instance Refresh 실행
   - Server 3, 4 종료
   - Server 5, 6 생성 (previous 이미지)

결과:
  - Server 5 (previous) ✅ 롤백 완료!
  - Server 6 (previous) ✅ 롤백 완료!
```

---

## 💡 실전 사용법

### 패턴 1: 버전마다 Launch Template 생성

```
배포 흐름:

1. 코드 변경 → 이미지 빌드
   ghcr.io/.../app:sha-abc123

2. Launch Template 새 버전 생성
   User Data:
     IMAGE_TAG="sha-abc123"

3. ASG 업데이트 + Instance Refresh

4. 다음 배포 시 반복

장점: ✅ 명확한 버전 관리
단점: ⚠️ 버전 많아짐
```

### 패턴 2: latest/previous 태그 활용 (추천!)

```
배포 흐름:

1. 배포 시:
   - current latest → previous로 태그
   - 새 이미지 → latest로 태그

   Docker 이미지:
     latest: sha-abc123 (새)
     previous: sha-old999 (이전)

2. Launch Template은 2개만 유지:
   Version 1: IMAGE_TAG="latest"
   Version 2: IMAGE_TAG="previous"

3. 배포:
   - ASG → Version 1 사용

4. 롤백:
   - ASG → Version 2 사용

장점: ✅ 간단
       ✅ 버전 2개만 관리
단점: ⚠️ 2단계 이상 롤백 어려움
```

### 패턴 3: 간소화 (5일 데모용)

```
Launch Template 1개만:
  - Version 1: latest

롤백 시:
  - SSH로 직접 접속
  - docker pull previous
  - docker restart

장점: ✅ 초간단
단점: ⚠️ 수동
```

---

## 🔍 Launch Template vs AMI

### 자주 하는 오해

```
Q: AMI에 Docker 이미지 포함하면 안되나요?

A: 가능하지만 비효율적!

AMI 방식:
  1. EC2 인스턴스 준비
  2. Docker 설치 + 앱 설치
  3. AMI 생성 (스냅샷)
  4. 새 배포마다 새 AMI

  문제:
    ❌ AMI 생성 10-20분
    ❌ AMI 용량 큼 (여러 GB)
    ❌ 관리 복잡

Launch Template + User Data 방식:
  1. 표준 AMI (Amazon Linux)
  2. User Data로 Docker 설치
  3. User Data로 이미지 pull

  장점:
    ✅ AMI 생성 불필요
    ✅ 배포 빠름
    ✅ 유연함
```

### 비교표

| 항목 | AMI | Launch Template |
|------|-----|-----------------|
| **생성 시간** | 10-20분 | 즉시 |
| **크기** | 수 GB | 수 KB |
| **유연성** | 낮음 | 높음 |
| **버전 관리** | 수동 | 자동 |
| **추천** | 기본 설정용 | 애플리케이션 배포 |

---

## 🎓 초보자 FAQ

### Q1: Launch Template은 필수인가요?

```
Auto Scaling 사용 시: 필수!

ASG는 인스턴스 자동 생성 시
Launch Template(또는 구형 Launch Configuration) 필요

수동 EC2 생성: 불필요
```

### Q2: 버전은 몇 개까지?

```
제한 없음 (사실상 무제한)

실전 팁:
  - 배포용: 1-2개 (latest, previous)
  - 환경별: 3-4개 (dev, staging, prod)
  - 실험용: 필요한 만큼

오래된 버전 삭제 가능
```

### Q3: User Data는 매번 실행되나요?

```
No! 인스턴스 최초 시작 시 1회만 실행

시나리오:
  1. ASG가 인스턴스 생성
  2. User Data 실행 (Docker 설치, 앱 시작)
  3. 인스턴스 실행 중
  4. 재부팅 → User Data 실행 안됨!

재실행 원하면:
  - cloud-init 설정 변경
  - 또는 systemd 서비스 사용
```

### Q4: Launch Template 수정하면 기존 서버에 반영되나요?

```
No! 새로 생성되는 인스턴스만 적용

예:
  현재 Server 1, 2 (Version 1)
  Launch Template Version 2 생성

  → Server 1, 2는 그대로
  → Instance Refresh 해야 적용
  → 또는 Auto Scaling으로 새 서버 생성 시 적용
```

### Q5: User Data 디버깅 방법?

```
User Data 실행 로그 확인:

ssh ec2-user@<instance-ip>

# 로그 확인
sudo cat /var/log/cloud-init-output.log

# 또는
sudo cat /var/log/user-data.log

# 실시간 확인
sudo tail -f /var/log/cloud-init-output.log
```

---

## 📊 Launch Template 구조 요약

### 전체 구조

```
Launch Template: feedback-api-lt
│
├── Version 1 (Default)
│   ├── AMI: Amazon Linux 2023
│   ├── Type: t3.small
│   ├── Security Group: app-sg
│   ├── IAM Role: ec2-instance-role
│   └── User Data:
│       ├── Docker 설치
│       ├── Node Exporter 설치
│       └── IMAGE_TAG="latest"
│           docker pull ghcr.io/.../app:latest
│
├── Version 2 (Rollback)
│   ├── AMI: 동일
│   ├── Type: 동일
│   ├── Security Group: 동일
│   ├── IAM Role: 동일
│   └── User Data:
│       ├── Docker 설치
│       ├── Node Exporter 설치
│       └── IMAGE_TAG="previous"  ← 변경!
│           docker pull ghcr.io/.../app:previous
│
└── Version 3 (Future)
    └── ...
```

### ASG 연결

```
Auto Scaling Group: feedback-api-asg
│
├── Launch Template: feedback-api-lt
│   └── Version: Default (= Version 1)
│
├── Desired Capacity: 2
│   ├── Instance 1 (Version 1 기반)
│   └── Instance 2 (Version 1 기반)
│
└── Scaling Policies:
    ├── CPU > 70% → Scale Out
    └── CPU < 30% → Scale In
```

---

## ✅ 핵심 정리

### Launch Template 한 줄 요약

**"Auto Scaling이 서버를 찍어낼 때 사용하는 쿠키 커터"**

### 구성 요소

```
1. 하드웨어:
   - AMI (운영체제)
   - Instance Type (크기)

2. 네트워크:
   - Security Group (방화벽)

3. 소프트웨어:
   - User Data (설치 스크립트)
   - IAM Role (권한)

4. 버전 관리:
   - Version 1, 2, 3...
   - 롤백에 활용
```

### 롤백 핵심

```
1. Launch Template Version 1
   User Data: IMAGE_TAG="latest"

2. Launch Template Version 2
   User Data: IMAGE_TAG="previous"

3. 롤백:
   ASG → Version 2 사용
   Instance Refresh 실행
   → 무중단 롤백 ✅
```

### 만들기 3단계

```
1. AWS Console → Launch Templates → Create
2. AMI, Type, Security Group, User Data 입력
3. Auto Scaling Group에 연결
```

---

**이제 Launch Template 이해되셨나요? 🚀**

**다음 궁금한 점 있으시면 말씀해주세요!**
