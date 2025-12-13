# 데이터베이스 스키마 Ver 3.0

**Version:** 3.0  
**Date:** 2025-12-14  
**Database:** Supabase (PostgreSQL)  
**Changes:** exit_reason 필드 추가, 환율 필터 지원, BB 지표 저장

---

## Ver 3.0 주요 변경사항

| 변경 | 설명 |
|:---|:---|
| `trade_history.exit_reason` | 청산 사유 ('Target' / 'Breakout') 필수 저장 |
| `exchange_rates_ma` | 환율 12시간 MA 뷰 추가 |
| `kimp_indicators` | 김프 지표 테이블 (Z-Score, BB) |
| `exchange_rate_filter_status` | 환율 필터 상태 뷰 |

---

## 테이블 구조

### 1. ohlcv (시세 데이터)

```sql
CREATE TABLE ohlcv (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(20) NOT NULL,
    open DECIMAL(20, 8) NOT NULL,
    high DECIMAL(20, 8) NOT NULL,
    low DECIMAL(20, 8) NOT NULL,
    close DECIMAL(20, 8) NOT NULL,
    volume DECIMAL(20, 8) NOT NULL,
    quote_volume DECIMAL(20, 8),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(timestamp, symbol, exchange)
);

CREATE INDEX idx_ohlcv_symbol_time ON ohlcv(symbol, timestamp DESC);
CREATE INDEX idx_ohlcv_exchange ON ohlcv(exchange, symbol, timestamp DESC);
```

### 2. exchange_rates (환율) - TradingView FX_IDC:USDKRW

```sql
CREATE TABLE exchange_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    base_currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    quote_currency VARCHAR(10) NOT NULL DEFAULT 'KRW',
    
    -- 가격 데이터 (TradingView OHLC)
    rate DECIMAL(20, 8) NOT NULL,      -- 종가/현재가 (김프 계산용)
    open DECIMAL(20, 8),                -- 시가
    high DECIMAL(20, 8),                -- 고가
    low DECIMAL(20, 8),                 -- 저가
    
    -- 데이터 소스 추적
    source VARCHAR(50) NOT NULL DEFAULT 'tradingview:FX_IDC:USDKRW',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 분 단위 중복 방지
    UNIQUE(timestamp, base_currency, quote_currency, source)
);

-- 조회 최적화 인덱스
CREATE INDEX idx_exchange_rate_time ON exchange_rates (timestamp DESC);
CREATE INDEX idx_exchange_rate_source ON exchange_rates (source, timestamp DESC);
CREATE INDEX idx_exchange_rate_latest ON exchange_rates (base_currency, quote_currency, timestamp DESC);
```

### 3. exchange_rates_ma (환율 이동평균 뷰) - Ver 3.0 신규

```sql
-- 환율 12시간 MA 뷰 (환율 필터용)
CREATE OR REPLACE VIEW exchange_rates_ma AS
SELECT 
    timestamp,
    rate,
    AVG(rate) OVER (
        ORDER BY timestamp 
        ROWS BETWEEN 719 PRECEDING AND CURRENT ROW
    ) AS ma_12h,  -- 720분 = 12시간
    rate / NULLIF(AVG(rate) OVER (
        ORDER BY timestamp 
        ROWS BETWEEN 719 PRECEDING AND CURRENT ROW
    ), 0) AS rate_ratio  -- 현재 환율 / 12시간 MA
FROM exchange_rates
WHERE source = 'tradingview:FX_IDC:USDKRW'
ORDER BY timestamp DESC;

-- 환율 필터 상태 조회용 함수
CREATE OR REPLACE FUNCTION check_exchange_rate_filter()
RETURNS TABLE (
    current_rate DECIMAL(20, 8),
    ma_12h DECIMAL(20, 8),
    rate_ratio DECIMAL(10, 6),
    is_blocked BOOLEAN,
    checked_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.rate AS current_rate,
        e.ma_12h,
        e.rate_ratio,
        (e.rate_ratio > 1.001) AS is_blocked,  -- 0.1% 초과 시 차단
        NOW() AS checked_at
    FROM exchange_rates_ma e
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;
```

### 4. kimp_rates (김프율)

```sql
CREATE TABLE kimp_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 가격 데이터
    upbit_price DECIMAL(20, 8) NOT NULL,      -- 업비트 가격 (KRW)
    binance_price DECIMAL(20, 8) NOT NULL,    -- 바이낸스 가격 (USDT)
    exchange_rate DECIMAL(20, 8) NOT NULL,    -- USD/KRW 환율
    
    -- 계산된 값
    kimp_rate DECIMAL(10, 4) NOT NULL,        -- 김프율 (%)
    
    -- 환율 소스 추적
    rate_source VARCHAR(50) DEFAULT 'tradingview:FX_IDC:USDKRW',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(timestamp, symbol)
);

CREATE INDEX idx_kimp_time ON kimp_rates (timestamp DESC);
CREATE INDEX idx_kimp_symbol_time ON kimp_rates (symbol, timestamp DESC);
```

### 5. kimp_indicators (김프 지표) - Ver 3.0 신규

```sql
-- 김프 지표 테이블 (Z-Score, BB)
CREATE TABLE kimp_indicators (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 김프 값
    kimp_rate DECIMAL(10, 4) NOT NULL,
    
    -- Z-Score 지표
    zscore DECIMAL(10, 4),
    zscore_ma20 DECIMAL(10, 4),     -- 20분 이동평균
    zscore_std20 DECIMAL(10, 4),    -- 20분 표준편차
    zscore_min_5min DECIMAL(10, 4), -- 최근 5분 최저점 (Ver 3.0)
    
    -- 볼린저밴드 (김프% 대상)
    bb_upper DECIMAL(10, 4),        -- 상단밴드 (MA + 2σ)
    bb_middle DECIMAL(10, 4),       -- 중간선 (MA)
    bb_lower DECIMAL(10, 4),        -- 하단밴드 (MA - 2σ)
    
    -- 환율 필터 상태 (Ver 3.0)
    exchange_rate_ratio DECIMAL(10, 6),  -- 현재환율/12시간MA
    is_entry_blocked BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(timestamp, symbol)
);

CREATE INDEX idx_kimp_indicators_time ON kimp_indicators (timestamp DESC);
CREATE INDEX idx_kimp_indicators_symbol ON kimp_indicators (symbol, timestamp DESC);
```

### 6. trade_history (거래 내역) - Ver 3.0 업데이트

```sql
CREATE TABLE trade_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- 거래 식별
    trade_id VARCHAR(50) UNIQUE,
    strategy VARCHAR(50) NOT NULL DEFAULT 'kimp_delta_neutral',
    
    -- 진입 정보
    entry_timestamp TIMESTAMPTZ NOT NULL,
    entry_level VARCHAR(20) NOT NULL,      -- 'level1', 'level2', 'full'
    entry_kimp DECIMAL(10, 4) NOT NULL,
    entry_zscore DECIMAL(10, 4),
    
    -- 가격 정보
    upbit_entry_price DECIMAL(20, 8) NOT NULL,
    binance_entry_price DECIMAL(20, 8) NOT NULL,
    exchange_rate_at_entry DECIMAL(20, 8) NOT NULL,
    
    -- 포지션 크기
    invested_amount DECIMAL(20, 2) NOT NULL,  -- 투입금액 (KRW)
    btc_amount DECIMAL(20, 8) NOT NULL,
    
    -- 청산 정보
    exit_timestamp TIMESTAMPTZ,
    exit_kimp DECIMAL(10, 4),
    upbit_exit_price DECIMAL(20, 8),
    binance_exit_price DECIMAL(20, 8),
    
    -- ⭐ Ver 3.0 필수: 청산 사유
    exit_reason VARCHAR(20),               -- 'Target' | 'Breakout' | NULL(미청산)
    
    -- 수익 정보
    gross_pnl DECIMAL(20, 2),              -- 총 수익 (수수료 전)
    gross_pnl_pct DECIMAL(10, 4),          -- 총 수익률 (%)
    fees_paid DECIMAL(20, 2),              -- 지불한 수수료
    net_pnl DECIMAL(20, 2),                -- 순 수익 (수수료 후)
    net_pnl_pct DECIMAL(10, 4),            -- 순 수익률 (%)
    
    -- 보유 기간
    holding_duration_hours DECIMAL(10, 2),
    
    -- 상태
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN, CLOSED, CANCELLED
    
    -- 메타데이터
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT
);

CREATE INDEX idx_trade_history_status ON trade_history (status, created_at DESC);
CREATE INDEX idx_trade_history_exit_reason ON trade_history (exit_reason, exit_timestamp DESC);
CREATE INDEX idx_trade_history_strategy ON trade_history (strategy, created_at DESC);

-- 청산 사유별 통계 뷰
CREATE OR REPLACE VIEW exit_reason_stats AS
SELECT 
    exit_reason,
    COUNT(*) AS total_trades,
    ROUND(COUNT(*)::DECIMAL / SUM(COUNT(*)) OVER () * 100, 2) AS percentage,
    ROUND(AVG(gross_pnl_pct), 4) AS avg_gross_pnl_pct,
    ROUND(AVG(net_pnl_pct), 4) AS avg_net_pnl_pct,
    ROUND(AVG(holding_duration_hours), 2) AS avg_holding_hours
FROM trade_history
WHERE status = 'CLOSED' AND exit_reason IS NOT NULL
GROUP BY exit_reason;
```

### 7. orders (주문)

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_id UUID REFERENCES trade_history(id),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,      -- BUY, SELL
    type VARCHAR(20) NOT NULL,      -- MARKET, LIMIT
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8),
    filled_quantity DECIMAL(20, 8) DEFAULT 0,
    avg_fill_price DECIMAL(20, 8),
    status VARCHAR(20) NOT NULL,    -- PENDING, FILLED, PARTIAL, CANCELLED, FAILED
    error_message TEXT,
    exchange_order_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_orders_trade_id ON orders (trade_id);
CREATE INDEX idx_orders_status ON orders (status, created_at DESC);
CREATE INDEX idx_orders_exchange ON orders (exchange, created_at DESC);
```

### 8. positions (현재 포지션)

```sql
CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_id UUID REFERENCES trade_history(id),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,      -- LONG (upbit), SHORT (binance)
    quantity DECIMAL(20, 8) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    current_price DECIMAL(20, 8),
    unrealized_pnl DECIMAL(20, 8),
    unrealized_pnl_pct DECIMAL(10, 4),
    leverage INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    opened_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(exchange, symbol, trade_id)
);

CREATE INDEX idx_positions_active ON positions (is_active, exchange);
CREATE INDEX idx_positions_trade ON positions (trade_id);
```

### 9. system_status (시스템 상태)

```sql
CREATE TABLE system_status (
    id SERIAL PRIMARY KEY,
    component VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,    -- OK, WARNING, ERROR, STOPPED
    last_heartbeat TIMESTAMPTZ,
    message TEXT,
    metadata JSONB,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(component)
);

-- 초기 컴포넌트 등록
INSERT INTO system_status (component, status) VALUES
    ('data_collector', 'STOPPED'),
    ('strategy_engine', 'STOPPED'),
    ('order_executor', 'STOPPED'),
    ('telegram_bot', 'STOPPED'),
    ('exchange_rate_filter', 'STOPPED');
```

### 10. strategy_params (전략 파라미터)

```sql
CREATE TABLE strategy_params (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL UNIQUE,
    version VARCHAR(10) DEFAULT '3.0',
    params JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ver 3.0 기본 파라미터
INSERT INTO strategy_params (strategy, version, params) VALUES (
    'kimp_delta_neutral',
    '3.0',
    '{
        "capital": {"total": 40000000, "reserve_ratio": 0.05},
        "zscore": {"window": 20, "lookback_seconds": 300, "level1": -2.0, "level2": -2.5},
        "exchange_rate_filter": {"ma_period_minutes": 720, "threshold_ratio": 1.001},
        "exit": {
            "track_a": {"target_profit": 0.007},
            "track_b": {"min_profit": 0.0048, "bb_period": 20, "bb_stddev": 2.0}
        },
        "stop_loss": {"enabled": false}
    }'::jsonb
);
```

---

## 인덱스 전략

| 테이블 | 인덱스 | 용도 |
|:---|:---|:---|
| ohlcv | (symbol, timestamp DESC) | 심볼별 시계열 조회 |
| exchange_rates | (source, timestamp DESC) | TradingView 환율 조회 |
| kimp_indicators | (timestamp DESC) | 최신 지표 조회 |
| trade_history | (exit_reason, exit_timestamp DESC) | 청산 사유별 분석 |
| positions | (is_active, exchange) | 활성 포지션 조회 |

---

## 데이터 보존 정책

| 테이블 | 보존 기간 | 이유 |
|:---|:---|:---|
| ohlcv | 무기한 | 백테스트 핵심 |
| exchange_rates | 1년 | 환율 필터 분석 |
| kimp_rates | 무기한 | 전략 분석 |
| kimp_indicators | 90일 | 지표 검증 |
| trade_history | 무기한 | 성과 분석 |
| orders | 1년 | 실행 검증 |

---

## 마이그레이션 (v2.0 → v3.0)

```sql
-- 1. trade_history 테이블에 exit_reason 추가
ALTER TABLE trade_history 
ADD COLUMN IF NOT EXISTS exit_reason VARCHAR(20);

-- 2. kimp_indicators 테이블 생성
-- (위 스키마 참조)

-- 3. 환율 필터 함수 생성
-- (위 스키마 참조)

-- 4. 기존 데이터 마이그레이션 (필요 시)
UPDATE trade_history 
SET exit_reason = 'Target'
WHERE status = 'CLOSED' AND exit_reason IS NULL;

-- 5. 새 인덱스 추가
CREATE INDEX IF NOT EXISTS idx_trade_history_exit_reason 
ON trade_history (exit_reason, exit_timestamp DESC);

-- 6. strategy_params 버전 업데이트
UPDATE strategy_params 
SET version = '3.0', 
    params = params || '{"exit": {"track_a": {"target_profit": 0.007}, "track_b": {"min_profit": 0.0048}}}'::jsonb,
    updated_at = NOW()
WHERE strategy = 'kimp_delta_neutral';
```

---

*— Ver 3.0 스키마 문서 끝 —*
