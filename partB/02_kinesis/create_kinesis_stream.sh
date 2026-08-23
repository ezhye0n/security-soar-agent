#!/usr/bin/env bash
# Kinesis Data Stream 생성 (1:00–1:30 구간)
# 사전: source ../00_common/set_env.sh
set -euo pipefail

: "${KINESIS_STREAM_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/3] Kinesis Stream 생성: $KINESIS_STREAM_NAME"
aws kinesis create-stream \
  --stream-name "$KINESIS_STREAM_NAME" \
  --shard-count 1 \
  --region "$AWS_REGION"

echo "[2/3] ACTIVE 상태 대기 중..."
aws kinesis wait stream-exists \
  --stream-name "$KINESIS_STREAM_NAME" \
  --region "$AWS_REGION"

echo "[3/3] 스트림 정보"
aws kinesis describe-stream-summary \
  --stream-name "$KINESIS_STREAM_NAME" \
  --region "$AWS_REGION"

STREAM_ARN=$(aws kinesis describe-stream-summary \
  --stream-name "$KINESIS_STREAM_NAME" \
  --region "$AWS_REGION" \
  --query 'StreamDescriptionSummary.StreamARN' --output text)

echo ""
echo "완료. STREAM_ARN=$STREAM_ARN"
echo "이 값을 파트A Producer/Consumer Lambda 환경변수(KINESIS_STREAM_NAME 또는 ARN)로 전달하세요."
