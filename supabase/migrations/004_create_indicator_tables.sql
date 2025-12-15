-- ============================================
-- 004_create_indicator_tables.sql
-- 지표 로그 테이블 (Z-Score, 볼린저 밴드)
-- ============================================

-- ----------------------------------------
-- zscore_log: Z-Score 계산 로그
-- 1시간(60분) 롤링 윈도우 기준
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS zscore_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 김프 데이터
    kimp_current    DECIMAL(10, 4) NOT NULL,
    kimp_mean       DECIMAL(10, 4) NOT NULL,
    kimp_std        DECIMAL(10, 4) NOT NULL,
    
    -- Z-Score
    zscore          DECIMAL(10, 4) NOT NULL,
    
    -- 5분 Lookback 최저값 (Ver 3.0)
    zscore_5m_min   DECIMAL(10, 4),
    
    -- 윈도우 크기
    window_size     INTEGER NOT NULL DEFAULT 60,
    
    -- 신호 상태 (Level 임계값 터치)
    level1_triggered BOOLEAN DEFAULT FALSE,  -- Z ≤ -2.0
    level2_triggered BOOLEAN DEFAULT FALSE,  -- Z ≤ -2.5
    
    -- 회귀 감지 (Ver 3.0)
    level1_reversion BOOLEAN DEFAULT FALSE,  -- -2.0 회귀 발생
    level2_reversion BOOLEAN DEFAULT FALSE,  -- -2.5 회귀 발생
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_zscore_log_timestamp 
    ON zscore_log(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_zscore_log_symbol_ts 
    ON zscore_log(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_zscore_log_zscore 
    ON zscore_log(zscore);
CREATE INDEX IF NOT EXISTS idx_zscore_log_reversion 
    ON zscore_log(level1_reversion, level2_reversion);

-- ----------------------------------------
-- bb_log: 볼린저 밴드 로그 (Ver 3.0 신규)
-- 김프% 시계열 기반 (가격 아님!)
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS bb_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 볼린저 밴드 값
    bb_upper        DECIMAL(10, 4) NOT NULL,
    bb_middle       DECIMAL(10, 4) NOT NULL,
    bb_lower        DECIMAL(10, 4) NOT NULL,
    
    -- 현재 김프
    kimp_current    DECIMAL(10, 4) NOT NULL,
    
    -- 돌파 상태
    is_upper_break  BOOLEAN DEFAULT FALSE,
    is_lower_break  BOOLEAN DEFAULT FALSE,
    
    -- 파라미터
    period          INTEGER NOT NULL DEFAULT 20,
    std_mult        DECIMAL(4, 2) NOT NULL DEFAULT 2.0,
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_bb_log_timestamp 
    ON bb_log(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_bb_log_symbol_ts 
    ON bb_log(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_bb_log_upper_break 
    ON bb_log(is_upper_break, timestamp DESC);

-- ----------------------------------------
-- 볼린저 밴드 돌파 체크 함수
-- ----------------------------------------
CREATE OR REPLACE FUNCTION check_bb_breakout(
    p_current_kimp DECIMAL,
    p_bb_upper DECIMAL,
    p_entry_kimp DECIMAL,
    p_min_profit DECIMAL DEFAULT 0.48
) RETURNS BOOLEAN AS $$
BEGIN
    -- Track B 조건: 최소 마진 확보 + BB 상단 돌파
    RETURN (p_current_kimp - p_entry_kimp) >= p_min_profit 
           AND p_current_kimp > p_bb_upper;
END;
$$ LANGUAGE plpgsql;

-- 코멘트
COMMENT ON TABLE zscore_log IS 'Z-Score 계산 로그 (1시간 윈도우)';
COMMENT ON TABLE bb_log IS '볼린저 밴드 로그 - 김프% 기반 (20기간, 2σ)';
COMMENT ON FUNCTION check_bb_breakout IS 'Track B 청산 조건 체크 (BB 돌파 + 최소 0.48% 수익)';
