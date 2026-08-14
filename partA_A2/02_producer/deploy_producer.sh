#!/usr/bin/env bash
# Producer Lambda 배포 (demo_logs.csv를 Kinesis로 시간압축 재생)
#
# 사전 준비:
#   1. Kinesis Stream이 이미 생성되어 있어야 함 (KINESIS_STREAM_NAME)
#   2. slice_for_demo.py로 demo_logs.csv를 이 폴더 안에 미리 만들어둘 것
#      python3 slice_for_demo.py --input ~/logs_clean.csv --output ./demo_logs.csv
#
# 사용법:
#   source ../../00_common/set_env.sh   # 또는 직접 env var export
#   export KINESIS_STREAM_NAME=soar-agent-log-stream-soara
#   bash deploy_producer.sh
set -euo pipefail

: "${AWS_REGION:?export AWS_REGION=ap-northeast-2 먼저 하세요}"
: "${KINESIS_STREAM_NAME:?export KINESIS_STREAM_NAME=soar-agent-log-stream-soara 먼저 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"
FUNCTION_NAME="${PRODUCER_FUNCTION_NAME:-soar-agent-producer-soara}"
ROLE_NAME="${PRODUCER_ROLE_NAME:-soar-agent-producer-role-soara}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

if [ ! -f "$DIR/demo_logs.csv" ]; then
  echo "[오류] $DIR/demo_logs.csv 가 없습니다. 먼저 slice_for_demo.py로 만들어주세요." >&2
  exit 1
fi

echo "[1/5] IAM 역할 준비: $ROLE_NAME"
cat > /tmp/producer_trust_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "lambda.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
EOF

aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/producer_trust_policy.json \
  || echo "  (이미 존재하면 무시하고 진행)"

aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "soar-agent-producer-kinesis-put" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"kinesis:PutRecord\", \"kinesis:PutRecords\"],
      \"Resource\": \"arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}\"
    }]
  }"

echo "  IAM 전파 대기 (10초)"; sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo "[2/5] 패키징 (producer_lambda.py + demo_logs.csv)"
rm -rf /tmp/producer_build && mkdir -p /tmp/producer_build
cp "$DIR/producer_lambda.py" /tmp/producer_build/lambda_function.py
cp "$DIR/demo_logs.csv" /tmp/producer_build/demo_logs.csv
( cd /tmp/producer_build && zip -q -r ../producer_build.zip . )
echo "  패키지 크기: $(du -h /tmp/producer_build.zip | cut -f1)"

echo "[3/5] Lambda 생성/업데이트: $FUNCTION_NAME (timeout 300초로 넉넉히 설정)"
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION_NAME" \
    --zip-file fileb:///tmp/producer_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
  aws lambda update-function-configuration --function-name "$FUNCTION_NAME" \
    --timeout 300 --memory-size 256 \
    --environment "Variables={KINESIS_STREAM_NAME=$KINESIS_STREAM_NAME}" \
    --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/producer_build.zip \
    --timeout 300 --memory-size 256 \
    --environment "Variables={KINESIS_STREAM_NAME=$KINESIS_STREAM_NAME}" \
    --region "$AWS_REGION" >/dev/null
fi

FUNC_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo "[4/5] Function URL 생성 (curl/브라우저로 바로 호출 가능한 'API' — 데모용, 인증 없음 주의)"
if ! aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda create-function-url-config --function-name "$FUNCTION_NAME" \
    --auth-type NONE --region "$AWS_REGION" >/dev/null
  aws lambda add-permission --function-name "$FUNCTION_NAME" \
    --statement-id FunctionURLAllowPublicAccess --action lambda:InvokeFunctionUrl \
    --principal "*" --function-url-auth-type NONE --region "$AWS_REGION" >/dev/null
fi
FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'FunctionUrl' --output text)

echo "[5/5] 완료."
echo ""
echo "FUNC_ARN=$FUNC_ARN"
echo "FUNCTION_URL=$FUNCTION_URL"
echo ""
echo "=== 실행 방법 ==="
echo "1) curl로 바로 호출 (동기, 응답 올 때까지 대기):"
echo "   curl -X POST \"$FUNCTION_URL\" -d '{\"targetDurationSeconds\": 60}'"
echo ""
echo "2) aws cli로 비동기 호출 (바로 리턴, 로그로 진행상황 확인):"
echo "   aws lambda invoke --function-name $FUNCTION_NAME --invocation-type Event \\"
echo "     --payload '{\"targetDurationSeconds\": 180}' --cli-binary-format raw-in-base64-out out.json"
echo "   aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $AWS_REGION"
echo ""
echo "[주의] Function URL은 인증 없음(NONE)으로 만들어졌습니다. 데모 끝나면 지우거나"
echo "       'aws lambda delete-function-url-config --function-name $FUNCTION_NAME' 로 제거하세요."
