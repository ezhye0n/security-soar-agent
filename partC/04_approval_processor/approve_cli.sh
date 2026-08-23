#!/usr/bin/env bash
# 운영자(담당자)가 승인/거부를 실행하는 CLI. 웹 대시보드 대신 사용 (스코프 컷 항목).
# 데모에서도 이 스크립트로 "사람이 승인" 하는 장면을 보여주면 됩니다.
#
# 사용법: ./approve_cli.sh <requestId> approve|reject
# requestId는 SNS로 온 알림 메일 본문에 적혀 있거나, list_pending_approvals.sh 로 조회 가능합니다.
set -euo pipefail
: "${DDB_PENDING_APPROVALS_TABLE:?먼저 00_common/set_env.sh 를 source 하세요}"

REQUEST_ID="${1:?사용법: approve_cli.sh <requestId> approve|reject}"
DECISION_RAW="${2:?사용법: approve_cli.sh <requestId> approve|reject}"

ITEM_JSON=$(aws dynamodb get-item \
  --table-name "$DDB_PENDING_APPROVALS_TABLE" \
  --key "{\"requestId\": {\"S\": \"$REQUEST_ID\"}}" \
  --region "$AWS_REGION")

TASK_TOKEN=$(echo "$ITEM_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
item = d.get("Item")
if not item:
    sys.exit(1)
print(item["taskToken"]["S"])
' ) || {
  echo "[오류] requestId=$REQUEST_ID 에 대한 승인 대기 항목을 찾을 수 없습니다."
  echo "       ApprovalProcessor Lambda가 아직 SQS 메시지를 처리하지 않았을 수 있습니다. 잠시 후 다시 시도하세요."
  exit 1
}

case "$DECISION_RAW" in
  approve) DECISION="APPROVE"; NEW_STATUS="APPROVED" ;;
  reject)  DECISION="REJECT";  NEW_STATUS="REJECTED" ;;
  *) echo "두번째 인자는 approve 또는 reject 여야 합니다."; exit 1 ;;
esac

aws stepfunctions send-task-success \
  --task-token "$TASK_TOKEN" \
  --task-output "{\"decision\":\"$DECISION\"}" \
  --region "$AWS_REGION"

aws dynamodb update-item \
  --table-name "$DDB_PENDING_APPROVALS_TABLE" \
  --key "{\"requestId\": {\"S\": \"$REQUEST_ID\"}}" \
  --update-expression "SET #s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values "{\":s\": {\"S\": \"$NEW_STATUS\"}}" \
  --region "$AWS_REGION"

echo "requestId=$REQUEST_ID → $NEW_STATUS 처리 완료 (Step Functions 실행이 재개됩니다)"
