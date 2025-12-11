# 🗄️ Storage 세부 기획서

**Repository:** trading-platform-storage  
**Version:** 1.0  
**Date:** 2025-12-11  
**Tech Stack:** Supabase (PostgreSQL)

---

## 1. 개요

### 1.1 목적

전체 트레이딩 플랫폼의 데이터를 중앙에서 관리하는 저장소입니다. 시세 데이터, 주문/체결 기록, 포지션 현황, 전략 파라미터, 백테스트 결과 등 모든 데이터가 이 레포를 통해 저장됩니다.

### 1.2 핵심 책임

- **시세 데이터:** OHLCV, 김프율, 펀딩비 저장
- **거래 기록:** 주문, 체결, 포지션 이력 관리
- **전략 관리:** 파라미터, 백테스트 결과 보관
- **인프라:** Docker, DB 스키마, 마이그레이션
- **시스템 로그:** 에러, 이벤트 추적

### 1.3 연관 레포지토리

| 레포 | 관계 | 데이터 흐름 |
|------|------|-------------|
| research | 데이터 소비자 | storage → 시세 → research |
| order | 데이터 생산자 | order → 주문/체결 → storage |
| portfolio | 데이터 소비자 | storage → 거래이력 → portfolio |

---

## 2. 기술 스택

### 2.1 Supabase 선택 이유

| 장점 | 설명 |
|------|------|
| PostgreSQL 기반 | 강력한 SQL, JSONB, 트랜잭션 지원 |
| 로컬 + 클라우드 | Docker로 로컬 개발, Cloud로 운영 동일 환경 |
| Free Tier | 500MB DB, 1GB Storage 무료 |
| 내장 기능 | 인증, Storage, Realtime 기본 제공 |
| 마이그레이션 | Supabase CLI로 스키마 버전 관리 |

### 2.2 인프라 구성

| 환경 | 기술 | 접속 정보 |
|------|------|-----------|
| 로컬 개발 | Supabase CLI + Docker | localhost:54322 |
| Studio UI | 웹 기반 DB 관리 | localhost:54323 |
| REST API | PostgREST 자동 생성 | localhost:54321 |
| 운영 (Cloud) | Supabase Cloud | *.supabase.co |

---

## 3. 데이터베이스 스키마

### 3.1 테이블 구조

#### 3.1.1 ohlcv (시세 데이터)

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
    UNIQUE(timestamp, symbol, exchange)
);
```

#### 3.1.2 orders (주문)

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,      -- BUY, SELL
    type VARCHAR(20) NOT NULL,      -- MARKET, LIMIT
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8),
    status VARCHAR(20) NOT NULL,    -- PENDING, FILLED, CANCELLED
    strategy VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 3.1.3 fills (체결)

```sql
CREATE TABLE fills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8) NOT NULL,
    commission DECIMAL(20, 8),
    filled_at TIMESTAMPTZ NOT NULL
);
```

#### 3.1.4 positions (포지션)

```sql
CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,      -- LONG, SHORT
    quantity DECIMAL(20, 8) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    unrealized_pnl DECIMAL(20, 8),
    strategy VARCHAR(50),
    UNIQUE(exchange, symbol, strategy)
);
```

#### 3.1.5 strategy_params (전략 파라미터)

```sql
CREATE TABLE strategy_params (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL UNIQUE,
    params JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true
);
```

#### 3.1.6 backtest_results (백테스트 결과)

```sql
CREATE TABLE backtest_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_return DECIMAL(10, 4),
    sharpe_ratio DECIMAL(10, 4),
    max_drawdown DECIMAL(10, 4),
    win_rate DECIMAL(10, 4),
    params JSONB
);
```

### 3.2 인덱스 전략

| 테이블 | 인덱스 | 용도 |
|--------|--------|------|
| ohlcv | (symbol, timestamp DESC) | 시계열 조회 |
| orders | (exchange, status) | 상태별 조회 |
| fills | (order_id) | 주문별 체결 |
| positions | (exchange, symbol) | 포지션 조회 |

---

## 4. 디렉토리 구조

```
trading-platform-storage/
├── README.md
├── docker-compose.yml           # 로컬 Supabase
│
├── docs/
│   ├── SCHEMA.md                # 스키마 문서
│   └── DETAILED_SPEC.md         # 세부 기획서 (이 문서)
│
├── supabase/
│   ├── config.toml              # Supabase 설정
│   ├── migrations/              # 스키마 마이그레이션
│   │   ├── 001_initial_schema.sql
│   │   └── 002_add_indexes.sql
│   └── seed.sql                 # 초기 데이터
│
├── scripts/
│   ├── backup.sh                # 백업 스크립트
│   └── restore.sh               # 복구 스크립트
│
└── strategies/                  # 전략 공유 (심볼릭 링크)
```

---

## 5. 사용 가이드

### 5.1 로컬 환경 시작

```bash
# 1. Supabase CLI 설치
brew install supabase/tap/supabase

# 2. 로컬 Supabase 시작
cd trading-platform-storage
supabase start

# 3. 마이그레이션 실행
supabase db reset
```

### 5.2 Python 연결 예시

```python
from supabase import create_client

url = 'http://localhost:54321'
key = 'your-anon-key'
supabase = create_client(url, key)

# 데이터 조회
data = supabase.table('ohlcv').select('*').limit(10).execute()

# 데이터 삽입
supabase.table('orders').insert({
    'exchange': 'upbit',
    'symbol': 'BTC-KRW',
    'side': 'BUY',
    'type': 'MARKET',
    'quantity': 0.001,
    'status': 'PENDING'
}).execute()
```

### 5.3 마이그레이션 관리

```bash
# 새 마이그레이션 생성
supabase migration new add_new_table

# 마이그레이션 적용
supabase db push

# 마이그레이션 상태 확인
supabase migration list
```

---

## 6. 데이터 플로우

### 6.1 시세 데이터 수집

```
거래소 API → DataFetcher → storage.ohlcv
  ↓
  - 업비트: BTC-KRW 1분봉
  - 바이낸스: BTCUSDT 1분봉
  - 환율: USD/KRW
```

### 6.2 거래 데이터 저장

```
order 레포 → OrderExecutor → storage
  ↓
  1. orders 테이블에 주문 기록
  2. fills 테이블에 체결 기록
  3. positions 테이블 업데이트
```

---

## 7. 백업 & 복구

### 7.1 백업 스크립트

```bash
#!/bin/bash
# scripts/backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
pg_dump $DATABASE_URL > backups/backup_$DATE.sql
```

### 7.2 복구 스크립트

```bash
#!/bin/bash
# scripts/restore.sh

psql $DATABASE_URL < backups/$1
```

---

## 8. 구현 로드맵

| 주차 | 작업 | 산출물 |
|------|------|--------|
| 1주차 | DB 스키마 구현 | 마이그레이션 파일, 인덱스 |
| 1주차 | Docker 설정 | docker-compose.yml, Supabase 로컬 |
| 2주차 | 데이터 수집 연동 | research 레포와 연결 |

---

*— 문서 끝 —*
