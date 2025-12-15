-- ============================================
-- 006_create_views.sql
-- 모니터링 뷰
-- ============================================

-- ----------------------------------------
-- v_latest_kimp: 최신 김프 상태
-- ----------------------------------------
CREATE OR REPLACE VIEW v_latest_kimp AS
SELECT 
    k.timestamp,
    k.symbol,
    k.kimp_close,
    k.upbit_price,
    k.binance_price,
    k.exchange_rate,
    z.zscore,
    z.zscore_5m_min,
    b.bb_upper,
    b.bb_middle,
    b.bb_lower,
    b.is_upper_break
FROM kimp_1m k
LEFT JOIN LATERAL (
    SELECT zscore, zscore_5m_min
    FROM zscore_log 
    WHERE symbol = k.symbol 
    ORDER BY timestamp DESC 
    LIMIT 1
) z ON TRUE
LEFT JOIN LATERAL (
    SELECT bb_upper, bb_middle, bb_lower, is_upper_break
    FROM bb_log 
    WHERE symbol = k.symbol 
    ORDER BY timestamp DESC 
    LIMIT 1
) b ON TRUE
ORDER BY k.timestamp DESC
LIMIT 1;

-- ----------------------------------------
-- v_fx_filter_status: 환율 필터 상태
-- ----------------------------------------
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

-- ----------------------------------------
-- v_open_positions: 현재 오픈 포지션
-- ----------------------------------------
CREATE OR REPLACE VIEW v_open_positions AS
SELECT 
    p.id,
    p.symbol,
    p.entry_level,
    p.entry_timestamp,
    p.entry_kimp,
    p.entry_zscore,
    p.total_invested,
    p.upbit_amount,
    p.binance_amount,
    -- 보유 시간
    EXTRACT(EPOCH FROM (NOW() - p.entry_timestamp)) / 3600 AS holding_hours,
    -- 현재 상태 (조인)
    k.kimp_close AS current_kimp,
    (k.kimp_close - p.entry_kimp) AS kimp_change,
    z.zscore AS current_zscore,
    b.bb_upper AS current_bb_upper
FROM positions p
LEFT JOIN LATERAL (
    SELECT kimp_close FROM kimp_1m 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC LIMIT 1
) k ON TRUE
LEFT JOIN LATERAL (
    SELECT zscore FROM zscore_log 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC LIMIT 1
) z ON TRUE
LEFT JOIN LATERAL (
    SELECT bb_upper FROM bb_log 
    WHERE symbol = p.symbol 
    ORDER BY timestamp DESC LIMIT 1
) b ON TRUE
WHERE p.status = 'open';

-- ----------------------------------------
-- v_exit_reason_stats: 청산 사유별 통계
-- ----------------------------------------
CREATE OR REPLACE VIEW v_exit_reason_stats AS
SELECT 
    exit_reason,
    COUNT(*) AS trade_count,
    SUM(realized_pnl) AS total_pnl,
    ROUND(AVG(realized_pnl_pct)::NUMERIC, 4) AS avg_pnl_pct,
    ROUND(AVG(holding_hours)::NUMERIC, 2) AS avg_holding_hours,
    ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER(), 0), 2) AS pct_of_trades
FROM positions
WHERE status = 'closed' AND exit_reason IS NOT NULL
GROUP BY exit_reason
ORDER BY trade_count DESC;

-- ----------------------------------------
-- v_collection_stats: 수집 현황 통계
-- ----------------------------------------
CREATE OR REPLACE VIEW v_collection_stats AS
SELECT 
    'kimp_1m' AS table_name,
    COUNT(*) AS total_rows,
    MIN(timestamp) AS first_record,
    MAX(timestamp) AS last_record,
    COUNT(*) FILTER (WHERE timestamp > NOW() - INTERVAL '1 hour') AS last_hour
FROM kimp_1m
UNION ALL
SELECT 
    'fx_rates',
    COUNT(*),
    MIN(timestamp),
    MAX(timestamp),
    COUNT(*) FILTER (WHERE timestamp > NOW() - INTERVAL '1 hour')
FROM fx_rates
UNION ALL
SELECT 
    'zscore_log',
    COUNT(*),
    MIN(timestamp),
    MAX(timestamp),
    COUNT(*) FILTER (WHERE timestamp > NOW() - INTERVAL '1 hour')
FROM zscore_log
UNION ALL
SELECT 
    'bb_log',
    COUNT(*),
    MIN(timestamp),
    MAX(timestamp),
    COUNT(*) FILTER (WHERE timestamp > NOW() - INTERVAL '1 hour')
FROM bb_log;

-- ----------------------------------------
-- v_daily_kimp_summary: 일별 김프 요약
-- ----------------------------------------
CREATE OR REPLACE VIEW v_daily_kimp_summary AS
SELECT 
    DATE(timestamp) AS date,
    symbol,
    COUNT(*) AS candle_count,
    ROUND(AVG(kimp_close)::NUMERIC, 4) AS avg_kimp,
    ROUND(MIN(kimp_low)::NUMERIC, 4) AS min_kimp,
    ROUND(MAX(kimp_high)::NUMERIC, 4) AS max_kimp,
    ROUND(STDDEV(kimp_close)::NUMERIC, 4) AS kimp_volatility
FROM kimp_1m
GROUP BY DATE(timestamp), symbol
ORDER BY date DESC;

-- 코멘트
COMMENT ON VIEW v_latest_kimp IS '최신 김프 상태 + 지표 조인';
COMMENT ON VIEW v_fx_filter_status IS '현재 환율 필터 상태';
COMMENT ON VIEW v_open_positions IS '오픈 포지션 + 현재 시장 상태';
COMMENT ON VIEW v_collection_stats IS '데이터 수집 현황 모니터링';
