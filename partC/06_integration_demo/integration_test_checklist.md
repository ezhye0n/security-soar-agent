# 06. 통합 테스트 체크리스트 (6:30–9:00)

파트A/B/C 산출물이 모두 모인 뒤, 아래 순서로 전체 흐름을 검증하세요. 각 항목은 최대한
독립적으로 테스트 가능하도록 순서를 잡았습니다 (문제가 생기면 어느 구간인지 바로 좁힐 수 있음).

## 1. 파트C 인프라 단독 확인
- [ ] `aws sns list-topics` → 승인/완료 토픽 2개 존재, 이메일 구독 Confirmed 상태 (콘솔에서 확인)
- [ ] `aws sqs list-queues` → 승인 큐 존재
- [ ] `aws dynamodb list-tables` → pending-approvals, blocklist 테이블 존재
- [ ] `aws stepfunctions list-state-machines` → `$STATE_MACHINE_NAME` 존재, 최신 상태(Stage4)로 배포됨
- [ ] `aws lambda list-event-source-mappings --function-name $APPROVAL_PROCESSOR_FUNCTION_NAME` → State: Enabled

## 2. 오케스트레이션 단독 (스텁 기준, 파트A/B 없이도 가능)
- [ ] `06_integration_demo/smoke_test.sh` 실행 → 승인 대기 → 승인 → SUCCEEDED
- [ ] REJECT 케이스: `approve_cli.sh <requestId> reject` → `RecordRejected`로 종료되는지
- [ ] LOW/MEDIUM 케이스: `{"testScore": 30}` 입력 → `NoActionNeeded`로 바로 끝나는지
- [ ] 타임아웃 케이스(선택, 오래 걸림): 승인 없이 방치 → `States.Timeout` → `RecordRejected`
- [ ] 의도적으로 `CallAgentLambdaArn`을 잘못된 ARN으로 배포 → `HandleError` 경로 확인 (예외 처리 검증)

## 3. 파트A 연동 확인
- [ ] Producer Lambda가 CSV 한 줄을 Kinesis로 정상 전송하는지 (CloudWatch Logs)
- [ ] Consumer Lambda가 위협 점수를 계산해 S3에 저장하는지
- [ ] 5분 내 동일 IP 다수 BLOCK → HIGH로 분류되는지 (파트A 샘플 데이터의 공격자 IP로 확인)
- [ ] (연동 시) Step Functions 트리거를 "담당자 요청" 또는 스케줄로 받을 방법을 파트B/A와 확정

## 4. 파트B 연동 확인
- [ ] `agentcore invoke "최근 위협 상황 확인해줘"` 정상 응답
- [ ] Agent가 `checkIPReputation`, `blockIP` 도구를 실제로 호출하는지 (로그 확인)
- [ ] Cognito 토큰 발급이 정상 동작하는지 (`05_call_agent_lambda/call_agent_lambda.py`가 사용하는 값과 일치)
- [ ] 파트B 실제 Lambda로 `CallAgentLambdaArn`/`BlockIpLambdaArn` 교체 후 재배포 → 전체 흐름 재확인

## 5. 엔드투엔드 (전체 연결)
- [ ] 파트A 정제 CSV → Producer Lambda → Kinesis → Consumer Lambda → S3에 HIGH 점수 기록
- [ ] 담당자가 Agent에게 "최근 위협 상황 확인해줘"라고 요청 (또는 Step Functions가 직접 트리거)
- [ ] Agent가 도구를 호출해 위협 여부 판단 (파트B)
- [ ] Step Functions가 판단 결과를 받아 승인 요청 → 승인 → 차단 기록 → 완료 알림까지 전 구간 확인 (파트C)

## 자주 발생하는 문제
| 증상 | 원인 후보 | 확인 |
|---|---|---|
| SNS 메일이 안 옴 | 구독 미확인(Confirm 안 누름) | `aws sns list-subscriptions-by-topic --topic-arn ...` 의 `SubscriptionArn`이 `PendingConfirmation`인지 |
| approve_cli.sh가 requestId를 못 찾음 | ApprovalProcessor Lambda의 SQS 트리거 미연결/지연 | `aws lambda list-event-source-mappings ...` State가 Enabled인지, CloudWatch Logs 확인 |
| Step Functions가 Lambda 호출에서 계속 실패 | IAM 역할에 lambda:InvokeFunction 권한 누락 | 해당 stage의 `grant_lambda_permission_to_sfn.sh` 재실행했는지 확인 |
| Agent 호출 Lambda에서 401/403 | Cognito 토큰/스코프 불일치 | 파트B와 함께 토큰 발급 curl 테스트로 별도 확인 |
| WaitForApproval이 타임아웃까지 감 | approve_cli.sh를 안 돌렸거나 requestId 오타 | `list_pending_approvals.sh`로 정확한 requestId 재확인 |
| 리소스 이름 충돌 (다른 팀과) | `-soara` 접미사 누락 | `00_common/set_env.sh`의 `TEAM_SUFFIX` 적용 여부 확인 |
