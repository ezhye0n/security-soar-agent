#!/usr/bin/env bash
# 차단 목록 테이블 + 승인 대기 테이블 생성 (1:30–2:30 구간)
# - blocklist 테이블: 파트A의 blockIP Lambda가 씁니다 (모의 차단 기록)
# - pending-approvals 테이블: ApprovalProcessor Lambda가 taskToken을 저장, approve_cli.sh가 조회
set -euo pipefail
: "${DDB_BLOCKLIST_TABLE:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/2] 차단 목록 테이블 생성: $DDB_BLOCKLIST_TABLE (PK: ip)"
aws dynamodb create-table \
  --table-name "$DDB_BLOCKLIST_TABLE" \
  --attribute-definitions AttributeName=ip,AttributeType=S \
  --key-schema AttributeName=ip,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

echo "[2/2] 승인 대기 테이블 생성: $DDB_PENDING_APPROVALS_TABLE (PK: requestId)"
aws dynamodb create-table \
  --table-name "$DDB_PENDING_APPROVALS_TABLE" \
  --attribute-definitions AttributeName=requestId,AttributeType=S \
  --key-schema AttributeName=requestId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

echo "테이블 ACTIVE 대기 중..."
aws dynamodb wait table-exists --table-name "$DDB_BLOCKLIST_TABLE" --region "$AWS_REGION"
aws dynamodb wait table-exists --table-name "$DDB_PENDING_APPROVALS_TABLE" --region "$AWS_REGION"

echo "완료."
