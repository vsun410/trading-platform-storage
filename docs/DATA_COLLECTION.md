# 📊 데이터 수집 시스템 명세서

**Repository:** trading-platform-storage  
**Version:** 1.0  
**Date:** 2025-12-11  
**Tech Stack:** CCXT + WebSocket + Supabase

---

## 1. 개요

### 1.1 목적

모든 레포에서 사용할 시장 데이터를 **자동으로 수집하고 저장**하는 시스템입니다.
Docker 컨테이너로 24/7 실행되며, 다른 레포(research, order, portfolio)에서 언제든 접근 가능합니다.

### 1.2 수집 대상 데이터

| 데이터 | 거래소 | 수집 방법 | 주기 | 용도 |
|--------|--------|-----------|------|------|
| **OHLCV** | 업비트, 바이낸스 | CCXT REST | 1분 | 백테스트, 신호 생성 |
| **Orderbook** | 업비트, 바이낸스 | WebSocket | 실시간 (100ms) | 슬리피지 계산, 스트레스 테스트 |
| **체결 (Trades)** | 업비트, 바이낸스 | WebSocket | 실시간 | 체결 강도 분석 |
| **펀딩비** | 바이낸스 선물 | CCXT REST | 8시간 | 비용 계산 |
| **환율** | 외부 API | REST | 1분 | 김프 계산 |
| **김프율** | 계산값 | 내부 | 1분 | 전략 신호 |

### 1.3 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                     DATA COLLECTOR SERVICE                      │
│                   (Docker Container - 24/7)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │   Upbit     │    │  Binance    │    │  Exchange   │        │
│   │  Collector  │    │  Collector  │    │    Rate     │        │
│   └──────┬──────┘    └──────┬──────┘    └──────┬──────┘        │
│          │                  │                  │                │
│          ▼                  ▼                  ▼                │
│   ┌─────────────────────────────────────────────────────┐      │
│   │              Data Normalizer & Calculator            │      │
│   │         (김프율 계산, 타임스탬프 정렬)                 │      │
│   └──────────────────────────┬──────────────────────────┘      │
│                              │                                  │
│                              ▼                                  │
│   ┌─────────────────────────────────────────────────────┐      │
│   │                   Supabase (PostgreSQL)              │      │
│   │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐ │      │
│   │  │  ohlcv  │ │orderbook│ │ trades  │ │funding_rate│ │      │
│   │  └─────────┘ └─────────┘ └─────────┘ └───────────┘ │      │
│   └─────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │         OTHER REPOSITORIES ACCESS        │
        ├─────────────────────────────────────────┤
        │  research  │  order  │  portfolio       │
        │  (읽기)    │ (읽기)  │  (읽기)          │
        └─────────────────────────────────────────┘
```

---

## 2. 데이터베이스 스키마 (추가)

### 2.1 orderbook_snapshots (호가 스냅샷)

```sql
CREATE TABLE orderbook_snapshots (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(20) NOT NULL,
    
    -- 매수 호가 (JSON 배열: [[price, quantity], ...])
    bids JSONB NOT NULL,
    -- 매도 호가
    asks JSONB NOT NULL,
    
    -- 메타데이터
    bid_total_volume DECIMAL(20, 8),  -- 총 매수 잔량
    ask_total_volume DECIMAL(20, 8),  -- 총 매도 잔량
    spread DECIMAL(20, 8),            -- 스프레드 (ask1 - bid1)
    mid_price DECIMAL(20, 8),         -- 중간가
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 시계열 조회용 인덱스
CREATE INDEX idx_orderbook_symbol_time 
ON orderbook_snapshots (symbol, exchange, timestamp DESC);

-- 파티셔닝 (일별) - 대용량 데이터 관리
-- Supabase에서는 pg_partman 또는 수동 파티셔닝 사용
```

### 2.2 trades (체결 내역)

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

CREATE INDEX idx_trades_symbol_time 
ON trades (symbol, exchange, timestamp DESC);
```

### 2.3 funding_rates (펀딩비)

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

CREATE INDEX idx_funding_symbol_time 
ON funding_rates (symbol, timestamp DESC);
```

### 2.4 exchange_rates (환율)

```sql
CREATE TABLE exchange_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    base_currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    quote_currency VARCHAR(10) NOT NULL DEFAULT 'KRW',
    
    rate DECIMAL(20, 8) NOT NULL,
    source VARCHAR(50),  -- 데이터 소스 (예: exchangerate-api)
    
    UNIQUE(timestamp, base_currency, quote_currency)
);

CREATE INDEX idx_exchange_rate_time 
ON exchange_rates (timestamp DESC);
```

### 2.5 kimp_rates (김프율)

```sql
CREATE TABLE kimp_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    upbit_price DECIMAL(20, 8) NOT NULL,      -- 업비트 가격 (KRW)
    binance_price DECIMAL(20, 8) NOT NULL,    -- 바이낸스 가격 (USDT)
    exchange_rate DECIMAL(20, 8) NOT NULL,    -- USD/KRW 환율
    
    kimp_rate DECIMAL(10, 4) NOT NULL,        -- 김프율 (%)
    
    -- 계산: (upbit - binance * rate) / (binance * rate) * 100
    
    UNIQUE(timestamp, symbol)
);

CREATE INDEX idx_kimp_time ON kimp_rates (timestamp DESC);
CREATE INDEX idx_kimp_symbol_time ON kimp_rates (symbol, timestamp DESC);
```

---

## 3. 수집 모듈 구조

### 3.1 디렉토리 구조

```
trading-platform-storage/
├── docker-compose.yml           # 전체 서비스 (DB + Collector)
├── .env.example
│
├── collector/                   # 🆕 데이터 수집 서비스
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                  # 진입점 (스케줄러)
│   │
│   ├── collectors/
│   │   ├── __init__.py
│   │   ├── base.py              # BaseCollector 추상 클래스
│   │   ├── upbit.py             # 업비트 수집기
│   │   ├── binance.py           # 바이낸스 수집기
│   │   ├── exchange_rate.py     # 환율 수집기
│   │   └── kimp.py              # 김프 계산기
│   │
│   ├── websocket/               # WebSocket 클라이언트
│   │   ├── __init__.py
│   │   ├── upbit_ws.py          # 업비트 WebSocket
│   │   ├── binance_ws.py        # 바이낸스 WebSocket
│   │   └── orderbook_manager.py # 로컬 호가창 관리
│   │
│   ├── storage/
│   │   ├── __init__.py
│   │   ├── supabase_client.py   # Supabase 연결
│   │   └── batch_writer.py      # 배치 저장 (성능 최적화)
│   │
│   └── config.py                # 설정
│
├── supabase/
│   ├── migrations/
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_add_indexes.sql
│   │   └── 003_add_collector_tables.sql  # 🆕
│   └── seed.sql
│
└── scripts/
    ├── backup.sh
    └── data_health_check.py     # 🆕 데이터 무결성 검사
```

### 3.2 핵심 클래스 설계

#### BaseCollector (추상 클래스)

```python
# collector/collectors/base.py

from abc import ABC, abstractmethod
from datetime import datetime
from typing import List, Dict, Any
import ccxt

class BaseCollector(ABC):
    """모든 수집기의 기본 클래스"""
    
    def __init__(self, exchange_id: str, symbols: List[str]):
        self.exchange_id = exchange_id
        self.symbols = symbols
        self.exchange = self._create_exchange()
    
    @abstractmethod
    def _create_exchange(self) -> ccxt.Exchange:
        """거래소 인스턴스 생성"""
        pass
    
    @abstractmethod
    async def fetch_ohlcv(self, symbol: str, timeframe: str = '1m', limit: int = 100) -> List[Dict]:
        """OHLCV 데이터 수집"""
        pass
    
    @abstractmethod
    async def fetch_orderbook(self, symbol: str, limit: int = 20) -> Dict:
        """호가 데이터 수집"""
        pass
    
    async def fetch_trades(self, symbol: str, limit: int = 100) -> List[Dict]:
        """체결 데이터 수집 (기본 구현)"""
        trades = await self.exchange.fetch_trades(symbol, limit=limit)
        return self._normalize_trades(trades)
    
    def _normalize_trades(self, trades: List) -> List[Dict]:
        """거래소별 데이터를 통일 형식으로 변환"""
        return [
            {
                'timestamp': trade['timestamp'],
                'symbol': trade['symbol'],
                'exchange': self.exchange_id,
                'trade_id': trade['id'],
                'price': trade['price'],
                'quantity': trade['amount'],
                'side': trade['side'].upper(),
            }
            for trade in trades
        ]
```

#### UpbitCollector

```python
# collector/collectors/upbit.py

import ccxt
from .base import BaseCollector

class UpbitCollector(BaseCollector):
    """업비트 데이터 수집기"""
    
    def __init__(self, symbols: List[str] = None):
        symbols = symbols or ['BTC/KRW', 'ETH/KRW']
        super().__init__('upbit', symbols)
    
    def _create_exchange(self) -> ccxt.Exchange:
        return ccxt.upbit({
            'enableRateLimit': True,
            'rateLimit': 100,  # 초당 10회 제한 준수
        })
    
    async def fetch_ohlcv(self, symbol: str, timeframe: str = '1m', limit: int = 100):
        ohlcv = await self.exchange.fetch_ohlcv(symbol, timeframe, limit=limit)
        return [
            {
                'timestamp': candle[0],
                'symbol': symbol.replace('/', '-'),  # BTC/KRW → BTC-KRW
                'exchange': 'upbit',
                'open': candle[1],
                'high': candle[2],
                'low': candle[3],
                'close': candle[4],
                'volume': candle[5],
            }
            for candle in ohlcv
        ]
    
    async def fetch_orderbook(self, symbol: str, limit: int = 15):
        """업비트 호가 (최대 15호가)"""
        orderbook = await self.exchange.fetch_order_book(symbol, limit)
        
        bids = [[float(b[0]), float(b[1])] for b in orderbook['bids'][:limit]]
        asks = [[float(a[0]), float(a[1])] for a in orderbook['asks'][:limit]]
        
        bid_total = sum(b[1] for b in bids)
        ask_total = sum(a[1] for a in asks)
        spread = asks[0][0] - bids[0][0] if bids and asks else 0
        mid_price = (asks[0][0] + bids[0][0]) / 2 if bids and asks else 0
        
        return {
            'timestamp': orderbook['timestamp'],
            'symbol': symbol.replace('/', '-'),
            'exchange': 'upbit',
            'bids': bids,
            'asks': asks,
            'bid_total_volume': bid_total,
            'ask_total_volume': ask_total,
            'spread': spread,
            'mid_price': mid_price,
        }
```

#### BinanceCollector

```python
# collector/collectors/binance.py

import ccxt
from .base import BaseCollector

class BinanceCollector(BaseCollector):
    """바이낸스 선물 데이터 수집기"""
    
    def __init__(self, symbols: List[str] = None):
        symbols = symbols or ['BTC/USDT', 'ETH/USDT']
        super().__init__('binance', symbols)
    
    def _create_exchange(self) -> ccxt.Exchange:
        return ccxt.binance({
            'enableRateLimit': True,
            'options': {
                'defaultType': 'future',  # 선물 모드
            }
        })
    
    async def fetch_ohlcv(self, symbol: str, timeframe: str = '1m', limit: int = 100):
        ohlcv = await self.exchange.fetch_ohlcv(symbol, timeframe, limit=limit)
        return [
            {
                'timestamp': candle[0],
                'symbol': symbol.replace('/', ''),  # BTC/USDT → BTCUSDT
                'exchange': 'binance',
                'open': candle[1],
                'high': candle[2],
                'low': candle[3],
                'close': candle[4],
                'volume': candle[5],
            }
            for candle in ohlcv
        ]
    
    async def fetch_funding_rate(self, symbol: str):
        """펀딩비 수집"""
        funding = await self.exchange.fetch_funding_rate(symbol)
        return {
            'timestamp': funding['timestamp'],
            'symbol': symbol.replace('/', ''),
            'exchange': 'binance',
            'funding_rate': funding['fundingRate'],
            'mark_price': funding.get('markPrice'),
        }
```

#### KimpCalculator

```python
# collector/collectors/kimp.py

from decimal import Decimal
from datetime import datetime

class KimpCalculator:
    """김프율 계산기"""
    
    @staticmethod
    def calculate(
        upbit_price: float,
        binance_price: float,
        exchange_rate: float
    ) -> dict:
        """
        김프율 계산
        
        공식: (업비트가격 - 바이낸스가격 × 환율) / (바이낸스가격 × 환율) × 100
        """
        binance_krw = binance_price * exchange_rate
        kimp_rate = ((upbit_price - binance_krw) / binance_krw) * 100
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'upbit_price': upbit_price,
            'binance_price': binance_price,
            'exchange_rate': exchange_rate,
            'kimp_rate': round(kimp_rate, 4),
        }
```

---

## 4. WebSocket 실시간 수집

### 4.1 업비트 WebSocket

```python
# collector/websocket/upbit_ws.py

import asyncio
import websockets
import json
import uuid
from typing import Callable, List

class UpbitWebSocket:
    """업비트 실시간 데이터 스트림"""
    
    URI = "wss://api.upbit.com/websocket/v1"
    
    def __init__(self, symbols: List[str], on_message: Callable):
        self.symbols = symbols  # ['KRW-BTC', 'KRW-ETH']
        self.on_message = on_message
        self.ws = None
    
    async def connect(self):
        """WebSocket 연결 및 구독"""
        async with websockets.connect(self.URI) as ws:
            self.ws = ws
            
            # 구독 요청
            subscribe = [
                {"ticket": str(uuid.uuid4())},
                {
                    "type": "orderbook",
                    "codes": self.symbols,
                    "isOnlyRealtime": True
                },
                {
                    "type": "trade",
                    "codes": self.symbols,
                    "isOnlyRealtime": True
                },
                {"format": "DEFAULT"}
            ]
            await ws.send(json.dumps(subscribe))
            
            # 메시지 수신 루프
            async for message in ws:
                data = json.loads(message)
                await self.on_message(data)
    
    async def reconnect(self, delay: int = 5):
        """재연결 로직"""
        while True:
            try:
                await self.connect()
            except Exception as e:
                print(f"WebSocket error: {e}, reconnecting in {delay}s...")
                await asyncio.sleep(delay)
```

### 4.2 바이낸스 WebSocket (Diff Depth 동기화)

```python
# collector/websocket/binance_ws.py

import asyncio
import websockets
import json
import aiohttp
from typing import Dict, List

class BinanceOrderbookManager:
    """
    바이낸스 로컬 호가창 관리
    
    Diff Depth 방식:
    1. REST로 초기 스냅샷 가져오기
    2. WebSocket으로 델타 업데이트 수신
    3. 로컬에서 호가창 동기화
    """
    
    REST_URL = "https://fapi.binance.com/fapi/v1/depth"
    WS_URL = "wss://fstream.binance.com/ws"
    
    def __init__(self, symbol: str = "btcusdt"):
        self.symbol = symbol.lower()
        self.orderbook: Dict = {'bids': {}, 'asks': {}}
        self.last_update_id = 0
        self.initialized = False
    
    async def initialize(self):
        """REST API로 초기 스냅샷 로드"""
        async with aiohttp.ClientSession() as session:
            url = f"{self.REST_URL}?symbol={self.symbol.upper()}&limit=100"
            async with session.get(url) as resp:
                data = await resp.json()
                
                self.orderbook['bids'] = {float(b[0]): float(b[1]) for b in data['bids']}
                self.orderbook['asks'] = {float(a[0]): float(a[1]) for a in data['asks']}
                self.last_update_id = data['lastUpdateId']
                self.initialized = True
    
    async def connect(self, on_update):
        """WebSocket 연결 및 델타 업데이트"""
        await self.initialize()
        
        stream = f"{self.symbol}@depth@100ms"
        url = f"{self.WS_URL}/{stream}"
        
        async with websockets.connect(url) as ws:
            async for message in ws:
                data = json.loads(message)
                
                # 동기화 검증
                if data['u'] <= self.last_update_id:
                    continue  # 이미 처리된 업데이트
                
                if not (data['U'] <= self.last_update_id + 1 <= data['u']):
                    # 동기화 실패 → 재초기화
                    await self.initialize()
                    continue
                
                # 델타 적용
                self._apply_delta(data)
                self.last_update_id = data['u']
                
                # 콜백
                await on_update(self.get_snapshot())
    
    def _apply_delta(self, data: Dict):
        """델타 업데이트 적용"""
        for bid in data['b']:
            price, qty = float(bid[0]), float(bid[1])
            if qty == 0:
                self.orderbook['bids'].pop(price, None)
            else:
                self.orderbook['bids'][price] = qty
        
        for ask in data['a']:
            price, qty = float(ask[0]), float(ask[1])
            if qty == 0:
                self.orderbook['asks'].pop(price, None)
            else:
                self.orderbook['asks'][price] = qty
    
    def get_snapshot(self, depth: int = 20) -> Dict:
        """현재 호가창 스냅샷 반환"""
        bids = sorted(self.orderbook['bids'].items(), reverse=True)[:depth]
        asks = sorted(self.orderbook['asks'].items())[:depth]
        
        return {
            'symbol': self.symbol.upper(),
            'exchange': 'binance',
            'bids': [[p, q] for p, q in bids],
            'asks': [[p, q] for p, q in asks],
            'last_update_id': self.last_update_id,
        }
```

---

## 5. 메인 스케줄러

```python
# collector/main.py

import asyncio
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from collectors.upbit import UpbitCollector
from collectors.binance import BinanceCollector
from collectors.exchange_rate import ExchangeRateCollector
from collectors.kimp import KimpCalculator
from websocket.upbit_ws import UpbitWebSocket
from websocket.binance_ws import BinanceOrderbookManager
from storage.supabase_client import SupabaseClient
from storage.batch_writer import BatchWriter

class DataCollectorService:
    """메인 데이터 수집 서비스"""
    
    def __init__(self):
        self.upbit = UpbitCollector(['BTC/KRW', 'ETH/KRW'])
        self.binance = BinanceCollector(['BTC/USDT', 'ETH/USDT'])
        self.exchange_rate = ExchangeRateCollector()
        self.kimp = KimpCalculator()
        
        self.db = SupabaseClient()
        self.batch_writer = BatchWriter(self.db, batch_size=100)
        
        self.scheduler = AsyncIOScheduler()
    
    async def collect_ohlcv(self):
        """1분마다 OHLCV 수집"""
        # 업비트
        for symbol in self.upbit.symbols:
            data = await self.upbit.fetch_ohlcv(symbol, '1m', limit=1)
            await self.batch_writer.add('ohlcv', data)
        
        # 바이낸스
        for symbol in self.binance.symbols:
            data = await self.binance.fetch_ohlcv(symbol, '1m', limit=1)
            await self.batch_writer.add('ohlcv', data)
    
    async def collect_funding_rate(self):
        """8시간마다 펀딩비 수집"""
        for symbol in self.binance.symbols:
            data = await self.binance.fetch_funding_rate(symbol)
            await self.db.insert('funding_rates', data)
    
    async def collect_exchange_rate(self):
        """1분마다 환율 수집"""
        data = await self.exchange_rate.fetch()
        await self.db.insert('exchange_rates', data)
    
    async def calculate_kimp(self):
        """1분마다 김프율 계산"""
        upbit_price = await self.upbit.fetch_ticker('BTC/KRW')
        binance_price = await self.binance.fetch_ticker('BTC/USDT')
        exchange_rate = await self.exchange_rate.get_latest()
        
        kimp_data = self.kimp.calculate(
            upbit_price['last'],
            binance_price['last'],
            exchange_rate
        )
        await self.db.insert('kimp_rates', kimp_data)
    
    async def on_orderbook_update(self, data: dict):
        """실시간 호가 업데이트 → 저장"""
        await self.batch_writer.add('orderbook_snapshots', data)
    
    def start(self):
        """서비스 시작"""
        # 스케줄 등록
        self.scheduler.add_job(self.collect_ohlcv, 'interval', minutes=1)
        self.scheduler.add_job(self.collect_exchange_rate, 'interval', minutes=1)
        self.scheduler.add_job(self.calculate_kimp, 'interval', minutes=1)
        self.scheduler.add_job(self.collect_funding_rate, 'interval', hours=8)
        
        self.scheduler.start()
        
        # WebSocket 시작 (별도 태스크)
        asyncio.create_task(self._start_websockets())
    
    async def _start_websockets(self):
        """WebSocket 스트림 시작"""
        upbit_ws = UpbitWebSocket(
            ['KRW-BTC', 'KRW-ETH'],
            self.on_orderbook_update
        )
        
        binance_manager = BinanceOrderbookManager('btcusdt')
        
        await asyncio.gather(
            upbit_ws.reconnect(),
            binance_manager.connect(self.on_orderbook_update),
        )


if __name__ == "__main__":
    service = DataCollectorService()
    service.start()
    
    # 이벤트 루프 유지
    asyncio.get_event_loop().run_forever()
```

---

## 6. Docker 설정

### 6.1 docker-compose.yml (업데이트)

```yaml
version: '3.8'

services:
  # Supabase (기존)
  supabase-db:
    image: supabase/postgres:15.1.0.117
    ports:
      - "54322:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - supabase-db:/var/lib/postgresql/data

  # 데이터 수집기 (신규)
  data-collector:
    build:
      context: ./collector
      dockerfile: Dockerfile
    depends_on:
      - supabase-db
    environment:
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_KEY=${SUPABASE_KEY}
      - UPBIT_API_KEY=${UPBIT_API_KEY}
      - UPBIT_SECRET_KEY=${UPBIT_SECRET_KEY}
      - BINANCE_API_KEY=${BINANCE_API_KEY}
      - BINANCE_SECRET_KEY=${BINANCE_SECRET_KEY}
    restart: always
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  supabase-db:
```

### 6.2 Collector Dockerfile

```dockerfile
# collector/Dockerfile

FROM python:3.11-slim

WORKDIR /app

# 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 복사
COPY . .

# 실행
CMD ["python", "main.py"]
```

### 6.3 Requirements

```txt
# collector/requirements.txt

ccxt==4.2.0
websockets==12.0
aiohttp==3.9.0
apscheduler==3.10.4
supabase==2.0.0
python-dotenv==1.0.0
```

---

## 7. 데이터 접근 가이드 (다른 레포용)

### 7.1 Research 레포에서 데이터 조회

```python
# research/src/data/storage_client.py

from supabase import create_client
import pandas as pd

class StorageClient:
    """Storage 레포 데이터 접근 클라이언트"""
    
    def __init__(self, url: str, key: str):
        self.client = create_client(url, key)
    
    def get_ohlcv(
        self, 
        symbol: str, 
        exchange: str,
        start_date: str, 
        end_date: str
    ) -> pd.DataFrame:
        """OHLCV 데이터 조회"""
        response = self.client.table('ohlcv') \
            .select('*') \
            .eq('symbol', symbol) \
            .eq('exchange', exchange) \
            .gte('timestamp', start_date) \
            .lte('timestamp', end_date) \
            .order('timestamp') \
            .execute()
        
        return pd.DataFrame(response.data)
    
    def get_kimp_history(
        self,
        start_date: str,
        end_date: str
    ) -> pd.DataFrame:
        """김프율 히스토리 조회"""
        response = self.client.table('kimp_rates') \
            .select('*') \
            .gte('timestamp', start_date) \
            .lte('timestamp', end_date) \
            .order('timestamp') \
            .execute()
        
        return pd.DataFrame(response.data)
    
    def get_orderbook_snapshots(
        self,
        symbol: str,
        exchange: str,
        start_time: str,
        end_time: str,
        limit: int = 1000
    ) -> pd.DataFrame:
        """호가 스냅샷 조회 (스트레스 테스트용)"""
        response = self.client.table('orderbook_snapshots') \
            .select('*') \
            .eq('symbol', symbol) \
            .eq('exchange', exchange) \
            .gte('timestamp', start_time) \
            .lte('timestamp', end_time) \
            .order('timestamp') \
            .limit(limit) \
            .execute()
        
        return pd.DataFrame(response.data)
```

---

## 8. 데이터 보존 정책

### 8.1 보존 기간

| 데이터 | 보존 기간 | 이유 |
|--------|-----------|------|
| OHLCV (1분) | **무기한** | 백테스트 핵심 데이터 |
| 김프율 | **무기한** | 전략 신호 분석 |
| 펀딩비 | **무기한** | 비용 계산 |
| 호가 스냅샷 | **90일** | 용량 큼, 최근 데이터만 필요 |
| 체결 내역 | **30일** | 분석용, 장기 보관 불필요 |

### 8.2 자동 정리 스크립트

```sql
-- 90일 이상 된 호가 데이터 삭제
DELETE FROM orderbook_snapshots 
WHERE timestamp < NOW() - INTERVAL '90 days';

-- 30일 이상 된 체결 데이터 삭제
DELETE FROM trades 
WHERE timestamp < NOW() - INTERVAL '30 days';
```

---

## 9. 모니터링

### 9.1 수집 상태 확인 쿼리

```sql
-- 최근 1시간 데이터 수집 현황
SELECT 
    exchange,
    symbol,
    COUNT(*) as count,
    MAX(timestamp) as latest
FROM ohlcv
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY exchange, symbol;

-- 김프율 최신값
SELECT * FROM kimp_rates 
ORDER BY timestamp DESC 
LIMIT 1;
```

### 9.2 Discord 알림 (선택)

```python
# 수집 실패 시 Discord 알림
async def alert_collection_failure(error: str):
    webhook_url = os.getenv('DISCORD_WEBHOOK')
    async with aiohttp.ClientSession() as session:
        await session.post(webhook_url, json={
            'content': f'⚠️ 데이터 수집 오류: {error}'
        })
```

---

*— 문서 끝 —*
