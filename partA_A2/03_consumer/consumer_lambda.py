"""
Consumer Lambda — Kinesis Stream(soar-agent-log-stream-soara)을 트리거로 받아
"최근 WINDOW_SECONDS초 안에 같은 IP가 BLOCK된 횟수"를 슬라이딩 윈도우로 집계하고,
위협 레벨(LOW/MEDIUM/HIGH)을 판정해서 S3에 결과 JSON을 기록하는 함수.

=== 설계 결정: DynamoDB 윈도우 카운터 방식 = TTL 기반 (이벤트별 아이템) ===
집계 카운터(분 단위 버킷) 방식 대신 TTL 기반을 선택했습니다. 이유:
  1. 정확도: 버킷 방식은 "정확히 최근 5분"이 아니라 "최근 5개 버킷" 같은 근사치가 되기 쉬움
     (예: 4분59초 전 버킷 경계까지 걸리면 6분치가 잡히는 등). TTL 기반은 Query 한 번으로
     진짜 슬라이딩 윈도우 카운트를 얻습니다.
  2. 구현 단순함: DynamoDB Query(KeyConditionExpression + Select=COUNT) 한 번으로 끝.
     버킷 방식처럼 "여러 분 버킷을 합산" 로직이 필요 없음.
  3. 비용: BLOCK 이벤트만 저장하므로(전체 트래픽의 1.5% 수준) 쓰기 비용이 작고,
     TTL로 자동 삭제되어 테이블이 무한정 커지지 않음.
  단점(트레이드오프): 매 BLOCK 이벤트마다 Query 1회가 발생하지만, BLOCK 자체가 희소해서
  이 데모/해커톤 규모에서는 문제없습니다.

=== DynamoDB 테이블 스키마 (단일 테이블) ===
테이블명: 환경변수 DDB_TABLE_NAME (기본 soar-agent-ip-state-soara)
Partition Key : ip      (String)
Sort Key      : sk       (String)
  - 누적 카운터 아이템: sk = "STATE"                 (attrs: total_count, updatedAt)
  - BLOCK 이벤트 아이템: sk = "EVT#<epoch_ms 20자리 0패딩>#<Kinesis sequenceNumber>"
    (attrs: timestamp, port, expiresAt)
TTL 속성: expiresAt (Number, epoch seconds) — EVT# 아이템에만 설정, STATE 아이템엔 없음
  (문자열 "EVT#..."가 "STATE"보다 항상 사전순으로 앞이라 Query 시 범위가 절대 겹치지 않음)

주의: Producer Lambda는 1초 압축 버킷 단위로 timestamp를 한 번만 찍어서(now_iso) 그 버킷의
모든 레코드에 동일하게 붙입니다. 즉 같은 IP가 같은 버킷 안에서 여러 번 BLOCK되면 epoch_ms가
완전히 동일할 수 있습니다. sk에 epoch_ms만 쓰면 같은 sk를 가진 이전 아이템을 put_item이
덮어써서 카운트가 누락되는 버그가 생기므로, Kinesis 레코드의 sequenceNumber(레코드마다 고유)를
sk 끝에 덧붙여 충돌을 방지합니다. Query 시 상한은 f"EVT#{end_ms}#~" 처럼 숫자보다 사전순으로
큰 문자(~)를 붙여서, 같은 epoch_ms를 가진 모든 suffix를 빠짐없이 포함하도록 합니다.

=== S3 출력 스키마 ===
버킷: 환경변수 S3_BUCKET_NAME
키   : scores/<ip>/<epoch_ms>.json
바디 : {ip, windowStart, windowEnd, blockCount, totalCount, score, level, reason}
  - blockCount : 이 IP가 최근 WINDOW_SECONDS초 안에 BLOCK된 횟수 (진짜 슬라이딩 윈도우)
  - totalCount : 이 IP에 대해 지금까지 Consumer가 처리한 전체 이벤트 수(ALLOW+BLOCK 누적,
                 윈도우가 아닌 누적치입니다 — 참고용 컨텍스트 값)
  - score      : blockCount를 0~100으로 정규화한 값 (HIGH_THRESHOLD 도달 시 100)
  - level      : LOW / MEDIUM / HIGH
  - reason     : 사람이 읽을 수 있는 판정 사유 문자열

Kinesis 트리거 이벤트는 매 레코드(ALLOW/BLOCK 둘 다)마다 들어오며, Consumer는:
  - 모든 이벤트: STATE 아이템의 total_count를 원자적으로 +1
  - BLOCK 이벤트만: EVT# 아이템 기록 → 윈도우 Query → 레벨 판정 → S3 기록
"""
import base64
import json
import os
from datetime import datetime, timedelta, timezone

import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

DDB_TABLE_NAME = os.environ.get("DDB_TABLE_NAME", "soar-agent-ip-state-soara")
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "soar-agent-threat-scores-soara")
WINDOW_SECONDS = int(os.environ.get("WINDOW_SECONDS", "300"))
HIGH_THRESHOLD = int(os.environ.get("HIGH_THRESHOLD", "5"))
MEDIUM_THRESHOLD = int(os.environ.get("MEDIUM_THRESHOLD", "2"))
TTL_BUFFER_SECONDS = int(os.environ.get("TTL_BUFFER_SECONDS", "60"))  # 윈도우 지나고 여유 있게 삭제

SK_PAD_WIDTH = 20  # epoch_ms(13자리)보다 넉넉하게 0패딩 -> 문자열 정렬 = 숫자 정렬


def _table():
    return dynamodb.Table(DDB_TABLE_NAME)


def parse_ts(raw):
    raw = raw.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"타임스탬프 파싱 실패: {raw}")


def decode_kinesis_record(record):
    """Kinesis 레코드(base64) -> {ip, timestamp, port, action} dict."""
    payload = base64.b64decode(record["kinesis"]["data"])
    return json.loads(payload)


def bump_total_count(ip, now_iso):
    """IP별 누적 이벤트 카운터(+1). 윈도우 아님, 참고용 누적치."""
    resp = _table().update_item(
        Key={"ip": ip, "sk": "STATE"},
        UpdateExpression="ADD total_count :one SET updatedAt = :now",
        ExpressionAttributeValues={":one": 1, ":now": now_iso},
        ReturnValues="UPDATED_NEW",
    )
    return int(resp["Attributes"]["total_count"])


def record_block_event(ip, event_dt, port, sequence_number):
    """BLOCK 이벤트를 EVT# 아이템으로 기록 (TTL 포함).

    sk에 Kinesis sequenceNumber를 덧붙여, 같은 압축 버킷 안에서 동일 timestamp를 가진
    레코드끼리 sk가 충돌해 put_item이 서로 덮어쓰는 것을 방지한다.
    """
    epoch_ms = int(event_dt.timestamp() * 1000)
    sk = f"EVT#{epoch_ms:0{SK_PAD_WIDTH}d}#{sequence_number}"
    expires_at = int(event_dt.timestamp()) + WINDOW_SECONDS + TTL_BUFFER_SECONDS
    _table().put_item(
        Item={
            "ip": ip,
            "sk": sk,
            "timestamp": event_dt.isoformat().replace("+00:00", "Z"),
            "port": port,
            "expiresAt": expires_at,
        }
    )
    return epoch_ms


def query_window_block_count(ip, window_start_dt, window_end_dt):
    """[window_start, window_end] 구간 안의 BLOCK 이벤트 수를 진짜 슬라이딩 윈도우로 집계.

    상한에 "#~" 센티널을 붙여, end_ms와 epoch_ms가 같은 아이템(어떤 sequenceNumber든)까지
    빠짐없이 포함한다 ('~'는 숫자/일반 문자보다 사전순으로 뒤에 오는 문자).
    """
    start_ms = int(window_start_dt.timestamp() * 1000)
    end_ms = int(window_end_dt.timestamp() * 1000)
    resp = _table().query(
        KeyConditionExpression=(
            Key("ip").eq(ip)
            & Key("sk").between(
                f"EVT#{start_ms:0{SK_PAD_WIDTH}d}", f"EVT#{end_ms:0{SK_PAD_WIDTH}d}#~"
            )
        ),
        Select="COUNT",
    )
    return int(resp["Count"])


def classify(block_count):
    if block_count >= HIGH_THRESHOLD:
        level = "HIGH"
        reason = f"최근 {WINDOW_SECONDS}초 내 BLOCK {block_count}회 (HIGH 기준 {HIGH_THRESHOLD}회 이상)"
    elif block_count >= MEDIUM_THRESHOLD:
        level = "MEDIUM"
        reason = f"최근 {WINDOW_SECONDS}초 내 BLOCK {block_count}회 (MEDIUM 기준 {MEDIUM_THRESHOLD}회 이상)"
    else:
        level = "LOW"
        reason = f"최근 {WINDOW_SECONDS}초 내 BLOCK {block_count}회 (기준 미달)"
    score = min(100, round(block_count / HIGH_THRESHOLD * 100)) if HIGH_THRESHOLD > 0 else 0
    return level, score, reason


def write_score_to_s3(ip, window_start_dt, window_end_dt, block_count, total_count, score, level, reason, epoch_ms):
    body = {
        "ip": ip,
        "windowStart": window_start_dt.isoformat().replace("+00:00", "Z"),
        "windowEnd": window_end_dt.isoformat().replace("+00:00", "Z"),
        "blockCount": block_count,
        "totalCount": total_count,
        "score": score,
        "level": level,
        "reason": reason,
    }
    key = f"scores/{ip}/{epoch_ms}.json"
    s3.put_object(
        Bucket=S3_BUCKET_NAME,
        Key=key,
        Body=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )
    return key, body


def handler(event, context):
    records = event.get("Records", [])
    processed = 0
    block_processed = 0
    high_ips = []
    errors = []

    for raw in records:
        try:
            r = decode_kinesis_record(raw)
            ip = r["ip"]
            action = r["action"]
            port = int(r.get("port", 0))
            event_dt = parse_ts(r["timestamp"])
            now_iso = event_dt.isoformat().replace("+00:00", "Z")

            total_count = bump_total_count(ip, now_iso)
            processed += 1

            if action == "BLOCK":
                sequence_number = raw["kinesis"].get("sequenceNumber", str(id(raw)))
                epoch_ms = record_block_event(ip, event_dt, port, sequence_number)
                window_start = event_dt - timedelta(seconds=WINDOW_SECONDS)
                block_count = query_window_block_count(ip, window_start, event_dt)
                level, score, reason = classify(block_count)
                write_score_to_s3(
                    ip, window_start, event_dt, block_count, total_count, score, level, reason, epoch_ms
                )
                block_processed += 1
                if level == "HIGH":
                    high_ips.append(ip)
        except Exception as e:  # 레코드 1건 실패해도 나머지는 계속 처리
            errors.append(str(e))
            print(f"[Consumer] 레코드 처리 실패: {e}")

    result = {
        "processed": processed,
        "blockProcessed": block_processed,
        "highIps": sorted(set(high_ips)),
        "errors": errors,
    }
    print(f"[Consumer] 배치 완료: {json.dumps(result, ensure_ascii=False)}")
    return result
