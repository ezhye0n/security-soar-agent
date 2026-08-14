#!/usr/bin/env python3
"""
Kaggle 데이터 정제가 끝나기 전에 파이프라인(Kinesis→Consumer→S3→Agent→Step Functions)을
먼저 테스트할 수 있도록 합성 샘플 로그 CSV를 생성합니다.

의도적으로 다음을 섞어 만듭니다:
  - 정상 IP 다수 (ALLOW 위주, 가끔 BLOCK)
  - "공격자" IP 1~2개: 5분 이내에 동일 IP로 BLOCK이 다수 발생 → Consumer Lambda 규칙에서
    HIGH 위협 점수가 나오도록 설계 (예: 5분 내 실패시도 N회 이상 → HIGH)

사용법:
    python3 generate_sample_logs.py --output logs_sample.csv --rows 300
"""
import argparse
import csv
import random
from datetime import datetime, timedelta, timezone

BENIGN_IPS = [f"10.0.{i}.{j}" for i in range(1, 4) for j in (10, 20, 30, 40)]
ATTACKER_IPS = ["203.0.113.77", "198.51.100.23"]
COMMON_PORTS = [80, 443, 22, 3389, 3306, 8080, 23]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="logs_sample.csv")
    parser.add_argument("--rows", type=int, default=300)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)
    start = datetime.now(timezone.utc) - timedelta(hours=1)

    rows = []

    # 1) 정상 트래픽
    for i in range(args.rows - 40):
        ip = random.choice(BENIGN_IPS)
        ts = start + timedelta(seconds=random.randint(0, 3600))
        port = random.choice(COMMON_PORTS)
        action = "ALLOW" if random.random() < 0.9 else "BLOCK"
        rows.append((ip, ts, port, action))

    # 2) 공격 패턴: 공격자 IP가 짧은 시간(3분) 내에 여러 포트로 반복 BLOCK 시도
    burst_start = start + timedelta(minutes=45)
    for attacker in ATTACKER_IPS:
        for i in range(20):
            ts = burst_start + timedelta(seconds=random.randint(0, 180))
            port = random.choice([22, 3389, 23, 3306])
            rows.append((attacker, ts, port, "BLOCK"))

    rows.sort(key=lambda r: r[1])

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["ip", "timestamp", "port", "action"])
        for ip, ts, port, action in rows:
            writer.writerow([ip, ts.strftime("%Y-%m-%dT%H:%M:%SZ"), port, action])

    print(f"샘플 로그 {len(rows)}행 생성 → {args.output}")
    print(f"공격자 IP(데모용): {', '.join(ATTACKER_IPS)}")


if __name__ == "__main__":
    main()
