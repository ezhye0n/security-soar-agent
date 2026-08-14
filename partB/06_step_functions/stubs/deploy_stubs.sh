#!/usr/bin/env bash
# 파트A의 실제 Lambda가 준비되기 전, Step Functions 흐름을 먼저 테스트하기 위한
# 스텁 Lambda 2개(call-agent, block-ip)를 배포합니다.
set -euo pipefail
: "${CALL_AGENT_LAMBDA_FUNCTION_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"
ROLE_NAME="${PROJECT_PREFIX}-stub-lambda-role"

echo "[1/6] 스텁용 IAM 역할 생성: $ROLE_NAME"
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$DIR/../../02_kinesis/lambda_trust_policy.json" \
  || echo "  (이미 존재하면 무시하고 진행)"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-stub-dynamodb" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"dynamodb:PutItem\"],
      \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_BLOCKLIST_TABLE}\"
    }]
  }"

echo "  IAM 전파 대기 (10초)"; sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo "[2/6] call-agent 스텁 패키징"
mkdir -p /tmp/stub_build/call_agent
cp "$DIR/call_agent_lambda_stub.py" /tmp/stub_build/call_agent/lambda_function.py
( cd /tmp/stub_build/call_agent && zip -q -r ../call_agent.zip . )

echo "[3/6] block-ip 스텁 패키징 (boto3는 Lambda 런타임에 기본 포함됨)"
mkdir -p /tmp/stub_build/block_ip
cp "$DIR/block_ip_lambda_stub.py" /tmp/stub_build/block_ip/lambda_function.py
( cd /tmp/stub_build/block_ip && zip -q -r ../block_ip.zip . )

echo "[4/6] call-agent 함수 생성/업데이트: $CALL_AGENT_LAMBDA_FUNCTION_NAME"
if aws lambda get-function --function-name "$CALL_AGENT_LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$CALL_AGENT_LAMBDA_FUNCTION_NAME" \
    --zip-file fileb:///tmp/stub_build/call_agent.zip --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$CALL_AGENT_LAMBDA_FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/stub_build/call_agent.zip --timeout 15 --region "$AWS_REGION" >/dev/null
fi

echo "[5/6] block-ip 함수 생성/업데이트: $BLOCK_IP_LAMBDA_FUNCTION_NAME"
if aws lambda get-function --function-name "$BLOCK_IP_LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$BLOCK_IP_LAMBDA_FUNCTION_NAME" \
    --zip-file fileb:///tmp/stub_build/block_ip.zip --region "$AWS_REGION" >/dev/null
  aws lambda update-function-configuration --function-name "$BLOCK_IP_LAMBDA_FUNCTION_NAME" \
    --environment "Variables={DDB_BLOCKLIST_TABLE=$DDB_BLOCKLIST_TABLE}" --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$BLOCK_IP_LAMBDA_FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/stub_build/block_ip.zip --timeout 15 --region "$AWS_REGION" \
    --environment "Variables={DDB_BLOCKLIST_TABLE=$DDB_BLOCKLIST_TABLE}" >/dev/null
fi

echo "[6/6] 완료. ARN:"
CALL_AGENT_LAMBDA_ARN=$(aws lambda get-function --function-name "$CALL_AGENT_LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)
BLOCK_IP_LAMBDA_ARN=$(aws lambda get-function --function-name "$BLOCK_IP_LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)
echo "CALL_AGENT_LAMBDA_ARN=$CALL_AGENT_LAMBDA_ARN"
echo "BLOCK_IP_LAMBDA_ARN=$BLOCK_IP_LAMBDA_ARN"
echo ""
echo "다음처럼 export 후 create_state_machine.sh 를 실행하세요:"
echo "  export CALL_AGENT_LAMBDA_ARN=$CALL_AGENT_LAMBDA_ARN"
echo "  export BLOCK_IP_LAMBDA_ARN=$BLOCK_IP_LAMBDA_ARN"
