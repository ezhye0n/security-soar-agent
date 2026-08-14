# 07. 통합 테스트 체크리스트 (7:30–9:00)

파트A/파트B 산출물이 모두 모인 뒤, 아래 순서로 전체 흐름을 검증하세요. 각 항목은 독립적으로도
테스트 가능하도록 순서를 잡았습니다 (문제가 생기면 어느 구간인지 바로 좁힐 수 있음).

## 1. 인프라 단독 확인
- [ ] `aws kinesis describe-stream-summary --stream-name $KINESIS_STREAM_NAME` → ACTIVE
- [ ] `aws s3 ls | grep soar-agent` → 버킷 존재
- [ ] `aws sns list-topics` → 토픽 2개 존재, 이메일 구독 Confirmed 상태인지 콘솔에서 확인
- [ ] `aws sqs list-queues` → 큐 존재
- [ ] `aws dynamodb list-tables` → blocklist, pending-approvals 테이블 존재

## 2. 로그 수집 파이프라인 (파트A 담당 기능, 인프라는 파트B 확인)
- [ ] Producer Lambda가 CSV 한 줄을 Kinesis로 정상 전송하는지 (CloudWatch Logs 확인)
- [ ] Consumer Lambda가 Kinesis 트리거로 실행되어 위협 점수를 계산하는지
- [ ] 계산 결과가 S3에 JSON으로 저장되는지 (`aws s3 ls s3://$S3_BUCKET_NAME/ --recursive`)
- [ ] 5분 내 동일 IP 다수 BLOCK → HIGH로 분류되는지 (샘플 데이터의 공격자 IP로 확인)

## 3. Agent (파트A 담당)
- [ ] `agentcore invoke "최근 위협 상황 확인해줘"` 가 정상 응답하는지
- [ ] Agent가 `checkIPReputation`, `blockIP` 도구를 실제로 호출하는지 (로그로 확인)
- [ ] Gateway 인증(Cognito 토큰)이 정상 발급/검증되는지

## 4. Step Functions 오케스트레이션 (파트B 담당, 이 리포지토리)
- [ ] `bash 06_step_functions/stubs/deploy_stubs.sh` 또는 실제 Lambda ARN으로 상태머신 배포
- [ ] HIGH 시나리오 입력으로 실행 → `NotifyApprover` SNS 이메일 수신 확인
- [ ] `list_pending_approvals.sh` 로 requestId 확인
- [ ] `approve_cli.sh <requestId> approve` → `BlockIP` 상태 실행 → DynamoDB blocklist에 기록 확인
      ```bash
      aws dynamodb get-item --table-name $DDB_BLOCKLIST_TABLE --key '{"ip":{"S":"203.0.113.77"}}'
      ```
- [ ] `NotifyCompletionApproved` SNS 완료 메일 수신 확인
- [ ] REJECT 케이스도 한 번 테스트 (`approve_cli.sh <requestId> reject` → RecordRejected로 종료)
- [ ] LOW/MEDIUM 시나리오 입력 시 `NoActionNeeded`로 바로 끝나는지 확인
- [ ] 의도적으로 Lambda ARN을 잘못 넣어 `HandleError` 경로도 한 번 확인 (예외 처리 검증)

## 5. 엔드투엔드 (전체 연결)
- [ ] `01_data_prep`의 정제 CSV를 Producer Lambda로 흘려보내기
- [ ] Consumer Lambda가 HIGH 점수를 S3에 기록
- [ ] 담당자가 Agent에게 "최근 위협 상황 확인해줘"라고 요청 (또는 스케줄)
- [ ] Agent가 도구를 호출해 위협 여부 판단
- [ ] Step Functions가 판단 결과를 받아 승인 요청 → 승인 → 차단 기록 → 완료 알림까지 전 구간 확인

## 자주 발생하는 문제
| 증상 | 원인 후보 | 확인 |
|---|---|---|
| SNS 메일이 안 옴 | 구독 미확인(Confirm 안 누름) | `aws sns list-subscriptions-by-topic --topic-arn ...` 의 `SubscriptionArn`이 `PendingConfirmation`인지 |
| approve_cli.sh가 requestId를 못 찾음 | ApprovalProcessor Lambda의 SQS 트리거 미연결/지연 | `aws lambda list-event-source-mappings ...` State가 Enabled인지, CloudWatch Logs 확인 |
| Step Functions가 Lambda 호출에서 계속 실패 | IAM 역할에 lambda:InvokeFunction 권한 누락 | `step_functions_role_policy.json.template` 치환값(ARN) 확인 |
| Agent 호출 Lambda에서 401/403 | Cognito 토큰/스코프 불일치 | `04_cognito/README.md`의 토큰 발급 curl 테스트로 별도 확인 |
| WaitForApproval이 타임아웃까지 감 | approve_cli.sh를 안 돌렸거나 requestId 오타 | `list_pending_approvals.sh`로 정확한 requestId 재확인 |
