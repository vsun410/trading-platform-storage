# 📈 TradingView 환율 데이터 수집 명세 (Ver 3.0)

## 1. 개요

### 1.1 목적
- **역할**: 김프 전략의 환율 필터를 위한 실시간 USD/KRW 환율 데이터 수집
- **핵심 기능**: 환율 급등 구간 감지 → 진입 차단
- **데이터 소스**: TradingView `FX_IDC:USDKRW`

### 1.2 왜 TradingView인가?

| 소스 | 장점 | 단점 | 채택 |
|:---|:---|:---|:---|
| **TradingView** | 실시간, 무료, 안정적 | API 제한 있음 | ✅ **채택** |
| 한국은행 | 공식 데이터 | 지연(1일), 실시간 불가 | ❌ |
| ExchangeRate-API | 쉬운 API | 1분 지연, 유료 | 백업 |
| Open Exchange Rates | 다양한 통화 | 유료, 속도 느림 | ❌ |

---

## 2. TradingView 데이터 수집 아키텍처

### 2.1 시스템 구조

```
┌─────────────────────────────────────────────────────────────────────┐
│                  TradingView FX Data Pipeline                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│   │ TradingView │ →   │   Fetcher   │ →   │    Cache    │           │
│   │ FX_IDC:     │     │  (Python)   │     │  (Redis/    │           │
│   │ USDKRW      │     │             │     │   Memory)   │           │
│   └─────────────┘     └─────────────┘     └─────────────┘           │
│                                                  │                    │
│                                                  ▼                    │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│   │  fx_rates   │ ←   │   Writer    │ ←   │ 12h MA      │           │
│   │   (DB)      │     │             │     │ Calculator  │           │
│   └─────────────┘     └─────────────┘     └─────────────┘           │
│                                                  │                    │
│                                                  ▼                    │
│                                           ┌─────────────┐           │
│                                           │ fx_filter   │           │
│                                           │ _log (DB)   │           │
│                                           └─────────────┘           │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 데이터 흐름

1. **Fetch**: TradingView에서 FX_IDC:USDKRW 실시간 조회
2. **Cache**: 메모리/Redis에 캐싱 (TTL: 60초)
3. **Calculate**: 12시간 이동평균 계산
4. **Filter**: 환율 급등 여부 판단
5. **Store**: DB에 환율 데이터 및 필터 상태 저장

---

## 3. TradingView 데이터 수집 방법

### 3.1 방법 1: tvDatafeed 라이브러리 (권장)

```python
from tvDatafeed import TvDatafeed, Interval

class TradingViewFXFetcher:
    """TradingView 환율 데이터 수집기"""
    
    def __init__(self):
        # 무료 계정으로 연결 (로그인 불필요)
        self.tv = TvDatafeed()
        self.symbol = "USDKRW"
        self.exchange = "FX_IDC"
        self.cache = {}
        self.cache_ttl = 60  # 60초 캐시
    
    def get_current_rate(self) -> float:
        """현재 환율 조회"""
        # 캐시 확인
        if self._is_cache_valid():
            return self.cache['rate']
        
        # TradingView에서 조회
        df = self.tv.get_hist(
            symbol=self.symbol,
            exchange=self.exchange,
            interval=Interval.in_1_minute,
            n_bars=1
        )
        
        if df is not None and not df.empty:
            rate = float(df['close'].iloc[-1])
            self._update_cache(rate)
            return rate
        
        raise Exception("Failed to fetch FX rate from TradingView")
    
    def get_historical_rates(self, bars: int = 720) -> list:
        """
        과거 환율 데이터 조회
        bars: 720 = 12시간 (1분봉 기준)
        """
        df = self.tv.get_hist(
            symbol=self.symbol,
            exchange=self.exchange,
            interval=Interval.in_1_minute,
            n_bars=bars
        )
        
        if df is not None and not df.empty:
            return df['close'].tolist()
        
        return []
    
    def _is_cache_valid(self) -> bool:
        if 'rate' not in self.cache or 'timestamp' not in self.cache:
            return False
        elapsed = time.time() - self.cache['timestamp']
        return elapsed < self.cache_ttl
    
    def _update_cache(self, rate: float):
        self.cache = {
            'rate': rate,
            'timestamp': time.time()
        }
```

### 3.2 방법 2: tradingview-ta 라이브러리

```python
from tradingview_ta import TA_Handler, Interval

class TradingViewTAFetcher:
    """TradingView Technical Analysis 기반 환율 조회"""
    
    def __init__(self):
        self.handler = TA_Handler(
            symbol="USDKRW",
            exchange="FX_IDC",
            screener="forex",
            interval=Interval.INTERVAL_1_MINUTE
        )
    
    def get_current_rate(self) -> float:
        """현재 환율 조회"""
        analysis = self.handler.get_analysis()
        return analysis.indicators['close']
    
    def get_indicators(self) -> dict:
        """기술적 지표 함께 조회"""
        analysis = self.handler.get_analysis()
        return {
            'close': analysis.indicators['close'],
            'open': analysis.indicators['open'],
            'high': analysis.indicators['high'],
            'low': analysis.indicators['low'],
            'sma_20': analysis.indicators.get('SMA20'),
            'ema_12': analysis.indicators.get('EMA12'),
        }
```

### 3.3 방법 3: WebSocket (고급)

```python
import asyncio
import websockets
import json

class TradingViewWebSocket:
    """TradingView WebSocket 실시간 연결"""
    
    WS_URL = "wss://data.tradingview.com/socket.io/websocket"
    
    async def connect(self):
        """WebSocket 연결 및 구독"""
        async with websockets.connect(self.WS_URL) as ws:
            # 심볼 구독
            subscribe_msg = {
                "m": "quote_add_symbols",
                "p": ["FX_IDC:USDKRW"]
            }
            await ws.send(json.dumps(subscribe_msg))
            
            # 데이터 수신
            async for message in ws:
                data = json.loads(message)
                if 'p' in data and 'v' in data['p']:
                    yield data['p']['v']['lp']  # last price
```

---

## 4. 12시간 이동평균 계산

### 4.1 MA 계산 로직

```python
from collections import deque
from typing import Optional

class FXMovingAverage:
    """환율 12시간 이동평균 계산기"""
    
    def __init__(self, period_minutes: int = 720):  # 12시간 = 720분
        self.period = period_minutes
        self.rates = deque(maxlen=period_minutes)
        self.ma_cache: Optional[float] = None
    
    def add_rate(self, rate: float):
        """새 환율 추가"""
        self.rates.append(rate)
        self._invalidate_cache()
    
    def get_ma(self) -> Optional[float]:
        """12시간 이동평균 반환"""
        if len(self.rates) < self.period:
            # 데이터 부족 시 현재까지의 평균 반환
            if len(self.rates) > 0:
                return sum(self.rates) / len(self.rates)
            return None
        
        if self.ma_cache is None:
            self.ma_cache = sum(self.rates) / self.period
        
        return self.ma_cache
    
    def is_surge(self, current_rate: float, threshold: float = 1.001) -> bool:
        """환율 급등 여부 판단"""
        ma = self.get_ma()
        if ma is None:
            return False  # 데이터 부족 시 통과
        
        return current_rate > ma * threshold
    
    def _invalidate_cache(self):
        self.ma_cache = None
```

### 4.2 초기 데이터 로딩

```python
async def initialize_ma(fetcher: TradingViewFXFetcher, ma_calc: FXMovingAverage):
    """
    시스템 시작 시 12시간 과거 데이터로 MA 초기화
    """
    historical_rates = fetcher.get_historical_rates(bars=720)
    
    for rate in historical_rates:
        ma_calc.add_rate(rate)
    
    print(f"MA initialized with {len(historical_rates)} data points")
    print(f"Current MA(12h): {ma_calc.get_ma():.2f}")
```

---

## 5. 환율 필터 로직

### 5.1 필터 클래스

```python
from dataclasses import dataclass
from datetime import datetime

@dataclass
class FXFilterResult:
    timestamp: datetime
    current_rate: float
    ma_12h: float
    threshold: float
    is_blocked: bool
    surge_pct: float

class FXFilter:
    """환율 급등 필터"""
    
    def __init__(self, threshold: float = 1.001):
        self.threshold = threshold  # 0.1% 급등 기준
    
    def check(self, current_rate: float, ma_12h: float) -> FXFilterResult:
        """
        환율 필터 체크
        
        Returns:
            FXFilterResult: 필터 결과
        """
        threshold_value = ma_12h * self.threshold
        is_blocked = current_rate > threshold_value
        surge_pct = ((current_rate / ma_12h) - 1) * 100
        
        return FXFilterResult(
            timestamp=datetime.now(),
            current_rate=current_rate,
            ma_12h=ma_12h,
            threshold=threshold_value,
            is_blocked=is_blocked,
            surge_pct=round(surge_pct, 4)
        )
```

### 5.2 사용 예시

```python
# 초기화
fetcher = TradingViewFXFetcher()
ma_calc = FXMovingAverage(period_minutes=720)
fx_filter = FXFilter(threshold=1.001)

# MA 초기화
await initialize_ma(fetcher, ma_calc)

# 실시간 체크
current_rate = fetcher.get_current_rate()
ma_12h = ma_calc.get_ma()

result = fx_filter.check(current_rate, ma_12h)

if result.is_blocked:
    print(f"⛔ 진입 차단: 환율 {result.current_rate:.2f} > {result.threshold:.2f}")
    print(f"   급등률: +{result.surge_pct:.2f}%")
else:
    print(f"✅ 진입 가능: 환율 {result.current_rate:.2f}")
```

---

## 6. DB 저장

### 6.1 환율 데이터 저장

```python
async def save_fx_rate(db, rate: float, ma_12h: float):
    """환율 데이터 DB 저장"""
    await db.execute("""
        INSERT INTO fx_rates (timestamp, symbol, rate, ma_12h, source)
        VALUES (NOW(), 'FX_IDC:USDKRW', $1, $2, 'TradingView')
    """, rate, ma_12h)
```

### 6.2 필터 상태 저장

```python
async def save_fx_filter_log(db, result: FXFilterResult):
    """환율 필터 상태 DB 저장"""
    await db.execute("""
        INSERT INTO fx_filter_log 
        (timestamp, current_rate, ma_12h, threshold, is_blocked, surge_pct)
        VALUES ($1, $2, $3, $4, $5, $6)
    """, 
    result.timestamp, 
    result.current_rate, 
    result.ma_12h, 
    result.threshold, 
    result.is_blocked, 
    result.surge_pct
    )
```

---

## 7. 스케줄링

### 7.1 데이터 수집 스케줄

| 작업 | 주기 | 설명 |
|:---|:---|:---|
| 환율 조회 | 60초 | TradingView API 호출 |
| MA 업데이트 | 60초 | 새 환율로 MA 갱신 |
| 필터 체크 | 1초 | 진입 시그널 발생 시 |
| DB 저장 | 60초 | 환율 및 필터 상태 저장 |

### 7.2 스케줄러 구현

```python
import asyncio
from apscheduler.schedulers.asyncio import AsyncIOScheduler

class FXScheduler:
    """환율 데이터 수집 스케줄러"""
    
    def __init__(self, fetcher, ma_calc, fx_filter, db):
        self.fetcher = fetcher
        self.ma_calc = ma_calc
        self.fx_filter = fx_filter
        self.db = db
        self.scheduler = AsyncIOScheduler()
    
    def start(self):
        # 60초마다 환율 수집
        self.scheduler.add_job(
            self.collect_fx_rate,
            'interval',
            seconds=60,
            id='fx_rate_collector'
        )
        
        self.scheduler.start()
    
    async def collect_fx_rate(self):
        """환율 수집 및 저장"""
        try:
            rate = self.fetcher.get_current_rate()
            self.ma_calc.add_rate(rate)
            
            ma_12h = self.ma_calc.get_ma()
            result = self.fx_filter.check(rate, ma_12h)
            
            # DB 저장
            await save_fx_rate(self.db, rate, ma_12h)
            await save_fx_filter_log(self.db, result)
            
            # 로깅
            status = "🚫 BLOCKED" if result.is_blocked else "✅ OK"
            print(f"[FX] {rate:.2f} | MA: {ma_12h:.2f} | {status}")
            
        except Exception as e:
            print(f"[FX ERROR] {e}")
```

---

## 8. 에러 처리 및 백업

### 8.1 폴백 전략

```python
class FXFetcherWithFallback:
    """백업 소스 포함 환율 조회"""
    
    def __init__(self):
        self.primary = TradingViewFXFetcher()
        self.backup = ExchangeRateAPIFetcher()  # 백업
        self.last_valid_rate = None
    
    def get_current_rate(self) -> float:
        try:
            rate = self.primary.get_current_rate()
            self.last_valid_rate = rate
            return rate
        except Exception as e:
            print(f"[FX] Primary failed: {e}, trying backup...")
            
            try:
                rate = self.backup.get_current_rate()
                self.last_valid_rate = rate
                return rate
            except Exception as e2:
                print(f"[FX] Backup failed: {e2}")
                
                if self.last_valid_rate:
                    print(f"[FX] Using last valid rate: {self.last_valid_rate}")
                    return self.last_valid_rate
                
                raise Exception("All FX sources failed")
```

### 8.2 API Rate Limit 대응

```python
import time
from functools import wraps

def rate_limit(min_interval: float = 1.0):
    """API 호출 간격 제한 데코레이터"""
    last_call = [0.0]
    
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            elapsed = time.time() - last_call[0]
            if elapsed < min_interval:
                time.sleep(min_interval - elapsed)
            
            result = func(*args, **kwargs)
            last_call[0] = time.time()
            return result
        
        return wrapper
    return decorator

# 사용
@rate_limit(min_interval=1.0)  # 최소 1초 간격
def get_fx_rate():
    return fetcher.get_current_rate()
```

---

## 9. 의존성

```txt
# requirements.txt
tvDatafeed>=2.1.0
tradingview-ta>=3.3.0
websockets>=11.0
redis>=4.5.0
apscheduler>=3.10.0
asyncpg>=0.27.0
```

---

## 10. 설정

```yaml
# config/fx_config.yaml
fx_data:
  source: "TradingView"
  symbol: "FX_IDC:USDKRW"
  
  collection:
    interval_seconds: 60
    cache_ttl_seconds: 60
    
  ma:
    period_minutes: 720  # 12시간
    
  filter:
    surge_threshold: 1.001  # +0.1%
    
  fallback:
    enabled: true
    sources:
      - name: "ExchangeRate-API"
        url: "https://api.exchangerate-api.com/v4/latest/USD"
```

---

**버전**: 3.0  
**작성일**: 2025-12-14  
**레포**: trading-platform-storage
