# 파트B (인프라/오케스트레이션) 실습 키트

Security SOAR Agent 프로젝트의 파트B 담당 산출물입니다. 10시간 일정표 순서대로 폴더가 나뉘어 있고,
각 폴더 안의 스크립트를 위에서 아래로 실행하면 됩니다. **모든 스크립트는 실습용 CLI 스크립트이며,
실제 실행은 여러분의 AWS 계정에서 직접 하셔야 합니다.** (이 세션에는 AWS 자격증명이 없습니다.)

## 0. 사전 준비

```bash
aws --version          # AWS CLI v2 권장
aws configure           # Access Key / Secret / 기본 리전 설정
aws sts get-caller-identity   # 자격증명 확인
```

- **리전**: Amazon Bedrock AgentCore는 아직 모든 리전에서 제공되지 않습니다. 이 키트는 기본값을
  `us-west-2`로 두었습니다. 다른 리전을 쓰려면 `00_common/set_env.sh`의 `AWS_REGION`을 바꾸세요.
- **IAM 권한**: 실습 계정에 Kinesis, S3, SNS, SQS, DynamoDB, Cognito, Lambda, Step Functions, IAM
  역할 생성 권한이 있어야 합니다.
- 모든 후속 스크립트는 먼저 아래처럼 공통 환경변수를 로드한다고 가정합니다.

```bash
cd partB
source ./00_common/set_env.sh
```

## 1. 폴더 맵 (10시간 일정표 기준)

| 시간대 | 폴더 | 내용 |
|---|---|---|
| 0:00–1:00 | `01_data_prep/` | Kaggle 로그 → IP/시각/포트/허용or차단 CSV 정제, 샘플 데이터 생성 |
| 1:00–1:30 | `02_kinesis/` | Kinesis Data Stream 생성, Producer/Consumer Lambda IAM 역할 |
| 1:30–2:30 | `03_storage_notify/` | S3 버킷, SNS 토픽 2개, SQS 승인 큐, DynamoDB 테이블 2개 |
| 2:30–4:00 | `04_cognito/` | Cognito User Pool/Domain/Client (Gateway OAuth용), Gateway 서비스 역할 |
| 4:00–5:30 | `05_agent_support/` | agentcore 환경변수, requirements.txt, configure/deploy 가이드 |
| 5:30–7:30 | `06_step_functions/` | 상태머신 정의(ASL), Choice 분기, Human-in-the-Loop, ApprovalProcessor Lambda |
| 7:30–9:00 | `07_testing/` | 통합 테스트 체크리스트, 스모크 테스트 스크립트 |
| 9:00–10:00 | `08_demo/` | 데모 시나리오, 발표 스크립트 |

## 2. 파트A와 연결되는 지점 (인터페이스)

파트B가 만든 인프라를 파트A 산출물과 연결하려면 아래 값들을 주고받아야 합니다.

| 값 | 만드는 쪽 | 쓰는 쪽 |
|---|---|---|
| `KINESIS_STREAM_NAME` (ARN) | 파트B (`02_kinesis`) | 파트A Producer/Consumer Lambda |
| `S3_BUCKET_NAME` | 파트B (`03_storage_notify`) | 파트A Consumer Lambda (위협점수 저장) |
| `DDB_BLOCKLIST_TABLE` | 파트B (`03_storage_notify`) | 파트A `blockIP` Lambda |
| Cognito `CLIENT_ID`/`CLIENT_SECRET`/토큰 엔드포인트 | 파트B (`04_cognito`) | 파트A Agent (`agent.py`, Gateway 인증) |
| Gateway URL / Target ARN | 파트A (`AgentCore Gateway`) | 파트B Step Functions가 호출하는 "Agent 호출 Lambda" |
| `CALL_AGENT_LAMBDA_ARN` | 파트A (Step Functions에서 Agent 호출하는 Lambda) | 파트B `06_step_functions/state_machine.asl.json` |
| `BLOCK_IP_LAMBDA_ARN` | 파트A (`blockIP` Lambda) | 파트B `06_step_functions/state_machine.asl.json` |

파트A 쪽 Lambda가 아직 준비되지 않았어도 `06_step_functions/`에 **목업(stub) Lambda 2개**를 넣어뒀으니,
그걸로 먼저 Step Functions 흐름 전체를 테스트하고 나중에 실제 ARN으로 교체하면 됩니다.

## 3. 진행 순서 요약

1. `01_data_prep` → CSV 정제 + 샘플 데이터
2. `02_kinesis` → 스트림/IAM
3. `03_storage_notify` → S3/SNS/SQS/DynamoDB
4. `04_cognito` → Cognito (파트A와 협업 필요)
5. `05_agent_support` → 파트A 배포 지원 파일
6. `06_step_functions` → 상태머신 + HITL Lambda (스텁으로 먼저 테스트 가능)
7. `07_testing` → 통합 테스트
8. `08_demo` → 데모/발표 준비
