# 📊 데이터 수집 시스템 명세서

**Repository:** trading-platform-storage  
**Version:** 2.0  
**Date:** 2025-12-12  
**Tech Stack:** CCXT + WebSocket + TradingView Webhook + Supabase

---

## 1. 개요

### 1.1 목적

모든 레포에서 사용할 시장 데이터를 **자동으로 수집하고 저장**하는 시스템입니다.
Docker 컨테이너로 24/7 실행되며, 다른 레포(research, order, portfolio)에서 언제든 접근 가능합니다.

### 1.2 수집 대상 데이터

| 데이터 | 거래소/소스 | 수집 방법 | 주기 | 용도 |
|--------|------------|-----------|------|------|
| **OHLCV** | 업비트, 바이낸스 | CCXT REST | 1분 | 백테스트, 신호 생성 |
| **Orderbook** | 업비트, 바이낸스 | WebSocket | 실시간 (100ms) | 슬리피지 계산, 스트레스 테스트 |
| **체결 (Trades)** | 업비트, 바이낸스 | WebSocket | 실시간 | 체결 강도 분석 |
| **펀딩비** | 바이낸스 선물 | CCXT REST | 8시간 | 비용 계산 |
| **환율** | **TradingView** | **Webhook** | **1분** | 김프 계산 (핵심) |
| **김프율** | 계산값 | 내부 | 1분 | 전략 신호 |

### 1.3 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                     DATA COLLECTOR SERVICE                      │
│                   (Docker Container - 24/7)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐    │
│   │   Upbit     │    │  Binance    │    │   TradingView   │    │
│   │  Collector  │    │  Collector  │    │ Webhook Receiver│    │
│   │  (CCXT/WS)  │    │  (CCXT/WS)  │    │   (FastAPI)     │    │
│   └──────┬──────┘    └──────┬──────┘    └────────┬────────┘    │
│          │                  │                    │              │
│          │                  │                    │              │
│          ▼                  ▼                    ▼              │
│   ┌─────────────────────────────────────────────────────┐      │
│   │              Data Normalizer & Calculator            │      │
│   │         (김프율 계산, 타임스탬프 정렬)                 │      │
│   └──────────────────────────┬──────────────────────────┘      │
│                              │                                  │
│                              ▼                                  │
│   ┌─────────────────────────────────────────────────────┐      │
│   │                   Supabase (PostgreSQL)              │      │
│   │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐ │      │
│   │  │  ohlcv  │ │orderbook│ │exchange │ │ kimp_rates│ │      │
│   │  │         │ │         │ │ _rates  │ │           │ │      │
│   │  └─────────┘ └─────────┘ └─────────┘ └───────────┘ │      │
│   └─────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
        ▼                                           ▼
┌───────────────────┐                    ┌───────────────────┐
│  TradingView      │                    │  OTHER REPOS      │
│  Pine Script      │────Webhook────────▶│  research/order/  │
│  (FX_IDC:USDKRW)  │    POST            │  portfolio        │
└───────────────────┘                    └───────────────────┘
```

---

## 2. 환율 데이터 수집 (TradingView Webhook)

### 2.1 왜 TradingView Webhook인가?

| 방법 | 1분봉 | 안정성 | 법적 리스크 | 비용 | 선택 |
|------|------|-------|-----------|------|------|
| 한국수출입은행 | ❌ 1일 1회 | 🟢 | 🟢 | 무료 | ❌ |
| OANDA API | ✅ | 🟢 | 🟢 | $199-1,499/월 | ❌ |
| **TradingView Webhook** | ✅ | 🟢 | 🟢 | **$56/월 (Premium)** | ✅ |
| 비공식 WebSocket | ✅ | 🟡 | 🟡 ToS 위반 | 무료 | ❌ |

**TradingView Premium 장점:**
- Alert 400개 (환율 외 다른 알림도 활용 가능)
- Alert **만료 없음** (무기한 운영)
- Webhook 지원
- FX_IDC:USDKRW (ICE 복합 데이터) 접근
- **이미 구독 중** → 추가 비용 없음

### 2.2 TradingView FX 데이터 소스

| 심볼 | 데이터 제공자 | 특징 | 권장 |
|------|-------------|------|------|
| **FX_IDC:USDKRW** | ICE (복합) | 수십 개 기여자 통합, 최고 신뢰도 | ✅ 사용 |
| OANDA:USDKRW | OANDA 브로커 | 자체 거래량 기반 | 백업용 |
| FOREXCOM:USDKRW | Forex.com | 볼륨 없음 | ❌ |
| FX:USDKRW | 표준 FX | 제한적 | ❌ |

### 2.3 Pine Script (TradingView에서 실행)

```pinescript
//@version=6
indicator("KRW/USD Webhook Sender for Kimp Trading", overlay=true)

// ============================================
// 📊 김프 트레이딩용 환율 데이터 전송기
// TradingView Premium 계정 필요
// 심볼: FX_IDC:USDKRW (1분봉 차트에서 실행)
// ============================================

// 봉 마감 시에만 전송 (중복 방지)
if barstate.isconfirmed
    // JSON 페이로드 구성
    payload = '{' +
        '"symbol":"' + syminfo.ticker + '",' +
        '"exchange":"' + syminfo.prefix + '",' +
        '"time":"' + str.format("{0,date,yyyy-MM-dd'T'HH:mm:ss'Z'}", time) + '",' +
        '"open":' + str.tostring(open, "#.########") + ',' +
        '"high":' + str.tostring(high, "#.########") + ',' +
        '"low":' + str.tostring(low, "#.########") + ',' +
        '"close":' + str.tostring(close, "#.########") + ',' +
        '"source":"tradingview"' +
    '}'
    
    // Webhook으로 전송
    alert(payload, alert.freq_once_per_bar_close)

// 차트에 현재 환율 표시
plot(close, "USD/KRW Rate", color=color.blue, linewidth=2)
```

### 2.4 TradingView Alert 설정 방법

```
┌─────────────────────────────────────────────────────────────────┐
│                  TradingView Alert 설정 가이드                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1️⃣ 차트 설정                                                   │
│     • 심볼: FX_IDC:USDKRW                                       │
│     • 타임프레임: 1분 (1m)                                       │
│     • Pine Script 추가 (위 코드)                                │
│                                                                 │
│  2️⃣ Alert 생성 (단축키: Alt + A)                                │
│     • Condition: "KRW/USD Webhook Sender"                       │
│     • Options:                                                  │
│       - Once Per Bar Close ✅                                   │
│       - Expiration: Open-ended ✅ (Premium 전용)                │
│                                                                 │
│  3️⃣ Notifications 탭                                           │
│     • Webhook URL: https://your-server.com/webhook/fx          │
│     • ✅ Webhook 체크                                           │
│                                                                 │
│  4️⃣ Message 탭                                                 │
│     • {{alert.message}} 그대로 유지                             │
│     (Pine Script에서 JSON 생성하므로)                           │
│                                                                 │
│  ⚠️ 주의사항                                                    │
│     • 2단계 인증(2FA) 활성화 필수                               │
│     • Webhook URL은 HTTPS 필수                                  │
│     • 빈도 제한: 3분 내 최대 15회 (1분마다 1회는 OK)            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.5 Webhook 수신 서버 (FastAPI)

```python
# collector/webhook/fx_webhook_server.py

from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
import hmac
import hashlib
import logging

logger = logging.getLogger(__name__)

app = FastAPI(title="TradingView Webhook Receiver")

# CORS 설정 (TradingView Webhook용)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST"],
    allow_headers=["*"],
)


class FXWebhookPayload(BaseModel):
    """TradingView에서 전송하는 환율 데이터"""
    symbol: str           # "USDKRW"
    exchange: str         # "FX_IDC"
    time: str            # "2025-12-12T10:30:00Z"
    open: float
    high: float
    low: float
    close: float
    source: str = "tradingview"


class WebhookReceiver:
    """TradingView Webhook 수신기"""
    
    def __init__(self, db_client, secret_key: str = None):
        self.db = db_client
        self.secret_key = secret_key  # 선택적 서명 검증
        self.last_rate: Optional[float] = None
        self.last_update: Optional[datetime] = None
    
    async def process_fx_webhook(self, payload: FXWebhookPayload):
        """환율 데이터 처리 및 저장"""
        
        # 1. 데이터 정규화
        rate_data = {
            'timestamp': payload.time,
            'base_currency': 'USD',
            'quote_currency': 'KRW',
            'rate': payload.close,  # 종가 사용
            'open': payload.open,
            'high': payload.high,
            'low': payload.low,
            'source': f"{payload.exchange}:{payload.symbol}",
        }
        
        # 2. 캐시 업데이트 (실시간 조회용)
        self.last_rate = payload.close
        self.last_update = datetime.utcnow()
        
        # 3. DB 저장
        await self.db.insert('exchange_rates', rate_data)
        
        logger.info(f"FX Rate Updated: {payload.close} KRW/USD at {payload.time}")
        
        return rate_data
    
    def get_latest_rate(self) -> Optional[float]:
        """최신 환율 조회 (캐시)"""
        return self.last_rate
    
    def is_stale(self, max_age_seconds: int = 120) -> bool:
        """데이터 신선도 확인"""
        if not self.last_update:
            return True
        age = (datetime.utcnow() - self.last_update).total_seconds()
        return age > max_age_seconds


# 글로벌 수신기 인스턴스
webhook_receiver: Optional[WebhookReceiver] = None


def init_webhook_receiver(db_client, secret_key: str = None):
    """수신기 초기화"""
    global webhook_receiver
    webhook_receiver = WebhookReceiver(db_client, secret_key)


@app.post("/webhook/fx")
async def receive_fx_webhook(
    request: Request,
    background_tasks: BackgroundTasks
):
    """TradingView FX 환율 Webhook 엔드포인트"""
    
    if not webhook_receiver:
        raise HTTPException(status_code=500, detail="Webhook receiver not initialized")
    
    try:
        # 요청 본문 파싱
        body = await request.json()
        payload = FXWebhookPayload(**body)
        
        # 비동기 처리 (빠른 응답을 위해)
        background_tasks.add_task(
            webhook_receiver.process_fx_webhook,
            payload
        )
        
        return {"status": "accepted", "rate": payload.close}
        
    except Exception as e:
        logger.error(f"Webhook processing error: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/fx/latest")
async def get_latest_fx_rate():
    """최신 환율 조회 API"""
    
    if not webhook_receiver:
        raise HTTPException(status_code=500, detail="Not initialized")
    
    rate = webhook_receiver.get_latest_rate()
    is_stale = webhook_receiver.is_stale()
    
    return {
        "rate": rate,
        "last_update": webhook_receiver.last_update.isoformat() if webhook_receiver.last_update else None,
        "is_stale": is_stale,
        "source": "tradingview:FX_IDC:USDKRW"
    }


@app.get("/health")
async def health_check():
    """헬스 체크"""
    return {
        "status": "healthy",
        "webhook_active": webhook_receiver is not None,
        "last_fx_update": webhook_receiver.last_update.isoformat() if webhook_receiver and webhook_receiver.last_update else None
    }
```

### 2.6 환율 데이터 백업 시스템

TradingView Webhook이 실패할 경우를 대비한 백업:

```python
# collector/collectors/exchange_rate_backup.py

import aiohttp
from datetime import datetime
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class ExchangeRateBackup:
    """
    환율 백업 수집기
    
    TradingView Webhook 실패 시 대체 소스
    우선순위: 1) dunamu API (업비트 제공, 무료)
             2) 한국수출입은행 (일 1회, 기준점)
    """
    
    # dunamu API (업비트에서 사용하는 환율 API)
    DUNAMU_URL = "https://quotation-api-cdn.dunamu.com/v1/forex/recent?codes=FRX.KRWUSD"
    
    # 한국수출입은행 API
    KOREAEXIM_URL = "https://www.koreaexim.go.kr/site/program/financial/exchangeJSON"
    
    def __init__(self, koreaexim_api_key: str = None):
        self.koreaexim_api_key = koreaexim_api_key
        self.last_rate: Optional[float] = None
    
    async def fetch_dunamu_rate(self) -> Optional[dict]:
        """
        dunamu API에서 환율 조회 (업비트 사용)
        
        장점: 무료, 실시간, 안정적
        단점: 공식 API 아님 (변경 가능성)
        """
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(self.DUNAMU_URL) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if data and len(data) > 0:
                            rate_data = data[0]
                            # dunamu는 KRW/USD 형식 (1달러 = X원)
                            self.last_rate = rate_data.get('basePrice')
                            
                            return {
                                'timestamp': datetime.utcnow().isoformat(),
                                'base_currency': 'USD',
                                'quote_currency': 'KRW',
                                'rate': self.last_rate,
                                'source': 'dunamu',
                            }
        except Exception as e:
            logger.error(f"Dunamu API error: {e}")
        
        return None
    
    async def fetch_koreaexim_rate(self) -> Optional[dict]:
        """
        한국수출입은행 환율 조회
        
        장점: 공식 데이터, 무료
        단점: 1일 1회 (11시), API 키 필요
        """
        if not self.koreaexim_api_key:
            return None
        
        try:
            params = {
                'authkey': self.koreaexim_api_key,
                'searchdate': datetime.now().strftime('%Y%m%d'),
                'data': 'AP01'
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.get(self.KOREAEXIM_URL, params=params) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        for item in data:
                            if item.get('cur_unit') == 'USD':
                                # 쉼표 제거 후 변환
                                rate = float(item['deal_bas_r'].replace(',', ''))
                                
                                return {
                                    'timestamp': datetime.utcnow().isoformat(),
                                    'base_currency': 'USD',
                                    'quote_currency': 'KRW',
                                    'rate': rate,
                                    'source': 'koreaexim',
                                }
        except Exception as e:
            logger.error(f"Korea Exim API error: {e}")
        
        return None
    
    async def get_backup_rate(self) -> Optional[dict]:
        """백업 환율 조회 (우선순위대로 시도)"""
        
        # 1순위: dunamu (실시간)
        rate = await self.fetch_dunamu_rate()
        if rate:
            return rate
        
        # 2순위: 한국수출입은행 (일 1회)
        rate = await self.fetch_koreaexim_rate()
        if rate:
            return rate
        
        return None
```

---

## 3. 데이터베이스 스키마

### 3.1 exchange_rates (환율) - 업데이트됨

```sql
CREATE TABLE exchange_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    base_currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    quote_currency VARCHAR(10) NOT NULL DEFAULT 'KRW',
    
    -- 가격 데이터
    rate DECIMAL(20, 8) NOT NULL,      -- 종가/현재가
    open DECIMAL(20, 8),                -- 시가 (TradingView)
    high DECIMAL(20, 8),                -- 고가 (TradingView)
    low DECIMAL(20, 8),                 -- 저가 (TradingView)
    
    -- 메타데이터
    source VARCHAR(50) NOT NULL,        -- 'tradingview:FX_IDC:USDKRW', 'dunamu', 'koreaexim'
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- 중복 방지 (분 단위)
    UNIQUE(timestamp, base_currency, quote_currency, source)
);

-- 조회 최적화 인덱스
CREATE INDEX idx_exchange_rate_time ON exchange_rates (timestamp DESC);
CREATE INDEX idx_exchange_rate_source ON exchange_rates (source, timestamp DESC);
```

### 3.2 orderbook_snapshots (호가 스냅샷)

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
```

### 3.3 trades (체결 내역)

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

### 3.4 funding_rates (펀딩비)

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

### 3.5 kimp_rates (김프율)

```sql
CREATE TABLE kimp_rates (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    symbol VARCHAR(20) NOT NULL DEFAULT 'BTC',
    
    upbit_price DECIMAL(20, 8) NOT NULL,      -- 업비트 가격 (KRW)
    binance_price DECIMAL(20, 8) NOT NULL,    -- 바이낸스 가격 (USDT)
    exchange_rate DECIMAL(20, 8) NOT NULL,    -- USD/KRW 환율
    
    kimp_rate DECIMAL(10, 4) NOT NULL,        -- 김프율 (%)
    
    -- 환율 소스 추적
    rate_source VARCHAR(50) DEFAULT 'tradingview',
    
    UNIQUE(timestamp, symbol)
);

CREATE INDEX idx_kimp_time ON kimp_rates (timestamp DESC);
CREATE INDEX idx_kimp_symbol_time ON kimp_rates (symbol, timestamp DESC);
```

---

## 4. 수집 모듈 구조

### 4.1 디렉토리 구조 (업데이트)

```
trading-platform-storage/
├── docker-compose.yml           # 전체 서비스 (DB + Collector + Webhook)
├── .env.example
│
├── collector/                   # 데이터 수집 서비스
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                  # 진입점 (스케줄러)
│   │
│   ├── collectors/
│   │   ├── __init__.py
│   │   ├── base.py              # BaseCollector 추상 클래스
│   │   ├── upbit.py             # 업비트 수집기
│   │   ├── binance.py           # 바이낸스 수집기
│   │   ├── exchange_rate_backup.py  # 🆕 환율 백업 (dunamu, 수출입은행)
│   │   └── kimp.py              # 김프 계산기
│   │
│   ├── webhook/                 # 🆕 TradingView Webhook
│   │   ├── __init__.py
│   │   ├── fx_webhook_server.py # FastAPI Webhook 서버
│   │   └── pine_scripts/        # Pine Script 백업
│   │       └── usdkrw_sender.pine
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
│   │   ├── 003_add_collector_tables.sql
│   │   └── 004_update_exchange_rates.sql  # 🆕 환율 테이블 업데이트
│   └── seed.sql
│
├── scripts/
│   ├── backup.sh
│   ├── data_health_check.py
│   └── test_webhook.py          # 🆕 Webhook 테스트
│
└── docs/
    ├── DATA_COLLECTION.md       # 이 문서
    ├── TRADINGVIEW_SETUP.md     # 🆕 TradingView 설정 가이드
    └── SCHEMA.md
```

### 4.2 핵심 클래스: KimpCalculator (환율 소스 통합)

```python
# collector/collectors/kimp.py

from decimal import Decimal
from datetime import datetime
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class KimpCalculator:
    """
    김프율 계산기
    
    환율 소스 우선순위:
    1. TradingView Webhook (실시간)
    2. dunamu API (백업)
    3. 한국수출입은행 (최후 수단)
    """
    
    def __init__(self, webhook_receiver, backup_collector):
        self.webhook_receiver = webhook_receiver
        self.backup_collector = backup_collector
    
    async def get_exchange_rate(self) -> tuple[float, str]:
        """
        환율 조회 (폴백 로직 포함)
        
        Returns:
            (rate, source) 튜플
        """
        # 1순위: TradingView Webhook
        if self.webhook_receiver and not self.webhook_receiver.is_stale(max_age_seconds=120):
            rate = self.webhook_receiver.get_latest_rate()
            if rate:
                return rate, 'tradingview'
        
        # 2순위: 백업 소스
        logger.warning("TradingView rate stale, using backup...")
        backup_data = await self.backup_collector.get_backup_rate()
        if backup_data:
            return backup_data['rate'], backup_data['source']
        
        # 실패
        raise ValueError("No exchange rate available from any source")
    
    async def calculate(
        self,
        upbit_price: float,
        binance_price: float,
    ) -> dict:
        """
        김프율 계산
        
        공식: (업비트가격 - 바이낸스가격 × 환율) / (바이낸스가격 × 환율) × 100
        """
        exchange_rate, rate_source = await self.get_exchange_rate()
        
        binance_krw = binance_price * exchange_rate
        kimp_rate = ((upbit_price - binance_krw) / binance_krw) * 100
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'upbit_price': upbit_price,
            'binance_price': binance_price,
            'exchange_rate': exchange_rate,
            'kimp_rate': round(kimp_rate, 4),
            'rate_source': rate_source,
        }
```

---

## 5. Docker 설정

### 5.1 docker-compose.yml (업데이트)

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

  # 데이터 수집기 + Webhook 서버
  data-collector:
    build:
      context: ./collector
      dockerfile: Dockerfile
    depends_on:
      - supabase-db
    ports:
      - "8000:8000"  # 🆕 Webhook 수신 포트
    environment:
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_KEY=${SUPABASE_KEY}
      - UPBIT_API_KEY=${UPBIT_API_KEY}
      - UPBIT_SECRET_KEY=${UPBIT_SECRET_KEY}
      - BINANCE_API_KEY=${BINANCE_API_KEY}
      - BINANCE_SECRET_KEY=${BINANCE_SECRET_KEY}
      - WEBHOOK_PORT=8000
      - KOREAEXIM_API_KEY=${KOREAEXIM_API_KEY}  # 선택
    restart: always
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Nginx (Webhook HTTPS 프록시) - 선택
  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/certs:/etc/nginx/certs
    depends_on:
      - data-collector

volumes:
  supabase-db:
```

### 5.2 메인 서비스 (업데이트)

```python
# collector/main.py

import asyncio
import uvicorn
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from collectors.upbit import UpbitCollector
from collectors.binance import BinanceCollector
from collectors.exchange_rate_backup import ExchangeRateBackup
from collectors.kimp import KimpCalculator
from webhook.fx_webhook_server import app, init_webhook_receiver
from websocket.upbit_ws import UpbitWebSocket
from websocket.binance_ws import BinanceOrderbookManager
from storage.supabase_client import SupabaseClient
from storage.batch_writer import BatchWriter
import os


class DataCollectorService:
    """메인 데이터 수집 서비스"""
    
    def __init__(self):
        self.upbit = UpbitCollector(['BTC/KRW', 'ETH/KRW'])
        self.binance = BinanceCollector(['BTC/USDT', 'ETH/USDT'])
        
        self.db = SupabaseClient()
        self.batch_writer = BatchWriter(self.db, batch_size=100)
        
        # 환율 관련
        self.exchange_rate_backup = ExchangeRateBackup(
            koreaexim_api_key=os.getenv('KOREAEXIM_API_KEY')
        )
        
        # Webhook 수신기 초기화
        init_webhook_receiver(self.db)
        
        from webhook.fx_webhook_server import webhook_receiver
        self.kimp = KimpCalculator(webhook_receiver, self.exchange_rate_backup)
        
        self.scheduler = AsyncIOScheduler()
    
    async def collect_ohlcv(self):
        """1분마다 OHLCV 수집"""
        for symbol in self.upbit.symbols:
            data = await self.upbit.fetch_ohlcv(symbol, '1m', limit=1)
            await self.batch_writer.add('ohlcv', data)
        
        for symbol in self.binance.symbols:
            data = await self.binance.fetch_ohlcv(symbol, '1m', limit=1)
            await self.batch_writer.add('ohlcv', data)
    
    async def collect_funding_rate(self):
        """8시간마다 펀딩비 수집"""
        for symbol in self.binance.symbols:
            data = await self.binance.fetch_funding_rate(symbol)
            await self.db.insert('funding_rates', data)
    
    async def calculate_kimp(self):
        """1분마다 김프율 계산"""
        try:
            upbit_ticker = await self.upbit.fetch_ticker('BTC/KRW')
            binance_ticker = await self.binance.fetch_ticker('BTC/USDT')
            
            kimp_data = await self.kimp.calculate(
                upbit_ticker['last'],
                binance_ticker['last'],
            )
            await self.db.insert('kimp_rates', kimp_data)
            
        except Exception as e:
            print(f"Kimp calculation error: {e}")
    
    async def on_orderbook_update(self, data: dict):
        """실시간 호가 업데이트 → 저장"""
        await self.batch_writer.add('orderbook_snapshots', data)
    
    def start(self):
        """서비스 시작"""
        # 스케줄 등록
        self.scheduler.add_job(self.collect_ohlcv, 'interval', minutes=1)
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


async def main():
    # 데이터 수집 서비스 시작
    service = DataCollectorService()
    service.start()
    
    # Webhook 서버 시작 (같은 프로세스에서)
    config = uvicorn.Config(
        app, 
        host="0.0.0.0", 
        port=int(os.getenv('WEBHOOK_PORT', 8000)),
        log_level="info"
    )
    server = uvicorn.Server(config)
    await server.serve()


if __name__ == "__main__":
    asyncio.run(main())
```

---

## 6. TradingView 설정 체크리스트

### 6.1 사전 준비

```
✅ TradingView Premium 계정 확인
✅ 2단계 인증(2FA) 활성화
✅ 서버 Webhook URL 준비 (HTTPS 필수)
   - 예: https://your-domain.com/webhook/fx
   - 또는 ngrok 테스트용: https://xxxx.ngrok.io/webhook/fx
```

### 6.2 Alert 설정

```
1. 차트 열기: FX_IDC:USDKRW, 1분봉
2. Pine Script 추가 (섹션 2.3 코드)
3. Alert 생성:
   - Condition: 스크립트 이름 선택
   - Options: Once Per Bar Close
   - Expiration: Open-ended
4. Notifications:
   - Webhook URL 입력
   - Webhook 체크박스 활성화
5. Create Alert 클릭
```

### 6.3 동작 확인

```bash
# 서버 로그에서 Webhook 수신 확인
docker logs -f data-collector 2>&1 | grep "FX Rate"

# API로 최신 환율 확인
curl https://your-server.com/fx/latest
```

---

## 7. 모니터링

### 7.1 환율 데이터 상태 확인

```sql
-- 최근 환율 데이터 (소스별)
SELECT 
    source,
    COUNT(*) as count,
    MAX(timestamp) as latest,
    AVG(rate) as avg_rate
FROM exchange_rates
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY source;

-- TradingView Webhook 수신 현황
SELECT 
    DATE_TRUNC('minute', timestamp) as minute,
    COUNT(*) as webhook_count
FROM exchange_rates
WHERE source LIKE 'tradingview%'
  AND timestamp > NOW() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute DESC;
```

### 7.2 Discord 알림 (환율 장애)

```python
# 환율 데이터 2분 이상 미수신 시 알림
async def check_exchange_rate_health():
    from webhook.fx_webhook_server import webhook_receiver
    
    if webhook_receiver and webhook_receiver.is_stale(max_age_seconds=120):
        await send_discord_alert(
            "⚠️ 환율 데이터 지연 경고",
            f"마지막 수신: {webhook_receiver.last_update}",
            "TradingView Webhook 상태 확인 필요"
        )
```

---

## 8. 데이터 보존 정책

| 데이터 | 보존 기간 | 이유 |
|--------|-----------|------|
| OHLCV (1분) | **무기한** | 백테스트 핵심 데이터 |
| 김프율 | **무기한** | 전략 신호 분석 |
| **환율** | **1년** | 김프 계산 검증 |
| 펀딩비 | **무기한** | 비용 계산 |
| 호가 스냅샷 | **90일** | 용량 큼, 최근 데이터만 필요 |
| 체결 내역 | **30일** | 분석용, 장기 보관 불필요 |

---

## 9. 요약

### 환율 데이터 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    환율 데이터 수집 체계                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  🥇 주 데이터: TradingView Webhook                              │
│     • 심볼: FX_IDC:USDKRW (ICE 복합)                           │
│     • 주기: 1분봉 마감 시 자동 전송                              │
│     • 비용: Premium 구독에 포함 ($56/월)                        │
│     • 안정성: 🟢 높음 (공식 기능)                               │
│                                                                 │
│  🥈 백업 1: dunamu API                                          │
│     • TradingView 2분 이상 지연 시 자동 전환                    │
│     • 비용: 무료                                                │
│     • 안정성: 🟢 (업비트 사용)                                  │
│                                                                 │
│  🥉 백업 2: 한국수출입은행                                       │
│     • 일 1회 기준점 (11시)                                      │
│     • 비용: 무료 (API 키 필요)                                  │
│     • 용도: 최후 수단, 회계 기준                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 다음 단계

1. ✅ TradingView에서 Pine Script 추가
2. ✅ Alert 생성 (FX_IDC:USDKRW, 1분봉)
3. ✅ Webhook URL 설정 (HTTPS)
4. ✅ 서버 배포 후 수신 테스트
5. ✅ 김프 계산 정확도 검증

---

*— 문서 끝 —*
