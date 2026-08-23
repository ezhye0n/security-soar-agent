#!/usr/bin/env bash
# Step Functions 실행 역할 생성 (0:00-1:00, 딱 한 번만 실행).
# 이 시점엔 아직 아무 리소스(SNS/SQS/Lambda)도 없으므로 신뢰 정책만 붙이고,
# 실제 권한은 이후 단계별 grant_*.sh 스크립트로 하나씩 추가합니다.
set -euo pipefail
: "${STEP_FUNCTIONS_ROLE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/2] Step Functions 실행 역할 생성: $STEP_FUNCTIONS_ROLE_NAME"
aws iam create-role \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --assume-role-policy-document "file://$DIR/step_functions_trust_policy.json" \
  || echo "  (이미 존재하면 무시하고 진행)"

echo "  IAM 전파 대기 (10초)"
sleep 10

echo "[2/2] 완료. 역할 ARN:"
aws iam get-role --role-name "$STEP_FUNCTIONS_ROLE_NAME" --query 'Role.Arn' --output text
