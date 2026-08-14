# Consumer — Kinesis → 윈도우 위협 판정 → S3

Kinesis Stream(`soar-agent-log-stream-soara`)을 트리거로 받아서, "IP별로 최근 N초 안에
BLOCK이 몇 번 발생했는지"를 진짜 슬라이딩 윈도우로 집계하고 LOW/MEDIUM/HIGH를 판정해
S3에 JSON으로 기록하는 게 이 부분(A2 본업)의 핵심입니다.

## 윈도우 카운터 설계 결정: TTL 기반 (집계 버킷 방식 아님)

DynamoDB에 IP별로 **BLOCK 이벤트 하나하나를 아이템으로 저장**하고(TTL로 자동 정리),
판정 시점마다 `Query(ip=.., sk between [now-5분, now])` 로 정확한 개수를 셉니다.

집계 카운터(분 단위 버킷 합산) 방식 대신 이걸 고른 이유:
- **정확도** — 분 버킷 방식은 "정확히 최근 5분"이 아니라 "최근 N개 버킷 합"이 되어 경계에서
  최대 1개 버킷만큼 오차가 생김. TTL 기반은 Query 한 번으로 진짜 슬라이딩 윈도우.
- **구현 단순함** — 여러 버킷을 순회하며 합산하는 로직이 필요 없음.
- **비용** — BLOCK은 전체 트래픽의 1.5%뿐이라 쓰기 비용이 작고, TTL로 알아서 정리됨.

## 스키마

**DynamoDB** (`soar-agent-ip-state-soara`, PK=`ip`, SK=`sk`)
- `sk = "STATE"` : IP별 누적 이벤트 카운터 (`total_count`) — 윈도우 아님, 참고용 누적치
- `sk = "EVT#<epoch_ms 20자리>#<Kinesis sequenceNumber>"` : BLOCK 이벤트 1건, `expiresAt`(TTL)로
  윈도우+여유시간 지나면 자동 삭제됨

> **주의(실제로 발견하고 고친 버그)**: Producer는 1초 압축 버킷당 timestamp를 한 번만 찍어서
> 그 버킷의 모든 레코드에 동일하게 붙입니다. 같은 IP가 같은 버킷에서 여러 번 BLOCK되면
> timestamp가 완전히 똑같아질 수 있어서, sk에 epoch_ms만 쓰면 나중 것이 이전 것을 덮어써
> 카운트가 누락됩니다. 그래서 Kinesis의 `sequenceNumber`(레코드마다 고유)를 sk 뒤에 붙여
> 충돌을 방지했습니다. `test_duplicate_timestamp_same_bucket_not_overwritten` 테스트로 검증함.

**S3** (`scores/<ip>/<epoch_ms>.json`)
```json
{
  "ip": "147.32.84.165",
  "windowStart": "...", "windowEnd": "...",
  "blockCount": 6, "totalCount": 42,
  "score": 100, "level": "HIGH",
  "reason": "최근 300초 내 BLOCK 6회 (HIGH 기준 5회 이상)"
}
```
BLOCK 이벤트가 들어올 때만 기록됩니다 (ALLOW는 total_count만 누적, S3 기록 없음).

## 판정 기준 (환경변수로 조절 가능)
- `WINDOW_SECONDS` (기본 300) 안에 `HIGH_THRESHOLD`(기본 5) 이상 BLOCK → **HIGH**
- `MEDIUM_THRESHOLD`(기본 2) 이상 → **MEDIUM**
- 그 미만 → **LOW**
- `score = min(100, round(blockCount / HIGH_THRESHOLD * 100))`

## 로컬 검증 (AWS 없이, moto로 실제 DynamoDB/S3 동작 그대로 재현)
```bash
python3 -m pip install boto3 "moto[dynamodb,s3]" --break-system-packages
python3 test_consumer_lambda.py
```
5개 테스트 모두 통과 확인됨:
1. ALLOW만 있을 때 DynamoDB EVT/S3 기록 없음, 누적치만 증가
2. 실제 감염 IP(`147.32.84.165`)로 BLOCK 6연속(60초 간격) → 5번째부터 HIGH, S3에 6건 기록
3. 10분 전 오래된 BLOCK은 TTL로 아직 안 지워졌어도 윈도우 Query에서 정확히 제외됨
4. TTL(`expiresAt`) 값이 `이벤트시각 + WINDOW_SECONDS + 60초 여유` 로 정확히 계산됨
5. (버그 회귀 테스트) 같은 버킷 안 동일 timestamp 5건이 sk 충돌 없이 전부 저장되고 HIGH 판정됨

## 배포
```bash
export AWS_REGION=ap-northeast-2
export KINESIS_STREAM_NAME=soar-agent-log-stream-soara
export DDB_TABLE_NAME=soar-agent-ip-state-soara
export S3_BUCKET_NAME=soar-agent-threat-scores-soara-<계정ID>   # 버킷명은 전역 유일해야 함
bash deploy_consumer.sh
```
DynamoDB 테이블(TTL 포함) + S3 버킷 + IAM 역할 + Lambda + **Kinesis Event Source Mapping**까지
한 번에 만들어줍니다 (`starting-position LATEST` — 매핑 생성 "이후"에 들어오는 데이터부터 처리).

## 동작 확인
```bash
aws logs tail /aws/lambda/soar-agent-consumer-soara --follow --region ap-northeast-2
aws s3 ls s3://$S3_BUCKET_NAME/scores/147.32.84.165/ --recursive | tail -5
aws s3 cp s3://$S3_BUCKET_NAME/scores/147.32.84.165/<최신-epoch_ms>.json - | python3 -m json.tool
```
CTU-13 정답 라벨상 `147.32.84.165`가 유일한 감염 호스트이므로, 이 IP가 HIGH로 뜨고 다른
정상 IP들은 LOW/MEDIUM에 머무는지 확인하면 됩니다.

## A1에게 전달할 내용 (인프라 스펙 확정됨)
- DynamoDB 테이블명 `soar-agent-ip-state-soara`, PK=`ip`(S), SK=`sk`(S), TTL 속성=`expiresAt`,
  빌링모드 PAY_PER_REQUEST — `deploy_consumer.sh`가 자동 생성하니 A1이 따로 만들 필요는 없고,
  이미 다른 이유로 먼저 만들어뒀다면 스키마만 위와 동일한지 확인 부탁.
- S3 버킷명은 계정ID를 붙여서 유일하게 만들어야 함 (예: `soar-agent-threat-scores-soara-054422645032`).
- Kinesis Event Source Mapping의 `starting-position`을 `LATEST`로 설정했으므로, Consumer 배포는
  Producer 실행 **전에** 먼저 끝내두는 게 좋음 (그래야 Producer가 쏘는 데이터를 놓치지 않음).
