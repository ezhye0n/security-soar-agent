# 03. S3 / SNS / SQS / DynamoDB (1:30–2:30)

실행 순서 (모두 `source ../00_common/set_env.sh` 이후):

```bash
bash create_s3_bucket.sh
bash create_sns_topics.sh        # 출력된 ARN 2개를 export 해두세요
bash create_sqs_queue.sh         # 출력된 URL/ARN을 export 해두세요
bash create_dynamodb_tables.sh
```

## 각 리소스의 역할
- **S3 버킷** (`$S3_BUCKET_NAME`): 파트A Consumer Lambda가 계산한 위협 점수 JSON을 저장.
- **SNS 승인 토픽**: 위협도 HIGH 발생 시 담당자에게 "확인해주세요" 알림.
- **SNS 완료 토픽**: 승인/거부 처리가 끝난 뒤 최종 결과 알림.
- **SQS 승인 큐**: Step Functions의 `WaitForApproval` 상태가 `taskToken`을 담아 메시지를 보내고
  응답(SendTaskSuccess/Failure)이 올 때까지 실행을 일시정지합니다.
- **DynamoDB blocklist 테이블**: 실제 방화벽 대신 "모의 차단 기록"을 저장 (파트A `blockIP` Lambda가 씀).
- **DynamoDB pending-approvals 테이블**: SQS로 들어온 taskToken을 requestId 기준으로 저장해두어,
  운영자가 `approve_cli.sh <requestId> approve|reject` 로 나중에 조회/승인할 수 있게 합니다.

## 확인
```bash
aws s3 ls | grep soar-agent
aws sns list-topics --query 'Topics[].TopicArn' --output table
aws sqs list-queues --query 'QueueUrls' --output table
aws dynamodb list-tables --query 'TableNames' --output table
```
