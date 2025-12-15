# 데이터베이스 스키마 (Ver 3.0)

> ⚠️ **이 문서는 참조용입니다.**  
> 최신 스키마는 [`strategies/kimchi_premium/DB_SCHEMA.md`](../strategies/kimchi_premium/DB_SCHEMA.md)를 참조하세요.  
> 실제 마이그레이션 SQL은 [`supabase/migrations/`](../supabase/migrations/)에 있습니다.

---

## 스키마 문서 구조

```
trading-platform-storage/
├── strategies/kimchi_premium/
│   └── DB_SCHEMA.md          ← 📌 메인 스키마 문서
│
├── supabase/migrations/       ← 📌 실제 SQL 파일
│   ├── 001_init_extensions.sql
│   ├── 002_create_kimp_tables.sql
│   ├── 003_create_fx_tables.sql
│   ├── 004_create_indicator_tables.sql
│   ├── 005_create_trade_tables.sql
│   └── 006_create_views.sql
│
└── docs/
    ├── SCHEMA.md              ← 이 문서 (요약)
    └── IMPLEMENTATION.md      ← 구현 가이드
```

---

## 테이블 요약

| 테이블 | 설명 | 용도 |
|:---|:---|:---|
| `kimp_ticks` | 실시간 김프 틱 | 원본 데이터 |
| `kimp_1m` | 1분봉 김프 | **백테스트 핵심** |
| `fx_rates` | USD/KRW 환율 | 환율 필터 |
| `fx_filter_log` | 환율 필터 상태 | 진입 차단 기록 |
| `zscore_log` | Z-Score 로그 | 신호 분석 |
| `bb_log` | 볼린저 밴드 | Track B 탈출 |
| `positions` | 포지션 관리 | 거래 관리 |
| `trades` | 체결 기록 | 실행 기록 |
| `orders` | 주문 큐 | 주문 관리 |
| `funding_rates` | Binance 펀딩비 | 비용 분석 |

---

## 상세 스키마

### 📌 메인 문서로 이동

**[→ strategies/kimchi_premium/DB_SCHEMA.md](../strategies/kimchi_premium/DB_SCHEMA.md)**

---

## 마이그레이션 실행

```bash
# Supabase Dashboard > SQL Editor에서 순서대로 실행
# 또는 Supabase CLI 사용

# 1. 확장 기능
cat supabase/migrations/001_init_extensions.sql

# 2. 김프 테이블
cat supabase/migrations/002_create_kimp_tables.sql

# 3. 환율 테이블
cat supabase/migrations/003_create_fx_tables.sql

# 4. 지표 테이블
cat supabase/migrations/004_create_indicator_tables.sql

# 5. 거래 테이블
cat supabase/migrations/005_create_trade_tables.sql

# 6. 뷰
cat supabase/migrations/006_create_views.sql
```

---

**버전**: 3.0  
**최종 수정**: 2025-12-15
