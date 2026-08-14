# 04. Cognito + Gateway 서비스 역할 (2:30–4:00)

AgentCore Gateway는 MCP 도구 호출 시 OAuth(client_credentials) 토큰을 검증합니다.
이 폴더는 그 토큰을 발급하는 Cognito 리소스와, Gateway가 Lambda Target을 호출할 때 쓰는
IAM 서비스 역할을 만듭니다. **파트A와 반드시 스코프/리소스서버 이름을 맞추고 진행하세요.**

```bash
source ../00_common/set_env.sh
bash create_cognito.sh              # cognito_output.env 생성됨 (시크릿 포함, git 커밋 금지)
bash create_gateway_service_role.sh
```

## 결과물 → 파트A 전달
`cognito_output.env` 안의 값들:

| 변수 | 설명 |
|---|---|
| `COGNITO_TOKEN_ENDPOINT` | Agent가 access token을 발급받는 엔드포인트 |
| `COGNITO_CLIENT_ID` / `COGNITO_CLIENT_SECRET` | client_credentials grant용 자격증명 |
| `COGNITO_SCOPE` | Gateway 호출에 필요한 OAuth 스코프 (`soar-gateway/invoke`) |

Gateway 서비스 역할 ARN도 함께 전달하세요 (`create_gateway_service_role.sh` 출력값).

## 검증 (토큰 발급 테스트)
```bash
source cognito_output.env
curl -s -X POST "$COGNITO_TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "$COGNITO_CLIENT_ID:$COGNITO_CLIENT_SECRET" \
  -d "grant_type=client_credentials&scope=$COGNITO_SCOPE" | python3 -m json.tool
```
`access_token` 필드가 나오면 성공입니다.
