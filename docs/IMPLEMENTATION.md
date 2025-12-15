# 🛠️ 구현 가이드 (Claude Code용)

**Repository:** trading-platform-storage  
**Version:** 3.0  
**Date:** 2025-12-15  
**Purpose:** Claude Code에서 참조할 구현 상세 스펙

---

## 1. 프로젝트 개요

### 1.1 목적
- **핵심**: 김프 전략 개발을 위한 시장 데이터 24/7 수집
- **기간**: 최소 3개월 데이터 축적
- **배포**: Docker → Vultr 클라우드

### 1.2 기술 스택

| 구분 | 기술 | 버전 |
|:---|:---|:---|
| Language | Python | 3.11+ |
| Exchange API | CCXT | 4.0+ |
| FX Data | tvDatafeed | 2.1+ |
| Database | Supabase (PostgreSQL) | - |
| Scheduler | APScheduler | 3.10+ |
| Container | Docker | 24.0+ |

---

## 2. 파일 구조 및 구현 순서

### 2.1 구현 순서 (의존성 기준)

```
Phase 1: 기반 설정
├── [1] .env.example
├── [2] requirements.txt
├── [3] src/database/supabase_client.py
└── [4] supabase/migrations/*.sql

Phase 2: 수집기
├── [5] src/collectors/base_collector.py
├── [6] src/collectors/upbit_collector.py
├── [7] src/collectors/binance_collector.py
└── [8] src/collectors/fx_collector.py

Phase 3: 계산기
├── [9] src/calculators/kimp_calculator.py
├── [10] src/calculators/zscore_calculator.py
└── [11] src/calculators/bb_calculator.py

Phase 4: 스케줄러 & 메인
├── [12] src/scheduler/jobs.py
├── [13] src/main.py
└── [14] Dockerfile + docker-compose.yml

Phase 5: 유틸리티
├── [15] scripts/health_check.py
└── [16] tests/test_collectors.py
```

---

## 3. 상세 구현 스펙

### 3.1 환경 변수 (.env.example)

```env
# ===========================================
# Supabase 설정
# ===========================================
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key

# ===========================================
# 수집 설정
# ===========================================
# 수집 주기 (초)
COLLECT_INTERVAL_SECONDS=60

# 대상 심볼
SYMBOLS=BTC

# Z-Score 윈도우 (분)
ZSCORE_WINDOW_MINUTES=60

# 볼린저 밴드 기간
BB_PERIOD=20
BB_STD_MULT=2.0

# 환율 MA 기간 (분) - 12시간 = 720
FX_MA_PERIOD_MINUTES=720

# ===========================================
# 알림 설정 (선택)
# ===========================================
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# ===========================================
# 개발/운영 모드
# ===========================================
ENV=development
LOG_LEVEL=INFO
```

---

### 3.2 의존성 (requirements.txt)

```txt
# Exchange API
ccxt>=4.0.0

# TradingView FX Data
tvDatafeed>=2.1.0

# Database
supabase>=2.0.0

# Scheduler
apscheduler>=3.10.0

# Data Processing
pandas>=2.0.0
numpy>=1.24.0

# Async
aiohttp>=3.9.0
asyncio-throttle>=1.0.0

# Utilities
python-dotenv>=1.0.0
loguru>=0.7.0

# Telegram (선택)
python-telegram-bot>=20.0
```

---

### 3.3 Supabase 클라이언트 (src/database/supabase_client.py)

```python
"""
Supabase 데이터베이스 클라이언트

사용법:
    from database.supabase_client import SupabaseClient
    
    db = SupabaseClient()
    await db.insert('kimp_1m', data)
    result = await db.query('kimp_1m', limit=100)
"""

import os
from datetime import datetime
from typing import Optional, List, Dict, Any
from supabase import create_client, Client
from loguru import logger


class SupabaseClient:
    """Supabase 클라이언트 래퍼"""
    
    def __init__(self):
        url = os.getenv('SUPABASE_URL')
        key = os.getenv('SUPABASE_KEY')
        
        if not url or not key:
            raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set")
        
        self.client: Client = create_client(url, key)
        logger.info("Supabase client initialized")
    
    async def insert(self, table: str, data: Dict[str, Any]) -> Dict:
        """단일 레코드 삽입"""
        try:
            result = self.client.table(table).insert(data).execute()
            return result.data[0] if result.data else {}
        except Exception as e:
            logger.error(f"Insert error [{table}]: {e}")
            raise
    
    async def insert_many(self, table: str, data_list: List[Dict[str, Any]]) -> List[Dict]:
        """다중 레코드 삽입 (배치)"""
        try:
            result = self.client.table(table).insert(data_list).execute()
            return result.data
        except Exception as e:
            logger.error(f"Batch insert error [{table}]: {e}")
            raise
    
    async def query(
        self, 
        table: str, 
        columns: str = "*",
        filters: Optional[Dict] = None,
        order_by: str = "timestamp",
        order_desc: bool = True,
        limit: int = 100
    ) -> List[Dict]:
        """데이터 조회"""
        try:
            query = self.client.table(table).select(columns)
            
            if filters:
                for key, value in filters.items():
                    query = query.eq(key, value)
            
            if order_desc:
                query = query.order(order_by, desc=True)
            else:
                query = query.order(order_by)
            
            result = query.limit(limit).execute()
            return result.data
        except Exception as e:
            logger.error(f"Query error [{table}]: {e}")
            raise
    
    async def get_latest(self, table: str, symbol: str = "BTC") -> Optional[Dict]:
        """최신 레코드 1개 조회"""
        result = await self.query(
            table=table,
            filters={"symbol": symbol},
            limit=1
        )
        return result[0] if result else None
    
    async def get_recent(
        self, 
        table: str, 
        minutes: int, 
        symbol: str = "BTC"
    ) -> List[Dict]:
        """최근 N분 데이터 조회"""
        try:
            from_time = datetime.utcnow() - timedelta(minutes=minutes)
            
            result = self.client.table(table)\
                .select("*")\
                .eq("symbol", symbol)\
                .gte("timestamp", from_time.isoformat())\
                .order("timestamp", desc=False)\
                .execute()
            
            return result.data
        except Exception as e:
            logger.error(f"Recent query error [{table}]: {e}")
            raise
```

---

### 3.4 수집기 베이스 클래스 (src/collectors/base_collector.py)

```python
"""
수집기 베이스 클래스

모든 수집기는 이 클래스를 상속받아 구현
"""

from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, Any, Optional
from loguru import logger


class BaseCollector(ABC):
    """데이터 수집기 추상 클래스"""
    
    def __init__(self, name: str):
        self.name = name
        self.last_collect_time: Optional[datetime] = None
        self.collect_count = 0
        self.error_count = 0
    
    @abstractmethod
    async def collect(self) -> Dict[str, Any]:
        """
        데이터 수집 (구현 필수)
        
        Returns:
            수집된 데이터 딕셔너리
        """
        pass
    
    @abstractmethod
    async def health_check(self) -> bool:
        """
        연결 상태 확인 (구현 필수)
        
        Returns:
            정상이면 True
        """
        pass
    
    async def safe_collect(self) -> Optional[Dict[str, Any]]:
        """
        안전한 수집 (에러 핸들링 포함)
        """
        try:
            data = await self.collect()
            self.last_collect_time = datetime.utcnow()
            self.collect_count += 1
            return data
        except Exception as e:
            self.error_count += 1
            logger.error(f"[{self.name}] Collect error: {e}")
            return None
    
    def get_stats(self) -> Dict[str, Any]:
        """수집 통계 반환"""
        return {
            "name": self.name,
            "last_collect": self.last_collect_time.isoformat() if self.last_collect_time else None,
            "total_collects": self.collect_count,
            "total_errors": self.error_count,
            "error_rate": self.error_count / max(self.collect_count, 1)
        }
```

---

### 3.5 Upbit 수집기 (src/collectors/upbit_collector.py)

```python
"""
Upbit 가격 데이터 수집기

- BTC/KRW 현재가 수집
- CCXT 라이브러리 사용
"""

import ccxt.async_support as ccxt
from datetime import datetime
from typing import Dict, Any
from loguru import logger

from .base_collector import BaseCollector


class UpbitCollector(BaseCollector):
    """Upbit 가격 수집기"""
    
    def __init__(self, symbol: str = "BTC/KRW"):
        super().__init__(name="upbit")
        self.symbol = symbol
        self.exchange = ccxt.upbit({
            'enableRateLimit': True,
        })
    
    async def collect(self) -> Dict[str, Any]:
        """
        현재가 수집
        
        Returns:
            {
                'timestamp': datetime,
                'symbol': 'BTC',
                'exchange': 'upbit',
                'price': float,
                'volume_24h': float
            }
        """
        ticker = await self.exchange.fetch_ticker(self.symbol)
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'exchange': 'upbit',
            'price': ticker['last'],
            'bid': ticker['bid'],
            'ask': ticker['ask'],
            'volume_24h': ticker['quoteVolume'],  # KRW 기준 거래량
        }
    
    async def fetch_ohlcv(self, timeframe: str = '1m', limit: int = 1) -> list:
        """
        OHLCV 데이터 수집
        
        Args:
            timeframe: '1m', '5m', '1h', '1d' 등
            limit: 캔들 개수
        
        Returns:
            [[timestamp, open, high, low, close, volume], ...]
        """
        ohlcv = await self.exchange.fetch_ohlcv(
            self.symbol, 
            timeframe=timeframe, 
            limit=limit
        )
        return ohlcv
    
    async def health_check(self) -> bool:
        """연결 상태 확인"""
        try:
            await self.exchange.fetch_ticker(self.symbol)
            return True
        except Exception as e:
            logger.warning(f"[upbit] Health check failed: {e}")
            return False
    
    async def close(self):
        """연결 종료"""
        await self.exchange.close()
```

---

### 3.6 Binance 수집기 (src/collectors/binance_collector.py)

```python
"""
Binance 가격 및 펀딩비 수집기

- BTCUSDT 현재가 수집
- BTCUSDT 선물 펀딩비 수집
"""

import ccxt.async_support as ccxt
from datetime import datetime
from typing import Dict, Any, Optional
from loguru import logger

from .base_collector import BaseCollector


class BinanceCollector(BaseCollector):
    """Binance 가격/펀딩비 수집기"""
    
    def __init__(self, symbol: str = "BTC/USDT"):
        super().__init__(name="binance")
        self.symbol = symbol
        self.futures_symbol = "BTC/USDT:USDT"  # 선물 심볼
        
        # 현물 거래소
        self.spot = ccxt.binance({
            'enableRateLimit': True,
        })
        
        # 선물 거래소
        self.futures = ccxt.binance({
            'enableRateLimit': True,
            'options': {'defaultType': 'future'}
        })
    
    async def collect(self) -> Dict[str, Any]:
        """
        현재가 수집 (현물)
        
        Returns:
            {
                'timestamp': datetime,
                'symbol': 'BTC',
                'exchange': 'binance',
                'price': float (USDT)
            }
        """
        ticker = await self.spot.fetch_ticker(self.symbol)
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'exchange': 'binance',
            'price': ticker['last'],
            'bid': ticker['bid'],
            'ask': ticker['ask'],
            'volume_24h': ticker['quoteVolume'],  # USDT 기준 거래량
        }
    
    async def fetch_funding_rate(self) -> Optional[Dict[str, Any]]:
        """
        펀딩비 수집 (8시간마다)
        
        Returns:
            {
                'timestamp': datetime,
                'symbol': 'BTC',
                'funding_rate': float,
                'next_funding_time': datetime
            }
        """
        try:
            # 펀딩비 정보 조회
            funding = await self.futures.fetch_funding_rate(self.futures_symbol)
            
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'symbol': 'BTC',
                'exchange': 'binance',
                'funding_rate': funding['fundingRate'],
                'funding_timestamp': funding['fundingTimestamp'],
                'next_funding_time': funding.get('nextFundingTimestamp'),
            }
        except Exception as e:
            logger.error(f"[binance] Funding rate error: {e}")
            return None
    
    async def health_check(self) -> bool:
        """연결 상태 확인"""
        try:
            await self.spot.fetch_ticker(self.symbol)
            return True
        except Exception as e:
            logger.warning(f"[binance] Health check failed: {e}")
            return False
    
    async def close(self):
        """연결 종료"""
        await self.spot.close()
        await self.futures.close()
```

---

### 3.7 환율 수집기 (src/collectors/fx_collector.py)

```python
"""
USD/KRW 환율 수집기

- tvDatafeed 라이브러리 사용
- TradingView FX_IDC:USDKRW 데이터
- 무료, 로그인 불필요
"""

import time
from datetime import datetime
from typing import Dict, Any, Optional, List
from collections import deque
from tvDatafeed import TvDatafeed, Interval
from loguru import logger

from .base_collector import BaseCollector


class FXCollector(BaseCollector):
    """TradingView 환율 수집기"""
    
    def __init__(self, ma_period_minutes: int = 720):
        super().__init__(name="fx")
        self.tv = TvDatafeed()  # 로그인 불필요
        self.symbol = "USDKRW"
        self.exchange = "FX_IDC"
        
        # 12시간 MA용 캐시
        self.ma_period = ma_period_minutes
        self.rate_cache: deque = deque(maxlen=ma_period_minutes)
        
        # 캐시
        self._last_rate: Optional[float] = None
        self._cache_time: Optional[datetime] = None
        self._cache_ttl = 30  # 30초 캐시
    
    async def collect(self) -> Dict[str, Any]:
        """
        현재 환율 수집
        
        Returns:
            {
                'timestamp': datetime,
                'symbol': 'FX_IDC:USDKRW',
                'rate': float,
                'ma_12h': float (있으면)
            }
        """
        # 캐시 확인
        if self._is_cache_valid():
            rate = self._last_rate
        else:
            rate = await self._fetch_rate()
            self._update_cache(rate)
        
        # MA 캐시에 추가
        self.rate_cache.append(rate)
        
        # MA 계산
        ma_12h = self._calculate_ma() if len(self.rate_cache) >= 60 else None
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': f'{self.exchange}:{self.symbol}',
            'rate': rate,
            'ma_12h': ma_12h,
            'source': 'tvDatafeed'
        }
    
    async def _fetch_rate(self) -> float:
        """TradingView에서 환율 조회"""
        try:
            df = self.tv.get_hist(
                symbol=self.symbol,
                exchange=self.exchange,
                interval=Interval.in_1_minute,
                n_bars=1
            )
            
            if df is not None and not df.empty:
                return float(df['close'].iloc[-1])
            
            raise ValueError("No data returned from TradingView")
            
        except Exception as e:
            logger.error(f"[fx] TradingView fetch error: {e}")
            raise
    
    async def fetch_historical(self, bars: int = 720) -> List[float]:
        """
        과거 환율 데이터 조회 (MA 초기화용)
        
        Args:
            bars: 조회할 캔들 수 (720 = 12시간)
        """
        try:
            df = self.tv.get_hist(
                symbol=self.symbol,
                exchange=self.exchange,
                interval=Interval.in_1_minute,
                n_bars=bars
            )
            
            if df is not None and not df.empty:
                return df['close'].tolist()
            
            return []
        except Exception as e:
            logger.error(f"[fx] Historical fetch error: {e}")
            return []
    
    async def initialize_ma(self):
        """MA 초기화 (시작 시 호출)"""
        logger.info(f"[fx] Initializing MA with {self.ma_period} bars...")
        
        rates = await self.fetch_historical(self.ma_period)
        for rate in rates:
            self.rate_cache.append(rate)
        
        logger.info(f"[fx] MA initialized with {len(self.rate_cache)} data points")
    
    def _calculate_ma(self) -> float:
        """12시간 이동평균 계산"""
        if len(self.rate_cache) == 0:
            return 0.0
        return sum(self.rate_cache) / len(self.rate_cache)
    
    def _is_cache_valid(self) -> bool:
        """캐시 유효성 확인"""
        if self._last_rate is None or self._cache_time is None:
            return False
        elapsed = (datetime.utcnow() - self._cache_time).total_seconds()
        return elapsed < self._cache_ttl
    
    def _update_cache(self, rate: float):
        """캐시 업데이트"""
        self._last_rate = rate
        self._cache_time = datetime.utcnow()
    
    def get_latest_rate(self) -> Optional[float]:
        """최신 환율 반환 (캐시)"""
        return self._last_rate
    
    def get_ma_12h(self) -> Optional[float]:
        """12시간 MA 반환"""
        if len(self.rate_cache) < 60:  # 최소 1시간
            return None
        return self._calculate_ma()
    
    async def health_check(self) -> bool:
        """연결 상태 확인"""
        try:
            await self._fetch_rate()
            return True
        except Exception:
            return False
```

---

### 3.8 김프 계산기 (src/calculators/kimp_calculator.py)

```python
"""
김치프리미엄 계산기

공식: (Upbit가격 - Binance가격 × 환율) / (Binance가격 × 환율) × 100
"""

from datetime import datetime
from typing import Dict, Any
from loguru import logger


class KimpCalculator:
    """김프율 계산기"""
    
    def calculate(
        self,
        upbit_price: float,
        binance_price: float,
        exchange_rate: float
    ) -> Dict[str, Any]:
        """
        김프율 계산
        
        Args:
            upbit_price: Upbit BTC/KRW 가격
            binance_price: Binance BTC/USDT 가격
            exchange_rate: USD/KRW 환율
        
        Returns:
            {
                'timestamp': datetime,
                'symbol': 'BTC',
                'upbit_price': float,
                'binance_price': float,
                'exchange_rate': float,
                'binance_krw': float,  # Binance 가격 KRW 환산
                'kimp_percent': float  # 김프율 (%)
            }
        """
        # Binance 가격을 KRW로 환산
        binance_krw = binance_price * exchange_rate
        
        # 김프율 계산
        kimp_percent = ((upbit_price - binance_krw) / binance_krw) * 100
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'upbit_price': upbit_price,
            'binance_price': binance_price,
            'exchange_rate': exchange_rate,
            'binance_krw': round(binance_krw, 2),
            'kimp_percent': round(kimp_percent, 4)
        }
```

---

### 3.9 Z-Score 계산기 (src/calculators/zscore_calculator.py)

```python
"""
Z-Score 계산기

- 1시간(60분) 롤링 윈도우 기반
- 김프% 시계열 대상
"""

from collections import deque
from typing import Optional, Dict, Any
from datetime import datetime
import math


class ZScoreCalculator:
    """Z-Score 계산기"""
    
    def __init__(self, window_minutes: int = 60):
        """
        Args:
            window_minutes: 롤링 윈도우 크기 (기본 60분 = 1시간)
        """
        self.window = window_minutes
        self.kimp_history: deque = deque(maxlen=window_minutes)
    
    def add_kimp(self, kimp_percent: float) -> Optional[Dict[str, Any]]:
        """
        김프값 추가 및 Z-Score 계산
        
        Args:
            kimp_percent: 현재 김프율 (%)
        
        Returns:
            Z-Score 계산 결과 (데이터 부족시 None)
        """
        self.kimp_history.append(kimp_percent)
        
        # 최소 데이터 확인 (30분 이상)
        if len(self.kimp_history) < 30:
            return None
        
        # 평균, 표준편차 계산
        mean = sum(self.kimp_history) / len(self.kimp_history)
        variance = sum((x - mean) ** 2 for x in self.kimp_history) / len(self.kimp_history)
        std = math.sqrt(variance)
        
        # Z-Score 계산 (0 나눗셈 방지)
        if std == 0:
            zscore = 0.0
        else:
            zscore = (kimp_percent - mean) / std
        
        # 최근 5분 최저 Z-Score (회귀 판단용)
        recent_5min = list(self.kimp_history)[-5:] if len(self.kimp_history) >= 5 else list(self.kimp_history)
        zscore_5m_min = min((k - mean) / std if std > 0 else 0 for k in recent_5min)
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'kimp_current': kimp_percent,
            'kimp_mean': round(mean, 4),
            'kimp_std': round(std, 4),
            'zscore': round(zscore, 4),
            'zscore_5m_min': round(zscore_5m_min, 4),
            'window_size': len(self.kimp_history)
        }
    
    def get_current_zscore(self) -> Optional[float]:
        """현재 Z-Score 반환"""
        if len(self.kimp_history) < 30:
            return None
        
        mean = sum(self.kimp_history) / len(self.kimp_history)
        variance = sum((x - mean) ** 2 for x in self.kimp_history) / len(self.kimp_history)
        std = math.sqrt(variance)
        
        if std == 0:
            return 0.0
        
        current_kimp = self.kimp_history[-1]
        return (current_kimp - mean) / std
    
    def check_entry_signal(self) -> Dict[str, Any]:
        """
        진입 신호 체크
        
        Returns:
            {
                'level1_triggered': bool,  # Z ≤ -2.0 회귀
                'level2_triggered': bool,  # Z ≤ -2.5 회귀
                'current_zscore': float
            }
        """
        if len(self.kimp_history) < 30:
            return {
                'level1_triggered': False,
                'level2_triggered': False,
                'current_zscore': None
            }
        
        mean = sum(self.kimp_history) / len(self.kimp_history)
        variance = sum((x - mean) ** 2 for x in self.kimp_history) / len(self.kimp_history)
        std = math.sqrt(variance) if variance > 0 else 0.0001
        
        # 최근 5분 Z-Score 계산
        recent_5min = list(self.kimp_history)[-5:]
        recent_zscores = [(k - mean) / std for k in recent_5min]
        
        min_zscore_5m = min(recent_zscores)
        current_zscore = recent_zscores[-1]
        
        # 회귀 판단: 최저점이 임계값 이하였다가 현재 회복
        level1_triggered = min_zscore_5m <= -2.0 and current_zscore > -2.0
        level2_triggered = min_zscore_5m <= -2.5 and current_zscore > -2.5
        
        return {
            'level1_triggered': level1_triggered,
            'level2_triggered': level2_triggered,
            'current_zscore': round(current_zscore, 4),
            'min_zscore_5m': round(min_zscore_5m, 4)
        }
```

---

### 3.10 볼린저 밴드 계산기 (src/calculators/bb_calculator.py)

```python
"""
볼린저 밴드 계산기

- 김프% 시계열 대상 (가격 아님!)
- 20기간, 2σ
"""

from collections import deque
from typing import Optional, Dict, Any
from datetime import datetime
import math


class BollingerBandCalculator:
    """볼린저 밴드 계산기 (김프% 기반)"""
    
    def __init__(self, period: int = 20, std_mult: float = 2.0):
        """
        Args:
            period: MA 기간 (기본 20)
            std_mult: 표준편차 배수 (기본 2.0)
        """
        self.period = period
        self.std_mult = std_mult
        self.kimp_history: deque = deque(maxlen=period)
    
    def add_kimp(self, kimp_percent: float) -> Optional[Dict[str, Any]]:
        """
        김프값 추가 및 BB 계산
        
        Args:
            kimp_percent: 현재 김프율 (%)
        
        Returns:
            BB 계산 결과 (데이터 부족시 None)
        """
        self.kimp_history.append(kimp_percent)
        
        # 최소 기간 확인
        if len(self.kimp_history) < self.period:
            return None
        
        # 평균, 표준편차 계산
        mean = sum(self.kimp_history) / len(self.kimp_history)
        variance = sum((x - mean) ** 2 for x in self.kimp_history) / len(self.kimp_history)
        std = math.sqrt(variance)
        
        # 밴드 계산
        upper = mean + self.std_mult * std
        lower = mean - self.std_mult * std
        
        # 돌파 상태
        is_upper_break = kimp_percent > upper
        is_lower_break = kimp_percent < lower
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'symbol': 'BTC',
            'kimp_current': kimp_percent,
            'bb_upper': round(upper, 4),
            'bb_middle': round(mean, 4),
            'bb_lower': round(lower, 4),
            'is_upper_break': is_upper_break,
            'is_lower_break': is_lower_break,
            'period': self.period,
            'std_mult': self.std_mult
        }
    
    def get_upper_band(self) -> Optional[float]:
        """현재 상단 밴드 반환"""
        if len(self.kimp_history) < self.period:
            return None
        
        mean = sum(self.kimp_history) / len(self.kimp_history)
        variance = sum((x - mean) ** 2 for x in self.kimp_history) / len(self.kimp_history)
        std = math.sqrt(variance)
        
        return mean + self.std_mult * std
    
    def check_breakout(self, kimp_percent: float, min_profit: float = 0.48) -> Dict[str, Any]:
        """
        Breakout 탈출 조건 체크 (Ver 3.0 Track B)
        
        Args:
            kimp_percent: 현재 김프율
            min_profit: 최소 수익률 (기본 0.48%)
        
        Returns:
            {
                'is_breakout': bool,
                'bb_upper': float,
                'current_kimp': float
            }
        """
        upper = self.get_upper_band()
        
        if upper is None:
            return {
                'is_breakout': False,
                'bb_upper': None,
                'current_kimp': kimp_percent
            }
        
        is_breakout = kimp_percent > upper
        
        return {
            'is_breakout': is_breakout,
            'bb_upper': round(upper, 4),
            'current_kimp': kimp_percent
        }
```

---

### 3.11 메인 스케줄러 (src/main.py)

```python
"""
메인 데이터 수집 서비스

Docker 컨테이너 엔트리포인트
24/7 데이터 수집 실행
"""

import os
import asyncio
from datetime import datetime
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from loguru import logger
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

from database.supabase_client import SupabaseClient
from collectors.upbit_collector import UpbitCollector
from collectors.binance_collector import BinanceCollector
from collectors.fx_collector import FXCollector
from calculators.kimp_calculator import KimpCalculator
from calculators.zscore_calculator import ZScoreCalculator
from calculators.bb_calculator import BollingerBandCalculator


class DataCollectorService:
    """메인 데이터 수집 서비스"""
    
    def __init__(self):
        # 설정
        self.interval = int(os.getenv('COLLECT_INTERVAL_SECONDS', 60))
        
        # 데이터베이스
        self.db = SupabaseClient()
        
        # 수집기
        self.upbit = UpbitCollector()
        self.binance = BinanceCollector()
        self.fx = FXCollector(
            ma_period_minutes=int(os.getenv('FX_MA_PERIOD_MINUTES', 720))
        )
        
        # 계산기
        self.kimp_calc = KimpCalculator()
        self.zscore_calc = ZScoreCalculator(
            window_minutes=int(os.getenv('ZSCORE_WINDOW_MINUTES', 60))
        )
        self.bb_calc = BollingerBandCalculator(
            period=int(os.getenv('BB_PERIOD', 20)),
            std_mult=float(os.getenv('BB_STD_MULT', 2.0))
        )
        
        # 스케줄러
        self.scheduler = AsyncIOScheduler()
    
    async def initialize(self):
        """초기화 (MA 데이터 로드)"""
        logger.info("Initializing service...")
        
        # 환율 MA 초기화
        await self.fx.initialize_ma()
        
        # 헬스체크
        upbit_ok = await self.upbit.health_check()
        binance_ok = await self.binance.health_check()
        fx_ok = await self.fx.health_check()
        
        logger.info(f"Health check - Upbit: {upbit_ok}, Binance: {binance_ok}, FX: {fx_ok}")
        
        if not all([upbit_ok, binance_ok, fx_ok]):
            raise RuntimeError("Health check failed")
    
    async def collect_and_save(self):
        """메인 수집 작업 (1분마다 실행)"""
        try:
            # 1. 가격 수집
            upbit_data = await self.upbit.safe_collect()
            binance_data = await self.binance.safe_collect()
            fx_data = await self.fx.safe_collect()
            
            if not all([upbit_data, binance_data, fx_data]):
                logger.warning("Some data collection failed, skipping this cycle")
                return
            
            # 2. 김프 계산
            kimp_data = self.kimp_calc.calculate(
                upbit_price=upbit_data['price'],
                binance_price=binance_data['price'],
                exchange_rate=fx_data['rate']
            )
            
            # 3. 지표 계산
            zscore_data = self.zscore_calc.add_kimp(kimp_data['kimp_percent'])
            bb_data = self.bb_calc.add_kimp(kimp_data['kimp_percent'])
            
            # 4. DB 저장
            # kimp_1m 테이블
            await self.db.insert('kimp_1m', {
                'timestamp': kimp_data['timestamp'],
                'symbol': 'BTC',
                'upbit_price': kimp_data['upbit_price'],
                'binance_price': kimp_data['binance_price'],
                'exchange_rate': kimp_data['exchange_rate'],
                'kimp_open': kimp_data['kimp_percent'],
                'kimp_high': kimp_data['kimp_percent'],
                'kimp_low': kimp_data['kimp_percent'],
                'kimp_close': kimp_data['kimp_percent'],
            })
            
            # fx_rates 테이블
            await self.db.insert('fx_rates', {
                'timestamp': fx_data['timestamp'],
                'symbol': fx_data['symbol'],
                'rate': fx_data['rate'],
                'ma_12h': fx_data.get('ma_12h'),
                'source': fx_data['source']
            })
            
            # zscore_log 테이블
            if zscore_data:
                await self.db.insert('zscore_log', zscore_data)
            
            # bb_log 테이블
            if bb_data:
                await self.db.insert('bb_log', bb_data)
            
            # 로그
            logger.info(
                f"[{datetime.utcnow().strftime('%H:%M:%S')}] "
                f"Kimp: {kimp_data['kimp_percent']:.2f}% | "
                f"FX: {fx_data['rate']:.2f} | "
                f"Z: {zscore_data['zscore']:.2f if zscore_data else 'N/A'}"
            )
            
        except Exception as e:
            logger.error(f"Collection error: {e}")
    
    async def collect_funding_rate(self):
        """펀딩비 수집 (8시간마다)"""
        try:
            funding_data = await self.binance.fetch_funding_rate()
            if funding_data:
                await self.db.insert('funding_rates', funding_data)
                logger.info(f"Funding rate saved: {funding_data['funding_rate']:.6f}")
        except Exception as e:
            logger.error(f"Funding rate error: {e}")
    
    def start(self):
        """스케줄러 시작"""
        # 1분마다 메인 수집
        self.scheduler.add_job(
            self.collect_and_save,
            IntervalTrigger(seconds=self.interval),
            id='main_collector',
            name='Main Data Collector'
        )
        
        # 8시간마다 펀딩비 수집
        self.scheduler.add_job(
            self.collect_funding_rate,
            IntervalTrigger(hours=8),
            id='funding_collector',
            name='Funding Rate Collector'
        )
        
        self.scheduler.start()
        logger.info(f"Scheduler started (interval: {self.interval}s)")
    
    async def shutdown(self):
        """종료 처리"""
        logger.info("Shutting down...")
        self.scheduler.shutdown()
        await self.upbit.close()
        await self.binance.close()


async def main():
    """메인 함수"""
    service = DataCollectorService()
    
    try:
        # 초기화
        await service.initialize()
        
        # 스케줄러 시작
        service.start()
        
        # 첫 수집 즉시 실행
        await service.collect_and_save()
        
        # 무한 대기
        while True:
            await asyncio.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
    finally:
        await service.shutdown()


if __name__ == "__main__":
    # 로그 설정
    logger.add(
        "logs/collector_{time}.log",
        rotation="1 day",
        retention="30 days",
        level=os.getenv('LOG_LEVEL', 'INFO')
    )
    
    asyncio.run(main())
```

---

### 3.12 Docker 설정

#### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# 시스템 의존성
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Python 의존성
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 복사
COPY src/ ./src/

# 로그 디렉토리
RUN mkdir -p logs

# 환경 변수
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# 실행
CMD ["python", "src/main.py"]
```

#### docker-compose.yml

```yaml
version: '3.8'

services:
  data-collector:
    build: .
    container_name: kimp-data-collector
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "python", "-c", "import sys; sys.exit(0)"]
      interval: 60s
      timeout: 10s
      retries: 3
```

---

## 4. SQL 마이그레이션

> 상세 스키마: [`strategies/kimchi_premium/DB_SCHEMA.md`](../strategies/kimchi_premium/DB_SCHEMA.md)

### 4.1 마이그레이션 파일 순서

```
supabase/migrations/
├── 001_init_extensions.sql      # 확장 기능
├── 002_create_kimp_tables.sql   # kimp_ticks, kimp_1m
├── 003_create_fx_tables.sql     # fx_rates, fx_filter_log
├── 004_create_indicator_tables.sql  # zscore_log, bb_log
├── 005_create_trade_tables.sql  # positions, trades, orders
└── 006_create_views.sql         # 모니터링 뷰
```

---

## 5. 테스트 체크리스트

### 5.1 수집기 테스트

```bash
# Upbit 연결 테스트
python -c "
import asyncio
from src.collectors.upbit_collector import UpbitCollector

async def test():
    c = UpbitCollector()
    print(await c.collect())
    await c.close()

asyncio.run(test())
"

# Binance 연결 테스트
python -c "
import asyncio
from src.collectors.binance_collector import BinanceCollector

async def test():
    c = BinanceCollector()
    print(await c.collect())
    await c.close()

asyncio.run(test())
"

# 환율 테스트
python -c "
import asyncio
from src.collectors.fx_collector import FXCollector

async def test():
    c = FXCollector()
    print(await c.collect())

asyncio.run(test())
"
```

### 5.2 통합 테스트

```bash
# Docker 로컬 실행
docker-compose up --build

# 로그 확인
docker-compose logs -f

# 1분 후 DB 확인 (Supabase Dashboard)
```

---

## 6. Vultr 배포 가이드

### 6.1 서버 요구사항

| 항목 | 최소 | 권장 |
|:---|:---|:---|
| vCPU | 1 | 2 |
| RAM | 1GB | 2GB |
| Storage | 25GB | 50GB |
| OS | Ubuntu 22.04 | Ubuntu 22.04 |
| 월 비용 | $5 | $10 |

### 6.2 배포 스크립트

```bash
#!/bin/bash
# deploy.sh

# Docker 설치
curl -fsSL https://get.docker.com | sh

# 레포 클론
git clone https://github.com/vsun410/trading-platform-storage.git
cd trading-platform-storage

# 환경 변수 설정
cp .env.example .env
nano .env  # 수동 편집

# 빌드 & 실행
docker-compose up -d --build

# 상태 확인
docker-compose ps
docker-compose logs --tail=50
```

---

**버전**: 3.0  
**작성일**: 2025-12-15  
**용도**: Claude Code 구현 참조용
