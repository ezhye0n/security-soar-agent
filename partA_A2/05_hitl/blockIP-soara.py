"""
blockIP-soara — 원본(팀원 코드)에 DynamoDB 기록 한 줄만 추가한 버전.
기존 동작(SUCCESS 응답 반환)은 그대로 유지하고, 추가로 soar-agent-ip-state-soara 테이블에
sk="BLOCKED" 아이템을 남겨서 "이 IP는 실제로 차단 처리됨"을 대시보드/다른 함수에서 조회 가능하게 함.

DynamoDB 기록이 실패해도 차단 응답 자체는 그대로 SUCCESS로 반환한다 (Step Functions 승인
플로우가 기록 실패 때문에 끊기면 안 되므로 — 로그만 남기고 넘어감).
"""
import datetime
import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
DDB_TABLE_NAME = os.environ.get("DDB_TABLE_NAME", "soar-agent-ip-state-soara")


def lambda_handler(event, context):
    target_ip = event.get('ip_address', 'unknown_ip')
    print(f"차단 요청 들어옴: {target_ip}")

    try:
        dynamodb.Table(DDB_TABLE_NAME).put_item(
            Item={
                "ip": target_ip,
                "sk": "BLOCKED",
                "blockedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        )
    except Exception as e:
        print(f"[blockIP] DynamoDB 기록 실패 (차단 응답은 정상 반환): {e}")

    result = {
        "status": "SUCCESS",
        "blocked_ip": target_ip,
        "message": f"IP {target_ip}가 성공적으로 차단되었습니다."
    }
    return result
