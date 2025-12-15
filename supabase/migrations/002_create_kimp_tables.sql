-- ============================================
-- 002_create_kimp_tables.sql
-- 김프 데이터 테이블 (핵심)
-- ============================================

-- ----------------------------------------
-- kimp_ticks: 실시간 김프 데이터
-- 예상 용량: ~10GB/년 (1초당 1row 기준)
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS kimp_ticks (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 업비트 데이터
    upbit_price     DECIMAL(20, 2) NOT NULL,
    upbit_volume    DECIMAL(20, 8),
    
    -- 바이낸스 데이터
    binance_price   DECIMAL(20, 8) NOT NULL,
    binance_volume  DECIMAL(20, 8),
    
    -- 환율
    exchange_rate   DECIMAL(10, 4) NOT NULL,
    
    -- 김프 계산값
    kimp_percent    DECIMAL(10, 4) NOT NULL,
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_kimp_ticks_timestamp 
    ON kimp_ticks(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_kimp_ticks_symbol_ts 
    ON kimp_ticks(symbol, timestamp DESC);

-- ----------------------------------------
-- kimp_1m: 1분봉 집계 데이터 (백테스트 핵심)
-- 예상 용량: ~500MB/년
-- 보존: 무기한
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS kimp_1m (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 김프 OHLC
    kimp_open       DECIMAL(10, 4) NOT NULL,
    kimp_high       DECIMAL(10, 4) NOT NULL,
    kimp_low        DECIMAL(10, 4) NOT NULL,
    kimp_close      DECIMAL(10, 4) NOT NULL,
    
    -- 평균 가격
    upbit_price     DECIMAL(20, 2) NOT NULL,
    binance_price   DECIMAL(20, 8) NOT NULL,
    exchange_rate   DECIMAL(10, 4) NOT NULL,
    
    -- 메타데이터
    tick_count      INTEGER DEFAULT 1,
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    -- 중복 방지
    UNIQUE(symbol, timestamp)
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_kimp_1m_timestamp 
    ON kimp_1m(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_kimp_1m_symbol_ts 
    ON kimp_1m(symbol, timestamp DESC);

-- ----------------------------------------
-- funding_rates: Binance 펀딩비
-- 8시간마다 수집
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS funding_rates (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    exchange        VARCHAR(20) NOT NULL DEFAULT 'binance',
    
    funding_rate    DECIMAL(20, 10) NOT NULL,
    funding_timestamp TIMESTAMPTZ,
    next_funding_time TIMESTAMPTZ,
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(symbol, timestamp, exchange)
);

CREATE INDEX IF NOT EXISTS idx_funding_rates_timestamp 
    ON funding_rates(timestamp DESC);
