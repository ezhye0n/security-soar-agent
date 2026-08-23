"""
로컬 데모 서버 — 계정 정책이 Lambda Function URL / API Gateway를 통한 공개(익명) 호출을
막고 있어서, 대신 CloudShell(또는 발표용 노트북)에서 직접 실행하는 대체 서버입니다.

- GET /            -> dashboard.html 서빙
- GET /api         -> dashboard_api.py 로직 그대로 재사용 (DynamoDB/S3 읽기 전용 집계)
- GET /api/analyze?ip=... -> B파트 Bedrock AgentCore Runtime(agent_runtime.py)을 IAM 인증으로
                              직접 호출해서 AI 위협 분석 결과(JSON)를 반환. Cognito는 Agent
                              내부에서 MCP Gateway 도구(checkIPReputation) 호출용으로만 쓰이고,
                              Runtime 자체를 외부에서 부를 때는 boto3 IAM 인증만 있으면 됨.

사용법 (CloudShell 또는 노트북에서):
  cd ~/partA_A2/04_dashboard
  export DDB_TABLE_NAME=soar-agent-ip-state-soara
  export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID>
  export AGENT_RUNTIME_ARN=arn:aws:bedrock-agentcore:ap-northeast-2:054422645032:agent-runtime/<runtime-id>
  python3 local_server.py

그 다음 로컬이면 http://localhost:8080, CloudShell이면 `npx localtunnel --port 8080`으로 받은
공개 URL을 브라우저에서 열면 됩니다.
"""
import http.server
import json
import os
import urllib.parse
import uuid

import boto3

import dashboard_api  # 기존 검증된 로직(get_aggregate_stats/get_active_threats) 그대로 재사용

PORT = int(os.environ.get("PORT", "8080"))
HTML_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dashboard.html")

AWS_REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
AGENT_RUNTIME_ARN = os.environ.get("AGENT_RUNTIME_ARN", "")
_bedrock_agentcore = boto3.client("bedrock-agentcore", region_name=AWS_REGION)


def invoke_agent(ip: str) -> dict:
    """B파트 AgentCore Runtime을 IAM 인증으로 직접 호출해 위협 분석 JSON을 받아온다."""
    if not AGENT_RUNTIME_ARN:
        return {"error": "AGENT_RUNTIME_ARN 환경변수가 설정되지 않았습니다."}
    if not ip:
        return {"error": "ip 파라미터가 없습니다."}

    payload = json.dumps({"prompt": ip}).encode("utf-8")
    resp = _bedrock_agentcore.invoke_agent_runtime(
        agentRuntimeArn=AGENT_RUNTIME_ARN,
        runtimeSessionId=str(uuid.uuid4()),
        payload=payload,
    )

    content_type = resp.get("contentType", "")
    if "text/event-stream" in content_type:
        chunks = []
        for line in resp["response"].iter_lines(chunk_size=10):
            if not line:
                continue
            # 줄 단위(개행 경계)로만 디코딩 — 개행 바이트는 UTF-8 멀티바이트 문자 중간에
            # 절대 나오지 않으므로 이 경우는 줄 단위 decode가 안전함.
            decoded = line.decode("utf-8") if isinstance(line, bytes) else line
            if decoded.startswith("data: "):
                chunks.append(decoded[6:])
        raw = "\n".join(chunks)
    else:
        # 청크가 임의의 바이트 위치에서 잘려서 올 수 있어 한글 같은 멀티바이트 문자가
        # 청크 경계에서 끊길 수 있음. 청크별로 decode하지 말고 바이트를 전부 모은 뒤
        # 마지막에 한 번만 decode해야 함 (이게 원래 버그였음).
        raw_bytes = b"".join(
            chunk if isinstance(chunk, bytes) else chunk.encode("utf-8")
            for chunk in resp.get("response", [])
        )
        raw = raw_bytes.decode("utf-8")

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/analyze":
            self._serve_analyze(parsed)
        elif parsed.path.startswith("/api"):
            self._serve_api()
        else:
            self._serve_html()

    def _serve_api(self):
        result = dashboard_api.handler(
            {"requestContext": {"http": {"method": "GET"}}}, context=None
        )
        self.send_response(result["statusCode"])
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(result["body"].encode("utf-8"))

    def _serve_analyze(self, parsed):
        qs = urllib.parse.parse_qs(parsed.query)
        ip = (qs.get("ip") or [""])[0]
        try:
            result = invoke_agent(ip)
            body = json.dumps(result, ensure_ascii=False).encode("utf-8")
            status = 200
        except Exception as e:  # noqa: BLE001 - 데모용, 원인 그대로 프론트에 보여줌
            body = json.dumps({"error": str(e)}, ensure_ascii=False).encode("utf-8")
            status = 500
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _serve_html(self):
        try:
            with open(HTML_PATH, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"dashboard.html not found next to local_server.py")

    def log_message(self, format, *args):
        print("[local_server] " + (format % args))


if __name__ == "__main__":
    print(f"[local_server] DDB_TABLE_NAME={os.environ.get('DDB_TABLE_NAME')}")
    print(f"[local_server] S3_BUCKET_NAME={os.environ.get('S3_BUCKET_NAME')}")
    print(f"[local_server] AGENT_RUNTIME_ARN={AGENT_RUNTIME_ARN or '(미설정 - AI 분석 버튼 작동 안 함)'}")
    print(f"[local_server] http://0.0.0.0:{PORT} 에서 서빙 중")
    http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
