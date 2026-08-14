# 01. 로그 데이터 정제 (0:00–1:00)

## 목표
Kaggle 보안 로그 데이터셋을 `ip,timestamp,port,action` 4개 컬럼짜리 단순 CSV로 정제합니다.
(파트A와 공동 작업 후 분리하는 구간이므로, 컬럼 매핑 규칙을 파트A와 먼저 합의하세요.)

## 추천 Kaggle 데이터셋 후보 (택 1)
- CICIDS2017 / CICIDS2018 (Canadian Institute for Cybersecurity)
- UNSW-NB15
- Network Intrusion Detection (다양한 파생 버전 다수 존재)

> 데이터셋마다 컬럼명이 다르므로, 실제 다운로드한 파일의 헤더를 먼저 확인하세요:
> `head -1 raw_kaggle_logs.csv`

## 사용 순서

1. (선택) 실제 Kaggle 데이터가 아직 없다면 합성 샘플로 먼저 파이프라인을 검증합니다.
   ```bash
   python3 generate_sample_logs.py --output logs_sample.csv --rows 300
   ```
   이 샘플은 공격자 IP(`203.0.113.77`, `198.51.100.23`)가 3분 내 20회 BLOCK을 발생시키도록
   설계되어 있어, Consumer Lambda의 "5분 내 동일 IP 실패 N회 이상 → HIGH" 규칙을 바로 테스트할 수
   있습니다.

2. 실제 Kaggle CSV가 준비되면 컬럼명을 맞춰 정제합니다.
   ```bash
   python3 clean_logs.py \
     --input raw_kaggle_logs.csv \
     --output logs_clean.csv \
     --ip-col "Src IP" \
     --time-col "Timestamp" \
     --port-col "Dst Port" \
     --action-col "Label" \
     --action-map "BENIGN=ALLOW,DoS=BLOCK,DDoS=BLOCK,PortScan=BLOCK,Bot=BLOCK"
   ```

3. 결과 확인
   ```bash
   head -5 logs_clean.csv
   wc -l logs_clean.csv
   cut -d, -f4 logs_clean.csv | sort | uniq -c   # ALLOW/BLOCK 비율 확인
   ```

4. 정제된 CSV를 파트A에게 전달 → Producer Lambda가 이 CSV를 한 줄씩 Kinesis로 전송합니다.

## 체크리스트
- [ ] `action` 값이 ALLOW/BLOCK 두 가지로만 정규화되었는지 확인
- [ ] `timestamp`가 ISO8601 UTC(`YYYY-MM-DDTHH:MM:SSZ`)인지 확인
- [ ] `port`가 정수인지 확인 (문자열/결측치 제거됨)
- [ ] 공격 시나리오(짧은 시간 내 동일 IP 반복 BLOCK)가 최소 1개 이상 데이터에 포함되어 있는지 확인
      (없으면 데모가 HIGH를 못 띄울 수 있으니 `generate_sample_logs.py`로 보강하거나 데이터를 섞으세요)
