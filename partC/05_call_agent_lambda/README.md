# 05. Agent 호출 Lambda + 최종 통합 (5:00–6:30)

## A. 파트B가 아직 준비 전이라면 → 먼저 스텁으로 전체 흐름 완성
```bash
source ../00_common/set_env.sh
bash create_blocklist_table.sh          # 공유 인프라, 팀에서 누가 먼저 해도 됨
bash deploy_lambdas.sh stub             # call-agent, block-ip 스텁 둘 다 배포
export CallAgentLambdaArn=<위 출력값>
export BlockIpLambdaArn=<위 출력값>
bash grant_lambda_permission_to_sfn.sh

export SnsApprovalTopicArn=$SNS_APPROVAL_TOPIC_ARN
export SnsCompletionTopicArn=$SNS_COMPLETION_TOPIC_ARN
export SqsApprovalQueueUrl=$SQS_APPROVAL_QUEUE_URL
bash ../00_common/deploy_state_machine.sh state_machine_stage4_full.asl.json
```
이 시점에 전체 흐름(로그확인→위협판단→승인 대기→승인→차단 기록→완료 알림)이 완전히
동작해야 합니다. `06_integration_demo/smoke_test.sh` 로 확인하세요.

## B. 파트B 준비되면 → 실제 Agent로 교체
파트B에게 다음 값을 받으세요: `COGNITO_TOKEN_ENDPOINT`, `COGNITO_CLIENT_ID`,
`COGNITO_CLIENT_SECRET`, `COGNITO_SCOPE`, `AGENT_RUNTIME_URL`(agentcore deploy 후 엔드포인트).

```bash
export COGNITO_TOKEN_ENDPOINT=...
export COGNITO_CLIENT_ID=...
export COGNITO_CLIENT_SECRET=...
export COGNITO_SCOPE=...
export AGENT_RUNTIME_URL=...
bash deploy_lambdas.sh call-agent
export CallAgentLambdaArn=<위 출력값>
```
`call_agent_lambda.py`의 `parse_agent_response()`는 파트B의 실제 응답 스키마에 맞춰
같이 조정하세요 (완전히 다른 JSON 구조라면 이 함수만 고치면 됩니다).

blockIP도 파트B의 실제 함수가 준비되면 교체:
```bash
export BlockIpLambdaArn=<파트B 실제 blockIP Lambda ARN>
```

교체 후 권한 재부여 + 상태머신 재배포:
```bash
bash grant_lambda_permission_to_sfn.sh
bash ../00_common/deploy_state_machine.sh state_machine_stage4_full.asl.json
```

## 파일 설명
| 파일 | 설명 |
|---|---|
| `call_agent_lambda.py` | 실제 Cognito 토큰 발급 + Agent Runtime HTTPS 호출 |
| `call_agent_lambda_stub.py` | 파트B 완성 전 테스트용 목업 |
| `block_ip_lambda_stub.py` | 파트B의 실제 blockIP Lambda 대신 쓰는 목업 (DynamoDB 모의 기록) |
| `create_blocklist_table.sh` | 차단 목록 테이블 (공유 인프라, idempotent) |
| `deploy_lambdas.sh` | stub / call-agent / block-ip-stub 모드로 배포 |
| `grant_lambda_permission_to_sfn.sh` | Step Functions 역할에 Lambda 호출 권한 추가 |
| `state_machine_stage4_full.asl.json` | Retry/Catch/에러 처리까지 포함한 최종 상태머신 |
