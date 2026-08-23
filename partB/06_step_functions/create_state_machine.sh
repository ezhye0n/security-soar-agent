#!/usr/bin/env bash
# Step Functions 상태머신 배포 (5:30–7:30 구간)
#
# 사전 필요 (export 되어 있어야 함, 각 스크립트 출력에서 복사):
#   SNS_APPROVAL_TOPIC_ARN, SNS_COMPLETION_TOPIC_ARN   (03_storage_notify/create_sns_topics.sh)
#   SQS_APPROVAL_QUEUE_URL, SQS_APPROVAL_QUEUE_ARN     (03_storage_notify/create_sqs_queue.sh)
#   CALL_AGENT_LAMBDA_ARN, BLOCK_IP_LAMBDA_ARN          (파트A 함수, 없으면 stubs/deploy_stubs.sh 결과 사용)
set -euo pipefail
: "${STATE_MACHINE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"
: "${SNS_APPROVAL_TOPIC_ARN:?03_storage_notify/create_sns_topics.sh 출력값을 export 하세요}"
: "${SNS_COMPLETION_TOPIC_ARN:?03_storage_notify/create_sns_topics.sh 출력값을 export 하세요}"
: "${SQS_APPROVAL_QUEUE_URL:?03_storage_notify/create_sqs_queue.sh 출력값을 export 하세요}"
: "${SQS_APPROVAL_QUEUE_ARN:?03_storage_notify/create_sqs_queue.sh 출력값을 export 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"

# 파트A 함수가 아직 없으면 stubs/deploy_stubs.sh 를 먼저 실행해서 얻은 ARN을 사용하세요.
CALL_AGENT_LAMBDA_ARN="${CALL_AGENT_LAMBDA_ARN:?CALL_AGENT_LAMBDA_ARN을 export 하세요 (파트A 함수 또는 stubs/deploy_stubs.sh 결과)}"
BLOCK_IP_LAMBDA_ARN="${BLOCK_IP_LAMBDA_ARN:?BLOCK_IP_LAMBDA_ARN을 export 하세요 (파트A 함수 또는 stubs/deploy_stubs.sh 결과)}"

export CallAgentLambdaArn="$CALL_AGENT_LAMBDA_ARN"
export BlockIpLambdaArn="$BLOCK_IP_LAMBDA_ARN"
export SnsApprovalTopicArn="$SNS_APPROVAL_TOPIC_ARN"
export SnsCompletionTopicArn="$SNS_COMPLETION_TOPIC_ARN"
export SqsApprovalQueueUrl="$SQS_APPROVAL_QUEUE_URL"
export SqsApprovalQueueArn="$SQS_APPROVAL_QUEUE_ARN"

echo "[1/4] ASL 템플릿 렌더링"
python3 "$DIR/../00_common/render_template.py" "$DIR/state_machine.asl.json" > /tmp/state_machine.rendered.json
python3 -m json.tool /tmp/state_machine.rendered.json > /dev/null && echo "  JSON 유효성 OK"

echo "[2/4] Step Functions 실행 역할 생성"
aws iam create-role \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --assume-role-policy-document "file://$DIR/step_functions_trust_policy.json" \
  || echo "  (이미 존재하면 무시하고 진행)"

python3 "$DIR/../00_common/render_template.py" "$DIR/step_functions_role_policy.json.template" > /tmp/sfn_policy.rendered.json
aws iam put-role-policy \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-sfn-inline" \
  --policy-document file:///tmp/sfn_policy.rendered.json

echo "  IAM 전파 대기 (10초)"
sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$STEP_FUNCTIONS_ROLE_NAME" --query 'Role.Arn' --output text)

echo "[3/4] 상태머신 생성/업데이트: $STATE_MACHINE_NAME"
if aws stepfunctions describe-state-machine \
     --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
     --region "$AWS_REGION" >/dev/null 2>&1; then
  aws stepfunctions update-state-machine \
    --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
    --definition file:///tmp/state_machine.rendered.json \
    --role-arn "$ROLE_ARN" \
    --region "$AWS_REGION"
else
  aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --definition file:///tmp/state_machine.rendered.json \
    --role-arn "$ROLE_ARN" \
    --type STANDARD \
    --region "$AWS_REGION"
fi

echo "[4/4] 완료. 상태머신 ARN:"
echo "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
