# Changelog

이 문서는 trading-platform-storage 레포지토리의 모든 주요 변경사항을 기록합니다.

형식: [Keep a Changelog](https://keepachangelog.com/ko/1.0.0/)  
버전 관리: [Semantic Versioning](https://semver.org/lang/ko/)

---

## [3.0.0] - 2025-12-14

### 🎯 핵심 변경: Ver 3.0 전략 지원 - 환율 필터 + Breakout Rescue

김치프리미엄 전략 Ver 3.0의 새로운 기능들을 지원하기 위한 DB 스키마 및 데이터 수집 체계를 업데이트했습니다.

### Added (추가)

#### 신규 테이블
- **fx_rates** - TradingView 환율 데이터 저장
  - FX_IDC:USDKRW 심볼 기본값
  - 12시간 이동평균 (ma_12h) 컬럼
  - TradingView 데이터 소스 메타데이터

- **fx_filter_log** - 환율 필터 상태 로그
  - 현재 환율, MA, threshold 기록
  - is_blocked (진입 차단 여부) 플래그
  - surge_pct (급등률) 기록

- **bb_log** - 볼린저 밴드 로그 (김프 % 기반)
  - bb_upper, bb_middle, bb_lower 값
  - is_upper_break (상단 돌파) 플래그
  - 파라미터 (period, std_mult) 기록

#### 신규 문서
- **TRADINGVIEW_FX.md** - TradingView 환율 데이터 수집 명세
  - tvDatafeed / tradingview-ta / WebSocket 방법
  - 12시간 MA 계산 로직
  - 환율 필터 구현 가이드
  - 스케줄링 및 에러 처리

### Changed (변경)

#### positions 테이블 확장
```sql
-- Ver 3.0 추가 컬럼
exit_reason VARCHAR(20)        -- 'Target' or 'Breakout'
exit_bb_upper DECIMAL(10, 4)   -- 청산 시점 BB 상단
entry_fx_rate DECIMAL(10, 4)   -- 진입 시점 환율
entry_fx_ma DECIMAL(10, 4)     -- 진입 시점 환율 MA
```

#### zscore_log 테이블 확장
```sql
-- Ver 3.0 추가 컬럼
zscore_5m_min DECIMAL(10, 4)   -- 5분간 최저 Z-Score
level1_reversion BOOLEAN       -- -2.0 회귀 발생
level2_reversion BOOLEAN       -- -2.5 회귀 발생
```

#### 신규 뷰
- **v_position_exit_status** - 포지션 청산 조건 모니터링
  - Track A (Target) 조건 체크
  - Track B (Breakout) 조건 체크
  
- **v_fx_filter_status** - 환율 필터 현재 상태
- **v_exit_reason_stats** - 청산 이유별 통계

#### 신규 함수
- `check_fx_surge()` - 환율 급등 체크
- `check_bb_breakout()` - BB 상단 돌파 체크

### Migration
- Ver 2.0 → Ver 3.0 마이그레이션 SQL 제공
- 하위 호환성 유지 (기존 데이터 보존)

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

### Changed (변경)

#### DATA_COLLECTION.md 전면 개편
- 환율 수집 아키텍처 변경
  ```
  Before: 외부 REST API (dunamu, 한국수출입은행) 단독
  After:  TradingView Webhook (주) + dunamu API (백업)
  ```

---

## [1.1.0] - 2025-12-11

### Added
- 기본 데이터 수집 아키텍처 설계
- CCXT 기반 OHLCV/호가 수집기
- Supabase 연동 설정
- Docker 기반 배포 구성

---

## [1.0.0] - 2025-12-10

### Added
- 초기 레포지토리 생성
- README.md 작성
- 기본 디렉토리 구조 설정

---

*— Changelog 끝 —*
