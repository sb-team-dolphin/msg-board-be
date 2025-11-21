# 데이터베이스 롤백 전략 가이드

애플리케이션 롤백 시 데이터베이스를 안전하게 처리하는 방법을 설명합니다.

## 목차
1. [문제 이해](#1-문제-이해)
2. [자동 백업 시스템](#2-자동-백업-시스템)
3. [안전한 마이그레이션 패턴](#3-안전한-마이그레이션-패턴)
4. [Flyway를 이용한 버전 관리](#4-flyway를-이용한-버전-관리)
5. [롤백 시나리오별 대응](#5-롤백-시나리오별-대응)
6. [긴급 복구 절차](#6-긴급-복구-절차)

---

## 1. 문제 이해

### 핵심 문제

```
애플리케이션 롤백: v3.0 → v2.0  (쉬움)
데이터베이스: v3.0 스키마 그대로 유지  (문제!)
```

### 위험 시나리오

#### 시나리오 A: 컬럼 추가 (안전) ✅

```sql
-- v2.0 스키마
CREATE TABLE feedback (
    id BIGINT PRIMARY KEY,
    content TEXT
);

-- v3.0 배포: 컬럼 추가
ALTER TABLE feedback ADD COLUMN created_at TIMESTAMP;

-- v2.0으로 롤백
-- ✅ 안전: v2.0은 created_at을 무시하고 정상 작동
```

#### 시나리오 B: 컬럼 삭제 (위험) ⚠️

```sql
-- v2.0 스키마
CREATE TABLE feedback (
    id BIGINT PRIMARY KEY,
    content TEXT,
    legacy_field TEXT  -- v2.0에서 사용 중
);

-- v3.0 배포: 컬럼 삭제
ALTER TABLE feedback DROP COLUMN legacy_field;

-- v2.0으로 롤백
-- ❌ 실패: v2.0이 legacy_field를 찾을 수 없어서 에러!
```

#### 시나리오 C: 타입 변경 (매우 위험) ❌

```sql
-- v2.0: status VARCHAR(50)
'pending', 'in_progress', 'completed'

-- v3.0: status INT로 변경
1, 2, 3

-- v2.0으로 롤백
-- ❌ 완전 실패: v2.0이 INT를 VARCHAR로 읽을 수 없음
```

#### 시나리오 D: 데이터 마이그레이션 (복잡) ⚠️

```sql
-- v2.0: 1000명의 사용자 데이터

-- v3.0 배포 시 마이그레이션
UPDATE users
SET email_verified = true,
    verified_at = NOW()
WHERE email IS NOT NULL;  -- 800명 업데이트

-- v2.0으로 롤백
-- ⚠️ email_verified, verified_at 컬럼을 v2.0이 모름
-- ⚠️ 800명의 변경된 데이터를 어떻게 처리할 것인가?
```

---

## 2. 자동 백업 시스템

### 현재 구현된 자동 백업

**deploy.yml:194-208**

```bash
# 매 배포마다 자동 백업
echo "💾 Backing up database..."
BACKUP_DIR=~/feedback-api/backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -f ~/feedback-api/data/feedbackdb.mv.db ]; then
  cp ~/feedback-api/data/feedbackdb.mv.db \
     "$BACKUP_DIR/feedbackdb_$TIMESTAMP.mv.db"

  # 7일 이상 된 백업 자동 삭제
  find $BACKUP_DIR -name "feedbackdb_*.mv.db" -mtime +7 -delete
fi
```

### 백업 위치

```
~/feedback-api/
├── data/
│   └── feedbackdb.mv.db           # 현재 운영 DB
├── backups/
│   ├── feedbackdb_20251117_120000.mv.db  # 배포 1
│   ├── feedbackdb_20251117_140000.mv.db  # 배포 2
│   └── feedbackdb_20251117_160000.mv.db  # 배포 3
└── data/feedbackdb_before_rollback.mv.db  # 롤백 전 백업
```

### 수동 백업

```bash
# EC2에서 수동 백업
cd ~/feedback-api
BACKUP_NAME="manual_$(date +%Y%m%d_%H%M%S)"
cp data/feedbackdb.mv.db "backups/feedbackdb_$BACKUP_NAME.mv.db"
```

### 백업 복원

```bash
# 1. 백업 목록 확인
ls -lh ~/feedback-api/backups/

# 2. 애플리케이션 중지
cd ~/feedback-api
docker compose down

# 3. 현재 DB 백업 (안전장치)
cp data/feedbackdb.mv.db data/feedbackdb_before_restore.mv.db

# 4. 특정 백업으로 복원
cp backups/feedbackdb_20251117_120000.mv.db data/feedbackdb.mv.db

# 5. 애플리케이션 재시작
docker compose up -d

# 6. 확인
curl http://localhost:8080/actuator/health
```

---

## 3. 안전한 마이그레이션 패턴

### Expand-Migrate-Contract 패턴

가장 안전한 스키마 변경 방법입니다.

#### 예제: status 컬럼 타입 변경 (String → Integer)

**Phase 1: Expand (v3.0 배포)**

```java
@Entity
public class Feedback {
    @Id
    private Long id;

    @Column(name = "status")
    @Deprecated  // 곧 제거 예정 표시
    private String status;  // 기존 컬럼 유지!

    @Column(name = "status_code")
    private Integer statusCode;  // 새 컬럼 추가

    // Dual Write: 양쪽 모두 업데이트
    public void setStatus(String status) {
        this.status = status;
        this.statusCode = convertToCode(status);
    }

    public void setStatusCode(Integer code) {
        this.statusCode = code;
        this.status = convertToString(code);
    }

    // Dual Read: 둘 중 하나라도 있으면 작동
    public Integer getStatusCode() {
        if (statusCode == null && status != null) {
            return convertToCode(status);
        }
        return statusCode;
    }
}
```

**마이그레이션 SQL:**
```sql
-- v3.0
ALTER TABLE feedback ADD COLUMN status_code INT;

-- 기존 데이터 마이그레이션 (백그라운드 작업)
UPDATE feedback
SET status_code = CASE
    WHEN status = 'pending' THEN 1
    WHEN status = 'in_progress' THEN 2
    WHEN status = 'completed' THEN 3
    ELSE 0
END
WHERE status_code IS NULL;
```

**✅ v2.0으로 롤백 가능!**
- status 컬럼이 그대로 있음
- v2.0은 status_code를 무시하고 작동

**Phase 2: Migrate (v3.1 배포)**

```java
// 모든 코드를 statusCode 사용으로 변경
public List<Feedback> getPendingFeedbacks() {
    // ❌ 기존: status = 'pending'
    // ✅ 새로운: statusCode = 1
    return repository.findByStatusCode(1);
}
```

**Phase 3: Contract (v4.0 배포)**

충분한 시간이 지난 후 (최소 1-2주 후):

```java
@Entity
public class Feedback {
    @Id
    private Long id;

    // status 컬럼 완전 제거
    @Column(name = "status_code")
    private Integer statusCode;
}
```

```sql
-- v4.0
ALTER TABLE feedback DROP COLUMN status;
```

**⚠️ v3.0 이전으로는 롤백 불가**

### 컬럼 추가 시 주의사항

```java
// ❌ 나쁜 예: NOT NULL 제약조건
ALTER TABLE users ADD COLUMN email VARCHAR(255) NOT NULL;
-- 기존 데이터가 있으면 실패!

// ✅ 좋은 예: Nullable로 추가 후 데이터 채우고 제약 추가
ALTER TABLE users ADD COLUMN email VARCHAR(255);  -- Nullable
UPDATE users SET email = 'noreply@example.com' WHERE email IS NULL;
ALTER TABLE users ALTER COLUMN email SET NOT NULL;  -- 나중에 추가
```

### 테이블 추가 시 주의사항

```java
// ✅ 새 테이블 추가는 항상 안전
CREATE TABLE notifications (
    id BIGINT PRIMARY KEY,
    user_id BIGINT,
    message TEXT
);

// v2.0으로 롤백해도 문제 없음
// v2.0은 notifications 테이블을 사용하지 않음
```

---

## 4. Flyway를 이용한 버전 관리

### Flyway 설정

**1. build.gradle**

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'com.h2database:h2'
    implementation 'org.flywaydb:flyway-core:10.10.0'
}
```

**2. application.yml**

```yaml
spring:
  flyway:
    enabled: true
    baseline-on-migrate: true
    baseline-version: 0
    locations: classpath:db/migration
    validate-on-migrate: true

  jpa:
    hibernate:
      ddl-auto: validate  # Flyway가 스키마 관리하므로 validate만
```

### 마이그레이션 파일 구조

```
src/main/resources/db/migration/
├── V1__Initial_schema.sql
├── V2__Add_created_at_to_feedback.sql
├── V3__Add_user_table.sql
├── V3.1__Add_email_to_user.sql
├── V4__Add_status_code_to_feedback.sql
└── V5__Remove_old_status_from_feedback.sql
```

### 마이그레이션 파일 예시

**V1__Initial_schema.sql:**
```sql
CREATE TABLE feedback (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feedback_created_at ON feedback(created_at);
```

**V4__Add_status_code_to_feedback.sql:**
```sql
-- Expand 단계: 새 컬럼 추가
ALTER TABLE feedback ADD COLUMN status_code INT;

-- 기존 데이터 마이그레이션
UPDATE feedback
SET status_code = CASE
    WHEN status = 'pending' THEN 1
    WHEN status = 'in_progress' THEN 2
    WHEN status = 'completed' THEN 3
    ELSE 0
END
WHERE status IS NOT NULL;

-- 인덱스 추가 (성능 최적화)
CREATE INDEX idx_feedback_status_code ON feedback(status_code);
```

**V5__Remove_old_status_from_feedback.sql:**
```sql
-- Contract 단계: 오래된 컬럼 제거 (충분한 시간 후)
ALTER TABLE feedback DROP COLUMN status;
```

### Flyway 롤백 (Undo)

Flyway Teams 버전에서만 가능 (유료):

```sql
-- U4__Undo_add_status_code.sql
ALTER TABLE feedback DROP COLUMN status_code;
DROP INDEX IF EXISTS idx_feedback_status_code;
```

무료 버전에서는 수동 롤백 스크립트 작성:

```
src/main/resources/db/rollback/
└── undo_V4.sql  # 수동 롤백 스크립트
```

---

## 5. 롤백 시나리오별 대응

### 시나리오 1: 스키마 변경 없는 배포

```
v2.0 → v3.0: 버그 수정, 성능 개선만
스키마: 변경 없음
```

**롤백 방법:**
```bash
# GitHub Actions로 원클릭 롤백
# DB는 그대로 유지

✅ 안전: 스키마가 같으므로 문제 없음
```

### 시나리오 2: Backward Compatible 변경 (컬럼 추가)

```
v2.0 → v3.0: created_at 컬럼 추가
v3.0 스키마: id, content, created_at
```

**롤백 방법:**
```bash
# 1. 애플리케이션만 롤백 (DB는 그대로)
GitHub Actions → Rollback

# 2. v2.0 시작
# created_at 컬럼을 무시하고 정상 작동

✅ 안전: v2.0은 created_at을 사용하지 않음
```

### 시나리오 3: Breaking Changes (컬럼 삭제/변경)

```
v2.0: status VARCHAR(50) 사용
v3.0: status 삭제, status_code INT 사용
```

**문제:**
```bash
# 애플리케이션만 v2.0으로 롤백하면
v2.0 코드: SELECT status FROM feedback
DB: status 컬럼이 없음!
❌ 에러 발생
```

**해결책 1: DB도 함께 롤백**
```bash
# GitHub Actions Rollback 실행 (자동으로 DB 복원)
# rollback.yml:85-97에서 자동 처리

echo "💾 Finding latest database backup..."
LATEST_BACKUP=$(ls -t ~/feedback-api/backups/feedbackdb_*.mv.db | head -n 1)
cp "$LATEST_BACKUP" ~/feedback-api/data/feedbackdb.mv.db

✅ 애플리케이션 + DB 모두 이전 상태로 복원
```

**해결책 2: 핫픽스 배포**
```sql
-- v3.1로 긴급 배포: status 컬럼 다시 추가
ALTER TABLE feedback ADD COLUMN status VARCHAR(50);

UPDATE feedback
SET status = CASE
    WHEN status_code = 1 THEN 'pending'
    WHEN status_code = 2 THEN 'in_progress'
    WHEN status_code = 3 THEN 'completed'
    ELSE 'unknown'
END;

-- v2.0으로 롤백 가능해짐
```

### 시나리오 4: 데이터 마이그레이션 있는 경우

```
v3.0 배포 시:
- 1000명 사용자 중 800명의 email_verified를 true로 변경
```

**롤백 옵션:**

**A. DB도 함께 롤백 (권장)**
```bash
# 배포 전 백업으로 완전 복원
# 단점: v3.0에서 생성된 새 데이터도 사라짐
```

**B. 애플리케이션만 롤백 + 데이터 유지**
```bash
# v2.0은 email_verified를 무시
# 단점: 데이터 일관성 문제 가능
```

**C. Forward Fix (핫픽스)**
```bash
# v3.1로 버그 수정 후 재배포
# 단점: 시간이 걸림
```

---

## 6. 긴급 복구 절차

### 상황 1: 롤백 후에도 계속 에러

```bash
# 1. 모든 컨테이너 중지
docker compose down
docker stop $(docker ps -aq)

# 2. 가장 최근 안정 백업 확인
cd ~/feedback-api/backups
ls -lht  # 시간순 정렬

# 3. 안정 백업으로 복원
cp feedbackdb_20251117_120000.mv.db ../data/feedbackdb.mv.db

# 4. 안정 버전 이미지로 강제 배포
docker pull ghcr.io/johnhuh619/simple-api:sha-2741b1c
sed -i 's/:latest/:sha-2741b1c/g' docker-compose.yml

# 5. 재시작
docker compose up -d

# 6. 확인
sleep 40
curl http://localhost:8080/actuator/health
```

### 상황 2: DB 파일 손상

```bash
# 1. 손상된 DB 격리
cd ~/feedback-api
mv data/feedbackdb.mv.db data/feedbackdb_corrupted.mv.db

# 2. 가장 최근 백업 복원
cp backups/feedbackdb_20251117_140000.mv.db data/feedbackdb.mv.db

# 3. 재시작
docker compose restart

# 4. 손상된 DB 분석 (나중에)
# H2 console로 접속해서 확인
```

### 상황 3: 모든 백업 손실

```bash
# 최악의 상황: 새로 시작

# 1. 데이터베이스 초기화
cd ~/feedback-api
rm -rf data/*

# 2. 안정 버전으로 재시작
docker compose up -d

# 3. Flyway가 자동으로 스키마 생성
# V1__Initial_schema.sql부터 순차 실행

# ⚠️ 모든 데이터 손실!
```

---

## 권장 사항 요약

### 필수 (Must)

1. **✅ 매 배포마다 자동 DB 백업** (구현됨)
2. **✅ Backward Compatible 마이그레이션**
3. **✅ Expand-Migrate-Contract 패턴 사용**

### 권장 (Should)

4. **Flyway로 마이그레이션 버전 관리**
5. **중요 배포 전 수동 백업**
6. **롤백 테스트 정기 실행**

### 선택 (Could)

7. **Feature Flags로 배포/출시 분리**
8. **Blue-Green 배포로 무중단 롤백**
9. **S3로 백업 자동 업로드**

---

## 체크리스트

### 배포 전

- [ ] 스키마 변경 사항 확인
- [ ] Breaking Changes 여부 확인
- [ ] Backward Compatible한지 검토
- [ ] 수동 DB 백업 실행 (중요 배포)
- [ ] 롤백 시나리오 검토

### 배포 중

- [ ] 자동 DB 백업 확인
- [ ] 마이그레이션 성공 확인
- [ ] Health Check 통과 확인

### 롤백 시

- [ ] 롤백 사유 명확히 파악
- [ ] DB 스키마 호환성 확인
- [ ] DB 복원 필요 여부 결정
- [ ] 롤백 후 데이터 검증
- [ ] CloudWatch 로그 확인

---

## 참고 자료

- [Flyway 공식 문서](https://flywaydb.org/documentation/)
- [Expand-Migrate-Contract 패턴](https://openpracticelibrary.com/practice/expand-contract-pattern/)
- [Zero-Downtime Deployments](https://www.martinfowler.com/bliki/BlueGreenDeployment.html)
- [Database Refactoring](https://databaserefactoring.com/)
