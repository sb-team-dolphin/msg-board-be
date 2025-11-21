# Deployment Status - Hibernate SEQUENCES Fix

## Last Commit
```
9ce2516 fix: Force Docker rebuild for Hibernate SEQUENCES fix
```

## Problem Being Fixed
**Issue**: `java.sql.SQLSyntaxErrorException: Unknown table 'SEQUENCES' in information_schema`

**Root Cause**: Hibernate trying to query MySQL information_schema.SEQUENCES table which doesn't exist in MySQL 8.0 (only in MariaDB)

## Solution Applied
Added to `src/main/resources/application-prod.yml`:

```yaml
jpa:
  properties:
    hibernate:
      dialect:
        database_minor_version: 0
      temp:
        use_jdbc_metadata_defaults: false
```

This configuration tells Hibernate to skip JDBC metadata queries for sequence information.

## Deployment Flow (Currently In Progress)

### 1. GitHub Actions Build (build-and-push job)
- ✅ Checkout code (includes updated application-prod.yml)
- ✅ Setup JDK 21
- ✅ Build JAR with `./gradlew bootJar`
  - JAR will include: `BOOT-INF/classes/application-prod.yml` with Hibernate fix
- ✅ Login to GHCR
- ✅ Save current latest image as previous (for rollback)
- ✅ Build Docker image
  - Stage 1: Copy src/ and build JAR
  - Stage 2: Copy JAR to runtime image
- ✅ Push to `ghcr.io/johnhuh619/simple-api:latest`

### 2. GitHub Actions Deploy (deploy job)
- ✅ SSH to EC2
- ✅ Create docker-compose.yml with RDS environment variables
- ✅ Pull latest image from GHCR
- ✅ Stop old container
- ✅ Start new container
- ⏳ Wait 40 seconds for startup
- ⏳ Health check: `curl -f http://localhost:8080/actuator/health`

### Expected Result
**✅ SUCCESS**: Application starts without SEQUENCES error, health check passes

**Verification**:
1. Check GitHub Actions: https://github.com/johnhuh619/simple-api/actions
2. Look for workflow run triggered at the time of your push
3. Check "deploy" job logs for:
   ```
   ✅ Deployment succeeded!
   📊 Container status:
   💾 Database: Using RDS MySQL
   ```

## If Deployment Succeeds

### What Happened
- Hibernate successfully connected to RDS MySQL
- Hibernate created tables automatically (`ddl-auto: update`)
- No SEQUENCES error because metadata defaults are disabled
- Application is now running and healthy

### Next Steps
1. Test API endpoints:
   ```bash
   # From local machine or EC2
   curl http://<EC2_PUBLIC_IP>:8080/actuator/health
   curl http://<EC2_PUBLIC_IP>:8080/api/feedback
   ```

2. Verify tables were created in RDS:
   ```bash
   # SSH to EC2
   mysql -h feedback-db.xxxxx.rds.amazonaws.com -u admin -pdolphin1234 feedbackdb

   # Check tables
   SHOW TABLES;
   DESCRIBE feedback;
   ```

3. Test frontend on CloudFront (should connect to EC2 backend)

## If Deployment Still Fails

### Troubleshooting Steps

1. **Verify Docker image was rebuilt**:
   ```bash
   # SSH to EC2
   docker images ghcr.io/johnhuh619/simple-api

   # Check image digest - should be different from previous
   docker inspect ghcr.io/johnhuh619/simple-api:latest | grep Created
   ```

2. **Verify JAR contains fix**:
   ```bash
   # On EC2
   docker run --rm ghcr.io/johnhuh619/simple-api:latest sh -c \
     "unzip -p app.jar BOOT-INF/classes/application-prod.yml | grep -A 5 'SEQUENCES'"

   # Should show:
   # MySQL 8.0 SEQUENCES 테이블 문제 해결
   # dialect:
   #   database_minor_version: 0
   # temp:
   #   use_jdbc_metadata_defaults: false
   ```

3. **Check detailed application logs**:
   ```bash
   # On EC2
   docker logs feedback-api 2>&1 | grep -i "sequences\|hibernate\|dialect"
   ```

4. **Alternative fix** (if still failing):
   Change Hibernate DDL strategy to validate instead of update:
   ```yaml
   jpa:
     hibernate:
       ddl-auto: validate  # Instead of update
   ```
   Then manually create tables using SQL script.

## Files Modified
- ✅ `src/main/resources/application-prod.yml` - Added Hibernate MySQL 8.0 fix
- ✅ `docker-compose.yml` - Added `external: true` for feedback-logs volume
- ✅ `README.md` - Updated documentation

## GitHub Actions Workflow
**Workflow**: `.github/workflows/deploy.yml`
**Trigger**: Push to main branch
**Expected Duration**: 2-4 minutes total
- Build & Push: ~2 minutes
- Deploy: ~1-2 minutes (includes 40s startup wait)

## Monitoring Commands

```bash
# Check GitHub Actions status (if gh CLI installed)
gh run list --limit 5

# Watch specific run
gh run watch

# SSH to EC2 and check logs in real-time
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2_IP>
docker logs -f feedback-api
```

## Current Time
This deployment was triggered at: 2025-11-19 ~12:15 (based on commit time)

Check GitHub Actions page to see current status.
