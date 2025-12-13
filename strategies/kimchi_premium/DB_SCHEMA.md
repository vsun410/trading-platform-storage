# 🗄️ 김프 전략 데이터베이스 스키마 (Ver 3.0)

## 1. 스키마 개요

### 1.1 테이블 구조

```
┌─────────────────────────────────────────────────────────────────────┐
│                      김프 전략 DB 스키마 (Ver 3.0)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│   │ kimp_ticks  │     │  kimp_1m    │     │ fx_rates    │ [NEW]     │
│   │ (실시간)     │ →   │  (1분봉)    │     │ (환율)      │           │
│   └─────────────┘     └─────────────┘     └─────────────┘           │
│                           │                      │                    │
│                           ▼                      ▼                    │
│                    ┌─────────────┐        ┌─────────────┐           │
│                    │ zscore_log  │        │ fx_filter   │ [NEW]     │
│                    │ (Z-Score)   │        │ (환율필터)  │           │
│                    └─────────────┘        └─────────────┘           │
│                           │                                          │
│                           ▼                                          │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│   │ positions   │ ←   │  trades     │     │ bb_log      │ [NEW]     │
│   │ (포지션)    │     │ (거래기록)  │     │ (볼린저)    │           │
│   └─────────────┘     └─────────────┘     └─────────────┘           │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 테이블 목록

| 테이블 | 설명 | 버전 | 예상 용량 |
|:---|:---|:---|:---|
| `kimp_ticks` | 실시간 김프 데이터 | 1.0 | ~10GB/년 |
| `kimp_1m` | 1분봉 집계 데이터 | 1.0 | ~500MB/년 |
| `fx_rates` | TradingView 환율 데이터 | **3.0** | ~200MB/년 |
| `fx_filter_log` | 환율 필터 상태 로그 | **3.0** | ~50MB/년 |
| `zscore_log` | Z-Score 계산 로그 | 1.0 | ~100MB/년 |
| `bb_log` | 볼린저 밴드 로그 | **3.0** | ~100MB/년 |
| `positions` | 현재 포지션 | 1.0→**3.0** | ~1MB |
| `trades` | 거래 기록 | 1.0 | ~10MB/년 |
| `orders` | 주문 기록 | 1.0 | ~20MB/년 |

---

## 2. 신규 테이블 (Ver 3.0)

### 2.1 fx_rates (TradingView 환율 데이터)

```sql
CREATE TABLE fx_rates (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    
    -- TradingView 심볼
    symbol          VARCHAR(30) NOT NULL DEFAULT 'FX_IDC:USDKRW',
    
    -- 환율 데이터
    rate            DECIMAL(10, 4) NOT NULL,  -- USD/KRW
    
    -- 이동평균 (12시간 = 720분)
    ma_12h          DECIMAL(10, 4),
    
    -- 데이터 소스 메타
    source          VARCHAR(20) NOT NULL DEFAULT 'TradingView',
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(symbol, timestamp)
);

-- 인덱스
CREATE INDEX idx_fx_rates_timestamp ON fx_rates(timestamp DESC);
CREATE INDEX idx_fx_rates_symbol_ts ON fx_rates(symbol, timestamp DESC);

-- 파티셔닝 (월별)
-- CREATE TABLE fx_rates_2025_12 PARTITION OF fx_rates
--     FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
```

### 2.2 fx_filter_log (환율 필터 상태)

```sql
CREATE TABLE fx_filter_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    
    -- 현재 환율 상태
    current_rate    DECIMAL(10, 4) NOT NULL,
    ma_12h          DECIMAL(10, 4) NOT NULL,
    threshold       DECIMAL(10, 4) NOT NULL,  -- ma_12h * 1.001
    
    -- 필터 결과
    is_blocked      BOOLEAN NOT NULL,  -- TRUE = 진입 차단
    surge_pct       DECIMAL(10, 4),    -- 급등률 (%)
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_fx_filter_timestamp ON fx_filter_log(timestamp DESC);
CREATE INDEX idx_fx_filter_blocked ON fx_filter_log(is_blocked, timestamp DESC);
```

### 2.3 bb_log (볼린저 밴드 로그)

```sql
CREATE TABLE bb_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- 볼린저 밴드 값 (김프 % 기반)
    bb_upper        DECIMAL(10, 4) NOT NULL,
    bb_middle       DECIMAL(10, 4) NOT NULL,
    bb_lower        DECIMAL(10, 4) NOT NULL,
    
    -- 현재 김프
    kimp_current    DECIMAL(10, 4) NOT NULL,
    
    -- 돌파 상태
    is_upper_break  BOOLEAN DEFAULT FALSE,  -- 상단 돌파 여부
    is_lower_break  BOOLEAN DEFAULT FALSE,  -- 하단 돌파 여부
    
    -- 파라미터
    period          INTEGER NOT NULL DEFAULT 20,
    std_mult        DECIMAL(4, 2) NOT NULL DEFAULT 2.0,
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_bb_log_timestamp ON bb_log(timestamp DESC);
CREATE INDEX idx_bb_log_upper_break ON bb_log(is_upper_break, timestamp DESC);
```

---

## 3. 수정된 테이블 (Ver 3.0)

### 3.1 positions (exit_reason 필드 추가)

```sql
-- 기존 테이블에 Ver 3.0 필드 추가
ALTER TABLE positions 
ADD COLUMN IF NOT EXISTS exit_reason VARCHAR(20);

-- exit_reason 값:
-- 'Target'    : Track A - 정상 목표가(0.7%) 도달
-- 'Breakout'  : Track B - BB 상단 돌파 + 0.48% 이상

-- 전체 스키마
CREATE TABLE positions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    
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
    
    -- 청산 정보 (Ver 3.0 업데이트)
    exit_timestamp  TIMESTAMPTZ,
    exit_kimp       DECIMAL(10, 4),
    exit_reason     VARCHAR(20),  -- 'Target' or 'Breakout' [NEW]
    exit_bb_upper   DECIMAL(10, 4),  -- 청산 시점 BB 상단 [NEW]
    
    -- 손익
    realized_pnl    DECIMAL(20, 2),
    realized_pnl_pct DECIMAL(10, 4),
    
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- exit_reason 인덱스
CREATE INDEX idx_positions_exit_reason ON positions(exit_reason);
```

### 3.2 zscore_log (5분 lookback 추가)

```sql
-- 기존 테이블에 5분 최저 Z-Score 필드 추가
ALTER TABLE zscore_log 
ADD COLUMN IF NOT EXISTS zscore_5m_min DECIMAL(10, 4);

-- 전체 스키마
CREATE TABLE zscore_log (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL,
    symbol          VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    -- Z-Score 계산값
    kimp_current    DECIMAL(10, 4) NOT NULL,
    kimp_mean       DECIMAL(10, 4) NOT NULL,
    kimp_std        DECIMAL(10, 4) NOT NULL,
    zscore          DECIMAL(10, 4) NOT NULL,
    
    -- 5분 Lookback 최저값 (Ver 3.0)
    zscore_5m_min   DECIMAL(10, 4),  -- 최근 5분간 최저 Z-Score
    
    -- 파라미터
    window_size     INTEGER NOT NULL DEFAULT 20,
    
    -- 신호 상태
    level1_triggered BOOLEAN DEFAULT FALSE,
    level2_triggered BOOLEAN DEFAULT FALSE,
    
    -- 회귀 감지 (Ver 3.0)
    level1_reversion BOOLEAN DEFAULT FALSE,  -- -2.0 회귀 발생
    level2_reversion BOOLEAN DEFAULT FALSE,  -- -2.5 회귀 발생
    
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_zscore_log_timestamp ON zscore_log(timestamp DESC);
CREATE INDEX idx_zscore_log_zscore ON zscore_log(zscore);
CREATE INDEX idx_zscore_log_reversion ON zscore_log(level1_reversion, level2_reversion);
```

---

## 4. 기존 테이블 (변경 없음)

### 4.1 kimp_ticks (실시간 데이터)

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
```

### 4.2 kimp_1m (1분봉 데이터)

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

### 4.3 trades (거래 기록)

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

---

## 5. 뷰 (Views)

### 5.1 현재 포지션 + 탈출 조건 모니터링 (Ver 3.0)

```sql
CREATE OR REPLACE VIEW v_position_exit_status AS
SELECT 
    p.*,
    k.kimp_close AS current_kimp,
    z.zscore AS current_zscore,
    b.bb_upper AS current_bb_upper,
    
    -- 수익률 계산
    (k.kimp_close - p.entry_kimp) AS kimp_change,
    
    -- Track A: 정상 익절 조건
    CASE 
        WHEN (k.kimp_close - p.entry_kimp) >= 0.7 THEN TRUE 
        ELSE FALSE 
    END AS target_exit_ready,
    
    -- Track B: Breakout 탈출 조건
    CASE 
        WHEN (k.kimp_close - p.entry_kimp) >= 0.48 
             AND k.kimp_close > b.bb_upper THEN TRUE 
        ELSE FALSE 
    END AS breakout_exit_ready

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
LEFT JOIN LATERAL (
    SELECT bb_upper 
    FROM bb_log 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC 
    LIMIT 1
) b ON TRUE
WHERE p.status = 'open';
```

### 5.2 환율 필터 상태 모니터링

```sql
CREATE OR REPLACE VIEW v_fx_filter_status AS
SELECT 
    f.timestamp,
    f.current_rate,
    f.ma_12h,
    f.threshold,
    f.is_blocked,
    f.surge_pct,
    CASE 
        WHEN f.is_blocked THEN '🚫 진입 차단'
        ELSE '✅ 진입 가능'
    END AS status_text
FROM fx_filter_log f
ORDER BY f.timestamp DESC
LIMIT 1;
```

### 5.3 청산 이유별 통계

```sql
CREATE OR REPLACE VIEW v_exit_reason_stats AS
SELECT 
    exit_reason,
    COUNT(*) AS trade_count,
    SUM(realized_pnl) AS total_pnl,
    AVG(realized_pnl_pct) AS avg_pnl_pct,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_trades
FROM positions
WHERE status = 'closed' AND exit_reason IS NOT NULL
GROUP BY exit_reason
ORDER BY trade_count DESC;
```

---

## 6. 함수 (Functions)

### 6.1 환율 급등 체크 함수 (Ver 3.0)

```sql
CREATE OR REPLACE FUNCTION check_fx_surge(
    p_current_rate DECIMAL,
    p_ma_12h DECIMAL,
    p_threshold DECIMAL DEFAULT 1.001
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_current_rate > (p_ma_12h * p_threshold);
END;
$$ LANGUAGE plpgsql;

-- 사용 예시
-- SELECT check_fx_surge(1350.0, 1345.0, 1.001);  -- TRUE (차단)
```

### 6.2 볼린저 밴드 상단 돌파 체크

```sql
CREATE OR REPLACE FUNCTION check_bb_breakout(
    p_current_kimp DECIMAL,
    p_bb_upper DECIMAL,
    p_entry_kimp DECIMAL,
    p_min_profit DECIMAL DEFAULT 0.48
) RETURNS BOOLEAN AS $$
BEGIN
    -- 조건 1: 최소 마진 확보
    -- 조건 2: BB 상단 돌파
    RETURN (p_current_kimp - p_entry_kimp) >= p_min_profit 
           AND p_current_kimp > p_bb_upper;
END;
$$ LANGUAGE plpgsql;
```

---

## 7. 마이그레이션 스크립트

### 7.1 Ver 2.0 → Ver 3.0 마이그레이션

```sql
-- 1. 신규 테이블 생성
CREATE TABLE IF NOT EXISTS fx_rates (...);
CREATE TABLE IF NOT EXISTS fx_filter_log (...);
CREATE TABLE IF NOT EXISTS bb_log (...);

-- 2. positions 테이블 필드 추가
ALTER TABLE positions 
ADD COLUMN IF NOT EXISTS exit_reason VARCHAR(20),
ADD COLUMN IF NOT EXISTS exit_bb_upper DECIMAL(10, 4),
ADD COLUMN IF NOT EXISTS entry_fx_rate DECIMAL(10, 4),
ADD COLUMN IF NOT EXISTS entry_fx_ma DECIMAL(10, 4);

-- 3. zscore_log 테이블 필드 추가
ALTER TABLE zscore_log 
ADD COLUMN IF NOT EXISTS zscore_5m_min DECIMAL(10, 4),
ADD COLUMN IF NOT EXISTS level1_reversion BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS level2_reversion BOOLEAN DEFAULT FALSE;

-- 4. 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_positions_exit_reason ON positions(exit_reason);
CREATE INDEX IF NOT EXISTS idx_zscore_log_reversion ON zscore_log(level1_reversion, level2_reversion);

-- 5. 뷰 재생성
DROP VIEW IF EXISTS v_position_exit_status;
CREATE VIEW v_position_exit_status AS ...;
```

---

**버전**: 3.0  
**작성일**: 2025-12-14  
**레포**: trading-platform-storage
