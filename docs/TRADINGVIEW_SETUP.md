# TradingView 환율 설정 (DEPRECATED)

> ⚠️ **이 문서는 더 이상 사용되지 않습니다.**  
> 
> Ver 3.0에서는 **tvDatafeed 라이브러리** 방식을 사용합니다.  
> Webhook 방식보다 훨씬 간단하고 추가 설정이 필요 없습니다.

---

## 현재 권장 방식

### tvDatafeed 라이브러리 (권장)

| 항목 | 설명 |
|:---|:---|
| **방식** | Python 라이브러리 직접 호출 |
| **비용** | 무료 (로그인 불필요) |
| **복잡도** | 낮음 (pip install만 하면 됨) |
| **문서** | [`strategies/kimchi_premium/TRADINGVIEW_FX.md`](../strategies/kimchi_premium/TRADINGVIEW_FX.md) |

### 사용 예시

```python
from tvDatafeed import TvDatafeed, Interval

tv = TvDatafeed()  # 로그인 불필요

# USD/KRW 환율 조회
df = tv.get_hist(
    symbol="USDKRW",
    exchange="FX_IDC",
    interval=Interval.in_1_minute,
    n_bars=1
)

rate = df['close'].iloc[-1]
print(f"Current USD/KRW: {rate}")
```

---

## 참조 문서

- **구현 가이드**: [`docs/IMPLEMENTATION.md`](./IMPLEMENTATION.md)
- **환율 수집 상세**: [`strategies/kimchi_premium/TRADINGVIEW_FX.md`](../strategies/kimchi_premium/TRADINGVIEW_FX.md)

---

## Webhook 방식 (Archive)

아래는 이전 Webhook 방식의 아카이브입니다.  
특별한 이유가 없다면 **tvDatafeed 방식을 사용하세요.**

<details>
<summary>📦 Webhook 방식 아카이브 (클릭하여 펼치기)</summary>

### 왜 Webhook 방식을 더 이상 사용하지 않나요?

| 항목 | Webhook 방식 | tvDatafeed 방식 |
|:---|:---|:---|
| 복잡도 | 높음 (Pine Script, Alert 설정) | 낮음 (라이브러리만) |
| 비용 | Premium 필요 ($56/월) | 무료 |
| 서버 요구 | HTTPS Webhook 서버 필요 | 불필요 |
| 장점 | 실시간 푸시 | 간단한 구현 |

### 이전 Webhook 설정 참조

기존 Webhook 방식이 필요하다면, 이 파일의 Git 히스토리를 확인하세요:

```bash
git log --oneline docs/TRADINGVIEW_SETUP.md
git show <commit-hash>:docs/TRADINGVIEW_SETUP.md
```

</details>

---

**최종 수정**: 2025-12-15
