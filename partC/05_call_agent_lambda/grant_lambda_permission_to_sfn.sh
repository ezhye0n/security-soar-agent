#!/usr/bin/env bash
# Step Functions 실행 역할에 Lambda 호출 권한 추가 (5:00–6:30)
set -euo pipefail
: "${STEP_FUNCTIONS_ROLE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"
: "${CallAgentLambdaArn:?배포된 call-agent Lambda ARN을 export 하세요}"
: "${BlockIpLambdaArn:?배포된 block-ip Lambda ARN을 export 하세요}"

aws iam put-role-policy \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-sfn-invoke-lambdas" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"InvokeLambdas\",
      \"Effect\": \"Allow\",
      \"Action\": \"lambda:InvokeFunction\",
      \"Resource\": [\"${CallAgentLambdaArn}\", \"${BlockIpLambdaArn}\"]
    }]
  }"

echo "완료: $STEP_FUNCTIONS_ROLE_NAME 역할에 Lambda 호출 권한 추가됨"
