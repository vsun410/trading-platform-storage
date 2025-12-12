# Changelog

이 문서는 trading-platform-storage 레포지토리의 모든 주요 변경사항을 기록합니다.

형식: [Keep a Changelog](https://keepachangelog.com/ko/1.0.0/)  
버전 관리: [Semantic Versioning](https://semver.org/lang/ko/)

---

## [2.0.0] - 2025-12-12

### 🎯 핵심 변경: TradingView Webhook 환율 수집 체계 도입

기존 REST API 기반 환율 수집에서 **TradingView Webhook 기반**으로 전면 전환했습니다.
Premium 계정 보유로 추가 비용 없이 고품질 FX 데이터를 실시간으로 수집합니다.

### Added (추가)

#### 환율 수집 시스템
- **TradingView Webhook 수신 서버** (`collector/webhook/fx_webhook_server.py`)
  - FastAPI 기반 Webhook 엔드포인트 (`POST /webhook/fx`)
  - Background Tasks로 10초 타임아웃 내 응답
  - 최신 환율 조회 API (`GET /fx/latest`)
  
- **Pine Script** (`collector/webhook/pine_scripts/usdkrw_sender.pine`)
  - FX_IDC:USDKRW 1분봉 OHLC 데이터 전송
  - 봉 마감 시 자동 Alert 트리거
  - JSON 포맷 Webhook payload

- **백업 수집기** (`collector/collectors/exchange_rate_backup.py`)
  - dunamu API (업비트 사용, 무료, 실시간)
  - 한국수출입은행 API (일 1회, 기준점)
  - TradingView 2분 이상 지연 시 자동 전환

#### 문서
- **TRADINGVIEW_SETUP.md** - TradingView 설정 전용 가이드
  - Premium 계정 요구사항
  - Alert 생성 단계별 가이드
  - Webhook 빈도 제한 (3분당 15회)
  - 문제 해결 가이드

### Changed (변경)

#### DATA_COLLECTION.md 전면 개편
- 환율 수집 아키텍처 변경
  ```
  Before: 외부 REST API (dunamu, 한국수출입은행) 단독
  After:  TradingView Webhook (주) + dunamu API (백업)
  ```
- KimpCalculator 환율 소스 우선순위 추가
  - 1순위: TradingView (2분 이내)
  - 2순위: dunamu API
  - 3순위: 한국수출입은행

#### SCHEMA.md 스키마 업데이트
- `exchange_rates` 테이블 확장
  ```sql
  -- 추가된 컬럼
  open DECIMAL(20, 8)   -- TradingView 시가
  high DECIMAL(20, 8)   -- TradingView 고가
  low DECIMAL(20, 8)    -- TradingView 저가
  ```
- `kimp_rates` 테이블에 `rate_source` 컬럼 추가
- 마이그레이션 SQL 제공 (v1.0 → v2.0)

#### docker-compose.yml 업데이트
- data-collector 포트 8000 노출 (Webhook 수신)
- 환경변수 추가: `WEBHOOK_PORT`, `KOREAEXIM_API_KEY`
- nginx HTTPS 프록시 옵션 추가

### 디렉토리 구조 변경

```
collector/
├── webhook/                    # 🆕 Webhook 수신
│   ├── fx_webhook_server.py
│   └── pine_scripts/
│       └── usdkrw_sender.pine
├── collectors/
│   ├── ohlcv_collector.py
│   ├── orderbook_collector.py
│   └── exchange_rate_backup.py # 🆕 백업 수집기
└── ...
```

### 비용 영향
| 방법 | 월 비용 | 상태 |
|------|--------|------|
| OANDA API | $199-1,499 | ❌ 미채택 |
| Twelve Data | $229 | ❌ 미채택 |
| TradingView Webhook | **$0** | ✅ 채택 (Premium 구독 포함) |

---

## [1.1.0] - 2025-12-11

### Added
- 기본 데이터 수집 아키텍처 설계
- CCXT 기반 OHLCV/호가 수집기
- Supabase 연동 설정
- Docker 기반 배포 구성

### 문서
- DATA_COLLECTION.md - 데이터 수집 가이드
- SCHEMA.md - 데이터베이스 스키마
- DETAILED_SPEC.md - 세부 기획서

---

## [1.0.0] - 2025-12-10

### Added
- 초기 레포지토리 생성
- README.md 작성
- 기본 디렉토리 구조 설정

---

## 향후 계획 (Upcoming)

### [2.1.0] - 예정
- [ ] TimescaleDB 하이퍼테이블 적용 (P1)
- [ ] Redis Streams 실시간 파이프라인 (P1)
- [ ] 데이터 품질 모니터링 대시보드 (P2)

---

*— Changelog 끝 —*
