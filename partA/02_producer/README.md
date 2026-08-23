# Producer — Kinesis 실시간 스트리밍 "API"

로그 CSV를 Kinesis Stream에 실시간처럼 흘려보내는 Producer입니다. 요청하신 "API"는
Lambda Function URL로 구현했습니다 — curl 한 번으로 트리거하면 그 순간부터 Kinesis에
데이터가 스트리밍되기 시작합니다.

## 왜 전체 282만 행을 그대로 안 쏘나요?

세 가지 이유로 안 됩니다.

1. Kinesis 샤드 1개는 초당 1,000건/1MB가 한도라, 282만 건을 몇 분 안에 다 밀어넣을 수 없어요.
2. Lambda는 최대 15분까지만 실행돼요. 원본 캡처(6.15시간)를 그대로 압축해도 데이터 양이 너무 많아요.
3. 데모에서 282만 건 다 보여줄 필요도 없어요 — 공격 버스트 앞뒤로 자연스러운 배경 트래픽만
   있으면 스토리는 충분합니다.

그래서 **먼저 데모용 구간만 잘라내고(`slice_for_demo.py`), 그 구간의 시간 흐름을 압축해서
재생(`producer_lambda.py`)**하는 2단계 구조로 만들었습니다.

## 사용 순서

### 1) 데모용 슬라이스 만들기 (한 번만, CloudShell에서)
```bash
python3 slice_for_demo.py --input ~/logs_clean.csv --output ./demo_logs.csv \
  --before 3000 --total 8000
```
공격이 시작되는 첫 BLOCK 행 기준으로 앞 3000행(배경 트래픽) + 이후 트래픽을 합쳐 총 8000행을
뽑습니다. 데모를 더 짧게/길게 하고 싶으면 `--total` 값을 조절하세요.

### 2) Kinesis Stream이 아직 없다면 먼저 생성
```bash
aws kinesis create-stream --stream-name soar-agent-log-stream-soara --shard-count 1 --region ap-northeast-2
aws kinesis wait stream-exists --stream-name soar-agent-log-stream-soara --region ap-northeast-2
```

### 3) Producer 배포
```bash
export AWS_REGION=ap-northeast-2
export KINESIS_STREAM_NAME=soar-agent-log-stream-soara
bash deploy_producer.sh
```
끝나면 `FUNCTION_URL`이 출력됩니다. 이게 요청하신 "실시간으로 쏴주는 API"예요.

### 4) 실행 (재생 시작)
```bash
# 60초 동안 압축 재생 (동기 호출, 응답 올 때까지 curl이 대기함)
curl -X POST "https://xxxxxxxx.lambda-url.ap-northeast-2.on.aws/" \
  -d '{"targetDurationSeconds": 60}'
```
또는 비동기로 백그라운드 실행 후 로그로 실시간 진행상황 보기:
```bash
aws lambda invoke --function-name soar-agent-producer-soara \
  --invocation-type Event \
  --payload '{"targetDurationSeconds": 180}' \
  --cli-binary-format raw-in-base64-out out.json

aws logs tail /aws/lambda/soar-agent-producer-soara --follow --region ap-northeast-2
```
로그에 `[Producer] t=12s: 45건 전송 (누적 320건, 그 중 BLOCK 8건)` 같은 진행상황이
실시간으로 찍힙니다 — 데모에서 이 로그 화면을 띄워두면 "실시간 스트리밍"이 눈에 보여서 좋아요.

## 동작 방식 요약
- `demo_logs.csv`의 원본 타임스탬프 **간격 비율은 유지**한 채(공격 버스트가 몰려있는 패턴이
  그대로 보존됨), 전체 재생 시간을 `targetDurationSeconds`로 압축합니다.
- Kinesis로 보낼 때 `timestamp` 필드는 원본(2011년) 값이 아니라 **실제로 보낸 지금 시각**으로
  다시 씁니다 — Consumer Lambda의 "5분 이내" 판단이나 Agent의 "최근 상황" 질의가 자연스럽게
  맞아떨어지게 하기 위한 것입니다 (파트B에 전달한 설계와 일치).
- 레코드는 1초 단위로 묶어서 `PutRecords`로 배치 전송하고, `PartitionKey`는 `ip`로 설정해서
  같은 IP는 같은 샤드로 가게 했습니다 (Consumer 쪽 윈도우 집계에 유리).
- Lambda 잔여 실행시간이 5초 이하로 남으면 안전하게 조기 종료하고, 어디까지 보냈는지 로그로
  남깁니다 (묵묵히 잘리지 않도록).

## 로컬에서 로직만 미리 검증하고 싶다면
`producer_lambda.py`는 `boto3.client("kinesis")`만 모킹하면 AWS 없이도 타이밍/배치 로직을
그대로 테스트할 수 있게 짜여 있습니다 (실제로 이 방식으로 사전 검증 완료했습니다 — 합성
데이터로 3초 압축 재생 시 1200건 전량 정확히 전송, BLOCK 300건 100% 포함 확인됨).
