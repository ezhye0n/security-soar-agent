"""
[임시 스텁] Step Functions BlockIP 상태가 호출하는 blockIP Lambda의 목업 버전.
실제 방화벽/보안그룹은 절대 건드리지 않고, DynamoDB 차단 목록 테이블에 "모의 차단" 기록만 남깁니다.

파트A가 실제 blockIP Lambda(checkIPReputation과 함께 Gateway Target으로도 등록되는 그 함수)를
완성하면 이 스텁을 그 함수로 교체하세요. 인터페이스(입력/출력 계약)는 동일하게 맞춰뒀습니다.

환경변수: DDB_BLOCKLIST_TABLE (기본값 soar-agent-blocklist)
입력: {"ip": "...", "requestId": "...", "reason": "..."}
출력: {"status": "BLOCKED_SIMULATED", "ip": "..."}
"""
import os
import time

import boto3

ddb = boto3.resource("dynamodb")


def handler(event, context):
    table_name = os.environ.get("DDB_BLOCKLIST_TABLE", "soar-agent-blocklist")
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
