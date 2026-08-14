"""
[임시 스텁] Step Functions가 호출하는 "Agent 호출 Lambda"의 목업 버전.

파트A가 실제 Agent(HTTPS + Bearer Token)를 호출하는 Lambda를 완성하기 전까지,
Step Functions 흐름 전체(로그확인 -> 위협판단 -> 승인 -> 차단 -> 완료알림)를
먼저 테스트하기 위해 사용합니다.

실제 완성되면: state_machine.asl.json 의 CallAgentLambdaArn 자리를
파트A 함수 ARN으로 교체하세요. (create_state_machine.sh 실행 시 CALL_AGENT_LAMBDA_ARN env로 전달)

반환 계약 (Step Functions ThreatLevelChoice가 이 형식을 기대함):
{
  "ip": "203.0.113.77",
  "score": 92,
  "level": "HIGH" | "MEDIUM" | "LOW",
  "reason": "설명 문자열"
}

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
