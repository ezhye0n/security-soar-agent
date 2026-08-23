"""
Step Functions의 "NotifyAndWaitForApproval" 상태(.waitForTaskToken 패턴)가 호출하는 Lambda.
SNS로 담당자에게 승인/거부 링크가 담긴 이메일을 보낸다.

이 함수 자체는 State를 끝내지 않는다 — Step Functions는 이 함수가 return하는 값을 무시하고,
누군가 나중에 send_task_success(taskToken=...)를 호출할 때까지(=respond_lambda가 호출할 때까지)
계속 대기(Wait) 상태로 멈춰있는다. 이게 "Human-in-the-Loop"의 핵심 메커니즘.

입력(event) 형태 (Step Functions ASL의 Parameters에서 이렇게 조립해서 넘겨줌):
{
  "input": { ip, level, score, blockCount, totalCount, reason, windowStart, windowEnd, ... },
  "taskToken": "AAAAKgAAAAIAAAA..."
}
"""
import json
import os
import urllib.parse

import boto3

sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
RESPOND_URL = os.environ.get("RESPOND_URL", "")


def build_link(base_url, task_token, decision, ip):
    qs = urllib.parse.urlencode({"token": task_token, "decision": decision, "ip": ip})
    return f"{base_url}?{qs}"


def handler(event, context):
    data = event.get("input", {}) or {}
    task_token = event.get("taskToken", "")
    ip = data.get("ip", "unknown")

    approve_url = build_link(RESPOND_URL, task_token, "approve", ip)
    deny_url = build_link(RESPOND_URL, task_token, "deny", ip)

    subject = f"[SOAR] HIGH 위협 탐지 - 승인 필요: {ip}"
    message = (
        f"Security SOAR Agent가 HIGH 등급 위협을 탐지했습니다.\n\n"
        f"위협 IP     : {ip}\n"
        f"위협 점수   : {data.get('score')} / 100\n"
        f"최근 5분 BLOCK 횟수: {data.get('blockCount')}회\n"
        f"판정 근거   : {data.get('reason')}\n\n"
        f"이 IP를 차단하시겠습니까? 아래 링크 중 하나를 클릭해주세요.\n\n"
        f"[승인 - 즉시 차단 실행]\n{approve_url}\n\n"
        f"[거부 - 차단하지 않음]\n{deny_url}\n\n"
        f"(1시간 안에 응답하지 않으면 자동으로 만료됩니다)"
    )

    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
    print(f"[Notify] SNS 발행 완료: ip={ip}, taskToken 길이={len(task_token)}")
    return {"notified": True, "ip": ip}
