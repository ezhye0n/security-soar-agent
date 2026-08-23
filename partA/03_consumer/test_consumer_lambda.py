"""
consumer_lambda.py 로컬 검증 (moto로 실제와 거의 동일한 DynamoDB/S3 인메모리 모킹).
AWS 계정 없이도 Query/TTL 속성/S3 기록까지 실제 동작과 동일하게 확인할 수 있습니다.

실행:
    python3 -m pytest test_consumer_lambda.py -v
    (또는) python3 test_consumer_lambda.py
"""
import base64
import json
import os
from datetime import datetime, timedelta, timezone

os.environ["DDB_TABLE_NAME"] = "soar-agent-ip-state-soara"
os.environ["S3_BUCKET_NAME"] = "soar-agent-threat-scores-soara"
os.environ["WINDOW_SECONDS"] = "300"
os.environ["HIGH_THRESHOLD"] = "5"
os.environ["MEDIUM_THRESHOLD"] = "2"

import boto3
from boto3.dynamodb.conditions import Key
from moto import mock_aws

import consumer_lambda


def make_kinesis_event(rows, start_seq=0):
    """실제 Kinesis 트리거 이벤트 형태로 변환. sequenceNumber는 레코드마다 고유하게 부여
    (실제 Kinesis도 이렇게 동작함 — consumer_lambda의 sk 충돌 방지 로직 검증용)."""
    records = []
    for i, r in enumerate(rows):
        data = json.dumps(r).encode("utf-8")
        records.append(
            {
                "kinesis": {
                    "data": base64.b64encode(data).decode("utf-8"),
                    "sequenceNumber": str(start_seq + i).zfill(56),
                }
            }
        )
    return {"Records": records}


def setup_infra(region="ap-northeast-2"):
    ddb = boto3.client("dynamodb", region_name=region)
    ddb.create_table(
        TableName=os.environ["DDB_TABLE_NAME"],
        KeySchema=[
            {"AttributeName": "ip", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "ip", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    ddb.update_time_to_live(
        TableName=os.environ["DDB_TABLE_NAME"],
        TimeToLiveSpecification={"Enabled": True, "AttributeName": "expiresAt"},
    )
    s3 = boto3.client("s3", region_name=region)
    s3.create_bucket(
        Bucket=os.environ["S3_BUCKET_NAME"],
        CreateBucketConfiguration={"LocationConstraint": region},
    )


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


@mock_aws
def test_allow_only_no_s3_no_evt_items():
    setup_infra()
    consumer_lambda.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    consumer_lambda.s3 = boto3.client("s3", region_name="ap-northeast-2")

    base = datetime(2026, 8, 13, 3, 0, 0, tzinfo=timezone.utc)
    rows = [
        {"ip": "10.0.0.1", "timestamp": iso(base + timedelta(seconds=i)), "port": 80, "action": "ALLOW"}
        for i in range(5)
    ]
    result = consumer_lambda.handler(make_kinesis_event(rows), context=None)
    assert result["processed"] == 5
    assert result["blockProcessed"] == 0
    assert result["highIps"] == []

    table = consumer_lambda._table()
    state = table.get_item(Key={"ip": "10.0.0.1", "sk": "STATE"})["Item"]
    assert int(state["total_count"]) == 5

    s3 = consumer_lambda.s3
    listing = s3.list_objects_v2(Bucket=os.environ["S3_BUCKET_NAME"], Prefix="scores/")
    assert listing.get("KeyCount", 0) == 0
    print("[OK] ALLOW만 있는 경우: DynamoDB EVT/S3 기록 없음, total_count만 누적")


@mock_aws
def test_block_burst_escalates_to_high():
    setup_infra()
    consumer_lambda.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    consumer_lambda.s3 = boto3.client("s3", region_name="ap-northeast-2")

    ip = "147.32.84.165"
    base = datetime(2026, 8, 13, 3, 0, 0, tzinfo=timezone.utc)
    # 60초 간격으로 6번 BLOCK (모두 5분 윈도우 안에 들어옴)
    rows = [
        {"ip": ip, "timestamp": iso(base + timedelta(seconds=60 * i)), "port": 6667, "action": "BLOCK"}
        for i in range(6)
    ]
    levels = []
    for row in rows:
        result = consumer_lambda.handler(make_kinesis_event([row]), context=None)
        levels.append(result["highIps"])

    # 1~2번째: LOW/MEDIUM 미만, 3번째부터 MEDIUM(>=2), 6번째(6회)에서 HIGH(>=5)
    assert levels[0] == []  # blockCount=1 -> LOW
    assert levels[4] == [ip]  # blockCount=5 -> HIGH
    assert levels[5] == [ip]  # blockCount=6 -> HIGH

    s3 = consumer_lambda.s3
    listing = s3.list_objects_v2(Bucket=os.environ["S3_BUCKET_NAME"], Prefix=f"scores/{ip}/")
    assert listing["KeyCount"] == 6

    last_obj = sorted(listing["Contents"], key=lambda o: o["Key"])[-1]
    body = json.loads(s3.get_object(Bucket=os.environ["S3_BUCKET_NAME"], Key=last_obj["Key"])["Body"].read())
    assert body["ip"] == ip
    assert body["blockCount"] == 6
    assert body["level"] == "HIGH"
    assert body["score"] == 100
    assert body["totalCount"] == 6
    print(f"[OK] BLOCK 6연속(60초 간격): {levels} -> 5번째부터 HIGH, S3에 {listing['KeyCount']}건 기록")


@mock_aws
def test_old_block_outside_window_not_counted():
    """TTL로 아직 안 지워졌어도, 윈도우 밖(오래된) 이벤트는 Query에서 제외되어야 함."""
    setup_infra()
    consumer_lambda.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    consumer_lambda.s3 = boto3.client("s3", region_name="ap-northeast-2")

    ip = "192.168.1.50"
    old_time = datetime(2026, 8, 13, 3, 0, 0, tzinfo=timezone.utc)
    # 오래된 BLOCK 4건 (10분 전 -> 5분 윈도우 밖)
    old_rows = [
        {"ip": ip, "timestamp": iso(old_time + timedelta(seconds=i)), "port": 22, "action": "BLOCK"}
        for i in range(4)
    ]
    consumer_lambda.handler(make_kinesis_event(old_rows), context=None)

    # 10분 뒤, 새 BLOCK 2건만 발생 (윈도우 안에는 이 2건만 있어야 함)
    new_time = old_time + timedelta(minutes=10)
    new_rows = [
        {"ip": ip, "timestamp": iso(new_time + timedelta(seconds=i)), "port": 22, "action": "BLOCK"}
        for i in range(2)
    ]
    result = consumer_lambda.handler(make_kinesis_event(new_rows), context=None)

    s3 = consumer_lambda.s3
    listing = s3.list_objects_v2(Bucket=os.environ["S3_BUCKET_NAME"], Prefix=f"scores/{ip}/")
    last_obj = sorted(listing["Contents"], key=lambda o: o["Key"])[-1]
    body = json.loads(s3.get_object(Bucket=os.environ["S3_BUCKET_NAME"], Key=last_obj["Key"])["Body"].read())

    assert body["blockCount"] == 2, f"윈도우 밖 오래된 BLOCK이 섞이면 안 됨, 실제: {body['blockCount']}"
    assert body["level"] == "MEDIUM"  # blockCount=2 == MEDIUM_THRESHOLD
    assert body["totalCount"] == 6  # 누적치는 오래된 것도 포함 (참고용이므로 의도된 동작)
    print(f"[OK] 10분 전 BLOCK 4건은 윈도우에서 제외됨 (blockCount={body['blockCount']}, totalCount={body['totalCount']})")


@mock_aws
def test_expires_at_set_correctly():
    setup_infra()
    consumer_lambda.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    consumer_lambda.s3 = boto3.client("s3", region_name="ap-northeast-2")

    ip = "10.0.0.99"
    t = datetime(2026, 8, 13, 3, 0, 0, tzinfo=timezone.utc)
    row = {"ip": ip, "timestamp": iso(t), "port": 443, "action": "BLOCK"}
    consumer_lambda.handler(make_kinesis_event([row]), context=None)

    table = consumer_lambda._table()
    resp = table.query(KeyConditionExpression=Key("ip").eq(ip))
    evt_items = [i for i in resp["Items"] if i["sk"].startswith("EVT#")]
    assert len(evt_items) == 1
    expected_expiry = int(t.timestamp()) + 300 + 60  # WINDOW_SECONDS + TTL_BUFFER_SECONDS
    assert int(evt_items[0]["expiresAt"]) == expected_expiry
    print(f"[OK] TTL(expiresAt) = event_ts + WINDOW_SECONDS + BUFFER = {expected_expiry}")


@mock_aws
def test_duplicate_timestamp_same_bucket_not_overwritten():
    """Producer가 압축 버킷당 timestamp를 1개만 찍기 때문에, 같은 IP가 같은 버킷에서
    여러 번 BLOCK되면 timestamp 문자열이 완전히 동일한 채로 한 Kinesis 배치에 들어온다.
    sk에 sequenceNumber suffix가 없으면 put_item이 서로 덮어써서 blockCount가 누락된다."""
    setup_infra()
    consumer_lambda.dynamodb = boto3.resource("dynamodb", region_name="ap-northeast-2")
    consumer_lambda.s3 = boto3.client("s3", region_name="ap-northeast-2")

    ip = "147.32.84.165"
    same_ts = iso(datetime(2026, 8, 13, 3, 0, 0, tzinfo=timezone.utc))
    # 실제 Producer처럼: 같은 버킷 안 5건이 timestamp까지 완전히 동일
    rows = [{"ip": ip, "timestamp": same_ts, "port": 6667, "action": "BLOCK"} for _ in range(5)]
    result = consumer_lambda.handler(make_kinesis_event(rows), context=None)

    assert result["blockProcessed"] == 5
    assert result["highIps"] == [ip], f"5건 모두 카운트됐다면 HIGH(>=5)여야 함, 실제 결과: {result}"

    table = consumer_lambda._table()
    resp = table.query(KeyConditionExpression=Key("ip").eq(ip))
    evt_items = [i for i in resp["Items"] if i["sk"].startswith("EVT#")]
    assert len(evt_items) == 5, f"sk 충돌로 덮어써졌다면 5개 미만이 됨, 실제: {len(evt_items)}개"
    print(f"[OK] 동일 timestamp 5건이 sk 충돌 없이 전부 저장됨 (EVT# 아이템 {len(evt_items)}개, HIGH 판정 확인)")


if __name__ == "__main__":
    test_allow_only_no_s3_no_evt_items()
    test_block_burst_escalates_to_high()
    test_old_block_outside_window_not_counted()
    test_expires_at_set_correctly()
    test_duplicate_timestamp_same_bucket_not_overwritten()
    print("\n모든 로컬 검증 통과.")
