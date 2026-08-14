#!/usr/bin/env bash
# 위협 점수 저장용 S3 버킷 생성 (1:30–2:30 구간)
set -euo pipefail
: "${S3_BUCKET_NAME:?먼저 00_common/set_env.sh 를 source 하세요}"

echo "[1/3] S3 버킷 생성: $S3_BUCKET_NAME (region=$AWS_REGION)"
if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION"
else
  aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

echo "[2/3] 퍼블릭 액세스 차단"
aws s3api put-public-access-block \
  --bucket "$S3_BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "[3/3] 버전 관리 활성화 (선택, 디버깅용)"
aws s3api put-bucket-versioning \
  --bucket "$S3_BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo ""
echo "완료. S3_BUCKET_NAME=$S3_BUCKET_NAME"
echo "권장 키 규칙 예: threat-scores/YYYY/MM/DD/<ip>-<timestamp>.json"
