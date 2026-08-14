#!/usr/bin/env bash
# 승인 대기 테이블 생성 (3:00–5:00)
# ApprovalProcessor Lambda가 SQS로 들어온 taskToken을 여기에 저장하고,
# approve_cli.sh가 requestId로 조회해서 승인/거부를 처리합니다.
set -euo pipefail
: "${DDB_PENDING_APPROVALS_TABLE:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "승인 대기 테이블 생성: $DDB_PENDING_APPROVALS_TABLE (PK: requestId)"
aws dynamodb create-table \
  --table-name "$DDB_PENDING_APPROVALS_TABLE" \
  --attribute-definitions AttributeName=requestId,AttributeType=S \
  --key-schema AttributeName=requestId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

aws dynamodb wait table-exists --table-name "$DDB_PENDING_APPROVALS_TABLE" --region "$AWS_REGION"
echo "완료."
