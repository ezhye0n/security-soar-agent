#!/usr/bin/env python3
"""
envsubst 대체용 소형 유틸리티 (macOS 등 envsubst가 기본 설치되어 있지 않은 환경 대비).
템플릿 파일 안의 ${VAR_NAME} 을 현재 환경변수 값으로 치환해서 stdout으로 출력합니다.

사용법:
    python3 00_common/render_template.py <template-file> > <output-file>
"""
import os
import sys
from string import Template


def main():
    if len(sys.argv) != 2:
        print("사용법: render_template.py <template-file>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    rendered = Template(content).safe_substitute(os.environ)

    # 치환되지 않은 ${...} 가 남아있으면 경고 (필수 환경변수 누락 가능성)
    import re
    leftover = re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", rendered)
    if leftover:
        print(f"[경고] 치환되지 않은 변수: {sorted(set(leftover))}", file=sys.stderr)

    sys.stdout.write(rendered)


if __name__ == "__main__":
    main()
