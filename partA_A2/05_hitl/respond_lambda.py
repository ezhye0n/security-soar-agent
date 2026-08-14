"""
승인/거부 링크를 클릭하면 도착하는 Lambda (Function URL, 인증 없음 — 이메일 링크 클릭만으로
접근해야 하므로 로그인 절차 없음. 데모용으로만 사용).

쿼리 파라미터: ?token=<taskToken>&decision=approve|deny&ip=<ip>
Step Functions의 send_task_success를 호출해서, notify_lambda가 멈춰놓은 State를 재개시킨다.
이 output이 그대로 다음 State($.decision)로 전달되어 승인/거부 분기에 쓰인다.
"""
import json

import boto3

sfn = boto3.client("stepfunctions")


def handler(event, context):
    qs = event.get("queryStringParameters") or {}
    token = qs.get("token")
    decision = qs.get("decision")
    ip = qs.get("ip", "unknown")

    if not token or decision not in ("approve", "deny"):
        return _html(400, "잘못된 요청입니다 (token 또는 decision 값이 없거나 올바르지 않습니다).")

    try:
        sfn.send_task_success(
            taskToken=token,
            output=json.dumps({"decision": decision, "ip": ip}, ensure_ascii=False),
        )
    except sfn.exceptions.TaskTimedOut:
        return _html(410, "이미 시간이 만료되어 처리할 수 없는 요청입니다.")
    except Exception as e:
        print(f"[Respond] 오류: {e}")
        return _html(500, f"처리 중 오류가 발생했습니다: {e}")

    label = "차단 승인" if decision == "approve" else "차단 거부"
    return _html(200, f"IP {ip}에 대한 '{label}' 처리가 완료되었습니다. 이 창은 닫으셔도 됩니다.")


def _html(status_code, message):
    body = (
        "<!DOCTYPE html><html lang=\"ko\"><head><meta charset=\"UTF-8\">"
        "<title>SOAR Agent 승인</title>"
        "<style>body{font-family:system-ui,sans-serif;padding:60px;text-align:center;color:#0b0b0b;}"
        "p{font-size:18px;}</style></head>"
        f"<body><p>{message}</p></body></html>"
    )
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "text/html; charset=utf-8"},
        "body": body,
    }
