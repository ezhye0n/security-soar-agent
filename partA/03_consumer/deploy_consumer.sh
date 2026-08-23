#!/usr/bin/env bash
# Consumer Lambda 배포 (Kinesis Stream -> DynamoDB 윈도우 카운트 -> S3 threat score JSON)
#
# 사전 준비:
#   1. Kinesis Stream이 이미 있어야 함 (Producer와 같은 KINESIS_STREAM_NAME)
#   2. S3 버킷 이름은 전역적으로 유일해야 하므로 기본값 대신 계정ID를 붙이는 걸 권장합니다.
#      예: soar-agent-threat-scores-soara-054422645032
#
# 사용법:
#   export AWS_REGION=ap-northeast-2
#   export KINESIS_STREAM_NAME=soar-agent-log-stream-soara
#   export DDB_TABLE_NAME=soar-agent-ip-state-soara
#   export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID>
#   bash deploy_consumer.sh
set -euo pipefail

: "${AWS_REGION:?export AWS_REGION=ap-northeast-2 먼저 하세요}"
: "${KINESIS_STREAM_NAME:?export KINESIS_STREAM_NAME=soar-agent-log-stream-soara 먼저 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"
FUNCTION_NAME="${CONSUMER_FUNCTION_NAME:-soar-agent-consumer-soara}"
ROLE_NAME="${CONSUMER_ROLE_NAME:-soar-agent-consumer-role-soara}"
DDB_TABLE_NAME="${DDB_TABLE_NAME:-soar-agent-ip-state-soara}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-soar-agent-threat-scores-soara-${AWS_ACCOUNT_ID}}"
WINDOW_SECONDS="${WINDOW_SECONDS:-300}"
HIGH_THRESHOLD="${HIGH_THRESHOLD:-5}"
MEDIUM_THRESHOLD="${MEDIUM_THRESHOLD:-2}"

echo "[0/6] 설정 확인"
echo "  REGION=$AWS_REGION  STREAM=$KINESIS_STREAM_NAME  TABLE=$DDB_TABLE_NAME  BUCKET=$S3_BUCKET_NAME"

echo "[1/6] Kinesis Stream ARN 조회"
STREAM_ARN=$(aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" --region "$AWS_REGION" \
  --query 'StreamDescription.StreamARN' --output text)

echo "[2/6] DynamoDB 테이블 생성 (이미 있으면 무시)"
if ! aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "$DDB_TABLE_NAME" \
    --attribute-definitions AttributeName=ip,AttributeType=S AttributeName=sk,AttributeType=S \
    --key-schema AttributeName=ip,KeyType=HASH AttributeName=sk,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" >/dev/null
  aws dynamodb wait table-exists --table-name "$DDB_TABLE_NAME" --region "$AWS_REGION"
  aws dynamodb update-time-to-live --table-name "$DDB_TABLE_NAME" \
    --time-to-live-specification "Enabled=true,AttributeName=expiresAt" \
    --region "$AWS_REGION" >/dev/null
  echo "  생성 완료 + TTL(expiresAt) 활성화"
else
  echo "  이미 존재, 건너뜀"
fi

echo "[3/6] S3 버킷 생성 (이미 있으면 무시)"
if ! aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  echo "  생성 완료"
else
  echo "  이미 존재, 건너뜀"
fi

echo "[4/6] IAM 역할 준비: $ROLE_NAME"
cat > /tmp/consumer_trust_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "lambda.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
EOF

aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/consumer_trust_policy.json \
  || echo "  (이미 존재하면 무시하고 진행)"

aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name "soar-agent-consumer-permissions" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"kinesis:GetRecords\", \"kinesis:GetShardIterator\", \"kinesis:DescribeStream\", \"kinesis:DescribeStreamSummary\", \"kinesis:ListShards\", \"kinesis:ListStreams\", \"kinesis:SubscribeToShard\"],
        \"Resource\": \"${STREAM_ARN}\"
      },
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"dynamodb:PutItem\", \"dynamodb:Query\", \"dynamodb:UpdateItem\", \"dynamodb:GetItem\"],
        \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_TABLE_NAME}\"
      },
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:PutObject\"],
        \"Resource\": \"arn:aws:s3:::${S3_BUCKET_NAME}/*\"
      }
    ]
  }"

echo "  IAM 전파 대기 (10초)"; sleep 10
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo "[5/6] Lambda 생성/업데이트: $FUNCTION_NAME"
rm -rf /tmp/consumer_build && mkdir -p /tmp/consumer_build
cp "$DIR/consumer_lambda.py" /tmp/consumer_build/lambda_function.py
( cd /tmp/consumer_build && zip -q -r ../consumer_build.zip . )

ENV_VARS="Variables={DDB_TABLE_NAME=$DDB_TABLE_NAME,S3_BUCKET_NAME=$S3_BUCKET_NAME,WINDOW_SECONDS=$WINDOW_SECONDS,HIGH_THRESHOLD=$HIGH_THRESHOLD,MEDIUM_THRESHOLD=$MEDIUM_THRESHOLD}"

if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION_NAME" \
    --zip-file fileb:///tmp/consumer_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
  aws lambda update-function-configuration --function-name "$FUNCTION_NAME" \
    --timeout 60 --memory-size 256 \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/consumer_build.zip \
    --timeout 60 --memory-size 256 \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
fi

FUNC_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo "[6/6] Kinesis Event Source Mapping 연결 (이미 있으면 건너뜀)"
EXISTING_MAPPING=$(aws lambda list-event-source-mappings --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" --query "EventSourceMappings[?EventSourceArn=='${STREAM_ARN}'].UUID" --output text)
if [ -z "$EXISTING_MAPPING" ]; then
  aws lambda create-event-source-mapping \
    --function-name "$FUNCTION_NAME" \
    --event-source-arn "$STREAM_ARN" \
    --starting-position LATEST \
    --batch-size 100 \
    --maximum-batching-window-in-seconds 2 \
    --region "$AWS_REGION" >/dev/null
  echo "  생성 완료 (starting-position LATEST — Producer 실행 '이후' 데이터부터 처리)"
else
  echo "  이미 연결됨 (UUID=$EXISTING_MAPPING)"
fi

echo ""
echo "완료."
echo "FUNC_ARN=$FUNC_ARN"
echo "DDB_TABLE_NAME=$DDB_TABLE_NAME"
echo "S3_BUCKET_NAME=$S3_BUCKET_NAME"
echo ""
echo "=== 동작 확인 ==="
echo "1) Producer를 실행해서 Kinesis에 데이터를 흘려보낸 뒤:"
echo "   aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $AWS_REGION"
echo "2) S3에 threat score가 쌓이는지 확인:"
echo "   aws s3 ls s3://$S3_BUCKET_NAME/scores/ --recursive | tail -20"
echo "3) 특정 IP의 최신 판정 확인 (예: CTU-13 감염 호스트 147.32.84.165):"
echo "   aws s3 ls s3://$S3_BUCKET_NAME/scores/147.32.84.165/ --recursive | tail -5"
