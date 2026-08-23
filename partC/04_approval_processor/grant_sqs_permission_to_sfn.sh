#!/usr/bin/env bash
# Step Functions 실행 역할에 SQS SendMessage 권한 추가 (3:00–5:00)
set -euo pipefail
: "${STEP_FUNCTIONS_ROLE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"
: "${SQS_APPROVAL_QUEUE_ARN:?02_sns_sqs/create_sqs_queue.sh 출력값을 export 하세요}"

aws iam put-role-policy \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-sfn-sqs-send" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"SendSqs\",
      \"Effect\": \"Allow\",
      \"Action\": \"sqs:SendMessage\",
      \"Resource\": \"${SQS_APPROVAL_QUEUE_ARN}\"
    }]
  }"

echo "완료: $STEP_FUNCTIONS_ROLE_NAME 역할에 SQS SendMessage 권한 추가됨"
