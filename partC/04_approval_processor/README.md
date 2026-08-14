# 04. ApprovalProcessor + Human-in-the-Loop (3:00–5:00)

```bash
source ../00_common/set_env.sh
bash create_pending_approvals_table.sh
bash deploy_approval_processor.sh          # SQS_APPROVAL_QUEUE_ARN export 필요
bash grant_sqs_permission_to_sfn.sh

export SnsApprovalTopicArn=$SNS_APPROVAL_TOPIC_ARN
export SnsCompletionTopicArn=$SNS_COMPLETION_TOPIC_ARN
export SqsApprovalQueueUrl=$SQS_APPROVAL_QUEUE_URL
bash ../00_common/deploy_state_machine.sh state_machine_stage3_hitl.asl.json
```

## 실행 테스트
```bash
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{}' --region "$AWS_REGION" --query 'executionArn' --output text)

sleep 10
bash list_pending_approvals.sh
bash approve_cli.sh <requestId> approve     # 또는 reject

aws stepfunctions describe-execution --execution-arn "$EXEC_ARN" --region "$AWS_REGION"
```

이 단계부터 실행이 `WaitForApproval`에서 진짜로 멈춥니다 — `approve_cli.sh`를 실행하기 전까지는
`describe-execution`의 상태가 `RUNNING`으로 유지되는 게 정상입니다.

## 파일 설명
| 파일 | 설명 |
|---|---|
| `create_pending_approvals_table.sh` | requestId→taskToken 매핑용 DynamoDB 테이블 |
| `approval_processor_lambda.py` / `deploy_approval_processor.sh` | SQS 트리거로 taskToken을 테이블에 저장 |
| `grant_sqs_permission_to_sfn.sh` | Step Functions 역할에 sqs:SendMessage 권한 추가 |
| `approve_cli.sh` | 운영자가 승인/거부 실행 (SendTaskSuccess 호출) |
| `list_pending_approvals.sh` | 승인 대기/처리 목록 조회 |
| `state_machine_stage3_hitl.asl.json` | 실제 HITL이 연결된 상태머신 |
