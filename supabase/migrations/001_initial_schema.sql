-- 001_initial_schema.sql
-- Trading Platform 초기 스키마

-- 1. OHLCV 시세 데이터
CREATE TABLE IF NOT EXISTS ohlcv (
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

CREATE INDEX IF NOT EXISTS idx_ohlcv_symbol_time ON ohlcv(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_ohlcv_exchange ON ohlcv(exchange, timestamp DESC);

-- 2. 주문
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,
    type VARCHAR(20) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    strategy VARCHAR(50),
    external_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_strategy ON orders(strategy, created_at DESC);

-- 3. 체결
CREATE TABLE IF NOT EXISTS fills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8) NOT NULL,
    commission DECIMAL(20, 8),
    commission_asset VARCHAR(10),
    filled_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fills_order ON fills(order_id);

-- 4. 포지션
CREATE TABLE IF NOT EXISTS positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    current_price DECIMAL(20, 8),
    unrealized_pnl DECIMAL(20, 8),
    strategy VARCHAR(50),
    opened_at TIMESTAMPTZ NOT NULL,
    closed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(exchange, symbol, strategy) WHERE closed_at IS NULL
);

-- 5. 전략 파라미터
CREATE TABLE IF NOT EXISTS strategy_params (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL UNIQUE,
    params JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. 백테스트 결과
CREATE TABLE IF NOT EXISTS backtest_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    initial_capital DECIMAL(20, 2) NOT NULL,
    final_capital DECIMAL(20, 2) NOT NULL,
    total_return DECIMAL(10, 4),
    sharpe_ratio DECIMAL(10, 4),
    max_drawdown DECIMAL(10, 4),
    total_trades INTEGER,
    win_rate DECIMAL(10, 4),
    params JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. 시스템 로그
CREATE TABLE IF NOT EXISTS logs (
    id BIGSERIAL PRIMARY KEY,
    level VARCHAR(10) NOT NULL,
    module VARCHAR(50),
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level, created_at DESC);
