"""
Step Functions의 CheckThreatLog 상태가 호출하는 "Agent 호출 Lambda".
Cognito에서 client_credentials 토큰을 발급받아, 파트B가 배포한 AgentCore Agent Runtime을
HTTPS + Bearer Token으로 호출합니다.

환경변수 (파트B에게 받아서 설정):
  COGNITO_TOKEN_ENDPOINT   예) https://<domain>.auth.us-west-2.amazoncognito.com/oauth2/token
  COGNITO_CLIENT_ID
  COGNITO_CLIENT_SECRET
  COGNITO_SCOPE            예) soar-gateway/invoke
  AGENT_RUNTIME_URL        Agent Runtime의 HTTP 엔드포인트 (agentcore deploy 후 파트B가 전달)

반환 계약 (Step Functions ThreatLevelChoice가 이 형식을 기대함):
  { "ip": "...", "score": 92, "level": "HIGH"|"MEDIUM"|"LOW", "reason": "..." }

Agent 응답 형식은 파트B 구현에 따라 다를 수 있으므로, 아래 parse_agent_response()에서
실제 응답 스키마에 맞게 조정하세요.
"""
import base64
import json
import os
import urllib.parse
import urllib.request


def get_access_token():
    creds = f"{os.environ['COGNITO_CLIENT_ID']}:{os.environ['COGNITO_CLIENT_SECRET']}"
    auth = base64.b64encode(creds.encode()).decode()
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "scope": os.environ["COGNITO_SCOPE"],
    }).encode()
    req = urllib.request.Request(
        os.environ["COGNITO_TOKEN_ENDPOINT"],
        data=data,
        headers={
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())["access_token"]


def call_agent(token, prompt):
    req = urllib.request.Request(
        os.environ["AGENT_RUNTIME_URL"],
        data=json.dumps({"prompt": prompt}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read())


def parse_agent_response(raw):
    """
    파트B의 Agent 응답을 Step Functions 계약({ip, score, level, reason})으로 변환합니다.
    실제 Agent가 반환하는 JSON 구조에 맞게 이 함수를 조정하세요.
    아래는 Agent가 다음과 같은 구조를 반환한다고 가정한 기본 구현입니다:
      { "ip": "...", "score": 92, "level": "HIGH", "reason": "..." }
    또는 자연어 응답만 오는 경우를 대비해 최소한의 폴백도 포함합니다.
    """
    if isinstance(raw, dict) and "level" in raw:
        return {
            "ip": raw.get("ip", "unknown"),
            "score": raw.get("score", 0),
            "level": raw.get("level", "LOW"),
            "reason": raw.get("reason", ""),
        }
    # 폴백: 자연어 응답에서 최소 정보만 추출 (파트B와 스키마를 맞추는 것을 권장)
    text = raw.get("completion") if isinstance(raw, dict) else str(raw)
    return {
        "ip": "unknown",
        "score": 0,
        "level": "LOW",
        "reason": f"(파싱 실패, 원본 응답 일부) {str(text)[:200]}",
    }


def handler(event, context):
    prompt = (event or {}).get("prompt", "최근 위협 상황 확인해줘")
    token = get_access_token()
    raw = call_agent(token, prompt)
    return parse_agent_response(raw)
