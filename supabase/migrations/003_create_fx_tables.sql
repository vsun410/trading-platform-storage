-- ============================================
-- 003_create_fx_tables.sql
-- 환율 데이터 테이블 (Ver 3.0 신규)
-- ============================================

-- ----------------------------------------
-- fx_rates: TradingView USD/KRW 환율 데이터
-- 예상 용량: ~200MB/년
-- 보존: 1년
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS fx_rates (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    
    -- TradingView 심볼
    symbol          VARCHAR(30) NOT NULL DEFAULT 'FX_IDC:USDKRW',
    
    -- 환율 데이터
    rate            DECIMAL(10, 4) NOT NULL,  -- USD/KRW
    
    -- 12시간 이동평균 (720분)
    ma_12h          DECIMAL(10, 4),
    
    -- 데이터 소스
    source          VARCHAR(30) NOT NULL DEFAULT 'tvDatafeed',
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    -- 중복 방지
    UNIQUE(symbol, timestamp)
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_fx_rates_timestamp 
    ON fx_rates(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_fx_rates_symbol_ts 
    ON fx_rates(symbol, timestamp DESC);

-- ----------------------------------------
-- fx_filter_log: 환율 필터 상태 로그
-- Ver 3.0 신규 - 환율 급등 감지 기록
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS fx_filter_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    
    -- 환율 상태
    current_rate    DECIMAL(10, 4) NOT NULL,
    ma_12h          DECIMAL(10, 4) NOT NULL,
    threshold       DECIMAL(10, 4) NOT NULL,  -- ma_12h * 1.001
    
    -- 필터 결과
    is_blocked      BOOLEAN NOT NULL,  -- TRUE = 진입 차단
    surge_pct       DECIMAL(10, 4),    -- 급등률 (%)
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_fx_filter_timestamp 
    ON fx_filter_log(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_fx_filter_blocked 
    ON fx_filter_log(is_blocked, timestamp DESC);

-- ----------------------------------------
-- 환율 급등 체크 함수
-- ----------------------------------------
CREATE OR REPLACE FUNCTION check_fx_surge(
    p_current_rate DECIMAL,
    p_ma_12h DECIMAL,
    p_threshold DECIMAL DEFAULT 1.001
) RETURNS BOOLEAN AS $$
BEGIN
    -- 현재 환율이 MA × threshold 초과하면 급등
    RETURN p_current_rate > (p_ma_12h * p_threshold);
END;
$$ LANGUAGE plpgsql;

-- 코멘트
COMMENT ON TABLE fx_rates IS 'TradingView USD/KRW 환율 데이터 (1분 주기)';
COMMENT ON TABLE fx_filter_log IS '환율 필터 상태 로그 - 진입 차단 여부 기록';
COMMENT ON FUNCTION check_fx_surge IS '환율 급등 여부 체크 (기본 임계값: +0.1%)';
