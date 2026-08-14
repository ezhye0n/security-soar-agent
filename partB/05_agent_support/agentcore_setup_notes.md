# 05. Agent 배포 지원 (4:00–5:30)

파트B는 Agent 코드(`agent.py`) 자체는 만들지 않지만(파트A 담당), 배포에 필요한 환경설정/의존성
파일을 준비하고 `agentcore configure/deploy/invoke` 절차를 지원합니다.

> 아래 명령어는 [bedrock-agentcore-starter-toolkit](https://github.com/aws/bedrock-agentcore-starter-toolkit)
> (레거시 툴킷, 계획서에서 언급된 `agentcore configure/deploy/invoke` 흐름과 일치) 기준입니다.
> 최신 `agentcore-cli`(신규 프로젝트용, `agentcore create/dev/deploy`)로 바뀌었을 수도 있으니
> `agentcore --help` 로 실제 설치된 버전의 서브커맨드를 먼저 확인하세요.

## 사전 설치
```bash
pip install bedrock-agentcore-starter-toolkit boto3 strands-agents
agentcore --help
```

## 1) 구성 (configure)
```bash
agentcore configure \
  --entrypoint agent.py \
  --name soar_security_agent \
  --execution-role <AgentRuntime 실행 역할 ARN> \
  --requirements-file requirements.txt \
  --region "$AWS_REGION" \
  --disable-memory        # 초기 테스트는 메모리 없이, 이후 필요하면 STM_ONLY로 변경
```

## 2) 로컬 테스트
```bash
agentcore dev
agentcore dev "최근 위협 상황 확인해줘"
```

## 3) 배포
```bash
agentcore deploy -y
```
기본적으로 CodeBuild로 클라우드 빌드합니다. 로컬에 Docker가 있다면 `--local` 또는
`--local-build` 옵션도 가능합니다.

## 4) 호출 테스트 (curl 전 단계)
```bash
agentcore invoke "최근 위협 상황 확인해줘"
```

## 5) HTTPS + Bearer Token으로 호출 (Step Functions 연동용, 6:30–7:30 구간 지원)
Step Functions가 직접 Agent를 호출하려면, Agent Runtime의 HTTP 엔드포인트에 Cognito access
token을 Bearer로 실어 호출해야 합니다. 파트A가 만드는 "Agent 호출 Lambda"는 대략 이런 구조입니다.

```python
import os, json, urllib.request

def get_access_token():
    import base64, urllib.parse
    creds = f"{os.environ['COGNITO_CLIENT_ID']}:{os.environ['COGNITO_CLIENT_SECRET']}"
    auth = base64.b64encode(creds.encode()).decode()
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "scope": os.environ["COGNITO_SCOPE"],
    }).encode()
    req = urllib.request.Request(
        os.environ["COGNITO_TOKEN_ENDPOINT"], data=data,
        headers={"Authorization": f"Basic {auth}",
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())["access_token"]

def handler(event, context):
    token = get_access_token()
    req = urllib.request.Request(
        os.environ["AGENT_RUNTIME_URL"],
        data=json.dumps({"prompt": "최근 위협 상황 확인해줘"}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())
```

이 Lambda의 ARN이 `06_step_functions/state_machine.asl.json`의 `CallAgentLambdaArn` 자리에
들어갑니다. 파트A 것이 아직 없으면 `06_step_functions/stubs/call_agent_lambda_stub.py` 로
먼저 전체 흐름을 테스트하세요.

## 참고 문서
- [Get started with the AgentCore CLI](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-cli.html)
- [bedrock-agentcore-starter-toolkit CLI reference](https://github.com/aws/bedrock-agentcore-starter-toolkit/blob/main/documentation/docs/api-reference/cli.md)
- [bedrock-agentcore-starter-toolkit on PyPI](https://pypi.org/project/bedrock-agentcore-starter-toolkit/)
