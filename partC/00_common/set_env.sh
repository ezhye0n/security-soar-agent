#!/usr/bin/env bash
# 파트C 공통 환경 변수. 가장 먼저 이 파일을 source 하세요.
#   cd partC && source ./00_common/set_env.sh
#
# 팀 전체가 같은 AWS 계정을 쓰므로, 모든 리소스 이름 뒤에 팀 식별자(-soara)를 붙여
# 다른 팀과 충돌하지 않게 합니다.

set -a

TEAM_ID="soara"
TEAM_SUFFIX="-${TEAM_ID}"

AWS_REGION="${AWS_REGION:-us-west-2}"          # 팀이 합의한 리전과 동일하게 맞추세요 (Bedrock AgentCore 가용 리전 확인)
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "[경고] AWS 자격증명을 확인할 수 없습니다. 'aws configure'를 먼저 실행하세요." >&2
fi

PROJECT_PREFIX="soar-agent"

# ── 파트C가 직접 만드는 리소스 ──────────────────────────────────────
SNS_APPROVAL_TOPIC_NAME="${PROJECT_PREFIX}-approval-topic${TEAM_SUFFIX}"
SNS_COMPLETION_TOPIC_NAME="${PROJECT_PREFIX}-completion-topic${TEAM_SUFFIX}"
SQS_APPROVAL_QUEUE_NAME="${PROJECT_PREFIX}-approval-queue${TEAM_SUFFIX}"
DDB_PENDING_APPROVALS_TABLE="${PROJECT_PREFIX}-pending-approvals${TEAM_SUFFIX}"
STATE_MACHINE_NAME="${PROJECT_PREFIX}-orchestrator${TEAM_SUFFIX}"
STEP_FUNCTIONS_ROLE_NAME="${PROJECT_PREFIX}-sfn-role${TEAM_SUFFIX}"
APPROVAL_PROCESSOR_FUNCTION_NAME="${PROJECT_PREFIX}-approval-processor${TEAM_SUFFIX}"
CALL_AGENT_LAMBDA_FUNCTION_NAME="${PROJECT_PREFIX}-call-agent${TEAM_SUFFIX}"

# ── 다른 파트 산출물 참조용 (실제 값은 팀원에게 받아서 export) ─────────
# 파트A: Kinesis/S3 (데모에서 참조)
KINESIS_STREAM_NAME="${PROJECT_PREFIX}-log-stream${TEAM_SUFFIX}"
S3_BUCKET_NAME="${PROJECT_PREFIX}-threat-scores${TEAM_SUFFIX}-${AWS_ACCOUNT_ID}"
# 파트B: blockIP Lambda 함수명(실제 함수), Cognito 값들은 05_call_agent_lambda 에서 별도로 채움
BLOCK_IP_LAMBDA_FUNCTION_NAME="${PROJECT_PREFIX}-block-ip${TEAM_SUFFIX}"
# 파트B 함수가 아직 없을 때 C가 임시로 쓰는 스텁 (05_call_agent_lambda 참고)
BLOCK_IP_STUB_FUNCTION_NAME="${PROJECT_PREFIX}-block-ip-stub${TEAM_SUFFIX}"
DDB_BLOCKLIST_TABLE="${PROJECT_PREFIX}-blocklist${TEAM_SUFFIX}"   # 파트B blockIP Lambda가 씀 (공유 인프라, 먼저 만드는 사람이 생성)

# 담당자(승인자) 이메일 - 실제 값으로 바꾸세요
APPROVER_EMAIL="${APPROVER_EMAIL:-your-email@example.com}"

set +a

echo "[set_env.sh] 파트C 환경 변수 로드 완료 (팀 식별자: $TEAM_ID)"
echo "  AWS_REGION=$AWS_REGION"
echo "  AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "  STATE_MACHINE_NAME=$STATE_MACHINE_NAME"
echo "  APPROVER_EMAIL=$APPROVER_EMAIL  (다르면 'export APPROVER_EMAIL=본인메일' 후 다시 source)"
