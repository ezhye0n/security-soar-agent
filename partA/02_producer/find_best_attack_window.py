#!/usr/bin/env python3
"""
logs_clean.csv 전체에서 "BLOCK이 가장 밀집된 N초 구간"을 실제로 찾아서
그 구간(+앞뒤 여유시간)만 데모용으로 잘라냅니다.

이전 slice_for_demo.py(첫 BLOCK 행 기준 앞뒤 행 수로 자르는 방식)는 배경 트래픽이
워낙 많아서(전체의 98.5%) 잘라낸 구간에 BLOCK이 거의 안 섞이는 문제가 있었습니다.
이 스크립트는 실제 BLOCK 밀도를 스캔해서 가장 몰려있는 시간대를 찾습니다.

사용법:
    python3 find_best_attack_window.py --input logs_clean.csv --output demo_logs.csv \
        --window-seconds 300 --margin-seconds 120
"""
import argparse
import csv
import sys
from datetime import datetime, timedelta, timezone


def parse_ts(raw):
    raw = raw.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"타임스탬프 파싱 실패: {raw}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="logs_clean.csv")
    parser.add_argument("--output", default="demo_logs.csv")
    parser.add_argument("--window-seconds", type=int, default=300, help="이 구간(초) 안에서 BLOCK 최다 밀집 지점 탐색")
    parser.add_argument("--margin-seconds", type=int, default=120, help="찾은 구간 앞뒤 여유(배경 트래픽 맥락용)")
    args = parser.parse_args()

    with open(args.input, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    for r in rows:
        r["_ts"] = parse_ts(r["timestamp"])

    block_rows = sorted((r for r in rows if r["action"] == "BLOCK"), key=lambda r: r["_ts"])
    if not block_rows:
        print("[오류] BLOCK 행이 없습니다.", file=sys.stderr)
        sys.exit(1)

    window = timedelta(seconds=args.window_seconds)
    best_count = 0
    best_left_ts = best_right_ts = block_rows[0]["_ts"]
    left = 0
    for right in range(len(block_rows)):
        while (block_rows[right]["_ts"] - block_rows[left]["_ts"]) > window:
            left += 1
        count = right - left + 1
        if count > best_count:
            best_count = count
            best_left_ts = block_rows[left]["_ts"]
            best_right_ts = block_rows[right]["_ts"]

    margin = timedelta(seconds=args.margin_seconds)
    win_start = best_left_ts - margin
    win_end = best_right_ts + margin

    sliced = sorted(
        (r for r in rows if win_start <= r["_ts"] <= win_end),
        key=lambda r: r["_ts"],
    )

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["ip", "timestamp", "port", "action"])
        writer.writeheader()
        for r in sliced:
            writer.writerow({"ip": r["ip"], "timestamp": r["timestamp"], "port": r["port"], "action": r["action"]})

    block_count = sum(1 for r in sliced if r["action"] == "BLOCK")
    print(
        f"가장 밀집된 {args.window_seconds}초 구간에서 BLOCK {best_count}건 발견\n"
        f"확장 구간: {win_start.isoformat()} ~ {win_end.isoformat()}\n"
        f"완료: {len(sliced)}행 저장 → {args.output} "
        f"(BLOCK {block_count}행 / ALLOW {len(sliced) - block_count}행)",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
