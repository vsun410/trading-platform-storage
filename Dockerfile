# ============================================
# Trading Platform Storage - Dockerfile
# 김프 데이터 수집 서비스
# ============================================

FROM python:3.11-slim

# 메타데이터
LABEL maintainer="vsun410"
LABEL description="Kimchi Premium Data Collector"
LABEL version="3.0"

# 작업 디렉토리
WORKDIR /app

# 시스템 의존성 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Python 의존성 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY src/ ./src/

# 로그 디렉토리 생성
RUN mkdir -p logs

# 환경 변수 기본값
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV TZ=UTC

# 헬스체크
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

# 실행
CMD ["python", "src/main.py"]
