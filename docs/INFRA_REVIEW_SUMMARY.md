# Infrastructure Review Summary

## 1. 비용 및 구성 요약
- AWS Free Tier로 EC2 t2.micro, CloudWatch Logs, S3 등을 모두 크레딧으로 상쇄하여 월 $0 유지.
- 프리티어 종료 이후에는 EC2 $8.50, CloudWatch Logs $4.73 등 총 $13.28/월 수준으로 예상.
- 향후 확장을 고려해 단계별 비용안을 정의함: Phase 2는 RDS·CloudWatch Metrics·Secrets Manager 포함 $29/월, Phase 3는 ALB·ASG·RDS Multi-AZ 포함 $68/월.

## 2. 초급자 관점에서 잘한 점
- GitHub Actions를 이용한 빌드/테스트/컨테이너 빌드/배포까지의 완전 자동화 CI/CD 파이프라인 구축.
- 멀티스테이지 Dockerfile과 non-root 실행으로 경량화된 이미지를 유지하여 환경 차이 없이 배포 가능.
- CloudWatch Logs 수집과 Slack 알림으로 실행 상태와 배포 현황을 빠르게 파악할 수 있는 모니터링 체계 마련.
- 배포 직전 로컬 백업과 S3 업로드를 자동화하여 2중 백업 전략을 확보.

## 3. 아쉬운 점 및 리스크
- EC2 단일 인스턴스와 H2 파일 DB에 모든 워크로드가 집중되어 있어 SPOF로 인한 전체 중단 위험이 매우 큼.
- H2 특성상 동시성 및 복구 기능이 부족하고 롤백 시 서버 중단이 필요해 실서비스에는 부적합.
- Security Group에서 SSH/8080을 0.0.0.0/0으로 공개해 두어 오픈 인터넷에 바로 노출되는 상태.
- CloudWatch Alarms나 Dashboard가 없어 장애 징후를 임계치 기반으로 조기 탐지하기 어려움.

## 4. 고민했던 문제와 제안한 해결책
- SPOF 제거와 H2 → RDS 마이그레이션을 최우선 과제로 지목하고 Multi-AZ/ASG/ALB 도입을 로드맵에 배치.
- SSH 허용 IP 제한, CloudWatch 알람 2종, AWS Budgets 알림을 “즉시 작업” 체크리스트에 포함해 실행 가이드 제공.
- Phase 1~4 개선 로드맵으로 비용 대비 효과를 정리해 의사결정 시점을 명확히 함.

## 5. 향후 확장 시 예상 문제
- 현재 구조로는 SLA 99% 이상 유지가 어려우며 트래픽 증가 시 Auto Scaling, ALB, RDS 등 구조적 변화가 필수.
- RDS 도입 시 월 $20 이상 추가 비용이 발생하므로 수익·트래픽 지표에 맞춰 비용 전환 타이밍 결정 필요.
- 관측성 도구(알람, 대시보드)가 부족한 상태로 노드를 늘리면 장애 원인 파악이 더 어려워지고, 수동 보안그룹/백업 반복으로 운영 리스크가 증가.

## 6. 추천 다음 단계
1. SSH/HTTP 보안그룹 제한, CPU/Health 알람 2종 생성 등 즉시 조치로 기본 방어선 강화.
2. RDS PostgreSQL 마이그레이션 리허설 및 백업·복구 절차 문서화를 통해 데이터 이행 리드타임 축소.
3. Phase 2 예산 승인 후 CloudWatch Metrics·Dashboard를 도입해 트렌드 기반 모니터링 확보.

## 7. 해커톤 어필 포인트 제안
- **Fail-Safe Rollback 시나리오**: 단일 EC2 환경에서도 GitHub Actions가 직전 안정 빌드를 latest-stable 태그로 보존하고, `deploy-to-ec2.sh --rollback` 한 줄로 컨테이너와 H2 백업을 동시에 롤백하는 스토리를 준비하면 “장애 대비 자동화”를 강조할 수 있음.
- **가시성 번들**: CloudWatch Logs에 미리 정의된 쿼리/대시보드를 템플릿으로 공유하고, Slack 알림에 배포 링크·커밋 해시를 포함시켜 “챗Ops 기반 운영”을 보여주면 로그 수집 고민을 해결한 사례를 어필 가능.
- **경량 보안 하드닝**: SSH 접근을 Session Manager 또는 제한된 Bastion IP로 묶고, 8080을 ALB/CloudFront 없이도 Cloudflare Tunnel이나 Nginx 리버스 프록시로 감싸 “초기 단계에서도 네트워크 경계 방어를 구현”했다는 메시지가 전달됨.
- **미니 Auto-Heal 데모**: 실제 오토스케일은 어렵지만, 단일 인스턴스에서 `docker run --restart=always`와 간단한 health-check 스크립트로 프로세스 자가 복구를 시연해 “리소스 제약 속에서 복구 자동화를 설계했다”는 서사를 만들 수 있음.
- **런북/체크리스트 공개**: 배포 전 백업·알람 확인 등 현재 체크리스트를 README에 포함해 심사위원이 바로 따라 해볼 수 있게 하면 “교육용/실무 가이드”라는 해커톤 테마와 맞물려 가치를 높일 수 있음.

## 8. 현재 매력 포인트 정리
- **End-to-End CI/CD**: `git push` 한 번으로 빌드·테스트·컨테이너 빌드·EC2 배포·헬스 체크·Slack 알림까지 이어지는 파이프라인이 이미 동작한다는 점을 명시해 “운영 자동화 역량”을 증명한다.
- **컨테이너 품질**: 멀티스테이지 Dockerfile, non-root 실행, 다중 태깅(`latest`, `sha-...`, `stable`) 덕분에 경량 이미지와 즉시 롤백 가능한 태그 전략을 동시에 보여줄 수 있다.
- **가시성/알림**: CloudWatch Logs로 중앙집중된 로그와 배포 진행률을 표시하는 Slack 메시지를 묶어 “초급 프로젝트에서도 관측성과 커뮤니케이션을 고려했다”는 스토리를 제공한다.
- **백업 자동화**: 배포 전 로컬 스냅샷 후 S3 업로드, 7일 로테이션, Lifecycle 정책까지 포함된 2중 백업을 강조해 데이터 보호를 면밀히 설계했다는 인상을 준다.
- **비용·로드맵 투명성**: 프리티어를 활용한 현재 비용 $0, Phase 2/3 비용·효과를 표로 정리한 문서를 활용해 “비용 대비 성장 전략”을 명확히 설명할 수 있다.
- **운영 체크리스트 문화**: PRE_DEPLOYMENT_CHECKLIST 등 문서를 통해 배포 전 검증 항목을 공유함으로써 “런북 기반 운영”이라는 실무 관점을 부각한다.

## 9. Fail-Safe 및 모니터링 고도화 플랜

| 난이도 순서 | 개선 항목 | 기존 대비 Merit | 구현 방법(요약) | 예시 |
|-------------|-----------|-----------------|-----------------|------|
| 1 | Slack/알림 강화 | 배포·비용·경보를 한 채널로 묶어 즉각 판단 가능 | GitHub Actions, AWS Budgets, SNS→Slack Webhook을 연결해 헬스체크 결과·비용 경보를 함께 전송 | `deploy.yml` 마지막 단계에서 “배포 성공 ✅ (Health OK 200ms)” 메시지와 롤백 명령 링크 포함 |
| 2 | 안정 태그 전략 | 항상 `stable` 이미지가 존재해 롤백 신뢰도 향상 | Actions가 `candidate` → 헬스 통과 시 `stable` 태그로 승격, `deploy-to-ec2.sh --rollback`은 `stable`만 기동 | 배포 실패 시 `docker compose pull stable && docker compose up -d` 자동 실행 |
| 3 | 구조화 로그·Logs Insights | 로그/지표를 동일 뷰로 분석 가능 | logback JSON encoder 적용, CloudWatch Logs Insights 쿼리 템플릿을 저장 | `fields @timestamp, status | filter status >= 500 | limit 20` 템플릿을 README에 링크 |
| 4 | Health Gate & Auto-Heal | 단일 노드에서도 배포 실패를 자동 감지·복구 | 배포 스크립트에 사전/사후 헬스 체크 추가, `docker compose` `restart: always`와 cron 헬스 모니터 적용 | `deploy-to-ec2.sh --health http://localhost:8080/actuator/health` 실패 시 즉시 `stable` 재배포 |
| 5 | 데이터 백아웃 자동화 | 애플리케이션·데이터 버전을 함께 롤백 | 배포 전 H2 백업을 `s3://…/backups/{commit}`에 저장, 롤백 시 동일 커밋 디렉터리 복원 | `aws s3 cp s3://feedback-backups/abc123/feedbackdb.mv.db data/` 후 컨테이너 재기동 |
| 6 | CloudWatch Agent & Dashboard | 관측성/알람을 한 눈에 보여주는 운영 세트 구축 | CloudWatch Agent로 CPU/메모리/JVM 메트릭 전송, 알람·대시보드·배포 주석 구성 | Dashboard에 `Latency`, `ErrorCount`, `ContainerCPU`와 “Deploy #42” 주석 표시 |
