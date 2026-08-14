# 02. SNS/SQS + Stage 2 (0:00–1:00 생성, 1:00–3:00 연동)

## 0:00–1:00: 리소스 생성 (Step Functions 골격 작업과 병행)
```bash
source ../00_common/set_env.sh
bash create_sns_topics.sh     # 출력된 두 ARN을 export
bash create_sqs_queue.sh      # 출력된 URL/ARN을 export (실제 연결은 04 단계에서)
```

## 1:00–3:00: Choice 분기 완성 + SNS 실연동
```bash
bash grant_sns_permission_to_sfn.sh
export CallAgentLambdaArn=unused SnsApprovalTopicArn=$SNS_APPROVAL_TOPIC_ARN \
       SnsCompletionTopicArn=$SNS_COMPLETION_TOPIC_ARN
bash ../00_common/deploy_state_machine.sh state_machine_stage2_choice.asl.json
```

## 확인
```bash
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{}' --region "$AWS_REGION"
```
승인 요청/완료 이메일이 실제로 오는지 확인하세요 (SNS 구독 Confirm을 먼저 눌러야 합니다).
이 단계에서는 `WaitForApproval`이 아직 Pass라서 사람 승인 없이 바로 BlockIP(Pass)로 넘어갑니다 —
정상입니다. 3:00–5:00에 04_approval_processor에서 진짜 대기 로직으로 교체합니다.
