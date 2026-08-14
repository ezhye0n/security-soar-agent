#!/usr/bin/env bash
# 범용 Step Functions 배포 스크립트. 어느 단계의 ASL 파일이든 이 스크립트로 배포/갱신합니다.
#
# 사용법:
#   bash 00_common/deploy_state_machine.sh <ASL 파일 경로>
#
# 예)
#   bash 00_common/deploy_state_machine.sh 01_step_functions_skeleton/state_machine_stage1_skeleton.asl.json
#   bash 00_common/deploy_state_machine.sh 02_sns_sqs/state_machine_stage2_choice.asl.json
#   bash 00_common/deploy_state_machine.sh 04_approval_processor/state_machine_stage3_hitl.asl.json
#   bash 00_common/deploy_state_machine.sh 05_call_agent_lambda/state_machine_stage4_full.asl.json
set -euo pipefail
: "${STATE_MACHINE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

ASL_FILE="${1:?사용법: deploy_state_machine.sh <ASL 파일 경로>}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/3] 템플릿 렌더링: $ASL_FILE"
python3 "$DIR/render_template.py" "$ASL_FILE" > /tmp/state_machine.rendered.json
python3 -m json.tool /tmp/state_machine.rendered.json > /dev/null && echo "  JSON 유효성 OK"

echo "[2/3] 실행 역할 ARN 조회"
ROLE_ARN=$(aws iam get-role --role-name "$STEP_FUNCTIONS_ROLE_NAME" --query 'Role.Arn' --output text)
echo "  ROLE_ARN=$ROLE_ARN"

STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"

echo "[3/3] 상태머신 생성/업데이트: $STATE_MACHINE_NAME"
if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws stepfunctions update-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --definition file:///tmp/state_machine.rendered.json \
    --role-arn "$ROLE_ARN" \
    --region "$AWS_REGION" >/dev/null
  echo "  업데이트 완료"
else
  aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --definition file:///tmp/state_machine.rendered.json \
    --role-arn "$ROLE_ARN" \
    --type STANDARD \
    --region "$AWS_REGION" >/dev/null
  echo "  신규 생성 완료"
fi

echo ""
echo "STATE_MACHINE_ARN=$STATE_MACHINE_ARN"
echo "콘솔에서 그래프 뷰 확인: AWS Console > Step Functions > $STATE_MACHINE_NAME"
