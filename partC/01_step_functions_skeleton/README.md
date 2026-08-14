# 01. Step Functions 골격 (0:00–1:00)

목표: 전체 그래프 모양을 먼저 확정하고, 다른 팀원(A/B) 진행 상황과 무관하게 지금 바로 배포까지
해봅니다. 이 단계는 SNS/SQS/Lambda 등 아무 외부 리소스도 필요 없습니다 (전부 `Pass` 상태).

```bash
cd partC
source ./00_common/set_env.sh
bash 00_common/create_step_functions_role.sh
bash 00_common/deploy_state_machine.sh 01_step_functions_skeleton/state_machine_stage1_skeleton.asl.json
```

## 확인
```bash
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{}' \
  --region "$AWS_REGION"
```
AWS 콘솔 > Step Functions > `$STATE_MACHINE_NAME` 에서 그래프 뷰를 팀원들에게 공유하면서
"이게 우리가 만들 전체 흐름"이라고 먼저 정렬(align)하고 시작하면 좋습니다.

## 이 단계에서 팀원(A/B)과 합의해야 할 것
- `CheckThreatLog`가 받게 될 입력/출력 스키마: `{ "ip", "score", "level", "reason" }` (파트B 협의)
- `BlockIP`가 받을 입력: `{ "ip", "requestId", "reason" }`, 결과 테이블: `DDB_BLOCKLIST_TABLE`
- HIGH 판정 기준(`level == "HIGH"`)이 파트A의 위협 점수 로직과 일치하는지
