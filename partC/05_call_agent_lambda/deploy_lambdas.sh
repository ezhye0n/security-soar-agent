#!/usr/bin/env bash
# call-agent / block-ip Lambda 배포 (5:00–6:30)
#
# 사용법:
#   bash deploy_lambdas.sh stub        # 스텁 2개 모두 배포 (파트B 준비 전, 통합 테스트용)
#   bash deploy_lambdas.sh call-agent  # 실제 call_agent_lambda.py 배포 (파트B 값 필요)
#   bash deploy_lambdas.sh block-ip-stub  # block-ip 스텁만 배포
set -euo pipefail
: "${CALL_AGENT_LAMBDA_FUNCTION_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

MODE="${1:?사용법: deploy_lambdas.sh stub|call-agent|block-ip-stub}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROLE_NAME="${PROJECT_PREFIX}-lambda-role-${TEAM_ID}"

cat > /tmp/lambda_trust_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "lambda.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
EOF

echo "[1/3] IAM 역할 준비: $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/lambda_trust_policy.json \
  || echo "  (이미 존재하면 무시하고 진행)"
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-lambda-dynamodb" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"dynamodb:PutItem\"],
      \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_BLOCKLIST_TABLE}\"
    }]
  }"
sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

deploy_fn () {
  local FUNC_NAME="$1" SRC_FILE="$2" EXTRA_ENV="$3"
  echo "패키징: $SRC_FILE -> $FUNC_NAME"
  rm -rf /tmp/fn_build && mkdir -p /tmp/fn_build
  cp "$DIR/$SRC_FILE" /tmp/fn_build/lambda_function.py
  ( cd /tmp/fn_build && zip -q -r ../fn_build.zip . )

  if aws lambda get-function --function-name "$FUNC_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$FUNC_NAME" \
      --zip-file fileb:///tmp/fn_build.zip --region "$AWS_REGION" >/dev/null
    [ -n "$EXTRA_ENV" ] && aws lambda update-function-configuration --function-name "$FUNC_NAME" \
      --environment "Variables={$EXTRA_ENV}" --region "$AWS_REGION" >/dev/null
  else
    if [ -n "$EXTRA_ENV" ]; then
      aws lambda create-function --function-name "$FUNC_NAME" \
        --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
        --zip-file fileb:///tmp/fn_build.zip --timeout 25 --region "$AWS_REGION" \
        --environment "Variables={$EXTRA_ENV}" >/dev/null
    else
      aws lambda create-function --function-name "$FUNC_NAME" \
        --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
        --zip-file fileb:///tmp/fn_build.zip --timeout 25 --region "$AWS_REGION" >/dev/null
    fi
  fi
  aws lambda get-function --function-name "$FUNC_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text
}

case "$MODE" in
  stub)
    echo "[2/3] call-agent 스텁 배포"
    CALL_AGENT_ARN=$(deploy_fn "$CALL_AGENT_LAMBDA_FUNCTION_NAME" "call_agent_lambda_stub.py" "")
    echo "[3/3] block-ip 스텁 배포"
    BLOCK_IP_ARN=$(deploy_fn "$BLOCK_IP_STUB_FUNCTION_NAME" "block_ip_lambda_stub.py" "DDB_BLOCKLIST_TABLE=$DDB_BLOCKLIST_TABLE")
    echo ""
    echo "완료. 아래처럼 export 후 state_machine_stage4_full.asl.json 을 배포하세요:"
    echo "  export CallAgentLambdaArn=$CALL_AGENT_ARN"
    echo "  export BlockIpLambdaArn=$BLOCK_IP_ARN"
    ;;
  call-agent)
    echo "[2/3] 실제 call-agent Lambda 배포 (파트B 환경변수 필요: COGNITO_*, AGENT_RUNTIME_URL)"
    : "${COGNITO_TOKEN_ENDPOINT:?파트B에게 받은 값을 export 하세요}"
    : "${COGNITO_CLIENT_ID:?}"
    : "${COGNITO_CLIENT_SECRET:?}"
    : "${COGNITO_SCOPE:?}"
    : "${AGENT_RUNTIME_URL:?}"
    ENV="COGNITO_TOKEN_ENDPOINT=$COGNITO_TOKEN_ENDPOINT,COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID,COGNITO_CLIENT_SECRET=$COGNITO_CLIENT_SECRET,COGNITO_SCOPE=$COGNITO_SCOPE,AGENT_RUNTIME_URL=$AGENT_RUNTIME_URL"
    CALL_AGENT_ARN=$(deploy_fn "$CALL_AGENT_LAMBDA_FUNCTION_NAME" "call_agent_lambda.py" "$ENV")
    echo "[3/3] 완료. CallAgentLambdaArn=$CALL_AGENT_ARN"
    echo "  export CallAgentLambdaArn=$CALL_AGENT_ARN"
    ;;
  block-ip-stub)
    echo "[2/3] block-ip 스텁만 배포"
    BLOCK_IP_ARN=$(deploy_fn "$BLOCK_IP_STUB_FUNCTION_NAME" "block_ip_lambda_stub.py" "DDB_BLOCKLIST_TABLE=$DDB_BLOCKLIST_TABLE")
    echo "[3/3] 완료. BlockIpLambdaArn=$BLOCK_IP_ARN"
    echo "  export BlockIpLambdaArn=$BLOCK_IP_ARN"
    ;;
  *)
    echo "알 수 없는 모드: $MODE (stub|call-agent|block-ip-stub 중 하나)"
    exit 1
    ;;
esac
