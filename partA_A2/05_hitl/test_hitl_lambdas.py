"""
filter_trigger_lambda / notify_lambda / respond_lambda의 핵심 로직만 빠르게 검증.
Step Functions 콜백(taskToken) 자체는 실제 AWS 없이는 완전히 재현하기 어려워서,
"올바른 파라미터로 올바른 API를 호출하는지"를 mock으로 확인하는 방식으로 검증한다.
"""
import json
import os
from unittest.mock import MagicMock, patch

os.environ["DDB_TABLE_NAME"] = "soar-agent-ip-state-soara"
os.environ["STATE_MACHINE_ARN"] = "arn:aws:states:ap-northeast-2:054422645032:stateMachine:soar-agent-hitl-soara"
os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:ap-northeast-2:054422645032:soar-agent-approval-topic-soara"
os.environ["RESPOND_URL"] = "https://respond-fn.lambda-url.ap-northeast-2.on.aws/"

import boto3
from moto import mock_aws

import filter_trigger_lambda
import notify_lambda
import respond_lambda


def s3_event(bucket, key):
    return {"Records": [{"s3": {"bucket": {"name": bucket}, "object": {"key": key}}}]}


@mock_aws
def test_filter_dedup_only_triggers_once_per_ip():
    region = "ap-northeast-2"
    bucket = "soar-agent-threat-scores-soara"

    ddb = boto3.client("dynamodb", region_name=region)
    ddb.create_table(
        TableName=os.environ["DDB_TABLE_NAME"],
        KeySchema=[{"AttributeName": "ip", "KeyType": "HASH"}, {"AttributeName": "sk", "KeyType": "RANGE"}],
        AttributeDefinitions=[
            {"AttributeName": "ip", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    s3 = boto3.client("s3", region_name=region)
    s3.create_bucket(Bucket=bucket, CreateBucketConfiguration={"LocationConstraint": region})
    body = {
        "ip": "147.32.84.165", "level": "HIGH", "score": 100, "blockCount": 226,
        "reason": "테스트", "windowEnd": "2026-08-13T05:47:18Z",
    }
    s3.put_object(Bucket=bucket, Key="scores/147.32.84.165/1.json", Body=json.dumps(body))
    s3.put_object(Bucket=bucket, Key="scores/147.32.84.165/2.json", Body=json.dumps(body))

    filter_trigger_lambda.s3 = boto3.client("s3", region_name=region)
    filter_trigger_lambda.dynamodb = boto3.resource("dynamodb", region_name=region)

    with patch.object(filter_trigger_lambda, "sfn") as mock_sfn:
        r1 = filter_trigger_lambda.handler(s3_event(bucket, "scores/147.32.84.165/1.json"), None)
        r2 = filter_trigger_lambda.handler(s3_event(bucket, "scores/147.32.84.165/2.json"), None)

        assert r1["started"] == ["147.32.84.165"]
        assert r2["started"] == []
        assert r2["skipped"] == ["147.32.84.165"]
        assert mock_sfn.start_execution.call_count == 1, "같은 IP인데 두 번째에도 실행됐으면 스팸 방지 실패"
    print("[OK] 같은 IP에 대해 Step Functions 실행이 딱 1번만 시작됨 (스팸 방지 확인)")


@mock_aws
def test_filter_skips_non_high_level():
    region = "ap-northeast-2"
    bucket = "soar-agent-threat-scores-soara"
    ddb = boto3.client("dynamodb", region_name=region)
    ddb.create_table(
        TableName=os.environ["DDB_TABLE_NAME"],
        KeySchema=[{"AttributeName": "ip", "KeyType": "HASH"}, {"AttributeName": "sk", "KeyType": "RANGE"}],
        AttributeDefinitions=[
            {"AttributeName": "ip", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    s3 = boto3.client("s3", region_name=region)
    s3.create_bucket(Bucket=bucket, CreateBucketConfiguration={"LocationConstraint": region})
    s3.put_object(
        Bucket=bucket, Key="scores/10.0.0.5/1.json",
        Body=json.dumps({"ip": "10.0.0.5", "level": "MEDIUM", "blockCount": 2}),
    )
    filter_trigger_lambda.s3 = boto3.client("s3", region_name=region)
    filter_trigger_lambda.dynamodb = boto3.resource("dynamodb", region_name=region)

    with patch.object(filter_trigger_lambda, "sfn") as mock_sfn:
        r = filter_trigger_lambda.handler(s3_event(bucket, "scores/10.0.0.5/1.json"), None)
        assert r["started"] == []
        mock_sfn.start_execution.assert_not_called()
    print("[OK] MEDIUM/LOW 레벨은 Step Functions 실행 안 시킴")


def test_notify_builds_correct_links_and_publishes():
    with patch.object(notify_lambda, "sns") as mock_sns:
        event = {
            "input": {"ip": "147.32.84.165", "score": 100, "blockCount": 226, "reason": "최근 300초 내 BLOCK 226회"},
            "taskToken": "TOKEN123",
        }
        result = notify_lambda.handler(event, None)

        assert result == {"notified": True, "ip": "147.32.84.165"}
        mock_sns.publish.assert_called_once()
        _, kwargs = mock_sns.publish.call_args
        assert kwargs["TopicArn"] == os.environ["SNS_TOPIC_ARN"]
        assert "147.32.84.165" in kwargs["Subject"]
        assert "token=TOKEN123" in kwargs["Message"]
        assert "decision=approve" in kwargs["Message"]
        assert "decision=deny" in kwargs["Message"]
    print("[OK] SNS 메시지에 승인/거부 링크(taskToken 포함)가 정확히 들어감")


def test_respond_approve_calls_send_task_success():
    with patch.object(respond_lambda, "sfn") as mock_sfn:
        event = {"queryStringParameters": {"token": "TOKEN123", "decision": "approve", "ip": "147.32.84.165"}}
        result = respond_lambda.handler(event, None)

        assert result["statusCode"] == 200
        mock_sfn.send_task_success.assert_called_once()
        _, kwargs = mock_sfn.send_task_success.call_args
        assert kwargs["taskToken"] == "TOKEN123"
        output = json.loads(kwargs["output"])
        assert output == {"decision": "approve", "ip": "147.32.84.165"}
    print("[OK] 승인 클릭 -> send_task_success 호출, decision=approve 정확히 전달됨")


def test_respond_rejects_malformed_request():
    with patch.object(respond_lambda, "sfn") as mock_sfn:
        event = {"queryStringParameters": {"decision": "approve"}}  # token 없음
        result = respond_lambda.handler(event, None)
        assert result["statusCode"] == 400
        mock_sfn.send_task_success.assert_not_called()
    print("[OK] token 없는 잘못된 요청은 400 처리, AWS 호출 안 함")


if __name__ == "__main__":
    test_filter_dedup_only_triggers_once_per_ip()
    test_filter_skips_non_high_level()
    test_notify_builds_correct_links_and_publishes()
    test_respond_approve_calls_send_task_success()
    test_respond_rejects_malformed_request()
    print("\n모든 로컬 검증 통과.")
