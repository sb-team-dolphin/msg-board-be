# Dockerfile vs docker-compose.yml

**질문**: 왜 2개 파일이 필요한가요?

**답변**: 각각 **완전히 다른 일**을 하기 때문입니다!

---

## 🍳 요리 비유로 이해하기

```
Dockerfile           = 요리 레시피 📖
                      (어떻게 만들지)

docker-compose.yml  = 식탁 차리기 🍽️
                      (어떻게 서빙할지)
```

### 구체적 예시

**Dockerfile** (레시피):
```
1. 밀가루, 달걀, 우유를 준비한다
2. 섞는다
3. 팬에 굽는다
→ 결과: 팬케이크 완성!
```

**docker-compose.yml** (서빙):
```
- 접시: 도자기 접시
- 위치: 테이블 중앙
- 토핑: 메이플 시럽 + 버터
- 음료: 오렌지 주스
- 온도: 따뜻하게 유지
→ 결과: 먹을 수 있는 상태로 세팅!
```

---

## 📦 Docker 용어로 이해하기

| 구분 | Dockerfile | docker-compose.yml |
|------|-----------|-------------------|
| **역할** | 이미지 **만들기** | 컨테이너 **실행하기** |
| **명령어** | `docker build` | `docker compose up` |
| **결과물** | Docker Image | 실행 중인 Container |
| **비유** | 설계도 | 실행 환경 |
| **단계** | 1단계 (빌드) | 2단계 (실행) |

---

## 🔍 현재 프로젝트에서 각 파일이 하는 일

### Dockerfile이 하는 일

**목적**: Spring Boot 애플리케이션을 실행 가능한 **이미지로 빌드**

```dockerfile
# Dockerfile

# 1단계: Gradle로 JAR 파일 빌드
FROM gradle:8.10.2-jdk21-alpine AS builder
COPY src ./src
RUN ./gradlew bootJar
→ 결과: app.jar 파일 생성

# 2단계: 실행 환경 준비
FROM eclipse-temurin:21-jre-alpine
COPY --from=builder /app/build/libs/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
→ 결과: 실행 가능한 이미지
```

**핵심**:
- ✅ 어떤 베이스 이미지 사용할지 (JDK 21)
- ✅ 소스 코드를 어떻게 빌드할지 (Gradle)
- ✅ 어떤 파일들을 포함할지 (app.jar)
- ✅ 어떻게 실행할지 (java -jar)

**생성 명령**:
```bash
docker build -t feedback-api:latest .
```

**결과**: `feedback-api:latest` 이미지 생성 (아직 실행 안됨)

---

### docker-compose.yml이 하는 일

**목적**: 만들어진 이미지를 **어떻게 실행할지** 설정

```yaml
# docker-compose.yml

services:
  feedback-api:
    image: feedback-api:latest    # ← Dockerfile로 만든 이미지 사용
    ports:
      - "8080:8080"                # 포트 연결
    volumes:
      - feedback-data:/app/data    # 데이터 저장 위치
    environment:
      - SPRING_PROFILES_ACTIVE=prod  # 환경변수
    restart: unless-stopped        # 재시작 정책
```

**핵심**:
- ✅ 어떤 포트로 열지 (8080)
- ✅ 데이터를 어디에 저장할지 (volume)
- ✅ 환경변수는 뭘 쓸지 (SPRING_PROFILES_ACTIVE)
- ✅ 재시작 정책은 어떻게 할지
- ✅ 네트워크는 어떻게 구성할지

**실행 명령**:
```bash
docker compose up -d
```

**결과**: 실제 실행 중인 컨테이너 (접속 가능)

---

## 🎯 왜 분리되어 있나요?

### 이유 1: 재사용성

**Dockerfile**: 한 번만 작성
```dockerfile
# 동일한 이미지
FROM openjdk:21
COPY app.jar .
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**docker-compose.yml**: 환경마다 다르게
```yaml
# 개발 환경
environment:
  - SPRING_PROFILES_ACTIVE=dev
  - DEBUG=true
ports:
  - "8080:8080"

---

# 프로덕션 환경
environment:
  - SPRING_PROFILES_ACTIVE=prod
  - DEBUG=false
ports:
  - "80:8080"
```

→ **같은 이미지, 다른 실행 환경**

### 이유 2: 관심사의 분리

```
Dockerfile         → 개발자 관심사
- 어떤 언어/프레임워크
- 어떻게 빌드
- 어떤 의존성

docker-compose.yml → 운영자 관심사
- 어떤 포트
- 어떤 리소스 (CPU, 메모리)
- 어떤 네트워크
```

### 이유 3: 멀티 컨테이너 관리

**Dockerfile**: 컨테이너 1개만
```dockerfile
# 애플리케이션 이미지만 정의
FROM openjdk:21
...
```

**docker-compose.yml**: 여러 컨테이너 조합
```yaml
services:
  api:
    image: my-api

  database:
    image: postgres:15

  redis:
    image: redis:7

  nginx:
    image: nginx:latest
```

→ **전체 시스템 구성**

---

## 📚 실제 워크플로우

### 로컬 개발

```bash
# 1. 이미지 빌드 (Dockerfile 사용)
docker build -t feedback-api:latest .

# 2. 컨테이너 실행 (docker-compose.yml 사용)
docker compose up -d

# 결과: 로컬에서 실행 중
curl http://localhost:8080/api/feedbacks
```

### 프로덕션 배포 (CI/CD)

```bash
# GitHub Actions에서

# 1. 이미지 빌드 (Dockerfile)
docker build -t ghcr.io/user/feedback-api:latest .

# 2. 이미지 푸시
docker push ghcr.io/user/feedback-api:latest

# 3. EC2에서 실행 (docker-compose.yml)
ssh ec2-user@server
docker pull ghcr.io/user/feedback-api:latest
docker compose up -d
```

---

## 🤔 자주 묻는 질문

### Q1: Dockerfile 없이 docker-compose.yml만 쓰면 안되나요?

**A**: 가능하지만 제한적입니다.

```yaml
# 케이스 1: 공개 이미지 사용 (Dockerfile 불필요)
services:
  database:
    image: postgres:15  # Docker Hub에서 가져옴
```

```yaml
# 케이스 2: 커스텀 앱 (Dockerfile 필요!)
services:
  my-app:
    build: .  # ← Dockerfile 필요
```

→ **커스텀 애플리케이션은 Dockerfile 필수**

### Q2: docker-compose.yml 없이 Dockerfile만 쓰면?

**A**: 가능하지만 불편합니다.

**docker-compose.yml 없이**:
```bash
docker build -t my-app .
docker run -d \
  -p 8080:8080 \
  -v feedback-data:/app/data \
  -v feedback-logs:/app/logs \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e JAVA_OPTS="-Xmx512m" \
  -e SPRING_DATASOURCE_URL="jdbc:h2:file:/app/data/feedbackdb" \
  --restart unless-stopped \
  --name feedback-api \
  my-app
```
→ 😱 명령어 너무 김!

**docker-compose.yml 사용**:
```bash
docker compose up -d
```
→ 😊 간단!

### Q3: 그럼 둘 다 필요한 거네요?

**A**: 네! 각자 역할이 명확합니다.

```
Dockerfile        → 무엇을 (What to run)
docker-compose.yml → 어떻게 (How to run)
```

---

## 💡 현재 프로젝트 정리

### 우리 프로젝트에서

**Dockerfile의 역할**:
```
1. Gradle로 Spring Boot 앱 빌드
2. JRE 21 환경 준비
3. 보안 (non-root user 생성)
4. Health check 설정
5. JAR 실행 명령 정의

→ 결과: feedback-api:latest 이미지
```

**docker-compose.yml의 역할**:
```
1. 위 이미지를 8080 포트로 실행
2. Docker volume에 데이터 저장
3. 프로덕션 환경변수 주입
4. 자동 재시작 설정
5. 네트워크 구성

→ 결과: 실제 동작하는 서비스
```

---

## 🎯 결론

### 왜 2개 파일인가?

```
Dockerfile:
  "이미지 만드는 법" 📦
  - 빌드 과정
  - 의존성 설치
  - 실행 명령

docker-compose.yml:
  "컨테이너 실행 설정" 🚀
  - 포트 매핑
  - 볼륨 연결
  - 환경변수
  - 네트워크
```

### 비유 정리

```
Dockerfile         = 자동차 설계도
                    (엔진, 바퀴, 핸들 어떻게 조립)

docker-compose.yml = 자동차 운전 설정
                    (시트 위치, 라디오 채널, 에어컨 온도)
```

### 마지막 한 줄 요약

> **Dockerfile은 "만들기", docker-compose.yml은 "실행하기"**

**둘 다 필요하고, 의도적으로 분리되어 있습니다!** ✅

---

## 📖 더 알아보기

### Dockerfile 자세히
- `Dockerfile` (1-50줄): 멀티 스테이지 빌드로 이미지 최적화

### docker-compose.yml 자세히
- `docker-compose.yml` (1-45줄): 볼륨, 네트워크, 헬스체크 설정

### 함께 동작하는 방식
```bash
# 로컬
docker compose up --build  # 빌드 + 실행 동시에

# 프로덕션
docker build -t image .    # 빌드 (CI)
docker compose up -d       # 실행 (CD)
```
