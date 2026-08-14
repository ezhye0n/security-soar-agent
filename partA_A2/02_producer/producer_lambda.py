"""
Producer Lambda — demo_logs.csv(슬라이스된 CTU-13 데이터)를 시간축을 압축해서
Kinesis Stream에 "실시간처럼" 재생하는 함수.

핵심 동작:
1. Lambda 배포 패키지에 함께 담긴 demo_logs.csv를 읽는다.
2. 원본 timestamp 간격(상대적인 시간 흐름, 즉 공격 버스트의 "몰림" 패턴)은 유지한 채,
   전체 재생 시간을 targetDurationSeconds로 압축한다.
3. 1초 단위 버킷으로 묶어서, 그 시각이 될 때까지 sleep한 뒤 Kinesis PutRecords로 배치 전송한다.
4. 전송 시점에 timestamp를 원본 값이 아니라 "실제로 보낸 지금 시각"으로 다시 찍는다.
   → Consumer Lambda/Agent가 "최근 데이터"로 인식하게 하기 위함 (파트B와 합의된 사항).

호출 방법 (비동기 추천 - CLI가 기다리지 않고 바로 리턴, CloudWatch Logs로 진행상황 확인):
    aws lambda invoke --function-name soar-agent-producer-soara \
      --invocation-type Event \
      --payload '{"targetDurationSeconds": 180}' \
      --cli-binary-format raw-in-base64-out out.json

    aws logs tail /aws/lambda/soar-agent-producer-soara --follow --region ap-northeast-2

동기 호출(끝날 때까지 기다려서 결과 JSON 바로 받기, --cli-read-timeout을 넉넉히 줘야 함):
    aws lambda invoke --function-name soar-agent-producer-soara \
      --payload '{"targetDurationSeconds": 60}' \
      --cli-read-timeout 400 \
      --cli-binary-format raw-in-base64-out out.json && cat out.json
"""
import csv
import json
import math
import os
import time
from datetime import datetime, timezone

import boto3

kinesis = boto3.client("kinesis")

CSV_PATH = os.path.join(os.path.dirname(__file__), "demo_logs.csv")
STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "soar-agent-log-stream-soara")
DEFAULT_TARGET_DURATION = int(os.environ.get("DEFAULT_TARGET_DURATION_SECONDS", "180"))
MAX_RECORDS_PER_PUT = 500  # Kinesis PutRecords 1회 호출 최대 레코드 수


def parse_ts(raw):
    raw = raw.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"타임스탬프 파싱 실패: {raw}")


def load_rows():
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    rows.sort(key=lambda r: r["timestamp"])
    return rows


def put_batch(records):
    """Kinesis PutRecords 호출 (최대 500건, 실패 레코드는 1회 재시도)."""
    if not records:
        return 0
    entries = [
        {
            "Data": json.dumps(r).encode("utf-8"),
            "PartitionKey": r["ip"],
        }
        for r in records
    ]
    sent = 0
    to_send = entries
    for attempt in range(2):
        resp = kinesis.put_records(StreamName=STREAM_NAME, Records=to_send)
        failed_count = resp.get("FailedRecordCount", 0)
        sent += len(to_send) - failed_count
        if failed_count == 0:
            break
        # 실패한 것만 골라서 한 번 더 시도
        to_send = [
            e for e, res in zip(to_send, resp["Records"]) if "ErrorCode" in res
        ]
        if attempt == 0:
            time.sleep(0.5)
    return sent


def handler(event, context):
    event = event or {}
    target_duration = float(event.get("targetDurationSeconds", DEFAULT_TARGET_DURATION))

    rows = load_rows()
    if not rows:
        return {"sent": 0, "message": "demo_logs.csv에 데이터가 없습니다."}

    first_ts = parse_ts(rows[0]["timestamp"])
    last_ts = parse_ts(rows[-1]["timestamp"])
    original_span = max((last_ts - first_ts).total_seconds(), 0.001)
    compression = target_duration / original_span

    # 1초 단위 버킷으로 묶기 (압축된 상대 offset 기준)
    buckets = {}
    for r in rows:
        rel = (parse_ts(r["timestamp"]) - first_ts).total_seconds() * compression
        bucket = int(math.floor(rel))
        buckets.setdefault(bucket, []).append(r)

    replay_start = time.monotonic()
    total_sent = 0
    total_block_sent = 0
    safety_margin_ms = 5000  # Lambda 잔여시간이 이 아래로 내려가면 중단

    for bucket in sorted(buckets.keys()):
        # Lambda 실행시간 안전장치
        if context and context.get_remaining_time_in_millis() < safety_margin_ms:
            print(
                f"[Producer] 잔여 실행시간 부족으로 조기 종료. "
                f"bucket={bucket}s 까지만 전송, 총 버킷 {len(buckets)}개 중 일부만 처리됨."
            )
            break

        target_wall = replay_start + bucket
        now = time.monotonic()
        if target_wall > now:
            time.sleep(target_wall - now)

        batch = buckets[bucket]
        now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        # timestamp를 "실제 전송 시각"으로 재기록 (원본 2011년 시각 대신)
        rewritten = [
            {"ip": r["ip"], "timestamp": now_iso, "port": int(r["port"]), "action": r["action"]}
            for r in batch
        ]

        for i in range(0, len(rewritten), MAX_RECORDS_PER_PUT):
            chunk = rewritten[i : i + MAX_RECORDS_PER_PUT]
            sent = put_batch(chunk)
            total_sent += sent
            total_block_sent += sum(1 for r in chunk if r["action"] == "BLOCK")

        print(
            f"[Producer] t={bucket}s: {len(batch)}건 전송 "
            f"(누적 {total_sent}건, 그 중 BLOCK {total_block_sent}건)"
        )

    elapsed = time.monotonic() - replay_start
    result = {
        "sent": total_sent,
        "blockSent": total_block_sent,
        "elapsedSeconds": round(elapsed, 1),
        "targetDurationSeconds": target_duration,
        "totalRowsInFile": len(rows),
    }
    print(f"[Producer] 완료: {json.dumps(result, ensure_ascii=False)}")
    return result
