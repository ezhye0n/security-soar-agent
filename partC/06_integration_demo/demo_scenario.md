# 데모용 위협 시나리오 (9:00–10:00)

## 시나리오 개요
공격자 IP `203.0.113.77`가 3분 사이에 SSH(22)/RDP(3389)/Telnet(23)/MySQL(3306) 포트로
20회 연속 접속을 시도하다 방화벽에 모두 차단(BLOCK)됩니다. 시스템이 이를 자동으로 탐지해
HIGH 위협으로 분류하고, 담당자 승인을 거쳐 차단 목록에 등록하는 전체 흐름을 시연합니다.

## 시연 순서 (약 5분)

1. **위협 점수 계산 결과 보여주기** (30초, 파트A 연동)
   - S3에 저장된 최신 JSON 하나를 열어서 공격자 IP의 점수/레벨이 HIGH인 것을 보여줌

2. **Agent에게 직접 물어보기** (1분, 파트B 연동)
   ```bash
   agentcore invoke "최근 위협 상황 확인해줘"
   ```
   Agent가 `checkIPReputation`을 호출해 IP 이력을 조사하고 위협 여부를 판단하는 응답을 보여줌.

3. **Step Functions 실행 → 승인 요청 알림** (1분, 파트C)
   ```bash
   aws stepfunctions start-execution \
     --state-machine-arn arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STATE_MACHINE_NAME \
     --input '{"testIp":"203.0.113.77","testScore":92}' \
     --region "$AWS_REGION"
   ```
   콘솔의 Step Functions 그래프 뷰를 띄워 "AI가 판단했지만 사람 승인을 기다린다"는 지점을 강조.
   SNS 이메일도 함께 화면에 띄우기.

4. **담당자 승인 → 실제(모의) 차단 실행** (1분)
   ```bash
   bash 04_approval_processor/list_pending_approvals.sh
   bash 04_approval_processor/approve_cli.sh <requestId> approve
   aws dynamodb get-item --table-name $DDB_BLOCKLIST_TABLE --key '{"ip":{"S":"203.0.113.77"}}'
   ```
   "실제 방화벽/보안그룹은 건드리지 않고, 모의 차단 목록(DynamoDB)에 기록만 합니다"라고 명확히 설명.

5. **완료 알림 + 전체 이력 확인** (30초)
   - 완료 SNS 메일 캡처
   - Step Functions 콘솔의 실행 그래프(초록색 경로)로 전체 흐름을 한 번에 보여줌

## 백업 계획 (라이브 데모 실패 대비)
- 위 1~5단계를 사전에 한 번 실행해 스크린샷/터미널 로그를 저장해두고, 라이브가 막히면 캡처로 대체
- Step Functions 콘솔의 "Executions" 탭에서 과거 성공 실행의 그래프 뷰를 미리 열어두기
- SNS 이메일은 사전에 미리 한 번 받아서 스크린샷 확보
- 파트B의 Agent/Gateway가 데모 직전 불안정하면, `05_call_agent_lambda`의 스텁으로 즉시 폴백 가능
  (`CallAgentLambdaArn`을 스텁 ARN으로 되돌리고 재배포하면 5분 내 복구)

## REJECT / LOW 케이스도 짧게 언급
- `approve_cli.sh <requestId> reject` 로 거부 시나리오도 있다는 것만 말로 설명 (시간 되면 시연)
- 위협도가 LOW/MEDIUM이면 `NoActionNeeded`로 조용히 끝난다는 것도 그래프로 보여주면 좋음
