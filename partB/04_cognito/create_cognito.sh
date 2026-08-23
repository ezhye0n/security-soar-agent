#!/usr/bin/env bash
# AgentCore Gateway OAuth 인증용 Cognito 리소스 생성 (2:30–4:00 구간)
# Gateway는 M2M(Machine-to-Machine) client_credentials 플로우를 사용합니다:
#   Agent(agent.py) -> Cognito 토큰 엔드포인트에서 access token 발급
#                    -> Gateway 호출 시 Authorization: Bearer <token>
# 파트A와 함께 진행 권장 (Gateway 쪽 스코프/리소스 서버 이름을 맞춰야 함).
set -euo pipefail
: "${COGNITO_USER_POOL_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/6] User Pool 생성: $COGNITO_USER_POOL_NAME"
USER_POOL_ID=$(aws cognito-idp create-user-pool \
  --pool-name "$COGNITO_USER_POOL_NAME" \
  --region "$AWS_REGION" \
  --query 'UserPool.Id' --output text)
echo "  USER_POOL_ID=$USER_POOL_ID"

echo "[2/6] 도메인 생성: $COGNITO_DOMAIN_PREFIX (전역 유일해야 함, 실패 시 접두사 변경 후 재시도)"
aws cognito-idp create-user-pool-domain \
  --domain "$COGNITO_DOMAIN_PREFIX" \
  --user-pool-id "$USER_POOL_ID" \
  --region "$AWS_REGION"

echo "[3/6] 리소스 서버 생성: $COGNITO_RESOURCE_SERVER_ID (스코프: $COGNITO_SCOPE_NAME)"
aws cognito-idp create-resource-server \
  --user-pool-id "$USER_POOL_ID" \
  --identifier "$COGNITO_RESOURCE_SERVER_ID" \
  --name "SOAR Gateway Resource Server" \
  --scopes "ScopeName=$COGNITO_SCOPE_NAME,ScopeDescription=Invoke SOAR Gateway tools" \
  --region "$AWS_REGION"

echo "[4/6] 앱 클라이언트 생성 (client_credentials, 시크릿 생성됨): $COGNITO_APP_CLIENT_NAME"
CLIENT_JSON=$(aws cognito-idp create-user-pool-client \
  --user-pool-id "$USER_POOL_ID" \
  --client-name "$COGNITO_APP_CLIENT_NAME" \
  --generate-secret \
  --allowed-o-auth-flows client_credentials \
  --allowed-o-auth-scopes "${COGNITO_RESOURCE_SERVER_ID}/${COGNITO_SCOPE_NAME}" \
  --allowed-o-auth-flows-user-pool-client \
  --region "$AWS_REGION")

CLIENT_ID=$(echo "$CLIENT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["UserPoolClient"]["ClientId"])')
CLIENT_SECRET=$(echo "$CLIENT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["UserPoolClient"]["ClientSecret"])')

echo "[5/6] 값 저장 (04_cognito/cognito_output.env)"
cat > "$(dirname "$0")/cognito_output.env" <<EOF
# 자동 생성됨 - 이 파일은 절대 git에 커밋하지 마세요 (시크릿 포함)
export COGNITO_USER_POOL_ID="$USER_POOL_ID"
export COGNITO_DOMAIN="https://${COGNITO_DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com"
export COGNITO_TOKEN_ENDPOINT="https://${COGNITO_DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com/oauth2/token"
export COGNITO_CLIENT_ID="$CLIENT_ID"
export COGNITO_CLIENT_SECRET="$CLIENT_SECRET"
export COGNITO_SCOPE="${COGNITO_RESOURCE_SERVER_ID}/${COGNITO_SCOPE_NAME}"
EOF

echo "[6/6] 완료. 아래 파일을 source 하면 값을 바로 쓸 수 있습니다:"
echo "  source $(dirname "$0")/cognito_output.env"
echo ""
cat "$(dirname "$0")/cognito_output.env"
echo ""
echo "이 값들을 파트A에게 전달하세요 (agent.py / agentcore_env.sh 에서 사용)."
