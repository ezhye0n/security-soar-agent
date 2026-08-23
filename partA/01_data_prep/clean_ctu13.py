#!/usr/bin/env python3
"""
CTU-13 (capture20110810.binetflow, Botnet-42/Neris) 전용 정제 스크립트.
원본 컬럼: StartTime,Dur,Proto,SrcAddr,Sport,Dir,DstAddr,Dport,State,sTos,dTos,TotPkts,TotBytes,SrcBytes,Label

표준 스키마로 변환:
    ip          - SrcAddr
    timestamp   - StartTime (ISO8601 UTC로 변환)
    port        - Dport
    action      - Label이 --block-label-prefix로 시작하면 BLOCK, 아니면 ALLOW
                  (기본값 "flow=From-Botnet" — README 기준 진짜 악성 트래픽만 잡음.
                   "flow=To-Botnet"은 봇넷으로 들어온 외부 트래픽이라 악성이 아닐 수 있어서 제외)

사용법:
    python3 clean_ctu13.py --input capture20110810.binetflow --output logs_clean.csv

    # 먼저 소량으로 테스트
    python3 clean_ctu13.py --input capture20110810.binetflow --output logs_sample.csv --limit 5000
"""
import argparse
import csv
import sys
from datetime import datetime, timezone


def normalize_timestamp(raw: str) -> str:
    """CTU-13 StartTime 포맷(YYYY/MM/DD HH:MM:SS.ffffff)을 ISO8601 UTC로 변환."""
    raw = raw.strip()
    candidate_formats = [
        "%Y/%m/%d %H:%M:%S.%f",   # CTU-13 실제 포맷 (확인됨)
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S.%f",
        "%Y-%m-%d %H:%M:%S",
    ]
    for fmt in candidate_formats:
        try:
            dt = datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
            return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        except ValueError:
            continue
    return raw  # 파싱 실패 시 원본 유지 (나중에 확인 가능하도록)


def normalize_port(raw: str):
    """Dport가 10진수(확인됨)라고 가정하되, 혹시 모를 16진수(0x..)도 방어적으로 처리."""
    raw = raw.strip()
    try:
        if raw.lower().startswith("0x"):
            return int(raw, 16)
        return int(float(raw))
    except ValueError:
        return None


def main():
    parser = argparse.ArgumentParser(description="CTU-13 binetflow 정제 스크립트")
    parser.add_argument("--input", required=True, help="원본 capture20110810.binetflow 경로")
    parser.add_argument("--output", required=True, help="정제된 CSV 출력 경로")
    parser.add_argument(
        "--block-label-prefix",
        default="flow=From-Botnet",
        help="이 문자열로 시작하는 Label만 BLOCK으로 판정 (기본: flow=From-Botnet)",
    )
    parser.add_argument("--limit", type=int, default=0, help="최대 행 수 (0=전체, 테스트 시 작은 값 권장)")
    args = parser.parse_args()

    written = 0
    blocked = 0
    skipped = 0

    with open(args.input, newline="", encoding="utf-8", errors="replace") as f_in, \
         open(args.output, "w", newline="", encoding="utf-8") as f_out:
        reader = csv.DictReader(f_in)
        writer = csv.writer(f_out)
        writer.writerow(["ip", "timestamp", "port", "action"])

        # 원본 컬럼명이 정확히 이 이름들인지 확인
        required_cols = {"StartTime", "SrcAddr", "Dport", "Label"}
        missing = required_cols - set(reader.fieldnames or [])
        if missing:
            print(f"[오류] 원본 파일에 필요한 컬럼이 없습니다: {missing}", file=sys.stderr)
            print(f"       실제 헤더: {reader.fieldnames}", file=sys.stderr)
            sys.exit(1)

        for row in reader:
            try:
                ip = row["SrcAddr"].strip()
                ts = normalize_timestamp(row["StartTime"])
                port = normalize_port(row["Dport"])
                label = row["Label"].strip()

                if not ip or port is None:
                    skipped += 1
                    continue

                action = "BLOCK" if label.startswith(args.block_label_prefix) else "ALLOW"
                if action == "BLOCK":
                    blocked += 1

                writer.writerow([ip, ts, port, action])
                written += 1
            except (KeyError, ValueError):
                skipped += 1
                continue

            if args.limit and written >= args.limit:
                break

    print(
        f"완료: {written}행 저장 → {args.output} "
        f"(BLOCK {blocked}행 / ALLOW {written - blocked}행, 스킵 {skipped}행)",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
