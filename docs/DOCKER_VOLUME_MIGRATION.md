# Docker Volume 마이그레이션 가이드

Bind Mount에서 Docker Volume로 전환하여 권한 문제를 원천 차단합니다.

## 목차
1. [왜 Docker Volume인가?](#왜-docker-volume인가)
2. [마이그레이션 절차](#마이그레이션-절차)
3. [변경된 운영 방법](#변경된-운영-방법)
4. [트러블슈팅](#트러블슈팅)

---

## 왜 Docker Volume인가?

### 기존 문제 (Bind Mount)

```yaml
# docker-compose.yml (이전)
volumes:
  - ./data:/app/data      # Host directory
  - ./logs:/app/logs      # Host directory

문제점:
❌ 권한 충돌 (Host UID vs Container UID 1001)
   - cp: cannot create regular file: Permission denied
   - chown 명령 필요

❌ 플랫폼 의존적
   - Windows: 성능 저하
   - Mac: 파일 시스템 동기화 문제

❌ 수동 설정 필요
   - mkdir -p 명령 필요
   - chown -R 1001:1001 명령 필요

❌ 보안 취약
   - Host 파일 시스템 노출
```

### 개선 방안 (Docker Volume)

```yaml
# docker-compose.yml (이후)
volumes:
  - feedback-data:/app/data   # Docker managed
  - feedback-logs:/app/logs   # Docker managed

volumes:
  feedback-data:
  feedback-logs:

장점:
✅ Docker가 권한 자동 관리
   - UID 1001 자동 적용
   - chown 불필요

✅ 플랫폼 독립적
   - Windows/Mac/Linux 모두 동일

✅ 자동 생성
   - mkdir 불필요
   - docker volume create로 자동 생성

✅ 더 나은 성능
   - 특히 Mac/Windows에서 빠름

✅ 격리 및 보안
   - Host 파일 시스템과 완전 분리
```

---

## 마이그레이션 절차

### Phase 1: 현재 데이터 백업 (필수!)

```bash
# EC2에 SSH 접속
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2-IP>

cd ~/feedback-api

# 1. 현재 컨테이너 중지
docker compose down

# 2. 기존 데이터 압축 백업
tar -czf data-backup-$(date +%Y%m%d_%H%M%S).tar.gz data/

# 3. S3에도 업로드 (안전 장치)
aws s3 cp data-backup-*.tar.gz \
  s3://feedback-api-backups-396468676673/migration/ \
  --region ap-northeast-2

# 4. 백업 확인
ls -lh data-backup-*.tar.gz
```

### Phase 2: Docker Volume 생성

```bash
# Named volume 생성
docker volume create feedback-data
docker volume create feedback-logs

# Volume 확인
docker volume ls
# DRIVER    VOLUME NAME
# local     feedback-data
# local     feedback-logs

# Volume 상세 정보
docker volume inspect feedback-data
```

**출력 예시:**
```json
[
    {
        "CreatedAt": "2025-11-17T10:00:00Z",
        "Driver": "local",
        "Labels": null,
        "Mountpoint": "/var/lib/docker/volumes/feedback-data/_data",
        "Name": "feedback-data",
        "Options": null,
        "Scope": "local"
    }
]
```

### Phase 3: 기존 데이터를 Volume으로 복사

```bash
# 데이터 복사 (모든 파일과 권한 유지)
docker run --rm \
  -v $(pwd)/data:/source:ro \
  -v feedback-data:/dest \
  alpine \
  sh -c "cp -a /source/. /dest/ && chown -R 1001:1001 /dest"

# 로그 디렉토리도 복사 (있는 경우)
if [ -d "logs" ]; then
  docker run --rm \
    -v $(pwd)/logs:/source:ro \
    -v feedback-logs:/dest \
    alpine \
    sh -c "cp -a /source/. /dest/ && chown -R 1001:1001 /dest"
fi

# 복사 확인
echo "=== Data Volume Contents ==="
docker run --rm \
  -v feedback-data:/data \
  alpine \
  ls -lh /data

echo "=== Database File Check ==="
docker run --rm \
  -v feedback-data:/data \
  alpine \
  ls -lh /data/feedbackdb.mv.db
```

### Phase 4: docker-compose.yml 업데이트

파일이 이미 업데이트되어 있습니다:

```yaml
# docker-compose.yml
services:
  feedback-api:
    volumes:
      - feedback-data:/app/data    # ← 변경됨
      - feedback-logs:/app/logs    # ← 변경됨

volumes:  # ← 추가됨
  feedback-data:
    name: feedback-data
  feedback-logs:
    name: feedback-logs
```

### Phase 5: 새 설정으로 시작

```bash
# docker-compose.yml 다운로드 (GitHub에서 최신 버전)
curl -o docker-compose.yml \
  https://raw.githubusercontent.com/johnhuh619/simple-api/main/docker-compose.yml

# 컨테이너 시작
docker compose up -d

# 로그 확인
docker compose logs -f

# Health check
sleep 40
curl http://localhost:8080/actuator/health
```

### Phase 6: 검증

```bash
# 1. 컨테이너 상태 확인
docker compose ps
# NAME           IMAGE                  STATUS
# feedback-api   feedback-api:latest    Up X minutes (healthy)

# 2. 데이터베이스 파일 확인
docker run --rm \
  -v feedback-data:/data \
  alpine \
  ls -lh /data/feedbackdb.mv.db

# 3. API 테스트
curl http://localhost:8080/api/feedbacks

# 4. H2 Console 접속
# http://<EC2-IP>:8080/h2-console
# JDBC URL: jdbc:h2:file:/app/data/feedbackdb
```

### Phase 7: 정리 (검증 완료 후)

```bash
# 기존 bind mount 디렉토리 정리
mv data data.old
mv logs logs.old

# 일주일 후 문제 없으면 삭제
# rm -rf data.old logs.old
```

---

## 변경된 운영 방법

### 1. 백업 방법 변경

#### 이전 (Bind Mount)

```bash
# 직접 파일 복사
cp ~/feedback-api/data/feedbackdb.mv.db backups/
```

#### 이후 (Docker Volume)

```bash
# 임시 컨테이너를 통한 복사
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker run --rm \
  -v feedback-data:/data:ro \
  -v ~/feedback-api/backups:/backup \
  alpine \
  cp /data/feedbackdb.mv.db /backup/feedbackdb_$TIMESTAMP.mv.db

echo "Backup created: backups/feedbackdb_$TIMESTAMP.mv.db"
```

**자동화된 백업 (deploy.yml):**
배포 시 자동으로 위 방식으로 백업됩니다.

### 2. 데이터 확인 방법

#### 이전 (Bind Mount)

```bash
# 직접 확인
ls -lh ~/feedback-api/data/
cat ~/feedback-api/logs/app.log
```

#### 이후 (Docker Volume)

```bash
# Volume 내용 확인
docker run --rm \
  -v feedback-data:/data \
  alpine \
  ls -lh /data

# 파일 읽기
docker run --rm \
  -v feedback-data:/data \
  alpine \
  cat /data/feedbackdb.mv.db

# 또는 실행 중인 컨테이너로 접근
docker exec feedback-api ls -lh /app/data
docker exec feedback-api cat /app/logs/app.log
```

### 3. 복원 방법

#### 백업에서 복원

```bash
# 1. 컨테이너 중지
docker compose down

# 2. Volume에 복사
docker run --rm \
  -v feedback-data:/data \
  -v ~/feedback-api/backups:/backup \
  alpine \
  sh -c "cp /backup/feedbackdb_20251117_120000.mv.db /data/feedbackdb.mv.db && \
         chown 1001:1001 /data/feedbackdb.mv.db"

# 3. 컨테이너 재시작
docker compose up -d
```

#### S3에서 복원

```bash
# 1. S3에서 다운로드
aws s3 cp \
  s3://feedback-api-backups-396468676673/2025/11/17/feedbackdb_20251117_120000.mv.db \
  ~/feedback-api/backups/ \
  --region ap-northeast-2

# 2. Volume에 복사
docker run --rm \
  -v feedback-data:/data \
  -v ~/feedback-api/backups:/backup \
  alpine \
  sh -c "cp /backup/feedbackdb_20251117_120000.mv.db /data/feedbackdb.mv.db && \
         chown 1001:1001 /data/feedbackdb.mv.db"

# 3. 재시작
docker compose up -d
```

### 4. Volume 관리

#### Volume 목록 확인

```bash
docker volume ls
```

#### Volume 크기 확인

```bash
docker system df -v | grep feedback
```

#### Volume 상세 정보

```bash
docker volume inspect feedback-data
```

#### Volume 백업 (전체)

```bash
# Volume 전체를 tar로 백업
docker run --rm \
  -v feedback-data:/data:ro \
  -v $(pwd):/backup \
  alpine \
  tar czf /backup/feedback-data-full-$(date +%Y%m%d).tar.gz -C /data .
```

#### Volume 삭제 (주의!)

```bash
# 컨테이너 먼저 중지
docker compose down

# Volume 삭제
docker volume rm feedback-data feedback-logs

# ⚠️ 데이터 영구 손실! 백업 필수!
```

---

## 트러블슈팅

### 1. 마이그레이션 후 데이터 없음

**증상:**
```bash
curl http://localhost:8080/api/feedbacks
# 빈 배열 [] 반환
```

**원인:**
- 데이터 복사 실패
- Volume이 비어있음

**해결:**
```bash
# 1. 컨테이너 중지
docker compose down

# 2. Volume 내용 확인
docker run --rm -v feedback-data:/data alpine ls -lh /data
# 비어있으면 다시 복사

# 3. 백업에서 복원
docker run --rm \
  -v $(pwd)/data.old:/source:ro \
  -v feedback-data:/dest \
  alpine \
  sh -c "cp -a /source/. /dest/ && chown -R 1001:1001 /dest"

# 4. 재시작
docker compose up -d
```

### 2. 권한 에러 (여전히 발생)

**증상:**
```
org.h2.mvstore.MVStoreException: Could not open file
java.nio.file.AccessDeniedException: /app/data/feedbackdb.mv.db
```

**원인:**
- Volume 내 파일 소유자가 1001이 아님

**해결:**
```bash
# Volume 내 모든 파일 소유자 변경
docker run --rm \
  -v feedback-data:/data \
  alpine \
  chown -R 1001:1001 /data

# 재시작
docker compose restart
```

### 3. Volume이 생성되지 않음

**증상:**
```bash
docker volume ls
# feedback-data, feedback-logs가 없음
```

**해결:**
```bash
# 수동으로 생성
docker volume create feedback-data
docker volume create feedback-logs

# docker-compose로 자동 생성
docker compose up -d
```

### 4. 백업 실패

**증상:**
```bash
# deploy.yml에서
⚠️ No database found in volume, skipping backup
```

**원인:**
- Volume이 비어있음
- 파일 경로 오류

**해결:**
```bash
# Volume 내용 확인
docker run --rm -v feedback-data:/data alpine ls -lh /data

# 파일 있는지 확인
docker run --rm -v feedback-data:/data alpine \
  test -f /data/feedbackdb.mv.db && echo "EXISTS" || echo "NOT FOUND"
```

### 5. Volume 크기 증가

**증상:**
```bash
docker system df -v
# feedback-data: 5GB
```

**해결:**
```bash
# H2 데이터베이스 정리 (애플리케이션 레벨)
# 또는 오래된 데이터 삭제

# Volume 내용 확인
docker run --rm -v feedback-data:/data alpine du -sh /data/*
```

---

## 주의사항

### 1. Volume은 삭제 시 영구 손실

```bash
# ❌ 위험: Volume 삭제
docker volume rm feedback-data
# 모든 데이터 영구 손실!

# ✅ 안전: 백업 후 삭제
# 1. 백업
docker run --rm \
  -v feedback-data:/data \
  -v $(pwd):/backup \
  alpine \
  tar czf /backup/before-delete.tar.gz -C /data .

# 2. 삭제
docker volume rm feedback-data
```

### 2. 컨테이너 재생성 시 Volume 유지

```bash
# docker compose down은 Volume을 삭제하지 않음
docker compose down
# Volume은 그대로 유지 ✅

# Volume까지 삭제하려면 (주의!)
docker compose down -v
# ⚠️ 데이터 손실!
```

### 3. Volume 이름 변경 불가

```yaml
# ❌ 이름 변경 안 됨
volumes:
  new-name:/app/data  # 기존 데이터 손실

# ✅ 데이터 복사 필요
# 1. 새 Volume 생성
docker volume create new-name

# 2. 데이터 복사
docker run --rm \
  -v feedback-data:/source:ro \
  -v new-name:/dest \
  alpine \
  sh -c "cp -a /source/. /dest/"
```

---

## 롤백 계획

마이그레이션 후 문제가 생기면 Bind Mount로 되돌리기:

```bash
# 1. 컨테이너 중지
docker compose down

# 2. Volume에서 데이터 복사
docker run --rm \
  -v feedback-data:/source:ro \
  -v $(pwd)/data:/dest \
  alpine \
  sh -c "cp -a /source/. /dest/ && chown -R $(id -u):$(id -g) /dest"

# 3. docker-compose.yml을 이전 버전으로 복원
git checkout HEAD~1 docker-compose.yml

# 4. 재시작
docker compose up -d
```

---

## 요약

### 마이그레이션 체크리스트

- [ ] 현재 데이터 백업 (tar.gz + S3)
- [ ] Docker Volume 생성
- [ ] 데이터 복사 및 검증
- [ ] docker-compose.yml 업데이트
- [ ] 새 설정으로 시작
- [ ] API 테스트 및 검증
- [ ] 1주일 모니터링
- [ ] 기존 디렉토리 정리

### 기대 효과

✅ 권한 문제 완전 해결
✅ chown 명령 불필요
✅ 플랫폼 독립적
✅ 더 나은 성능 (특히 Mac/Windows)
✅ 격리 및 보안 향상

### 주의사항

⚠️ 백업 방법 변경 (임시 컨테이너 사용)
⚠️ 직접 파일 접근 불가 (docker run 필요)
⚠️ Volume 삭제 시 데이터 영구 손실

---

## 다음 단계

1. **로컬에서 먼저 테스트**
   ```bash
   # 로컬에서 docker-compose.yml 테스트
   docker compose up -d
   ```

2. **EC2에서 마이그레이션**
   - 낮은 트래픽 시간대 선택
   - 백업 확인
   - 단계별 진행

3. **모니터링**
   - CloudWatch Logs 확인
   - Health check 모니터링
   - 1주일 관찰

4. **정리**
   - 기존 디렉토리 삭제
   - 문서화
