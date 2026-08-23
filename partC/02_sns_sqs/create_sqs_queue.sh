#!/usr/bin/env bash
# Human-in-the-Loop 승인 대기용 SQS 큐 생성 (0:00–1:00, SNS와 병행)
# Step Functions가 SendMessage.waitForTaskToken 으로 taskToken을 이 큐에 넣고 대기합니다.
# (실제 배선은 3:00-5:00, 04_approval_processor 단계에서 연결합니다.)
set -euo pipefail
: "${SQS_APPROVAL_QUEUE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/2] SQS 큐 생성: $SQS_APPROVAL_QUEUE_NAME"
QUEUE_URL=$(aws sqs create-queue \
  --queue-name "$SQS_APPROVAL_QUEUE_NAME" \
  --attributes '{
    "VisibilityTimeout": "300",
    "MessageRetentionPeriod": "86400",
    "ReceiveMessageWaitTimeSeconds": "10"
  }' \
  --region "$AWS_REGION" --query 'QueueUrl' --output text)

echo "[2/2] 큐 ARN 조회"
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn --region "$AWS_REGION" --query 'Attributes.QueueArn' --output text)

echo ""
echo "완료."
echo "SQS_APPROVAL_QUEUE_URL=$QUEUE_URL"
echo "SQS_APPROVAL_QUEUE_ARN=$QUEUE_ARN"
echo ""
echo "다음 값을 이후 스크립트 실행 전에 export 하세요:"
echo "  export SQS_APPROVAL_QUEUE_URL=$QUEUE_URL"
echo "  export SQS_APPROVAL_QUEUE_ARN=$QUEUE_ARN"
