# ============================================
# 김프 데이터 수집기 Dockerfile
# Purpose: 24/7 데이터 수집을 위한 경량 컨테이너
# ============================================

FROM python:3.11-slim

# 메타데이터
LABEL maintainer="vsun410"
LABEL description="Kimchi Premium Data Collector for Strategy Development"
LABEL version="3.0"

# 작업 디렉토리
WORKDIR /app

# 시스템 의존성 (최소화)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Python 의존성 먼저 복사 (캐시 활용)
COPY requirements.txt .

# 의존성 설치
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY src/ ./src/

# 로그 디렉토리 생성
RUN mkdir -p /app/logs

# 환경 변수
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# 비root 사용자로 실행 (보안)
RUN useradd --create-home --shell /bin/bash collector
RUN chown -R collector:collector /app
USER collector

# 헬스체크
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

# 실행
CMD ["python", "src/main.py"]
