-- seed.sql
-- 테스트용 초기 데이터

-- 김프 차익거래 전략 파라미터
INSERT INTO strategy_params (strategy, params, is_active) VALUES
('kimp_cash_carry', '{
    "entry_threshold": 0.03,
    "exit_threshold": 0.01,
    "position_size": 1.0,
    "max_position_ratio": 0.2,
    "stop_loss_pct": 0.05
}', true);

-- 테스트 주문 데이터
INSERT INTO orders (exchange, symbol, side, type, quantity, price, status, strategy) VALUES
('upbit', 'BTC', 'BUY', 'MARKET', 0.001, 130000000, 'FILLED', 'kimp_cash_carry'),
('binance', 'BTCUSDT', 'SELL', 'MARKET', 0.001, 100000, 'FILLED', 'kimp_cash_carry');
