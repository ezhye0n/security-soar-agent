import json
import os

os.environ["DDB_TABLE_NAME"] = "soar-agent-ip-state-soara"
os.environ["S3_BUCKET_NAME"] = "soar-agent-threat-scores-soara"

import boto3
from moto import mock_aws

import dashboard_api


def setup_infra(region="ap-northeast-2"):
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
    s3.create_bucket(
        Bucket=os.environ["S3_BUCKET_NAME"], CreateBucketConfiguration={"LocationConstraint": region}
    )


@mock_aws
def test_dashboard_aggregates_and_threats():
    setup_infra()
    dashboard_api.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    dashboard_api.s3 = boto3.client("s3", region_name="ap-northeast-2")

    table = dashboard_api.dynamodb.Table(os.environ["DDB_TABLE_NAME"])
    # 감염 IP(누적 300건) + 정상 IP 2개(누적 120, 80건) 시뮬레이션
    table.put_item(Item={"ip": "147.32.84.165", "sk": "STATE", "total_count": 300})
    table.put_item(Item={"ip": "212.50.71.179", "sk": "STATE", "total_count": 120})
    table.put_item(Item={"ip": "10.0.0.5", "sk": "STATE", "total_count": 80})

    s3 = dashboard_api.s3
    bucket = os.environ["S3_BUCKET_NAME"]
    s3.put_object(
        Bucket=bucket,
        Key="scores/147.32.84.165/1000.json",
        Body=json.dumps({"ip": "147.32.84.165", "level": "MEDIUM", "blockCount": 3}),
    )
    s3.put_object(
        Bucket=bucket,
        Key="scores/147.32.84.165/2000.json",
        Body=json.dumps({"ip": "147.32.84.165", "level": "HIGH", "blockCount": 226}),
    )

    result = dashboard_api.handler({"requestContext": {"http": {"method": "GET"}}}, context=None)
    assert result["statusCode"] == 200
    body = json.loads(result["body"])

    assert body["totalIpsSeen"] == 3
    assert body["totalEventsProcessed"] == 500  # 300+120+80
    assert len(body["activeThreats"]) == 1  # 정상 IP 2개는 S3에 기록 자체가 없음(BLOCK 없었으므로)
    assert body["activeThreats"][0]["ip"] == "147.32.84.165"
    assert body["activeThreats"][0]["level"] == "HIGH"
    assert body["activeThreats"][0]["blockCount"] == 226  # 가장 최신(2000.json) 값이어야 함
    assert body["activeThreats"][0]["blocked"] is False  # 아직 blockIP-soara가 실행 안 됨
    assert body["activeThreats"][0]["blockedAt"] is None
    print("[OK] 대시보드 API: 정상 IP는 안 잡히고, 감염 IP는 최신 판정(HIGH, 226)만 반환됨")
    print(json.dumps(body, ensure_ascii=False, indent=2))


@mock_aws
def test_dashboard_shows_blocked_status():
    """blockIP-soara가 sk='BLOCKED' 아이템을 남긴 경우, 대시보드가 이걸 blocked:true로 보여주는지."""
    setup_infra()
    dashboard_api.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    dashboard_api.s3 = boto3.client("s3", region_name="ap-northeast-2")

    table = dashboard_api.dynamodb.Table(os.environ["DDB_TABLE_NAME"])
    table.put_item(Item={"ip": "147.32.84.165", "sk": "STATE", "total_count": 300})
    # blockIP-soara가 이미 실행되어 BLOCKED 아이템을 남긴 상태를 시뮬레이션
    table.put_item(Item={"ip": "147.32.84.165", "sk": "BLOCKED", "blockedAt": "2026-08-13T06:10:00Z"})

    s3 = dashboard_api.s3
    bucket = os.environ["S3_BUCKET_NAME"]
    s3.put_object(
        Bucket=bucket,
        Key="scores/147.32.84.165/2000.json",
        Body=json.dumps({"ip": "147.32.84.165", "level": "HIGH", "blockCount": 226}),
    )

    result = dashboard_api.handler({"requestContext": {"http": {"method": "GET"}}}, context=None)
    body = json.loads(result["body"])

    assert body["activeThreats"][0]["blocked"] is True
    assert body["activeThreats"][0]["blockedAt"] == "2026-08-13T06:10:00Z"
    print("[OK] blockIP-soara 실행 후 BLOCKED 아이템이 있으면 대시보드가 blocked:true로 표시함")


if __name__ == "__main__":
    test_dashboard_aggregates_and_threats()
    test_dashboard_shows_blocked_status()
    print("\n통과.")
