# 🗄️ 김프 전략 데이터베이스 스키마 (Database Schema)

## 1. 스키마 개요

### 1.1 테이블 구조

```
┌─────────────────────────────────────────────────────┐
│                   김프 전략 DB 스키마                  │
├─────────────────────────────────────────────────────┤
│                                                     │
│   ┌─────────────┐     ┌─────────────┐              │
│   │ kimp_ticks  │     │ kimp_1m     │              │
│   │ (실시간)     │ →   │ (1분봉)     │              │
│   └─────────────┘     └─────────────┘              │
│                           │                         │
│                           ▼                         │
│                    ┌─────────────┐                  │
│                    │ zscore_log │                  │
│                    │ (Z-Score)  │                  │
│                    └─────────────┘                  │
│                           │                         │
│                           ▼                         │
│   ┌─────────────┐     ┌─────────────┐              │
│   │ positions   │ ←   │ trades      │              │
│   │ (포지션)    │     │ (거래기록)  │              │
│   └─────────────┘     └─────────────┘              │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 1.2 테이블 목록

| 테이블 | 설명 | 예상 용량 |
|:---|:---|:---|
| `kimp_ticks` | 실시간 김프 데이터 | ~10GB/년 |
| `kimp_1m` | 1분봄 집계 데이터 | ~500MB/년 |
| `zscore_log` | Z-Score 계산 로그 | ~100MB/년 |
| `positions` | 현재 포지션 | ~1MB |
| `trades` | 거래 기록 | ~10MB/년 |
| `orders` | 주문 기록 | ~20MB/년 |

## 2. 테이블 상세 스키마

### 2.1 kimp_ticks (실시간 데이터)

```sql
CREATE TABLE kimp_ticks (
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
CREATE INDEX idx_kimp_ticks_timestamp ON kimp_ticks(timestamp DESC);
CREATE INDEX idx_kimp_ticks_symbol_ts ON kimp_ticks(symbol, timestamp DESC);

-- Supabase RLS
ALTER TABLE kimp_ticks ENABLE ROW LEVEL SECURITY;
```

### 2.2 kimp_1m (1분봄 데이터)

```sql
CREATE TABLE kimp_1m (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- OHLC
    kimp_open       DECIMAL(10, 4) NOT NULL,
    kimp_high       DECIMAL(10, 4) NOT NULL,
    kimp_low        DECIMAL(10, 4) NOT NULL,
    kimp_close      DECIMAL(10, 4) NOT NULL,
    
    -- 평균 가격
    upbit_avg       DECIMAL(20, 2) NOT NULL,
    binance_avg     DECIMAL(20, 8) NOT NULL,
    exchange_rate   DECIMAL(10, 4) NOT NULL,
    
    -- 거래량
    volume          DECIMAL(20, 8),
    tick_count      INTEGER,
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(symbol, timestamp)
);

-- 인덱스
CREATE INDEX idx_kimp_1m_timestamp ON kimp_1m(timestamp DESC);
CREATE INDEX idx_kimp_1m_symbol_ts ON kimp_1m(symbol, timestamp DESC);
```

### 2.3 zscore_log (Z-Score 로그)

```sql
CREATE TABLE zscore_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- Z-Score 계산값
    kimp_current    DECIMAL(10, 4) NOT NULL,
    kimp_mean       DECIMAL(10, 4) NOT NULL,
    kimp_std        DECIMAL(10, 4) NOT NULL,
    zscore          DECIMAL(10, 4) NOT NULL,
    
    -- 파라미터
    window_size     INTEGER NOT NULL DEFAULT 20,
    
    -- 신호 상태
    level1_triggered BOOLEAN DEFAULT FALSE,
    level2_triggered BOOLEAN DEFAULT FALSE,
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_zscore_log_timestamp ON zscore_log(timestamp DESC);
CREATE INDEX idx_zscore_log_zscore ON zscore_log(zscore);
```

### 2.4 positions (포지션)

```sql
CREATE TABLE positions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    
    -- 진입 정보
    entry_level     VARCHAR(10) NOT NULL,  -- 'level1', 'level2', 'combined'
    entry_timestamp TIMESTAMPTZ NOT NULL,
    entry_kimp      DECIMAL(10, 4) NOT NULL,
    entry_zscore    DECIMAL(10, 4) NOT NULL,
    
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
    
    -- 청산 정보 (nullable)
    exit_timestamp  TIMESTAMPTZ,
    exit_kimp       DECIMAL(10, 4),
    exit_reason     VARCHAR(50),
    
    -- 손익
    realized_pnl    DECIMAL(20, 2),
    realized_pnl_pct DECIMAL(10, 4),
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_positions_status ON positions(status);
CREATE INDEX idx_positions_symbol ON positions(symbol, status);
```

### 2.5 trades (거래 기록)

```sql
CREATE TABLE trades (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id     UUID REFERENCES positions(id),
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 거래 유형
    trade_type      VARCHAR(10) NOT NULL,  -- 'entry', 'exit', 'rollback'
    side            VARCHAR(10) NOT NULL,  -- 'buy', 'sell'
    exchange        VARCHAR(20) NOT NULL,  -- 'upbit', 'binance'
    
    -- 주문 정보
    order_id        VARCHAR(100),
    order_type      VARCHAR(20) NOT NULL,  -- 'market', 'limit'
    
    -- 체결 정보
    amount          DECIMAL(20, 8) NOT NULL,
    price           DECIMAL(20, 8) NOT NULL,
    filled_amount   DECIMAL(20, 8) NOT NULL,
    avg_price       DECIMAL(20, 8) NOT NULL,
    
    -- 비용
    fee             DECIMAL(20, 8),
    fee_currency    VARCHAR(10),
    
    -- 상태
    status          VARCHAR(20) NOT NULL,  -- 'pending', 'filled', 'canceled', 'failed'
    error_message   TEXT,
    
    executed_at     TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_trades_position_id ON trades(position_id);
CREATE INDEX idx_trades_executed_at ON trades(executed_at DESC);
CREATE INDEX idx_trades_exchange ON trades(exchange, executed_at DESC);
```

### 2.6 orders (주문 기록)

```sql
CREATE TABLE orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id     UUID REFERENCES positions(id),
    
    -- 거래소 주문 ID
    exchange        VARCHAR(20) NOT NULL,
    exchange_order_id VARCHAR(100) NOT NULL,
    
    -- 주문 정보
    symbol          VARCHAR(20) NOT NULL,
    side            VARCHAR(10) NOT NULL,
    order_type      VARCHAR(20) NOT NULL,
    amount          DECIMAL(20, 8) NOT NULL,
    price           DECIMAL(20, 8),
    
    -- 체결 정보
    filled_amount   DECIMAL(20, 8) DEFAULT 0,
    avg_price       DECIMAL(20, 8),
    fee             DECIMAL(20, 8),
    
    -- 상태
    status          VARCHAR(20) NOT NULL,
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_orders_exchange_id ON orders(exchange, exchange_order_id);
CREATE INDEX idx_orders_position_id ON orders(position_id);
```

## 3. 뷰 (Views)

### 3.1 현재 포지션 요약

```sql
CREATE VIEW v_current_positions AS
SELECT 
    p.*,
    k.kimp_close AS current_kimp,
    z.zscore AS current_zscore,
    (k.kimp_close - p.entry_kimp) AS kimp_change,
    ((k.kimp_close - p.entry_kimp) / p.entry_kimp * 100) AS kimp_change_pct
FROM positions p
LEFT JOIN LATERAL (
    SELECT kimp_close 
    FROM kimp_1m 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC 
    LIMIT 1
) k ON TRUE
LEFT JOIN LATERAL (
    SELECT zscore 
    FROM zscore_log 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC 
    LIMIT 1
) z ON TRUE
WHERE p.status = 'open';
```

### 3.2 일별 성과 요약

```sql
CREATE VIEW v_daily_performance AS
SELECT 
    DATE(exit_timestamp) AS trade_date,
    COUNT(*) AS trade_count,
    SUM(CASE WHEN realized_pnl > 0 THEN 1 ELSE 0 END) AS win_count,
    SUM(CASE WHEN realized_pnl < 0 THEN 1 ELSE 0 END) AS loss_count,
    SUM(realized_pnl) AS total_pnl,
    AVG(realized_pnl_pct) AS avg_pnl_pct,
    MAX(realized_pnl_pct) AS best_trade_pct,
    MIN(realized_pnl_pct) AS worst_trade_pct
FROM positions
WHERE status = 'closed'
GROUP BY DATE(exit_timestamp)
ORDER BY trade_date DESC;
```

## 4. 함수 (Functions)

### 4.1 김프 계산 함수

```sql
CREATE OR REPLACE FUNCTION calculate_kimp(
    p_upbit_price DECIMAL,
    p_binance_price DECIMAL,
    p_exchange_rate DECIMAL
) RETURNS DECIMAL AS $$
BEGIN
    RETURN ((p_upbit_price / (p_binance_price * p_exchange_rate)) - 1) * 100;
END;
$$ LANGUAGE plpgsql;
```

### 4.2 Z-Score 계산 함수

```sql
CREATE OR REPLACE FUNCTION calculate_zscore(
    p_symbol VARCHAR,
    p_window INTEGER DEFAULT 20
) RETURNS TABLE (
    current_kimp DECIMAL,
    mean_kimp DECIMAL,
    std_kimp DECIMAL,
    zscore DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    WITH recent_data AS (
        SELECT kimp_close
        FROM kimp_1m
        WHERE symbol = p_symbol
        ORDER BY timestamp DESC
        LIMIT p_window
    )
    SELECT 
        (SELECT kimp_close FROM recent_data LIMIT 1),
        AVG(kimp_close),
        STDDEV(kimp_close),
        CASE 
            WHEN STDDEV(kimp_close) = 0 THEN 0
            ELSE ((SELECT kimp_close FROM recent_data LIMIT 1) - AVG(kimp_close)) / STDDEV(kimp_close)
        END
    FROM recent_data;
END;
$$ LANGUAGE plpgsql;
```

## 5. Supabase 설정

### 5.1 RLS 정책

```sql
-- kimp_ticks: 인증된 사용자만 조회
CREATE POLICY "kimp_ticks_select" ON kimp_ticks
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- positions: 소유자만 접근
CREATE POLICY "positions_all" ON positions
    FOR ALL
    USING (auth.uid() = user_id);
```

### 5.2 실시간 구독

```sql
-- Realtime 활성화
ALTER PUBLICATION supabase_realtime ADD TABLE zscore_log;
ALTER PUBLICATION supabase_realtime ADD TABLE positions;
```

## 6. 마이그레이션

### 6.1 초기 마이그레이션

```bash
# Supabase CLI
supabase migration new create_kimp_tables

# 마이그레이션 실행
supabase db push
```

### 6.2 데이터 리텐션

```sql
-- 90일 이상 오래된 tick 데이터 삭제
DELETE FROM kimp_ticks 
WHERE timestamp < NOW() - INTERVAL '90 days';

-- 1년 이상 오래된 1분봄 데이터 아카이브
INSERT INTO kimp_1m_archive 
SELECT * FROM kimp_1m 
WHERE timestamp < NOW() - INTERVAL '1 year';
```

---

**작성일**: 2025-12-11  
**버전**: 1.0  
**레포**: trading-platform-storage
