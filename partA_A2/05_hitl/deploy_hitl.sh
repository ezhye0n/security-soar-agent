#!/usr/bin/env bash
# Part C: Human-in-the-Loop 승인 플로우 배포
# S3(HIGH 판정) -> filter_trigger_lambda -> Step Functions -> notify_lambda(SNS 이메일, 승인 대기)
#   -> respond_lambda(승인/거부 클릭 처리) -> BlockIP(blockIP-soara, 팀원이 이미 만든 함수 그대로 사용)
#
# 사용법:
#   export AWS_REGION=ap-northeast-2
#   export DDB_TABLE_NAME=soar-agent-ip-state-soara
#   export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID>
#   export EXISTING_ROLE_NAME=<DynamoDB+S3 권한 있는 기존 역할 이름>
#   export APPROVER_EMAIL=maryanna0427@sookmyung.ac.kr
#   export BLOCK_IP_FUNCTION_NAME=blockIP-soara
#   bash deploy_hitl.sh
set -euo pipefail

: "${AWS_REGION:?export AWS_REGION=ap-northeast-2 먼저 하세요}"
: "${DDB_TABLE_NAME:?export DDB_TABLE_NAME=soar-agent-ip-state-soara 먼저 하세요}"
: "${S3_BUCKET_NAME:?export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID> 먼저 하세요}"
: "${EXISTING_ROLE_NAME:?export EXISTING_ROLE_NAME=<기존 역할 이름> 먼저 하세요}"
: "${APPROVER_EMAIL:?export APPROVER_EMAIL=<승인 알림 받을 이메일> 먼저 하세요}"
: "${BLOCK_IP_FUNCTION_NAME:=blockIP-soara}"

DIR="$(cd "$(dirname "$0")" && pwd)"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

NOTIFY_FN="${NOTIFY_FUNCTION_NAME:-soar-agent-notify-soara}"
RESPOND_FN="${RESPOND_FUNCTION_NAME:-soar-agent-respond-soara}"
FILTER_FN="${FILTER_FUNCTION_NAME:-soar-agent-hitl-filter-soara}"
SFN_NAME="${STATE_MACHINE_NAME:-soar-agent-hitl-soara}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-soar-agent-approval-topic-soara}"

echo "[0/9] 기존 역할/BlockIP 함수 확인"
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$EXISTING_ROLE_NAME" --query 'Role.Arn' --output text)
BLOCK_IP_ARN=$(aws lambda get-function --function-name "$BLOCK_IP_FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)
echo "  LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN"
echo "  BLOCK_IP_ARN=$BLOCK_IP_ARN"

echo "[1/9] 기존 역할에 SNS/StepFunctions 권한 추가"
aws iam attach-role-policy --role-name "$EXISTING_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-role-policy --role-name "$EXISTING_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess
sleep 5

echo "[2/9] SNS 주제 생성 + 이메일 구독"
SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --region "$AWS_REGION" --query 'TopicArn' --output text)
aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$APPROVER_EMAIL" --region "$AWS_REGION" >/dev/null
echo "  ⚠️  $APPROVER_EMAIL 메일함에서 'AWS Notification - Subscription Confirmation' 메일의"
echo "     'Confirm subscription' 링크를 반드시 눌러야 실제 알림을 받을 수 있습니다. 지금 확인해주세요!"

echo "[3/9] respond_lambda 배포"
rm -rf /tmp/respond_build && mkdir -p /tmp/respond_build
cp "$DIR/respond_lambda.py" /tmp/respond_build/lambda_function.py
( cd /tmp/respond_build && zip -q -r ../respond_build.zip . )
if aws lambda get-function --function-name "$RESPOND_FN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$RESPOND_FN" --zip-file fileb:///tmp/respond_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$RESPOND_FN" --region "$AWS_REGION"
else
  aws lambda create-function --function-name "$RESPOND_FN" \
    --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/respond_build.zip --timeout 15 --memory-size 128 \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$RESPOND_FN" --region "$AWS_REGION"
fi
RESPOND_ARN=$(aws lambda get-function --function-name "$RESPOND_FN" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

if ! aws lambda get-function-url-config --function-name "$RESPOND_FN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda create-function-url-config --function-name "$RESPOND_FN" --auth-type NONE --region "$AWS_REGION" >/dev/null
  aws lambda add-permission --function-name "$RESPOND_FN" \
    --statement-id FunctionURLAllowPublicAccess --action lambda:InvokeFunctionUrl \
    --principal "*" --function-url-auth-type NONE --region "$AWS_REGION" >/dev/null
fi
RESPOND_URL=$(aws lambda get-function-url-config --function-name "$RESPOND_FN" --region "$AWS_REGION" --query 'FunctionUrl' --output text)
echo "  RESPOND_URL=$RESPOND_URL"

echo "[4/9] notify_lambda 배포"
rm -rf /tmp/notify_build && mkdir -p /tmp/notify_build
cp "$DIR/notify_lambda.py" /tmp/notify_build/lambda_function.py
( cd /tmp/notify_build && zip -q -r ../notify_build.zip . )
NOTIFY_ENV="Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN,RESPOND_URL=$RESPOND_URL}"
if aws lambda get-function --function-name "$NOTIFY_FN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$NOTIFY_FN" --zip-file fileb:///tmp/notify_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$NOTIFY_FN" --region "$AWS_REGION"
  aws lambda update-function-configuration --function-name "$NOTIFY_FN" --environment "$NOTIFY_ENV" --timeout 15 --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$NOTIFY_FN" \
    --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/notify_build.zip --timeout 15 --memory-size 128 \
    --environment "$NOTIFY_ENV" --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$NOTIFY_FN" --region "$AWS_REGION"
fi
NOTIFY_ARN=$(aws lambda get-function --function-name "$NOTIFY_FN" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo "[5/9] Step Functions 실행 역할 준비"
SFN_ROLE_NAME="${SFN_ROLE_NAME:-soar-agent-hitl-sfn-role-soara}"
cat > /tmp/sfn_trust_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "states.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
EOF
aws iam create-role --role-name "$SFN_ROLE_NAME" --assume-role-policy-document file:///tmp/sfn_trust_policy.json \
  || echo "  (이미 존재하면 무시)"
aws iam attach-role-policy --role-name "$SFN_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole
sleep 8
SFN_ROLE_ARN=$(aws iam get-role --role-name "$SFN_ROLE_NAME" --query 'Role.Arn' --output text)

echo "[6/9] Step Functions 상태 머신 생성/업데이트"
sed -e "s|__NOTIFY_FUNCTION_ARN__|$NOTIFY_ARN|g" -e "s|__BLOCK_IP_FUNCTION_ARN__|$BLOCK_IP_ARN|g" \
  "$DIR/state_machine.asl.json" > /tmp/state_machine_rendered.json

SFN_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${SFN_NAME}"
if aws stepfunctions describe-state-machine --state-machine-arn "$SFN_ARN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws stepfunctions update-state-machine --state-machine-arn "$SFN_ARN" \
    --definition file:///tmp/state_machine_rendered.json --role-arn "$SFN_ROLE_ARN" --region "$AWS_REGION" >/dev/null
else
  SFN_ARN=$(aws stepfunctions create-state-machine --name "$SFN_NAME" \
    --definition file:///tmp/state_machine_rendered.json --role-arn "$SFN_ROLE_ARN" \
    --type STANDARD --region "$AWS_REGION" --query 'stateMachineArn' --output text)
fi
echo "  SFN_ARN=$SFN_ARN"

echo "[7/9] filter_trigger_lambda 배포"
rm -rf /tmp/filter_build && mkdir -p /tmp/filter_build
cp "$DIR/filter_trigger_lambda.py" /tmp/filter_build/lambda_function.py
( cd /tmp/filter_build && zip -q -r ../filter_build.zip . )
FILTER_ENV="Variables={DDB_TABLE_NAME=$DDB_TABLE_NAME,STATE_MACHINE_ARN=$SFN_ARN}"
if aws lambda get-function --function-name "$FILTER_FN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FILTER_FN" --zip-file fileb:///tmp/filter_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FILTER_FN" --region "$AWS_REGION"
  aws lambda update-function-configuration --function-name "$FILTER_FN" --environment "$FILTER_ENV" --timeout 15 --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$FILTER_FN" \
    --runtime python3.12 --role "$LAMBDA_ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/filter_build.zip --timeout 15 --memory-size 128 \
    --environment "$FILTER_ENV" --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$FILTER_FN" --region "$AWS_REGION"
fi
FILTER_ARN=$(aws lambda get-function --function-name "$FILTER_FN" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo "[8/9] S3 -> filter_trigger_lambda 호출 권한 부여"
aws lambda add-permission --function-name "$FILTER_FN" \
  --statement-id S3InvokePermission --action lambda:InvokeFunction \
  --principal s3.amazonaws.com --source-arn "arn:aws:s3:::${S3_BUCKET_NAME}" \
  --region "$AWS_REGION" >/dev/null 2>&1 || echo "  (이미 있으면 무시)"

echo "[9/9] S3 버킷 이벤트 알림 설정 (scores/*.json 생성 시 filter_trigger_lambda 호출)"
cat > /tmp/s3_notification.json <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "$FILTER_ARN",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {"Name": "prefix", "Value": "scores/"},
            {"Name": "suffix", "Value": ".json"}
          ]
        }
      }
    }
  ]
}
EOF
aws s3api put-bucket-notification-configuration --bucket "$S3_BUCKET_NAME" \
  --notification-configuration file:///tmp/s3_notification.json --region "$AWS_REGION"

echo ""
echo "완료."
echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN"
echo "STATE_MACHINE_ARN=$SFN_ARN"
echo "RESPOND_URL=$RESPOND_URL"
echo ""
echo "=== 중요: 지금 바로 할 일 ==="
echo "1) $APPROVER_EMAIL 메일함에서 SNS 구독 확인 메일의 'Confirm subscription' 클릭 (안 하면 알림 자체가 안 옴)"
echo "2) Producer 실행해서 HIGH 판정 뜨면, 메일로 승인 요청 오는지 확인"
echo "3) Step Functions 콘솔(AWS 콘솔 -> Step Functions -> $SFN_NAME)에서 실행(Execution) 목록 보면"
echo "   'NotifyAndWaitForApproval' 상태에서 멈춰 대기 중인 게 보일 것 (사람 응답 기다리는 중)"
echo "4) 메일의 승인 링크 클릭 -> Step Functions 실행이 이어져서 BlockIP까지 실행되는지 확인"
