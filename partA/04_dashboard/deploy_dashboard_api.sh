#!/usr/bin/env bash
# 대시보드 읽기 전용 API 배포 — 기존 Consumer 인프라(DynamoDB, S3)를 그대로 재사용하고
# Lambda 하나 + Function URL(CORS 허용)만 새로 만듭니다. 시간 촉박한 상황용 빠른 CLI 배포.
#
# 사용법:
#   export AWS_REGION=ap-northeast-2
#   export DDB_TABLE_NAME=soar-agent-ip-state-soara
#   export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID>
#   export EXISTING_ROLE_NAME=<팀원이 만든 역할 이름>   # AmazonDynamoDBFullAccess + AmazonS3FullAccess 붙어있는 역할 재사용
#   bash deploy_dashboard_api.sh
set -euo pipefail

: "${AWS_REGION:?export AWS_REGION=ap-northeast-2 먼저 하세요}"
: "${DDB_TABLE_NAME:?export DDB_TABLE_NAME=soar-agent-ip-state-soara 먼저 하세요}"
: "${S3_BUCKET_NAME:?export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID> 먼저 하세요}"
: "${EXISTING_ROLE_NAME:?export EXISTING_ROLE_NAME=<DynamoDB+S3 권한 있는 기존 역할 이름> 먼저 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"
FUNCTION_NAME="${DASHBOARD_FUNCTION_NAME:-soar-agent-dashboard-api-soara}"

echo "[1/4] 기존 역할 ARN 조회: $EXISTING_ROLE_NAME"
ROLE_ARN=$(aws iam get-role --role-name "$EXISTING_ROLE_NAME" --query 'Role.Arn' --output text)
echo "  $ROLE_ARN"

echo "[2/4] 패키징"
rm -rf /tmp/dashboard_build && mkdir -p /tmp/dashboard_build
cp "$DIR/dashboard_api.py" /tmp/dashboard_build/lambda_function.py
( cd /tmp/dashboard_build && zip -q -r ../dashboard_build.zip . )

ENV_VARS="Variables={DDB_TABLE_NAME=$DDB_TABLE_NAME,S3_BUCKET_NAME=$S3_BUCKET_NAME}"

echo "[3/4] Lambda 생성/업데이트: $FUNCTION_NAME"
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNCTION_NAME" \
    --zip-file fileb:///tmp/dashboard_build.zip --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
  aws lambda update-function-configuration --function-name "$FUNCTION_NAME" \
    --timeout 30 --memory-size 256 \
    --handler lambda_function.handler \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
else
  aws lambda create-function --function-name "$FUNCTION_NAME" \
    --runtime python3.12 --role "$ROLE_ARN" --handler lambda_function.handler \
    --zip-file fileb:///tmp/dashboard_build.zip \
    --timeout 30 --memory-size 256 \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
fi

echo "[4/4] Function URL 생성 (CORS 전체 허용, 인증 없음 — 데모용)"
if ! aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda create-function-url-config --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --cors '{"AllowOrigins":["*"],"AllowMethods":["GET"],"AllowHeaders":["*"]}' \
    --region "$AWS_REGION" >/dev/null
  aws lambda add-permission --function-name "$FUNCTION_NAME" \
    --statement-id FunctionURLAllowPublicAccess --action lambda:InvokeFunctionUrl \
    --principal "*" --function-url-auth-type NONE --region "$AWS_REGION" >/dev/null
fi
FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'FunctionUrl' --output text)

echo ""
echo "완료."
echo "DASHBOARD_API_URL=$FUNCTION_URL"
echo ""
echo "브라우저에서 바로 확인: 위 URL을 새 탭에 열면 JSON이 보입니다."
echo "이 URL을 dashboard.html 안의 API_URL 변수에 넣으면 대시보드가 완성됩니다."
