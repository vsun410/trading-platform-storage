-- ============================================
-- 001_init_extensions.sql
-- 확장 기능 초기화
-- ============================================

-- UUID 확장
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 타임존 관련
SET timezone = 'UTC';

-- 버전 정보 테이블
CREATE TABLE IF NOT EXISTS schema_version (
    version VARCHAR(10) PRIMARY KEY,
    description TEXT,
    applied_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO schema_version (version, description) 
VALUES ('3.0', 'Ver 3.0 - 김프 전략 스키마 (환율 필터, Dual Track 청산)')
ON CONFLICT (version) DO NOTHING;
