#!/usr/bin/env bash
# 차단 목록 테이블 생성 (공유 인프라 - 파트B의 blockIP Lambda가 이 테이블에 씁니다).
# 팀에서 누가 먼저 이 단계에 도달하든 실행해도 됩니다 (idempotent: 이미 있으면 에러 무시).
set -euo pipefail
: "${DDB_BLOCKLIST_TABLE:?먼저 00_common/set_env.sh 를 source 하세요}"

if aws dynamodb describe-table --table-name "$DDB_BLOCKLIST_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "이미 존재함: $DDB_BLOCKLIST_TABLE (건너뜀)"
  exit 0
fi

echo "차단 목록 테이블 생성: $DDB_BLOCKLIST_TABLE (PK: ip)"
aws dynamodb create-table \
  --table-name "$DDB_BLOCKLIST_TABLE" \
  --attribute-definitions AttributeName=ip,AttributeType=S \
  --key-schema AttributeName=ip,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

aws dynamodb wait table-exists --table-name "$DDB_BLOCKLIST_TABLE" --region "$AWS_REGION"
echo "완료."
