-- ============================================
-- 005_create_trade_tables.sql
-- 포지션 및 거래 테이블
-- ============================================

-- ----------------------------------------
-- positions: 포지션 관리 (Ver 3.0 업데이트)
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS positions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    status          VARCHAR(20) NOT NULL DEFAULT 'open',  -- open, closed, error
    
    -- 진입 정보
    entry_level     VARCHAR(10) NOT NULL,  -- 'level1', 'level2', 'combined'
    entry_timestamp TIMESTAMPTZ NOT NULL,
    entry_kimp      DECIMAL(10, 4) NOT NULL,
    entry_zscore    DECIMAL(10, 4) NOT NULL,
    
    -- 환율 필터 상태 (Ver 3.0)
    entry_fx_rate   DECIMAL(10, 4),        -- 진입 시점 환율
    entry_fx_ma     DECIMAL(10, 4),        -- 진입 시점 환율 MA
    
    -- 업비트 포지션
    upbit_amount    DECIMAL(20, 8) NOT NULL,
    upbit_price     DECIMAL(20, 2) NOT NULL,
    upbit_order_id  VARCHAR(100),
    
    -- 바이낸스 포지션
    binance_amount  DECIMAL(20, 8) NOT NULL,
    binance_price   DECIMAL(20, 8) NOT NULL,
    binance_order_id VARCHAR(100),
    
    -- 총 투입금
    total_invested  DECIMAL(20, 2) NOT NULL,
    
    -- 청산 정보 (Ver 3.0 Dual Track)
    exit_timestamp  TIMESTAMPTZ,
    exit_kimp       DECIMAL(10, 4),
    exit_reason     VARCHAR(20),           -- 'Target' or 'Breakout' [NEW]
    exit_bb_upper   DECIMAL(10, 4),        -- 청산 시점 BB 상단 [NEW]
    
    -- 손익
    realized_pnl    DECIMAL(20, 2),
    realized_pnl_pct DECIMAL(10, 4),
    
    -- 보유 기간
    holding_hours   DECIMAL(10, 2),
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_positions_status 
    ON positions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_positions_exit_reason 
    ON positions(exit_reason);
CREATE INDEX IF NOT EXISTS idx_positions_symbol_status 
    ON positions(symbol, status);

-- ----------------------------------------
-- trades: 개별 거래 기록
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS trades (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id     UUID REFERENCES positions(id),
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 거래 유형
    trade_type      VARCHAR(10) NOT NULL,  -- 'entry', 'exit', 'rollback'
    side            VARCHAR(10) NOT NULL,  -- 'buy', 'sell'
    exchange        VARCHAR(20) NOT NULL,  -- 'upbit', 'binance'
    
    -- 주문 정보
    order_id        VARCHAR(100),
    order_type      VARCHAR(20) NOT NULL DEFAULT 'market',
    
    -- 체결 정보
    amount          DECIMAL(20, 8) NOT NULL,
    price           DECIMAL(20, 8) NOT NULL,
    filled_amount   DECIMAL(20, 8) NOT NULL,
    avg_price       DECIMAL(20, 8) NOT NULL,
    
    -- 비용
    fee             DECIMAL(20, 8),
    fee_currency    VARCHAR(10),
    
    -- 상태
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    error_message   TEXT,
    
    executed_at     TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_trades_position_id 
    ON trades(position_id);
CREATE INDEX IF NOT EXISTS idx_trades_executed_at 
    ON trades(executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_trades_exchange 
    ON trades(exchange, executed_at DESC);

-- ----------------------------------------
-- orders: 주문 큐 (실행 전 대기)
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id     UUID,
    
    -- 주문 정보
    exchange        VARCHAR(20) NOT NULL,
    symbol          VARCHAR(20) NOT NULL,
    side            VARCHAR(10) NOT NULL,
    order_type      VARCHAR(20) NOT NULL DEFAULT 'market',
    amount          DECIMAL(20, 8) NOT NULL,
    price           DECIMAL(20, 8),
    
    -- 상태
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    exchange_order_id VARCHAR(100),
    error_message   TEXT,
    
    -- 체결 정보
    filled_amount   DECIMAL(20, 8) DEFAULT 0,
    avg_fill_price  DECIMAL(20, 8),
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_status 
    ON orders(status, created_at DESC);

-- 코멘트
COMMENT ON TABLE positions IS '김프 포지션 관리 - Ver 3.0 Dual Track 청산 지원';
COMMENT ON COLUMN positions.exit_reason IS '청산 사유: Target(0.7% 도달) 또는 Breakout(BB돌파+0.48%)';
COMMENT ON TABLE trades IS '개별 거래 기록 (진입/청산/롤백)';
