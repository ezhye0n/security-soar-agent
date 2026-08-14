# Security SOAR Agent (team soara)

실시간 위협 탐지 → AI 기반 분석 → Human-in-the-Loop 승인 → 자동 차단까지 이어지는
AWS 서버리스 SOAR(Security Orchestration, Automation and Response) 파이프라인입니다.

![아키텍처](partA_A2/architecture_diagram.png)

## 왜 만들었나

보안 관제 담당자는 하루에도 수천 건의 이벤트를 마주하지만, 단순 탐지만으로는 신뢰하고
대응하기 어렵습니다. 이 프로젝트는 세 가지를 동시에 달성하려고 합니다.

- **설명 가능한 탐지**: 규칙 기반 점수 + Bedrock AgentCore AI 에이전트의 자연어 판단 근거
- **사람이 통제하는 자동화**: 탐지는 자동, 실제 차단은 반드시 사람의 승인을 거침
- **실시간 가시성**: 탐지부터 승인, 차단까지 전 과정을 대시보드에서 확인

## 전체 흐름

CTU-13 봇넷 트래픽 데이터셋을 Kinesis로 스트리밍 → Consumer Lambda가 5분 슬라이딩
윈도우로 위협 점수를 계산해 DynamoDB/S3에 기록 → HIGH 판정 시 Step Functions가 담당자
승인을 대기(waitForTaskToken) → SNS로 승인 요청 이메일 발송 → 승인 시 BlockIP Lambda가
실제 차단을 실행하고 결과를 다시 기록 → 대시보드가 이 모든 과정을 실시간으로 시각화하며,
Bedrock AgentCore 기반 AI 에이전트가 온디맨드로 심층 판단 근거를 제공합니다.

## 폴더 구조

- `partA_A2/` — 데이터 전처리, Producer/Consumer Lambda, Human-in-the-Loop 승인 플로우,
  실시간 대시보드(+ AI 분석 연동), 아키텍처 다이어그램, 발표 대본, 회고
- `partB/` — 인프라 프로비저닝(Kinesis, DynamoDB, S3, SNS/SQS, Cognito, Step Functions),
  AgentCore 연동 지원 자료
- `partC/` — Step Functions 기반 Human-in-the-Loop 승인 처리 단계별 구현(스켈레톤 → 실제
  구현까지)

## 주요 컴포넌트

| 구성 요소 | 역할 |
|---|---|
| Producer Lambda | CTU-13 데이터셋을 실시간처럼 Kinesis로 재생 |
| Consumer Lambda | 5분 슬라이딩 윈도우 기반 IP별 위협 점수 계산 (LOW/MEDIUM/HIGH) |
| Filter Trigger Lambda | S3 신규 판정 파일 감지, 동일 IP 중복 승인 요청 방지 |
| Step Functions | `waitForTaskToken` 패턴으로 사람의 승인을 최대 1시간 대기 |
| Notify / Respond Lambda | SNS 이메일 발송, 승인/거부 콜백 처리 |
| BlockIP Lambda | 승인된 IP만 실제 차단 실행 + DynamoDB에 기록 |
| Dashboard | DynamoDB/S3를 읽기 전용으로 폴링하는 실시간 대시보드 |
| Bedrock AgentCore (Strands Agent + MCP) | 온디맨드 호출 시 위협 조회 도구를 사용해 자연어 판단 근거 제공. 절대 스스로 차단을 실행하지 않음 |

## 참고 자료

- [발표 대본](partA_A2/demo_script.md)
- [느낀 점 및 경험한 성과](partA_A2/reflection.md)

## 보안 유의사항

이 저장소의 스크립트는 특정 AWS 계정/리전(ap-northeast-2)을 기준으로 작성되었습니다.
실제 자격 증명(Access Key, Client Secret 등)은 코드에 하드코딩되어 있지 않고 전부
환경 변수로 주입하도록 되어 있습니다. 이 저장소를 포크/재사용할 경우 각자의 AWS
계정 정보로 교체해서 사용하세요.
