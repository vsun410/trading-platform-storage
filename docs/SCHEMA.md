# 데이터베이스 스키마

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
```

### 2. orders (주문)

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,  -- BUY, SELL
    type VARCHAR(20) NOT NULL,  -- MARKET, LIMIT, STOP
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8),
    status VARCHAR(20) NOT NULL,  -- PENDING, FILLED, CANCELLED
    strategy VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 3. fills (체결)

```sql
CREATE TABLE fills (
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
```

### 4. positions (포지션)

```sql
CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,  -- LONG, SHORT
    quantity DECIMAL(20, 8) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    current_price DECIMAL(20, 8),
    unrealized_pnl DECIMAL(20, 8),
    strategy VARCHAR(50),
    opened_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(exchange, symbol, strategy)
);
```

### 5. strategy_params (전략 파라미터)

```sql
CREATE TABLE strategy_params (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL UNIQUE,
    params JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 6. backtest_results (백테스트 결과)

```sql
CREATE TABLE backtest_results (
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
```

## 인덱스 전략

| 테이블 | 인덱스 | 용도 |
|:---|:---|:---|
| ohlcv | (symbol, timestamp DESC) | 시계열 조회 |
| orders | (exchange, status) | 상태별 조회 |
| fills | (order_id) | 주문별 체결 조회 |
| positions | (exchange, symbol) | 포지션 조회 |
