# 파트C (오케스트레이션 & 데모) 실습 키트 — 팀 soara

Security SOAR Agent 프로젝트(3인 구성)의 파트C 담당 산출물입니다. 10시간 일정표 순서대로
폴더가 나뉘어 있고, 각 폴더의 스크립트를 위에서 아래로 실행하면 됩니다. **모든 스크립트는
실습용 CLI 스크립트이며, 실제 실행은 여러분의 AWS 계정에서 직접 하셔야 합니다.**

## 0. 사전 준비

```bash
aws --version
aws configure
aws sts get-caller-identity
```

```bash
cd partC
source ./00_common/set_env.sh
```

- 팀 식별자 `soara`가 모든 리소스 이름 뒤에 자동으로 붙습니다 (`00_common/set_env.sh`의
  `TEAM_SUFFIX`). 다른 팀과 리소스 이름이 겹치지 않습니다.
- 리전은 기본 `us-west-2`. 파트A/B와 반드시 같은 리전을 쓰세요 (Bedrock AgentCore 가용 리전
  확인 필요).

## 1. 핵심 전략: "Pass 상태로 골격 → 단계적으로 실제 로직 교체"

이 키트의 특징은 **의존성 없이 0:00부터 바로 시작**할 수 있다는 점입니다. Step Functions
상태머신을 처음엔 전부 `Pass`(가짜 통과) 상태로 만들어 배포하고, SNS/SQS/Lambda가 하나씩
준비될 때마다 해당 상태만 실제 로직으로 교체합니다. 그래서 파트A/B가 아직 끝나지 않아도
파트C는 계속 앞으로 나아갈 수 있습니다.

| 단계 | ASL 파일 | 상태 |
|---|---|---|
| Stage 1 (0:00–1:00) | `01_step_functions_skeleton/state_machine_stage1_skeleton.asl.json` | 전부 Pass |
| Stage 2 (1:00–3:00) | `02_sns_sqs/state_machine_stage2_choice.asl.json` | SNS 실연동, 나머지 Pass |
| Stage 3 (3:00–5:00) | `04_approval_processor/state_machine_stage3_hitl.asl.json` | SQS HITL 실연동 |
| Stage 4 (5:00–6:30, 최종) | `05_call_agent_lambda/state_machine_stage4_full.asl.json` | 전부 실연동 + 에러 처리 |

배포는 항상 같은 명령으로:
```bash
bash 00_common/deploy_state_machine.sh <위 표의 ASL 파일 경로>
```

## 2. 폴더 맵 (10시간 일정표 기준)

| 시간대 | 폴더 | 내용 |
|---|---|---|
| 0:00–1:00 | `01_step_functions_skeleton/` | 상태머신 골격 설계 + 최초 배포 |
| 0:00–1:00 (병행) | `02_sns_sqs/` | SNS 토픽 2개, SQS 승인 큐 생성 |
| 1:00–3:00 | `02_sns_sqs/` | Choice 분기 완성 + 실제 SNS 연동 |
| 3:00–5:00 | `04_approval_processor/` | ApprovalProcessor Lambda + SQS 트리거, 실제 HITL 연동 |
| 5:00–6:30 | `05_call_agent_lambda/` | Agent 호출 Lambda(HTTPS+Bearer Token), 최종 통합 상태머신 |
| 6:30–9:00 | `06_integration_demo/` | 통합 테스트, 스모크 테스트, 버그 수정 |
| 9:00–10:00 | `06_integration_demo/` | 데모 시나리오, 발표 스크립트 |

## 3. 파트A/B와 연결되는 지점 (인터페이스)

| 값 | 만드는 쪽 | 쓰는 쪽 |
|---|---|---|
| Kinesis 스트림, S3 버킷 | 파트A | 참조만(데모용), `00_common/set_env.sh`에 이름 규칙 반영됨 |
| Cognito `CLIENT_ID`/`CLIENT_SECRET`/토큰 엔드포인트/`AGENT_RUNTIME_URL` | 파트B | 파트C `05_call_agent_lambda/call_agent_lambda.py` |
| `checkIPReputation`/`blockIP` Lambda (Gateway Target) | 파트B | 파트C Step Functions `BlockIP` 상태 (`BlockIpLambdaArn`) |
| Agent 응답 스키마 | 파트B 구현에 따라 결정 | 파트C `call_agent_lambda.py`의 `parse_agent_response()`에서 흡수 |
| `DDB_BLOCKLIST_TABLE` | 공유 인프라 (누구든 먼저 생성, `05_call_agent_lambda/create_blocklist_table.sh`) | 파트B blockIP Lambda가 씀 |

파트A/B가 아직 준비되지 않았어도 **`05_call_agent_lambda/`의 스텁 2개**로 전체 흐름을
끝까지 테스트할 수 있습니다. 실제 함수가 준비되면 ARN만 바꿔서 재배포하면 됩니다.

## 4. 진행 순서 요약

1. `01_step_functions_skeleton` → 골격 배포 (즉시 가능)
2. `02_sns_sqs` → 리소스 생성 + Choice 분기 실연동
3. `04_approval_processor` → HITL 실연동
4. `05_call_agent_lambda` → 스텁으로 먼저 전체 완성 → 파트B 준비되면 실제로 교체
5. `06_integration_demo` → 통합 테스트, 데모/발표 준비
