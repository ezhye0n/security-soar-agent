"""
S3 이벤트 트리거 Lambda — Consumer가 scores/<ip>/<epoch_ms>.json을 새로 쓸 때마다 호출됨.
level이 HIGH인 것만 골라서 Step Functions(HITL 승인 플로우)를 시작시킨다.

같은 IP가 5분 윈도우 안에서 계속 BLOCK되면 그때마다 새 S3 객체가 생기고, 이 Lambda도
매번 호출된다. 그럴 때마다 승인 요청 이메일을 다시 보내면 스팸이 되므로, DynamoDB에
"이 IP는 이미 승인 요청을 보냈음" 마커를 조건부로 남겨서 IP당 한 번만 실행되게 막는다.
(soar-agent-ip-state-soara 테이블을 그대로 재사용 — sk="APPROVAL_TRIGGERED")
"""
import json
import os
import urllib.parse

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
sfn = boto3.client("stepfunctions")

DDB_TABLE_NAME = os.environ.get("DDB_TABLE_NAME", "soar-agent-ip-state-soara")
STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN", "")


def _table():
    return dynamodb.Table(DDB_TABLE_NAME)


def mark_triggered_once(ip, triggered_at):
    """이 IP에 대해 승인 요청을 처음 보내는 경우에만 True. 이미 보냈으면 False."""
    try:
        _table().put_item(
            Item={"ip": ip, "sk": "APPROVAL_TRIGGERED", "triggeredAt": triggered_at},
            ConditionExpression="attribute_not_exists(sk)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise


def handler(event, context):
    started = []
    skipped = []

    for record in event.get("Records", []):
        try:
            bucket = record["s3"]["bucket"]["name"]
            key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

            obj = s3.get_object(Bucket=bucket, Key=key)
            body = json.loads(obj["Body"].read())
            ip = body.get("ip")
            level = body.get("level")

            if not ip or level != "HIGH":
                continue

            if not mark_triggered_once(ip, body.get("windowEnd", "")):
                skipped.append(ip)
                continue

            sfn.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                input=json.dumps(body, ensure_ascii=False),
            )
            started.append(ip)
        except Exception as e:
            print(f"[Filter] 레코드 처리 실패: {e}")

    result = {"started": started, "skipped": skipped}
    print(f"[Filter] {json.dumps(result, ensure_ascii=False)}")
    return result
