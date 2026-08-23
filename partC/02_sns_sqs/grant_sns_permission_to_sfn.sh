#!/usr/bin/env bash
# Step Functions 실행 역할에 SNS Publish 권한 추가 (1:00–3:00)
set -euo pipefail
: "${STEP_FUNCTIONS_ROLE_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"
: "${SNS_APPROVAL_TOPIC_ARN:?create_sns_topics.sh 출력값을 export 하세요}"
: "${SNS_COMPLETION_TOPIC_ARN:?create_sns_topics.sh 출력값을 export 하세요}"

aws iam put-role-policy \
  --role-name "$STEP_FUNCTIONS_ROLE_NAME" \
  --policy-name "${PROJECT_PREFIX}-sfn-sns-publish" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"PublishSns\",
      \"Effect\": \"Allow\",
      \"Action\": \"sns:Publish\",
      \"Resource\": [\"${SNS_APPROVAL_TOPIC_ARN}\", \"${SNS_COMPLETION_TOPIC_ARN}\"]
    }]
  }"

echo "완료: $STEP_FUNCTIONS_ROLE_NAME 역할에 SNS Publish 권한 추가됨"
