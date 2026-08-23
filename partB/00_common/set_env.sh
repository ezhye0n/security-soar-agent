#!/usr/bin/env bash
# 파트B 공통 환경 변수. 가장 먼저 이 파일을 source 하세요.
#   cd partB && source ./00_common/set_env.sh
#
# 이후 모든 스크립트는 이 변수들을 그대로 사용합니다. 필요하면 실행 전에 export로 덮어써도 됩니다.
#   예) AWS_REGION=us-east-1 source ./00_common/set_env.sh

set -a

AWS_REGION="${AWS_REGION:-us-west-2}"          # Bedrock AgentCore 가용 리전 확인 후 필요시 변경
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "[경고] AWS 자격증명을 확인할 수 없습니다. 'aws configure'를 먼저 실행하세요." >&2
fi

PROJECT_PREFIX="soar-agent"

# 02_kinesis
KINESIS_STREAM_NAME="${PROJECT_PREFIX}-log-stream"

# 03_storage_notify
S3_BUCKET_NAME="${PROJECT_PREFIX}-threat-scores-${AWS_ACCOUNT_ID}"
SNS_APPROVAL_TOPIC_NAME="${PROJECT_PREFIX}-approval-topic"
SNS_COMPLETION_TOPIC_NAME="${PROJECT_PREFIX}-completion-topic"
SQS_APPROVAL_QUEUE_NAME="${PROJECT_PREFIX}-approval-queue"
DDB_BLOCKLIST_TABLE="${PROJECT_PREFIX}-blocklist"
DDB_PENDING_APPROVALS_TABLE="${PROJECT_PREFIX}-pending-approvals"

# 04_cognito
COGNITO_USER_POOL_NAME="${PROJECT_PREFIX}-pool"
COGNITO_DOMAIN_PREFIX="${PROJECT_PREFIX}-$(echo "$AWS_ACCOUNT_ID" | cut -c1-6)"   # 전역 유일해야 함
COGNITO_RESOURCE_SERVER_ID="soar-gateway"
COGNITO_SCOPE_NAME="invoke"
COGNITO_APP_CLIENT_NAME="${PROJECT_PREFIX}-gateway-client"

# 06_step_functions
STATE_MACHINE_NAME="${PROJECT_PREFIX}-orchestrator"
STEP_FUNCTIONS_ROLE_NAME="${PROJECT_PREFIX}-sfn-role"
APPROVAL_PROCESSOR_FUNCTION_NAME="${PROJECT_PREFIX}-approval-processor"
CALL_AGENT_LAMBDA_FUNCTION_NAME="${PROJECT_PREFIX}-call-agent"        # 파트A 산출물 (또는 스텁)
BLOCK_IP_LAMBDA_FUNCTION_NAME="${PROJECT_PREFIX}-block-ip"            # 파트A 산출물 (또는 스텁)

# 담당자(승인자) 이메일 - 실제 값으로 바꾸세요
APPROVER_EMAIL="${APPROVER_EMAIL:-your-email@example.com}"

set +a

echo "[set_env.sh] 환경 변수 로드 완료"
echo "  AWS_REGION=$AWS_REGION"
echo "  AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "  PROJECT_PREFIX=$PROJECT_PREFIX"
echo "  APPROVER_EMAIL=$APPROVER_EMAIL  (다르면 'export APPROVER_EMAIL=본인메일' 후 다시 source)"
