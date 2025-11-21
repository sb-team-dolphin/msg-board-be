# Simple API [배포 과정을 구현]

## 관련 레포지토리
- **프론트엔드**: https://github.com/johnhuh619/simple-api-frontend
- **백엔드**: 현재 레포

## 프로젝트 한눈에 보기
- Spring Boot 3.5와 Java 21을 사용하는 간단한 REST API입니다(`build.gradle`에서 확인).
- CI/CD 파이프라인은 GitHub Actions → GHCR → AWS EC2 컨테이너 재배포 순서로 구성했습니다.
- 로컬과 EC2 모두 Docker 기반으로 동일한 실행 환경을 맞추는 것을 목표로 했습니다.
- 프론트엔드는 별도 레포로 분리되어 CloudFront + S3로 독립 배포됩니다.

## 파일별로 정리한 배운 점

### Gradle 빌드 파이프라인 (`build.gradle`)
- `bootJar` 작업에 `mainClass`를 명시하고 `jar` 작업은 비활성화하여 배포 아티팩트를 fat jar 하나로 일관되게 유지했습니다.
- Gradle Wrapper와 의존성을 Docker 빌드 컨텍스트에 포함시키고, 캐시 워밍 단계(`./gradlew dependencies`)를 분리해 CI 환경에서 빌드 시간을 줄일 수 있음을 확인했습니다.
- Groovy DSL에서 Boolean 값을 소문자로 적어야 하는 등 Gradle 8.x 문법 차이를 트러블슈팅하면서 Spring Boot Gradle 플러그인 구성을 더 잘 이해하게 됐습니다.

### 컨테이너 이미지 빌드 (`docker/Dockerfile`)
- 멀티 스테이지 빌드로 빌드 단계와 런타임 단계를 분리하고, 최종 이미지를 `eclipse-temurin:21-jre-jammy`로 경량화해 배포 이미지를 가볍게 유지했습니다.
- Layertools로 레이어를 쪼갤 때 classpath 구성이 까다롭다는 점을 체감했고, 장애 시에는 fat jar를 그대로 실행하는 `ENTRYPOINT ["java", "-jar", "/app/app.jar"]` 방식이 더 안전하다는 교훈을 얻었습니다.
- 빌드 캐시가 잘 작동하도록 Gradle 관련 파일을 명확하게 COPY함으로써 Docker 레이어 캐싱의 중요성을 체험했습니다.

### 로컬 실행 및 검증 (`docker/docker-compose.yml`)
- GHCR에 푸시된 이미지를 그대로 가져와 기동하면서 운영과 동일한 이미지를 로컬에서 재현하는 방법을 익혔습니다.
- `ports: "8080:8080"` 매핑과 `curl`/Postman을 활용해 API를 검증하고, Actuator health endpoint까지 포함한 기본 진단 루틴을 마련했습니다.
- 이미지 레퍼런스를 `ghcr.io/<owner>/<repo>:tag` 형태로 일관되게 유지해야 CI/CD 파이프라인에서 배포한 아티팩트와 정확히 일치한다는 것을 확인했습니다.

### 배포 자동화 (`.github/workflows/deploy.yml`)
- 빌드와 배포 Job을 분리하고 `needs`로 순서를 제어해 실패 지점을 빠르게 파악할 수 있었습니다.
- SSH 배포 단계에서 컨테이너 기동을 기다리는 `sleep 30`이 없다면 health check가 실패해 롤백된다는 사실을 실전으로 확인했습니다.
- `curl -f http://localhost:8080/actuator/health`로 헬스체크를 수행할 때 컨테이너 내부 네트워크 조건(포트, 보안 그룹)까지 함께 살펴야 의미가 있다는 점을 배웠습니다.

## 트러블슈팅 타임라인 요약
1. **Gradle 빌드 오류**: CI에서 `bootJar` 설정이 잘못되어 실패 → Groovy 문법으로 수정 후 해결.
2. **Docker COPY 경로 문제**: `gradle/` 디렉터리가 빌드 컨텍스트에 포함되지 않아 checksum 오류 → `.dockerignore`와 COPY 경로 점검으로 해결.
3. **JarLauncher 실행 실패**: layertools 추출 후 classpath가 맞지 않아 `Start-Class`를 찾지 못함 → fat jar 직접 실행으로 전환.
4. **EC2 포트 접근 불가**: 애플리케이션은 살아 있지만 외부 접근 불가 → AWS 보안 그룹에서 8080 포트 개방.
5. **배포 후 헬스체크 실패**: 컨테이너 기동 시간이 충분하지 않아 GitHub Actions에서 롤백 → 기동 대기 시간 추가로 안정화.

# Updated
