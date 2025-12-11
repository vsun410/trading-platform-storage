#!/bin/bash
# backup.sh - PostgreSQL 백업 스크립트

set -e

# 설정
BACKUP_DIR="${BACKUP_DIR:-./backups}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-trading}"
DB_USER="${DB_USER:-postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 백업 디렉토리 생성
mkdir -p "$BACKUP_DIR"

# 백업 파일명 (날짜 포함)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "백업 시작: $BACKUP_FILE"

# pg_dump로 백업 (gzip 압축)
PGPASSWORD="$DB_PASSWORD" pg_dump \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --no-owner \
    --no-acl \
    | gzip > "$BACKUP_FILE"

echo "백업 완료: $(du -h "$BACKUP_FILE" | cut -f1)"

# 오래된 백업 삭제
echo "오래된 백업 정리 (${RETENTION_DAYS}일 이상)..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "남은 백업 파일:"
ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || echo "없음"

echo "완료!"
