# 데이터베이스 스키마

**Version:** 2.0  
**Date:** 2025-12-12  
**Database:** Supabase (PostgreSQL)

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

### 2. exchange_rates (환율) - TradingView Webhook

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
    source VARCHAR(50) NOT NULL,        -- 'tradingview:FX_IDC:USDKRW', 'dunamu', 'koreaexim'
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 분 단위 중복 방지
    UNIQUE(timestamp, base_currency, quote_currency, source)
);

-- 조회 최적화 인덱스
CREATE INDEX idx_exchange_rate_time ON exchange_rates (timestamp DESC);
CREATE INDEX idx_exchange_rate_source ON exchange_rates (source, timestamp DESC);

-- 최신 환율 빠른 조회용
CREATE INDEX idx_exchange_rate_latest ON exchange_rates (base_currency, quote_currency, timestamp DESC);
```

### 3. kimp_rates (김프율)

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
    -- 공식: (upbit - binance * rate) / (binance * rate) * 100
    
    -- 환율 소스 추적
    rate_source VARCHAR(50) DEFAULT 'tradingview',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(timestamp, symbol)
);

CREATE INDEX idx_kimp_time ON kimp_rates (timestamp DESC);
CREATE INDEX idx_kimp_symbol_time ON kimp_rates (symbol, timestamp DESC);
```

### 4. orderbook_snapshots (호가 스냅샷)

```sql
CREATE TABLE orderbook_snapshots (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(20) NOT NULL,
    
    -- 매수/매도 호가 (JSON 배열: [[price, quantity], ...])
    bids JSONB NOT NULL,
    asks JSONB NOT NULL,
    
    -- 집계 메트릭
    bid_total_volume DECIMAL(20, 8),  -- 총 매수 잔량
    ask_total_volume DECIMAL(20, 8),  -- 총 매도 잔량
    spread DECIMAL(20, 8),            -- 스프레드 (ask1 - bid1)
    mid_price DECIMAL(20, 8),         -- 중간가
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_orderbook_symbol_time ON orderbook_snapshots (symbol, exchange, timestamp DESC);
```

### 5. trades (체결 내역)

```sql
CREATE TABLE trades (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(20) NOT NULL,
    
    trade_id VARCHAR(50),             -- 거래소 체결 ID
    price DECIMAL(20, 8) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    side VARCHAR(10) NOT NULL,        -- BUY, SELL (Taker 기준)
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_trades_symbol_time ON trades (symbol, exchange, timestamp DESC);
```

### 6. funding_rates (펀딩비)

```sql
CREATE TABLE funding_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(20) NOT NULL DEFAULT 'binance',
    
    funding_rate DECIMAL(20, 10) NOT NULL,  -- 펀딩비율
    mark_price DECIMAL(20, 8),              -- 마크 가격
    
    UNIQUE(timestamp, symbol, exchange)
);

CREATE INDEX idx_funding_symbol_time ON funding_rates (symbol, timestamp DESC);
```

### 7. orders (주문)

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

CREATE INDEX idx_orders_exchange_status ON orders (exchange, status);
CREATE INDEX idx_orders_strategy ON orders (strategy, created_at DESC);
```

### 8. fills (체결)

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

CREATE INDEX idx_fills_order_id ON fills (order_id);
CREATE INDEX idx_fills_filled_at ON fills (filled_at DESC);
```

### 9. positions (포지션)

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

CREATE INDEX idx_positions_exchange_symbol ON positions (exchange, symbol);
```

### 10. strategy_params (전략 파라미터)

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

### 11. backtest_results (백테스트 결과)

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

CREATE INDEX idx_backtest_strategy ON backtest_results (strategy, created_at DESC);
```

---

## 인덱스 전략

| 테이블 | 인덱스 | 용도 |
|:---|:---|:---|
| ohlcv | (symbol, timestamp DESC) | 심볼별 시계열 조회 |
| ohlcv | (exchange, symbol, timestamp DESC) | 거래소별 조회 |
| exchange_rates | (timestamp DESC) | 최신 환율 조회 |
| exchange_rates | (source, timestamp DESC) | 소스별 환율 조회 |
| kimp_rates | (timestamp DESC) | 최신 김프 조회 |
| orderbook_snapshots | (symbol, exchange, timestamp DESC) | 호가 조회 |
| orders | (exchange, status) | 상태별 주문 조회 |
| fills | (order_id) | 주문별 체결 조회 |
| positions | (exchange, symbol) | 포지션 조회 |

---

## 데이터 보존 정책

| 테이블 | 보존 기간 | 이유 |
|:---|:---|:---|
| ohlcv | 무기한 | 백테스트 핵심 데이터 |
| exchange_rates | 1년 | 김프 계산 검증 |
| kimp_rates | 무기한 | 전략 분석 |
| funding_rates | 무기한 | 비용 계산 |
| orderbook_snapshots | 90일 | 용량 큼 |
| trades | 30일 | 분석용 |

---

## 마이그레이션 (v1.0 → v2.0)

```sql
-- exchange_rates 테이블 업데이트
ALTER TABLE exchange_rates 
ADD COLUMN IF NOT EXISTS open DECIMAL(20, 8),
ADD COLUMN IF NOT EXISTS high DECIMAL(20, 8),
ADD COLUMN IF NOT EXISTS low DECIMAL(20, 8);

-- source 컬럼 기본값 변경
ALTER TABLE exchange_rates 
ALTER COLUMN source SET DEFAULT 'tradingview:FX_IDC:USDKRW';

-- kimp_rates에 rate_source 추가
ALTER TABLE kimp_rates 
ADD COLUMN IF NOT EXISTS rate_source VARCHAR(50) DEFAULT 'tradingview';

-- 새 인덱스 추가
CREATE INDEX IF NOT EXISTS idx_exchange_rate_source 
ON exchange_rates (source, timestamp DESC);
```

---

*— 스키마 문서 끝 —*
