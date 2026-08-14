"""
[임시 스텁] 파트B의 실제 blockIP Lambda가 아직 준비되지 않았을 때
Step Functions BlockIP 상태를 먼저 테스트하기 위한 목업입니다.
실제 방화벽/보안그룹은 절대 건드리지 않고, DynamoDB 차단 목록 테이블에 "모의 차단" 기록만 남깁니다.

파트B가 실제 blockIP Lambda(Gateway Target으로도 등록되는 그 함수)를 완성하면
state_machine_stage4_full.asl.json 의 BlockIpLambdaArn을 그 함수 ARN으로 교체하세요.
인터페이스(입력/출력 계약)는 동일하게 맞춰뒀습니다.

환경변수: DDB_BLOCKLIST_TABLE
입력: {"ip": "...", "requestId": "...", "reason": "..."}
출력: {"status": "BLOCKED_SIMULATED", "ip": "..."}
"""
import os
import time

import boto3

ddb = boto3.resource("dynamodb")


def handler(event, context):
    table_name = os.environ["DDB_BLOCKLIST_TABLE"]
    table = ddb.Table(table_name)

    ip = event["ip"]
    table.put_item(
        Item={
            "ip": ip,
            "requestId": event.get("requestId", "unknown"),
            "reason": event.get("reason", ""),
            "blockedAt": int(time.time()),
            "mode": "SIMULATED",  # 실제 방화벽/보안그룹은 건드리지 않음 (모의 처리)
        }
    )
    return {"status": "BLOCKED_SIMULATED", "ip": ip}
