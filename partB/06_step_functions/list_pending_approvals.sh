#!/usr/bin/env bash
# 현재 승인 대기 중인(또는 처리된) 요청 목록을 보여줍니다. (CLI 결과 확인 화면 대용)
set -euo pipefail
: "${DDB_PENDING_APPROVALS_TABLE:?먼저 00_common/set_env.sh 를 source 하세요}"

aws dynamodb scan \
  --table-name "$DDB_PENDING_APPROVALS_TABLE" \
  --region "$AWS_REGION" \
  --query 'Items[].{requestId:requestId.S,ip:ip.S,score:score.N,status:status.S,receivedAt:receivedAt.N}' \
  --output table
