# Trading Platform - Storage

데이터 저장소 & 인프라

## 🎯 목적

- 시세 데이터 저장
- 주문/체결 기록
- 포지션 관리
- 전략 파라미터 보관
- 백테스트 결과 저장
- 시스템 로그

## 🗄️ 기술 스택

| 항목 | 기술 |
|:---|:---|
| Database | Supabase (PostgreSQL) |
| 로컬 개발 | Docker + Supabase CLI |
| 클라우드 | Supabase Cloud (Free Tier) |
| 파일 저장 | Supabase Storage |

## 🏗️ 프로젝트 구조

```
trading-platform-storage/
├── README.md
├── docker-compose.yml
├── docs/
│   └── SCHEMA.md
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   │   └── 001_initial_schema.sql
│   └── seed.sql
└── scripts/
    └── backup.sh
```

## 🚀 빠른 시작

### 로컬 개발 (Docker)

```bash
# 1. 클론
git clone https://github.com/vsun410/trading-platform-storage.git
cd trading-platform-storage

# 2. Supabase CLI 설치
brew install supabase/tap/supabase

# 3. 로컬 Supabase 시작
supabase start

# 접속 정보:
# PostgreSQL: localhost:54322
# Studio UI: localhost:54323
# API: localhost:54321
```

### 클라우드 설정

1. [Supabase](https://supabase.com) 가입
2. 새 프로젝트 생성
3. 연결 정보 복사
4. `.env` 파일에 설정

## 📊 주요 테이블

| 테이블 | 설명 |
|:---|:---|
| ohlcv | 시세 데이터 |
| orders | 주문 내역 |
| fills | 체결 내역 |
| positions | 포지션 현황 |
| strategy_params | 전략 파라미터 |
| backtest_results | 백테스트 결과 |
| logs | 시스템 로그 |

## 🔗 관련 레포

| 레포 | 역할 |
|:---|:---|
| [research](https://github.com/vsun410/trading-platform-research) | 전략 연구 |
| [portfolio](https://github.com/vsun410/trading-platform-portfolio) | 포트폴리오 검증 |
| [order](https://github.com/vsun410/trading-platform-order) | 주문 실행 |
