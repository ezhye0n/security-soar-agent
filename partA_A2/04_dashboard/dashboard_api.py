"""
Dashboard 읽기 전용 API — Consumer가 이미 쓰고 있는 DynamoDB(soar-agent-ip-state-soara) /
S3(soar-agent-threat-scores-soara-*)를 그대로 읽기만 해서 대시보드용 JSON을 만들어주는 함수.
Lambda Function URL(GET, 인증 없음, CORS 허용)로 노출합니다. 새 인프라 거의 없이 기존
Consumer 데이터만 재사용하는 구조라 배포가 빠릅니다.

응답 형식:
{
  "generatedAt": "2026-08-13T...",
  "totalIpsSeen": 3,            # DynamoDB에 STATE 아이템이 있는 IP 개수 (=지금까지 관측된 서로 다른 IP 수)
  "totalEventsProcessed": 48705, # 모든 IP의 total_count 합
  "activeThreats": [             # S3에 BLOCK 기록이 있는 IP들의 "최신" 판정
    {
      "ip": "147.32.84.165",
      "level": "HIGH", "score": 100, "blockCount": 226, "totalCount": 226,
      "reason": "...", "windowStart": "...", "windowEnd": "..."
    }
  ]
}
"""
import datetime
import json
import os

import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

DDB_TABLE_NAME = os.environ.get("DDB_TABLE_NAME", "soar-agent-ip-state-soara")
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "soar-agent-threat-scores-soara")

CORS_HEADERS = {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "*",
}


def get_aggregate_stats():
    """DynamoDB STATE 아이템들을 스캔해서 '지금까지 관측된 IP 수'와 '전체 이벤트 수'를 집계.
    해커톤 규모(수백~수천 IP)에서는 Scan으로 충분합니다."""
    table = dynamodb.Table(DDB_TABLE_NAME)
    total_ips = 0
    total_events = 0
    last_key = None
    while True:
        kwargs = {"FilterExpression": Attr("sk").eq("STATE")}
        if last_key:
            kwargs["ExclusiveStartKey"] = last_key
        resp = table.scan(**kwargs)
        for item in resp.get("Items", []):
            total_ips += 1
            total_events += int(item.get("total_count", 0))
        last_key = resp.get("LastEvaluatedKey")
        if not last_key:
            break
    return total_ips, total_events


def get_active_threats():
    """S3 scores/ 아래 IP별 폴더(CommonPrefixes)를 찾고, 각 IP의 가장 최근 판정 파일 1개만 읽어온다."""
    threats = []
    paginator = s3.get_paginator("list_objects_v2")
    ip_prefixes = []
    for page in paginator.paginate(Bucket=S3_BUCKET_NAME, Prefix="scores/", Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            ip_prefixes.append(cp["Prefix"])  # 예: "scores/147.32.84.165/"

    table = dynamodb.Table(DDB_TABLE_NAME)
    for prefix in ip_prefixes:
        resp = s3.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix=prefix)
        contents = resp.get("Contents", [])
        if not contents:
            continue
        latest = max(contents, key=lambda o: o["Key"])  # 파일명이 epoch_ms라 문자열 정렬 = 시간 정렬
        obj = s3.get_object(Bucket=S3_BUCKET_NAME, Key=latest["Key"])
        body = json.loads(obj["Body"].read())

        # blockIP-soara가 승인 후 실행되면 sk="BLOCKED" 아이템을 남김 - 있으면 차단 완료 상태로 표시
        blocked_item = table.get_item(Key={"ip": body.get("ip"), "sk": "BLOCKED"}).get("Item")
        body["blocked"] = bool(blocked_item)
        body["blockedAt"] = blocked_item.get("blockedAt") if blocked_item else None

        threats.append(body)

    level_rank = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    threats.sort(key=lambda t: (level_rank.get(t.get("level"), 3), -t.get("blockCount", 0)))
    return threats


def handler(event, context):
    method = (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod")
        or "GET"
    )
    if method == "OPTIONS":
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ""}

    try:
        total_ips, total_events = get_aggregate_stats()
        threats = get_active_threats()

        body = {
            "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
            "totalIpsSeen": total_ips,
            "totalEventsProcessed": total_events,
            "activeThreats": threats,
        }
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": json.dumps(body, ensure_ascii=False)}
    except Exception as e:
        print(f"[Dashboard API] 오류: {e}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e)}, ensure_ascii=False),
        }
