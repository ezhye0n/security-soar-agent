"""
SQS 승인 큐(soar-agent-approval-queue-soara)에 메시지가 도착하면 자동으로 트리거되는 Lambda.
Step Functions가 WaitForApproval 상태에서 보낸 {requestId, taskToken, ip, score, reason}을
DynamoDB pending-approvals 테이블에 저장해, 운영자가 나중에 (또는 데모에서 실시간으로)
approve_cli.sh 로 조회/승인할 수 있게 합니다.

이 Lambda 자체는 승인/거부를 판단하지 않습니다 (그건 사람이 합니다) -
그저 "지금 승인 대기 중인 요청이 있다"는 사실을 기록/조회 가능하게 만드는 역할입니다.
"""
import json
import os
import time

import boto3

ddb = boto3.resource("dynamodb")


def handler(event, context):
    table = ddb.Table(os.environ["DDB_PENDING_APPROVALS_TABLE"])
    processed = 0

    for record in event.get("Records", []):
        body = json.loads(record["body"])
        table.put_item(
            Item={
                "requestId": body["requestId"],
                "taskToken": body["taskToken"],
                "ip": body.get("ip"),
                "score": body.get("score"),
                "reason": body.get("reason"),
                "status": "PENDING",
                "receivedAt": int(time.time()),
            }
        )
        print(f"[ApprovalProcessor] 승인 대기 등록: requestId={body['requestId']} ip={body.get('ip')} score={body.get('score')}")
        processed += 1

    return {"processed": processed}
