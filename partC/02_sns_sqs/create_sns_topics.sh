#!/usr/bin/env bash
# 담당자용/완료알림용 SNS 토픽 2개 생성 + 이메일 구독 (0:00–1:00, SQS와 병행)
set -euo pipefail
: "${SNS_APPROVAL_TOPIC_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/4] 승인 요청 토픽 생성: $SNS_APPROVAL_TOPIC_NAME"
APPROVAL_TOPIC_ARN=$(aws sns create-topic --name "$SNS_APPROVAL_TOPIC_NAME" \
  --region "$AWS_REGION" --query 'TopicArn' --output text)

echo "[2/4] 완료 알림 토픽 생성: $SNS_COMPLETION_TOPIC_NAME"
COMPLETION_TOPIC_ARN=$(aws sns create-topic --name "$SNS_COMPLETION_TOPIC_NAME" \
  --region "$AWS_REGION" --query 'TopicArn' --output text)

echo "[3/4] 담당자 이메일 구독 등록 ($APPROVER_EMAIL) - 이메일 확인 링크를 클릭해야 실제 수신됩니다"
aws sns subscribe --topic-arn "$APPROVAL_TOPIC_ARN" \
  --protocol email --notification-endpoint "$APPROVER_EMAIL" --region "$AWS_REGION"
aws sns subscribe --topic-arn "$COMPLETION_TOPIC_ARN" \
  --protocol email --notification-endpoint "$APPROVER_EMAIL" --region "$AWS_REGION"

echo "[4/4] 완료"
echo "SNS_APPROVAL_TOPIC_ARN=$APPROVAL_TOPIC_ARN"
echo "SNS_COMPLETION_TOPIC_ARN=$COMPLETION_TOPIC_ARN"
echo ""
echo "다음 값을 이후 스크립트 실행 전에 export 하세요 (매 터미널 세션마다 필요):"
echo "  export SNS_APPROVAL_TOPIC_ARN=$APPROVAL_TOPIC_ARN"
echo "  export SNS_COMPLETION_TOPIC_ARN=$COMPLETION_TOPIC_ARN"
echo ""
echo "[중요] 메일함에서 'AWS Notification - Subscription Confirmation' 메일의 Confirm 링크를 눌러야"
echo "        실제로 알림을 받을 수 있습니다."
