#!/usr/bin/env python3
"""
logs_clean.csv(282만 행)는 그대로 실시간 재생하기엔 너무 큽니다
(Kinesis 샤드 처리량 한계, Lambda 15분 제한, 데모 시간 제약).
그래서 공격 시점을 중심으로 "배경 트래픽 + 공격 버스트"가 자연스럽게 섞인
작은 구간만 잘라내서 데모용 재생 파일을 만듭니다.

사용법:
    python3 slice_for_demo.py --input logs_clean.csv --output demo_logs.csv \
        --before 3000 --total 8000

--before: 공격이 시작되는 첫 BLOCK 행 기준, 그 이전 몇 행부터 포함할지
--total : 잘라낼 전체 행 수 (전이 배경 트래픽, 후반이 공격 트래픽 위주로 섞여 나옴)
"""
import argparse
import csv
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="logs_clean.csv")
    parser.add_argument("--output", default="demo_logs.csv")
    parser.add_argument("--before", type=int, default=3000, help="첫 BLOCK 행 이전 포함할 행 수")
    parser.add_argument("--total", type=int, default=8000, help="잘라낼 전체 행 수")
    args = parser.parse_args()

    with open(args.input, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    first_block_idx = next((i for i, r in enumerate(rows) if r["action"] == "BLOCK"), None)
    if first_block_idx is None:
        print("[오류] BLOCK 행을 찾을 수 없습니다. 입력 파일을 확인하세요.", file=sys.stderr)
        sys.exit(1)

    start = max(0, first_block_idx - args.before)
    end = min(len(rows), start + args.total)
    sliced = rows[start:end]

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["ip", "timestamp", "port", "action"])
        writer.writeheader()
        writer.writerows(sliced)

    block_count = sum(1 for r in sliced if r["action"] == "BLOCK")
    print(
        f"완료: {len(sliced)}행 저장 → {args.output} "
        f"(원본 {start}~{end}번째 행, BLOCK {block_count}행 / ALLOW {len(sliced) - block_count}행)\n"
        f"원본 시작 시각: {sliced[0]['timestamp']}\n"
        f"원본 종료 시각: {sliced[-1]['timestamp']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
