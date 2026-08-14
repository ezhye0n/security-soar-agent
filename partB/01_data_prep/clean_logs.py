#!/usr/bin/env python3
"""
Kaggle 보안 로그(방화벽/IDS) 원본 CSV를 프로젝트 표준 스키마로 정제합니다.

표준 스키마 (Producer Lambda가 Kinesis로 보낼 컬럼):
    ip          - 발신 IP (문자열)
    timestamp   - ISO8601 UTC (예: 2026-08-13T05:12:03Z)
    port         - 목적지 포트 (정수)
    action       - "ALLOW" 또는 "BLOCK"

사용법:
    python3 clean_logs.py --input raw_kaggle_logs.csv --output logs_clean.csv \
        --ip-col "Src IP" --time-col "Timestamp" --port-col "Dst Port" --action-col "Label"

컬럼명이 데이터셋마다 다르므로 --ip-col/--time-col/--port-col/--action-col 로 원본 컬럼명을 지정하세요.
--action-map 으로 원본 라벨 값을 ALLOW/BLOCK 으로 매핑할 수 있습니다.
    예) --action-map "BENIGN=ALLOW,Attack=BLOCK,DDoS=BLOCK"
"""
import argparse
import csv
import sys
from datetime import datetime, timezone


def parse_action_map(raw: str) -> dict:
    mapping = {}
    if not raw:
        return mapping
    for pair in raw.split(","):
        if not pair.strip():
            continue
        k, v = pair.split("=")
        mapping[k.strip()] = v.strip().upper()
    return mapping


def normalize_timestamp(raw: str) -> str:
    """다양한 원본 시각 포맷을 ISO8601 UTC로 변환. 파싱 실패 시 원본 값을 그대로 반환."""
    raw = raw.strip()
    candidate_formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%d/%m/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%d/%m/%Y %I:%M:%S %p",
        "%Y/%m/%d %H:%M:%S",
    ]
    for fmt in candidate_formats:
        try:
            dt = datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            continue
    return raw  # 그대로 통과 (필요하면 수동 확인)


def normalize_action(raw: str, action_map: dict) -> str:
    raw_stripped = raw.strip()
    if raw_stripped in action_map:
        return action_map[raw_stripped]
    upper = raw_stripped.upper()
    if upper in ("ALLOW", "ALLOWED", "PASS", "BENIGN", "NORMAL", "0"):
        return "ALLOW"
    if upper in ("BLOCK", "BLOCKED", "DENY", "DENIED", "ATTACK", "MALICIOUS", "1"):
        return "BLOCK"
    # 매핑을 못 찾으면 보수적으로 BLOCK 처리하지 않고 원본을 남겨서 나중에 검수하도록 함
    return upper


def main():
    parser = argparse.ArgumentParser(description="Kaggle 보안 로그 정제 스크립트")
    parser.add_argument("--input", required=True, help="원본 CSV 경로")
    parser.add_argument("--output", required=True, help="정제된 CSV 출력 경로")
    parser.add_argument("--ip-col", required=True, help="원본 IP 컬럼명")
    parser.add_argument("--time-col", required=True, help="원본 시각 컬럼명")
    parser.add_argument("--port-col", required=True, help="원본 포트 컬럼명")
    parser.add_argument("--action-col", required=True, help="원본 허용/차단(라벨) 컬럼명")
    parser.add_argument("--action-map", default="", help="라벨값=ALLOW|BLOCK 매핑 (쉼표 구분)")
    parser.add_argument("--limit", type=int, default=0, help="최대 행 수 (0=전체)")
    args = parser.parse_args()

    action_map = parse_action_map(args.action_map)

    written = 0
    skipped = 0
    with open(args.input, newline="", encoding="utf-8", errors="replace") as f_in, \
         open(args.output, "w", newline="", encoding="utf-8") as f_out:
        reader = csv.DictReader(f_in)
        writer = csv.writer(f_out)
        writer.writerow(["ip", "timestamp", "port", "action"])

        for row in reader:
            try:
                ip = row[args.ip_col].strip()
                ts = normalize_timestamp(row[args.time_col])
                port = int(float(row[args.port_col]))
                action = normalize_action(row[args.action_col], action_map)
                if not ip or action not in ("ALLOW", "BLOCK"):
                    skipped += 1
                    continue
                writer.writerow([ip, ts, port, action])
                written += 1
            except (KeyError, ValueError):
                skipped += 1
                continue

            if args.limit and written >= args.limit:
                break

    print(f"완료: {written}행 저장 → {args.output} (스킵 {skipped}행)", file=sys.stderr)


if __name__ == "__main__":
    main()
