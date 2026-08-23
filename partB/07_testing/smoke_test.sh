#!/usr/bin/env bash
# 인프라만으로 빠르게 end-to-end를 확인하는 스모크 테스트.
# Producer/Consumer Lambda(파트A)가 아직 없어도, Kinesis에 직접 레코드를 넣어서
# 최소한 "스트림이 살아있다"는 것과 "Step Functions 흐름이 동작한다"는 것을 확인할 수 있습니다.
set -euo pipefail
: "${KINESIS_STREAM_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/4] Kinesis에 테스트 레코드 1건 전송"
aws kinesis put-record \
  --stream-name "$KINESIS_STREAM_NAME" \
  --partition-key "203.0.113.77" \
  --data '{"ip":"203.0.113.77","timestamp":"2026-08-13T05:00:00Z","port":22,"action":"BLOCK"}' \
  --region "$AWS_REGION" \
  --cli-binary-format raw-in-base64-out

echo "[2/4] (파트A Consumer Lambda가 배포되어 있다면) S3에 결과가 쌓였는지 확인"
aws s3 ls "s3://${S3_BUCKET_NAME}/" --recursive | tail -5 || echo "  아직 없음 (Consumer Lambda 미배포 시 정상)"

echo "[3/4] Step Functions 실행 (스텁 또는 실제 Agent 호출 Lambda 사용, HIGH 강제)"
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --input '{"testIp":"203.0.113.77","testScore":92}' \
  --region "$AWS_REGION" --query 'executionArn' --output text)
echo "  ExecutionArn=$EXEC_ARN"

echo "[4/4] 10초 후 승인 대기 목록 확인 (approve_cli.sh 로 승인/거부 진행하세요)"
sleep 10
bash ../06_step_functions/list_pending_approvals.sh

echo ""
echo "다음 단계:"
echo "  requestId를 확인한 뒤: bash ../06_step_functions/approve_cli.sh <requestId> approve"
echo "  실행 상태 확인: aws stepfunctions describe-execution --execution-arn $EXEC_ARN --region $AWS_REGION"
