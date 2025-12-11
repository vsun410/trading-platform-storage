# 🗺️ 프로젝트 마스터 로드맵

**Last Updated:** 2025-12-11  
**Status:** Phase 1 진행 중

---

## 📋 프로젝트 개요

### 목표
김프(김치 프리미엄) 차익거래 자동화 시스템 구축

### 레포지토리 구조

```
trading-platform/
├── storage    → 데이터 수집 & 저장 (PostgreSQL + Supabase)
├── research   → 전략 개발 & 백테스트
├── order      → 실거래 실행
└── portfolio  → 성과 분석 & 리스크 관리
```

### 자본 규모
약 2천만원 (중소규모)

---

## 🎯 우선순위 (확정)

```
┌─────────────────────────────────────────────────────────────────┐
│                      개발 우선순위                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1️⃣ Storage (데이터 수집)                                      │
│      └── Docker 24/7 자동 수집                                  │
│      └── 모든 레포에서 접근 가능                                 │
│                                                                 │
│   2️⃣ Research (김프 전략만)                                     │
│      └── 김프 계산 & 신호 생성                                   │
│      └── 기본 백테스트                                          │
│                                                                 │
│   3️⃣ Order (실거래)                                             │
│      └── 업비트/바이낸스 동시 주문                               │
│      └── 95% 자본 투입, 손실 청산 금지                          │
│                                                                 │
│   4️⃣ Research 확장                                              │
│      └── Orderbook 기반 시뮬레이션                              │
│      └── 스트레스 테스트 (전체 시나리오)                         │
│                                                                 │
│   5️⃣ Portfolio (테스트 & 분석)                                  │
│      └── 성과 분석                                              │
│      └── Paper Trading 엔진                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📅 Phase 1: Storage - 데이터 수집 인프라 (2주)

### 목표
- Docker로 24/7 자동 데이터 수집
- 다른 레포에서 언제든 접근 가능한 데이터 파이프라인

### 작업 항목

| 주차 | 작업 | 산출물 | 상태 |
|------|------|--------|------|
| 1주차 | DB 스키마 확장 | orderbook, trades, kimp_rates 테이블 | ⬜ |
| 1주차 | CCXT 수집기 구현 | UpbitCollector, BinanceCollector | ⬜ |
| 1주차 | 환율/김프 계산기 | ExchangeRateCollector, KimpCalculator | ⬜ |
| 2주차 | WebSocket 실시간 | 업비트/바이낸스 호가 스트림 | ⬜ |
| 2주차 | Docker 구성 | docker-compose (DB + Collector) | ⬜ |
| 2주차 | 데이터 접근 클라이언트 | StorageClient (다른 레포용) | ⬜ |

### 핵심 수집 데이터

| 데이터 | 주기 | 용도 |
|--------|------|------|
| OHLCV (1분) | 1분 | 백테스트, 신호 생성 |
| Orderbook | 100ms | 슬리피지 계산, 스트레스 테스트 |
| 펀딩비 | 8시간 | 비용 계산 |
| 환율 | 1분 | 김프 계산 |
| 김프율 | 1분 | 전략 신호 |

### 완료 조건
- [ ] `docker-compose up` 으로 수집 시작
- [ ] 1시간 이상 무중단 수집 확인
- [ ] Research 레포에서 데이터 조회 성공

---

## 📅 Phase 2: Research - 김프 전략 구현 (2주)

### 목표
- 김프 차익거래 전략 신호 생성
- 기본 백테스트로 전략 검증

### 작업 항목

| 주차 | 작업 | 산출물 | 상태 |
|------|------|--------|------|
| 3주차 | Storage 연동 | StorageClient 설정, 데이터 로드 | ⬜ |
| 3주차 | 김프 전략 구현 | KimpStrategy (진입/청산 로직) | ⬜ |
| 3주차 | 신호 생성기 | Signal 클래스, generate_signal() | ⬜ |
| 4주차 | 백테스트 엔진 | BacktestEngine (기본) | ⬜ |
| 4주차 | 성과 지표 | 수익률, Sharpe, MDD 계산 | ⬜ |
| 4주차 | 파라미터 튜닝 | 진입/청산 임계값 최적화 | ⬜ |

### 김프 전략 로직 (확정)

```python
# 진입 조건
IF 김프율 > ENTRY_THRESHOLD (3.0%)
   AND 펀딩비 > 0
   AND 현재_포지션 == NONE:
       → SIGNAL = ENTER

# 청산 조건 (수정됨 - 손실 청산 금지)
IF 순이익 > 0:  # 차익 - 수수료 > 0
       → SIGNAL = EXIT
ELSE:
       → 포지션 유지, 프리미엄 수렴 대기
```

### 완료 조건
- [ ] 김프율 실시간 계산 동작
- [ ] 백테스트 1년 데이터 실행 (30초 이내)
- [ ] Sharpe > 1.0 달성하는 파라미터 발견

---

## 📅 Phase 3: Order - 실거래 시스템 (2주)

### 목표
- 업비트/바이낸스 동시 주문 실행
- 95% 자본 투입, 손실 청산 금지 로직

### 작업 항목

| 주차 | 작업 | 산출물 | 상태 |
|------|------|--------|------|
| 5주차 | 거래소 API 연동 | UpbitExchange, BinanceExchange | ⬜ |
| 5주차 | 주문 실행기 | OrderExecutor (동시 실행) | ⬜ |
| 5주차 | 청산 검증기 | ExitValidator (순이익 체크) | ⬜ |
| 6주차 | 자본 배분 | CapitalAllocator (95% 투입) | ⬜ |
| 6주차 | 중복 방지 | 멱등성 키, 신호 ID 추적 | ⬜ |
| 6주차 | Discord 알림 | 체결/에러 알림 | ⬜ |

### 자본 운용 규칙 (확정)

| 항목 | 설정 |
|------|------|
| 트레이딩 자본 | 95% |
| 예비비 | 5% |
| 청산 조건 | `순이익 > 0` 일 때만 |
| 손실 청산 | 🚫 금지 |

### 완료 조건
- [ ] 바이낸스 테스트넷에서 주문 성공
- [ ] 업비트 Test Order API 검증 통과
- [ ] 동시 주문 지연 < 500ms

---

## 📅 Phase 4: Research 확장 - 고급 시뮬레이션 (3주)

### 목표
- Orderbook 기반 체결 시뮬레이션
- 블랙스완 스트레스 테스트

### 작업 항목

| 주차 | 작업 | 산출물 | 상태 |
|------|------|--------|------|
| 7주차 | Orderbook 시뮬레이터 | OrderbookEngine | ⬜ |
| 7주차 | 슬리피지 모델 | VWAP 기반 SlippageModel | ⬜ |
| 8주차 | 스트레스 시나리오 | ChaosMonkey 엔진 | ⬜ |
| 8주차 | Flash Crash 테스트 | 급락 시나리오 | ⬜ |
| 8주차 | 유동성 고갈 테스트 | 호가 잔량 1/10 시나리오 | ⬜ |
| 9주차 | 네트워크 지연 테스트 | 2000ms 지연 주입 | ⬜ |
| 9주차 | 미체결 테스트 | 부분체결/거부 시나리오 | ⬜ |
| 9주차 | 한쪽 체결 실패 | One-leg Failure 시나리오 | ⬜ |

### 스트레스 시나리오 (전체)

```python
STRESS_SCENARIOS = {
    "flash_crash": "1분 내 10% 급락, 스프레드 10배 확대",
    "liquidity_dry": "호가 잔량 1/10로 감소",
    "latency_spike": "API 응답 50ms → 2000~5000ms",
    "partial_fill": "주문 60%만 체결, 40% 미체결",
    "order_rejection": "주문 30% 502 에러로 실패",
    "one_leg_failure": "업비트 체결, 바이낸스 실패 (또는 반대)",
    "exchange_maintenance": "한쪽 거래소 5분간 접속 불가",
}
```

### 완료 조건
- [ ] 모든 시나리오에서 알고리즘 생존
- [ ] 블랙스완 시 자동 알림 발송
- [ ] One-leg 실패 시 복구 로직 동작

---

## 📅 Phase 5: Portfolio - 분석 & Paper Trading (2주)

### 목표
- 실시간 성과 분석
- 업비트용 Paper Trading 엔진

### 작업 항목

| 주차 | 작업 | 산출물 | 상태 |
|------|------|--------|------|
| 10주차 | 성과 분석 | PerformanceAnalyzer | ⬜ |
| 10주차 | 리스크 지표 | VaR, 상관관계 분석 | ⬜ |
| 11주차 | Paper Trading | VirtualExchange (업비트 대체) | ⬜ |
| 11주차 | 대시보드 | 실시간 모니터링 UI | ⬜ |

### Paper Trading 엔진 (고급)

```python
# 실시간 호가 기반 매칭
class VirtualExchange:
    """업비트 테스트넷 대체"""
    
    def execute_market_order(self, side, quantity):
        # 1. 실시간 호가창 조회
        orderbook = self.get_live_orderbook()
        
        # 2. VWAP 슬리피지 적용
        execution_price = self.slippage_model.calculate(orderbook, quantity)
        
        # 3. 부분 체결 시뮬레이션
        filled_qty = self._simulate_partial_fill(quantity)
        
        # 4. 가상 잔고 업데이트
        self.balance_manager.update(side, filled_qty, execution_price)
        
        return Fill(price=execution_price, quantity=filled_qty)
```

### 완료 조건
- [ ] Paper Trading 1주일 무중단 실행
- [ ] 실거래 대비 오차 < 5%
- [ ] 대시보드에서 실시간 PnL 확인

---

## 📊 전체 타임라인

```
2025년
─────────────────────────────────────────────────────────────────
Week 1-2   │████████│ Phase 1: Storage (데이터 수집)
Week 3-4   │        │████████│ Phase 2: Research (김프 전략)
Week 5-6   │        │        │████████│ Phase 3: Order (실거래)
Week 7-9   │        │        │        │████████████│ Phase 4: Research 확장
Week 10-11 │        │        │        │            │████████│ Phase 5: Portfolio
─────────────────────────────────────────────────────────────────
           │        │        │        │            │        │
           ▼        ▼        ▼        ▼            ▼        ▼
        데이터    전략     실거래   스트레스     분석    완성
        수집     검증      테스트   테스트      대시보드
```

### 마일스톤

| 마일스톤 | 목표일 | 기준 |
|----------|--------|------|
| **M1: 데이터 파이프라인** | 2주차 | 24/7 수집 동작 |
| **M2: 전략 백테스트** | 4주차 | Sharpe > 1.0 |
| **M3: 실거래 준비** | 6주차 | 테스트넷 주문 성공 |
| **M4: 스트레스 테스트** | 9주차 | 모든 시나리오 통과 |
| **M5: 운영 준비** | 11주차 | Paper Trading 검증 |

---

## 🔧 기술 스택 요약

| 영역 | 기술 |
|------|------|
| **언어** | Python 3.11+ |
| **DB** | PostgreSQL (Supabase) |
| **컨테이너** | Docker, docker-compose |
| **데이터 수집** | CCXT, WebSocket |
| **백테스트** | 자체 엔진 (vectorbt 참고) |
| **알림** | Discord Webhook |
| **모니터링** | (Phase 5) Streamlit 또는 Grafana |

---

## 📁 문서 위치

| 레포 | 핵심 문서 |
|------|----------|
| **storage** | `docs/DATA_COLLECTION.md` - 수집 시스템 명세 |
| **research** | `docs/DETAILED_SPEC.md` - 전략 명세 |
| **order** | `docs/RISK_MANAGEMENT.md` - 자본 운용 전략 |
| **portfolio** | `docs/DETAILED_SPEC.md` - 분석 명세 |

---

## ✅ 현재 완료 항목

- [x] 4개 레포지토리 생성 (storage, research, order, portfolio)
- [x] 기본 문서 구조 업로드
- [x] 디자인 시스템 (Kinetic Minimalism) 정의
- [x] Order 레포 리스크 관리 전략 수정 (95% 투입, 손실 청산 금지)
- [x] Storage 데이터 수집 명세서 작성

---

## 🚀 다음 액션

### 즉시 (이번 주)
1. [ ] Storage: DB 마이그레이션 파일 작성 (003_add_collector_tables.sql)
2. [ ] Storage: UpbitCollector, BinanceCollector 구현
3. [ ] Storage: docker-compose.yml 업데이트

### 다음 주
4. [ ] Storage: WebSocket 실시간 수집 구현
5. [ ] Storage: 수집 테스트 (24시간 무중단)
6. [ ] Research: StorageClient 연동

---

*— 문서 끝 —*
