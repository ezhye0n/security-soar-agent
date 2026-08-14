#!/usr/bin/env bash
# Producer/Consumer Lambda용 IAM 실행 역할 생성 (1:00–1:30 구간)
# 파트A가 만드는 Lambda 함수들이 이 역할을 사용합니다.
set -euo pipefail

: "${AWS_REGION:?먼저 00_common/set_env.sh 를 source 하세요}"

TRUST_POLICY_FILE="$(dirname "$0")/lambda_trust_policy.json"
PRODUCER_POLICY_FILE="$(dirname "$0")/producer_lambda_policy.json"
CONSUMER_POLICY_FILE="$(dirname "$0")/consumer_lambda_policy.json"

PRODUCER_ROLE_NAME="${PROJECT_PREFIX}-producer-role"
CONSUMER_ROLE_NAME="${PROJECT_PREFIX}-consumer-role"

echo "[1/4] Producer Lambda 역할 생성: $PRODUCER_ROLE_NAME"
aws iam create-role \
  --role-name "$PRODUCER_ROLE_NAME" \
  --assume-role-policy-document "file://$TRUST_POLICY_FILE" || echo "(이미 존재하면 무시하고 진행)"

aws iam attach-role-policy \
  --role-name "$PRODUCER_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name "$PRODUCER_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-producer-kinesis-put" \
  --policy-document "file://$PRODUCER_POLICY_FILE"

echo "[2/4] Consumer Lambda 역할 생성: $CONSUMER_ROLE_NAME"
aws iam create-role \
  --role-name "$CONSUMER_ROLE_NAME" \
  --assume-role-policy-document "file://$TRUST_POLICY_FILE" || echo "(이미 존재하면 무시하고 진행)"

aws iam attach-role-policy \
  --role-name "$CONSUMER_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name "$CONSUMER_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-consumer-kinesis-s3" \
  --policy-document "file://$CONSUMER_POLICY_FILE"

echo "[3/4] IAM 전파 대기 (10초)"
sleep 10

echo "[4/4] 완료. 역할 ARN:"
aws iam get-role --role-name "$PRODUCER_ROLE_NAME" --query 'Role.Arn' --output text
aws iam get-role --role-name "$CONSUMER_ROLE_NAME" --query 'Role.Arn' --output text

echo ""
echo "주의: consumer_lambda_policy.json 안의 <S3_BUCKET_NAME> 은 03_storage_notify 실행 후"
echo "실제 버킷명(\$S3_BUCKET_NAME)으로 바꿔서 다시 put-role-policy 하거나, 아래처럼 미리 envsubst 하세요:"
echo "  envsubst < consumer_lambda_policy.json > /tmp/consumer_lambda_policy.json"
