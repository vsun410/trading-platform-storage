# 데이터 수집 시스템 (DEPRECATED)

> ⚠️ **이 문서는 더 이상 사용되지 않습니다.**  
> 
> Ver 3.0 구현 가이드: [`docs/IMPLEMENTATION.md`](./IMPLEMENTATION.md)

---

## 현재 문서 구조

```
docs/
├── IMPLEMENTATION.md    ← 📌 메인 구현 가이드 (Ver 3.0)
├── SCHEMA.md            ← DB 스키마 요약 (리다이렉트)
├── DATA_COLLECTION.md   ← 이 문서 (DEPRECATED)
└── TRADINGVIEW_SETUP.md ← Webhook 방식 (DEPRECATED)

strategies/kimchi_premium/
├── DB_SCHEMA.md         ← 📌 상세 스키마
└── TRADINGVIEW_FX.md    ← 📌 환율 수집 상세
```

---

## Ver 3.0 핵심 변경사항

### 환율 수집 방식 변경

| Ver 2.0 | Ver 3.0 |
|:---|:---|
| TradingView Webhook | **tvDatafeed 라이브러리** |
| Pine Script + Alert 필요 | Python 직접 호출 |
| HTTPS 서버 필요 | 불필요 |
| Premium 필요 ($56/월) | **무료** |

### 사용 예시 (Ver 3.0)

```python
from tvDatafeed import TvDatafeed, Interval

tv = TvDatafeed()  # 로그인 불필요

df = tv.get_hist(
    symbol="USDKRW",
    exchange="FX_IDC",
    interval=Interval.in_1_minute,
    n_bars=1
)

rate = df['close'].iloc[-1]
```

---

## 참조 문서

| 문서 | 내용 |
|:---|:---|
| [`docs/IMPLEMENTATION.md`](./IMPLEMENTATION.md) | 전체 구현 가이드 (Claude Code용) |
| [`strategies/kimchi_premium/DB_SCHEMA.md`](../strategies/kimchi_premium/DB_SCHEMA.md) | Ver 3.0 DB 스키마 |
| [`strategies/kimchi_premium/TRADINGVIEW_FX.md`](../strategies/kimchi_premium/TRADINGVIEW_FX.md) | 환율 수집 상세 |
| [`supabase/migrations/`](../supabase/migrations/) | SQL 마이그레이션 |

---

## Archive

기존 Webhook 방식이 필요한 경우 Git 히스토리를 확인하세요:

```bash
git show HEAD~1:docs/DATA_COLLECTION.md
```

---

**최종 수정**: 2025-12-15
