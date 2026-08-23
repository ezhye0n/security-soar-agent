#!/usr/bin/env bash
# 오케스트레이션 레이어만 빠르게 end-to-end 확인하는 스모크 테스트.
# 파트A/B 없이도(스텁만으로) HIGH 시나리오 전체가 도는지 확인합니다.
set -euo pipefail
: "${STATE_MACHINE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/4] Step Functions 실행 (HIGH 강제)"
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{"testIp":"203.0.113.77","testScore":92}' \
  --region "$AWS_REGION" --query 'executionArn' --output text)
echo "  ExecutionArn=$EXEC_ARN"

echo "[2/4] 10초 후 승인 대기 목록 확인"
sleep 10
bash ../04_approval_processor/list_pending_approvals.sh

echo "[3/4] 아래 명령으로 승인하세요 (requestId는 위 목록에서 확인)"
echo "  bash ../04_approval_processor/approve_cli.sh <requestId> approve"
echo ""
read -rp "승인을 완료했으면 Enter를 눌러 계속 진행하세요..." _

echo "[4/4] 실행 상태 확인 (SUCCEEDED 여야 정상)"
aws stepfunctions describe-execution --execution-arn "$EXEC_ARN" --region "$AWS_REGION" \
  --query '{status:status,output:output}' --output json

echo ""
echo "차단 목록(DynamoDB) 확인:"
aws dynamodb get-item --table-name "$DDB_BLOCKLIST_TABLE" \
  --key '{"ip":{"S":"203.0.113.77"}}' --region "$AWS_REGION" || echo "  (아직 blockIP 실제/스텁 Lambda가 연결 안 됐으면 없을 수 있음)"
