"""
[임시 스텁] 파트B의 Agent/Cognito/Gateway가 아직 준비되지 않았을 때
Step Functions 흐름 전체를 먼저 테스트하기 위한 목업입니다.

실제 완성되면: state_machine_stage4_full.asl.json 의 CallAgentLambdaArn 자리를
파트B와 협의해 완성한 call_agent_lambda.py의 함수 ARN으로 교체하세요.

테스트 입력으로 다음을 넘기면 원하는 시나리오를 강제로 만들 수 있습니다.
  {"testIp": "203.0.113.77", "testScore": 92}
"""


def handler(event, context):
    event = event or {}
    ip = event.get("testIp", "203.0.113.77")
    score = event.get("testScore", 92)

    if score >= 80:
        level = "HIGH"
    elif score >= 50:
        level = "MEDIUM"
    else:
        level = "LOW"

    return {
        "ip": ip,
        "score": score,
        "level": level,
        "reason": f"(STUB) 5분 내 {ip} 로부터 반복된 BLOCK 로그 다수 탐지 (score={score})",
    }
