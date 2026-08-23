#!/usr/bin/env bash
# AgentCore Gateway가 checkIPReputation/blockIP Lambda(Target)를 호출할 때 쓰는 서비스 역할
# (파트A의 Gateway 생성 작업을 지원하는 역할 - 2:30–4:00 구간)
set -euo pipefail
: "${PROJECT_PREFIX:?먼저 00_common/set_env.sh 를 source 하세요}"

ROLE_NAME="${PROJECT_PREFIX}-gateway-service-role"
DIR="$(dirname "$0")"

echo "[1/3] 역할 생성: $ROLE_NAME"
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$DIR/gateway_service_role_trust_policy.json" \
  || echo "(이미 존재하면 무시하고 진행)"

echo "[2/3] 권한 정책 연결 (Lambda Target 호출용)"
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-gateway-invoke-targets" \
  --policy-document "file://$DIR/gateway_service_role_policy.json"

echo "[3/3] 완료. 역할 ARN:"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "$ROLE_ARN"
echo ""
echo "이 ARN을 파트A에게 전달하세요: agentcore gateway create-mcp-gateway --role-arn $ROLE_ARN ..."
