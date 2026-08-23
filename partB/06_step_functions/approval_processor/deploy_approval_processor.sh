#!/usr/bin/env bash
# ApprovalProcessor Lambda 배포 + SQS 트리거 연결 (6:30–7:30 구간)
set -euo pipefail
: "${APPROVAL_PROCESSOR_FUNCTION_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"
: "${SQS_APPROVAL_QUEUE_ARN:?03_storage_notify/create_sqs_queue.sh 출력값을 export 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"
ROLE_NAME="${PROJECT_PREFIX}-approval-processor-role"

echo "[1/6] IAM 역할 생성: $ROLE_NAME"
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$DIR/../../02_kinesis/lambda_trust_policy.json" \
  || echo "  (이미 존재하면 무시하고 진행)"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-approval-processor-inline" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"dynamodb:PutItem\"],
        \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_PENDING_APPROVALS_TABLE}\"
      },
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"sqs:ReceiveMessage\",\"sqs:DeleteMessage\",\"sqs:GetQueueAttributes\"],
        \"Resource\": \"${SQS_APPROVAL_QUEUE_ARN}\"
      }
    ]
  }"

echo "  IAM 전파 대기 (10초)"; sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo "[2/6] 패키징"
mkdir -p /tmp/approval_build
cp "$DIR/approval_processor_lambda.py" /tmp/approval_build/lambda_function.py
( cd /tmp/approval_build && zip -q -r ../approval_processor.zip . )

echo "[3/6] Lambda 생성/업데이트: $APPROVAL_PROCESSOR_FUNCTION_NAME"
if aws lambda get-function --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" \
    --zip-file fileb:///tmp/approval_build/approval_processor.zip --region "$AWS_REGION" >/dev/null
  aws lambda update-function-configuration --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" \
    --environment "Variables={DDB_PENDING_APPROVALS_TABLE=$DDB_PENDING_APPROVALS_TABLE}" --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/approval_build/approval_processor.zip --timeout 15 --region "$AWS_REGION" \
    --environment "Variables={DDB_PENDING_APPROVALS_TABLE=$DDB_PENDING_APPROVALS_TABLE}" >/dev/null
fi

echo "[4/6] SQS 이벤트 소스 매핑 연결"
FUNC_ARN=$(aws lambda get-function --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)
EXISTING=$(aws lambda list-event-source-mappings --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" --region "$AWS_REGION" --query 'EventSourceMappings[?EventSourceArn==`'"$SQS_APPROVAL_QUEUE_ARN"'`]' --output text)
if [ -z "$EXISTING" ]; then
  aws lambda create-event-source-mapping \
    --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" \
    --event-source-arn "$SQS_APPROVAL_QUEUE_ARN" \
    --batch-size 1 \
    --region "$AWS_REGION" >/dev/null
  echo "  이벤트 소스 매핑 생성 완료"
else
  echo "  이미 매핑되어 있음, 건너뜀"
fi

echo "[5/6] 확인"
aws lambda list-event-source-mappings --function-name "$APPROVAL_PROCESSOR_FUNCTION_NAME" --region "$AWS_REGION" \
  --query 'EventSourceMappings[].{State:State,Arn:EventSourceArn}' --output table

echo "[6/6] 완료. FUNC_ARN=$FUNC_ARN"
