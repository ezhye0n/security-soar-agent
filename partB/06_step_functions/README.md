# 06. Step Functions + Human-in-the-Loop (5:30–7:30)

## 흐름 요약
```
CheckThreatLog (Agent 호출 Lambda)
  → ThreatLevelChoice
      HIGH  → NotifyApprover(SNS) → WaitForApproval(SQS waitForTaskToken)
                → ApprovalChoice
                    APPROVE → BlockIP(Lambda) → NotifyCompletionApproved(SNS)
                    REJECT/타임아웃 → RecordRejected(SNS)
      그 외  → NoActionNeeded
에러 발생 시 어디서든 → HandleError(SNS)
```

## 배포 순서

```bash
source ../00_common/set_env.sh

# (파트A 함수가 아직 없다면) 먼저 스텁으로 전체 흐름부터 테스트
bash stubs/deploy_stubs.sh
export CALL_AGENT_LAMBDA_ARN=<위 스크립트 출력값>
export BLOCK_IP_LAMBDA_ARN=<위 스크립트 출력값>

# 03_storage_notify 결과값들을 export 해뒀는지 확인
#   SNS_APPROVAL_TOPIC_ARN, SNS_COMPLETION_TOPIC_ARN
#   SQS_APPROVAL_QUEUE_URL, SQS_APPROVAL_QUEUE_ARN

bash create_state_machine.sh
bash approval_processor/deploy_approval_processor.sh
```

## 실행 테스트

```bash
# HIGH 시나리오로 강제 실행 (스텁 사용 시)
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{"testIp":"203.0.113.77","testScore":92}' \
  --region "$AWS_REGION"

# 잠시 후 승인 대기 목록 확인
bash list_pending_approvals.sh

# 승인 (또는 거부)
bash approve_cli.sh <requestId> approve

# 실행 상태 확인
aws stepfunctions describe-execution --execution-arn <ExecutionArn> --region "$AWS_REGION"
```

## 파트A 실제 함수로 교체
파트A의 Agent 호출 Lambda / blockIP Lambda가 완성되면:
```bash
export CALL_AGENT_LAMBDA_ARN=<파트A 실제 ARN>
export BLOCK_IP_LAMBDA_ARN=<파트A 실제 ARN>
bash create_state_machine.sh   # update-state-machine으로 자동 갱신됨
```

## 파일 설명
| 파일 | 설명 |
|---|---|
| `state_machine.asl.json` | 상태머신 정의 (플레이스홀더 `${...}` 포함, 배포 시 치환) |
| `create_state_machine.sh` | 템플릿 치환 + IAM 역할 + 상태머신 생성/업데이트 |
| `stubs/` | 파트A 함수 대신 쓰는 목업 Lambda 2개 (먼저 통합 테스트용) |
| `approval_processor/` | SQS 트리거로 taskToken을 DynamoDB에 저장하는 Lambda |
| `approve_cli.sh` | 운영자가 승인/거부를 실행하는 CLI (SendTaskSuccess 호출) |
| `list_pending_approvals.sh` | 승인 대기/처리 목록 조회 (CLI 결과 확인 화면 대용) |
