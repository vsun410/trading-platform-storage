# 📺 TradingView 환율 데이터 설정 가이드 Ver 3.0

**Repository:** trading-platform-storage  
**Version:** 3.0  
**Date:** 2025-12-14  
**요구사항:** TradingView Premium 계정  
**핵심 용도:** 김프 계산 + **환율 필터 (12시간 MA)**

---

## Ver 3.0 핵심 변경사항

| 항목 | 설명 |
|:---|:---|
| **환율 필터** | 현재 환율 > 12시간 MA × 1.001 시 진입 차단 |
| **MA 계산** | 720분(12시간) 이동평균 실시간 계산 |
| **필터 상태** | API로 현재 필터 상태 조회 가능 |

---

## 1. 개요

### 1.1 왜 TradingView FX_IDC:USDKRW인가?

김프(김치 프리미엄) 차익거래에서 **정확한 환율 데이터**는 수익성 판단의 핵심입니다.

| 문제 | 영향 |
|------|------|
| 0.5% 환율 오차 | 2% 김프가 1.5~2.5%로 왜곡 |
| 데이터 지연 | 잘못된 진입/청산 타이밍 |
| API 불안정 | 거래 중단 |

**TradingView FX_IDC 장점:**
- ✅ 실시간 1분봉 데이터
- ✅ ICE 복합 데이터 - 최고 신뢰도
- ✅ Premium 구독에 포함 (추가 비용 없음)
- ✅ Alert 만료 없음 (Premium)
- ✅ **12시간 MA 계산 가능** (Ver 3.0)

### 1.2 Ver 3.0 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                    Ver 3.0 환율 데이터 흐름                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   TradingView                      Your Server                   │
│   ┌────────────┐                  ┌────────────────────┐        │
│   │ FX_IDC:    │     POST        │                    │        │
│   │ USDKRW     │─────────────────▶│   Webhook          │        │
│   │ (1분봉)    │     JSON         │   Receiver         │        │
│   └────────────┘                  └─────────┬──────────┘        │
│                                             │                    │
│                                             ▼                    │
│                                   ┌─────────────────────┐        │
│                                   │   Supabase DB       │        │
│                                   │   ┌───────────────┐ │        │
│                                   │   │exchange_rates │ │        │
│                                   │   └───────────────┘ │        │
│                                   └─────────┬───────────┘        │
│                                             │                    │
│                    ┌────────────────────────┴──────────────────┐ │
│                    │                                           │ │
│                    ▼                                           ▼ │
│         ┌──────────────────┐                    ┌──────────────┐ │
│         │  김프 계산       │                    │ 환율 필터    │ │
│         │                  │                    │ (Ver 3.0)    │ │
│         │  kimp = (upbit-  │                    │              │ │
│         │   binance*rate)  │                    │ rate > MA*   │ │
│         │   / binance*rate │                    │ 1.001 → 차단 │ │
│         └──────────────────┘                    └──────────────┘ │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. 사전 준비

### 2.1 체크리스트

```
□ TradingView Premium 계정 (또는 그 이상)
□ 2단계 인증(2FA) 활성화 ← 필수!
□ HTTPS Webhook URL 준비
□ 서버 방화벽 포트 열기 (443)
```

### 2.2 2단계 인증 설정

Webhook을 사용하려면 **반드시 2FA가 활성화**되어야 합니다.

```
1. TradingView → 프로필 → 보안
2. 2단계 인증 → 활성화
3. Google Authenticator 또는 SMS 선택
4. 설정 완료
```

---

## 3. Pine Script 설정 (Ver 3.0)

### 3.1 Pine Script 코드

```pinescript
//@version=6
indicator("KRW/USD Webhook Sender for Kimp Trading v3.0", overlay=true)

// ============================================
// 📊 김프 트레이딩용 환율 데이터 전송기 Ver 3.0
// 
// 변경사항:
// - 12시간 MA 계산 추가
// - 환율 필터 상태 포함
// 
// 사용법:
// 1. FX_IDC:USDKRW 차트 열기 (1분봉)
// 2. 이 스크립트 추가
// 3. Alert 생성 (아래 가이드 참조)
// ============================================

// 12시간 MA 계산 (1분봉 기준 720개)
ma_12h = ta.sma(close, 720)

// 환율 필터 상태 계산
rate_ratio = close / ma_12h
is_entry_blocked = rate_ratio > 1.001  // 0.1% 초과 시 차단

// 봉 마감 시에만 전송 (중복 방지)
if barstate.isconfirmed
    // JSON 페이로드 구성 (Ver 3.0 확장)
    payload = '{' +
        '"symbol":"' + syminfo.ticker + '",' +
        '"exchange":"' + syminfo.prefix + '",' +
        '"time":"' + str.format("{0,date,yyyy-MM-dd'T'HH:mm:ss'Z'}", time) + '",' +
        '"open":' + str.tostring(open, "#.########") + ',' +
        '"high":' + str.tostring(high, "#.########") + ',' +
        '"low":' + str.tostring(low, "#.########") + ',' +
        '"close":' + str.tostring(close, "#.########") + ',' +
        '"ma_12h":' + str.tostring(ma_12h, "#.########") + ',' +
        '"rate_ratio":' + str.tostring(rate_ratio, "#.######") + ',' +
        '"is_entry_blocked":' + (is_entry_blocked ? 'true' : 'false') + ',' +
        '"source":"tradingview",' +
        '"version":"3.0"' +
    '}'
    
    // Webhook으로 전송
    alert(payload, alert.freq_once_per_bar_close)

// ============================================
// 차트 시각화
// ============================================

// 현재 환율 표시
plot(close, "USD/KRW Rate", color=color.blue, linewidth=2)

// 12시간 MA 표시
plot(ma_12h, "12H MA", color=color.orange, linewidth=1)

// 환율 필터 임계선 (MA × 1.001)
plot(ma_12h * 1.001, "Filter Threshold", color=color.red, style=plot.style_circles)

// 환율 필터 상태 배경색
bgcolor(is_entry_blocked ? color.new(color.red, 90) : na, title="Entry Blocked Zone")

// 정보 라벨 (최신 봉에만)
if barstate.islast
    label_text = "현재 환율: " + str.tostring(close, "#.##") + " KRW\n" +
                 "12H MA: " + str.tostring(ma_12h, "#.##") + " KRW\n" +
                 "Ratio: " + str.tostring(rate_ratio, "#.######") + "\n" +
                 "진입 차단: " + (is_entry_blocked ? "⛔ YES" : "✅ NO")
    
    label.new(
        bar_index, 
        high, 
        label_text,
        style=label.style_label_down,
        color=is_entry_blocked ? color.red : color.green,
        textcolor=color.white
    )
```

### 3.2 스크립트 추가 방법

```
1. TradingView 차트 열기
   - 심볼: FX_IDC:USDKRW
   - 타임프레임: 1분 (1m) ← 필수!

2. Pine Editor 열기
   - 하단 "Pine Editor" 탭 클릭
   - 또는 단축키: Alt + P

3. 코드 붙여넣기
   - 기존 코드 모두 삭제
   - 위 코드 복사하여 붙여넣기

4. 저장 및 차트에 추가
   - "저장" 클릭 (Ctrl + S)
   - "차트에 추가" 클릭
```

---

## 4. Alert 설정

### 4.1 Alert 생성 (상세)

```
1. Alert 대화상자 열기
   - 단축키: Alt + A
   - 또는 차트 우측 "알림" 아이콘 클릭

2. Condition (조건) 설정
   ┌────────────────────────────────────┐
   │ Condition                          │
   ├────────────────────────────────────┤
   │ ▼ KRW/USD Webhook Sender v3.0     │ ← 스크립트 선택
   │ ▼ alert() function calls only     │ ← 이것 선택!
   └────────────────────────────────────┘

3. Options 설정
   ┌────────────────────────────────────┐
   │ Options                            │
   ├────────────────────────────────────┤
   │ ○ Once Per Bar                     │
   │ ● Once Per Bar Close              │ ← 이것 선택!
   │ ○ Once Per Minute                  │
   │                                    │
   │ Expiration: Open-ended            │ ← Premium 전용
   │             (만료 없음)            │
   └────────────────────────────────────┘

4. Notifications 설정
   ┌────────────────────────────────────┐
   │ Notifications                      │
   ├────────────────────────────────────┤
   │ □ Notify on app                    │
   │ □ Show popup                       │
   │ □ Send email                       │
   │ □ Play sound                       │
   │ ☑ Webhook URL                     │ ← 체크!
   │   https://your-server/webhook/fx   │
   └────────────────────────────────────┘

5. Message 설정
   ┌────────────────────────────────────┐
   │ Message                            │
   ├────────────────────────────────────┤
   │ {{alert.message}}                  │ ← 그대로 유지
   └────────────────────────────────────┘

6. Alert 생성
   - "Create" 버튼 클릭
```

---

## 5. 서버 설정

### 5.1 Webhook 수신 엔드포인트 (Ver 3.0)

```python
# webhook/fx_receiver.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import asyncpg

app = FastAPI()

class FXWebhookPayload(BaseModel):
    symbol: str
    exchange: str
    time: str
    open: float
    high: float
    low: float
    close: float
    ma_12h: Optional[float] = None        # Ver 3.0
    rate_ratio: Optional[float] = None    # Ver 3.0
    is_entry_blocked: Optional[bool] = None  # Ver 3.0
    source: str = "tradingview"
    version: str = "3.0"

@app.post("/webhook/fx")
async def receive_fx_webhook(payload: FXWebhookPayload):
    """
    TradingView Webhook 수신 (Ver 3.0)
    """
    try:
        # DB 저장
        await save_exchange_rate(payload)
        
        # 환율 필터 상태 로깅
        if payload.is_entry_blocked:
            print(f"⚠️ 환율 필터 활성화: {payload.close} > {payload.ma_12h} × 1.001")
        
        return {
            "status": "accepted",
            "rate": payload.close,
            "ma_12h": payload.ma_12h,
            "is_entry_blocked": payload.is_entry_blocked,
            "version": payload.version
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

async def save_exchange_rate(payload: FXWebhookPayload):
    """환율 데이터 DB 저장"""
    conn = await asyncpg.connect(SUPABASE_URL)
    try:
        await conn.execute("""
            INSERT INTO exchange_rates 
            (timestamp, rate, open, high, low, source)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (timestamp, base_currency, quote_currency, source) 
            DO UPDATE SET rate = EXCLUDED.rate
        """, 
            datetime.fromisoformat(payload.time.replace('Z', '+00:00')),
            payload.close,
            payload.open,
            payload.high,
            payload.low,
            f"tradingview:{payload.exchange}:{payload.symbol}"
        )
    finally:
        await conn.close()
```

### 5.2 환율 필터 상태 API (Ver 3.0)

```python
@app.get("/fx/filter-status")
async def get_filter_status():
    """
    환율 필터 상태 조회 (Ver 3.0)
    """
    conn = await asyncpg.connect(SUPABASE_URL)
    try:
        result = await conn.fetchrow("""
            SELECT * FROM check_exchange_rate_filter()
        """)
        
        return {
            "current_rate": float(result['current_rate']),
            "ma_12h": float(result['ma_12h']),
            "rate_ratio": float(result['rate_ratio']),
            "is_entry_blocked": result['is_blocked'],
            "threshold": 1.001,
            "checked_at": result['checked_at'].isoformat()
        }
    finally:
        await conn.close()
```

### 5.3 수동 테스트 (Ver 3.0)

```bash
# Webhook 엔드포인트 테스트
curl -X POST https://your-server.com/webhook/fx \
  -H "Content-Type: application/json" \
  -d '{
    "symbol": "USDKRW",
    "exchange": "FX_IDC",
    "time": "2025-12-14T10:30:00Z",
    "open": 1380.50,
    "high": 1381.20,
    "low": 1380.10,
    "close": 1380.80,
    "ma_12h": 1378.50,
    "rate_ratio": 1.00167,
    "is_entry_blocked": true,
    "source": "tradingview",
    "version": "3.0"
  }'

# 응답 확인
# {
#   "status": "accepted",
#   "rate": 1380.80,
#   "ma_12h": 1378.50,
#   "is_entry_blocked": true,
#   "version": "3.0"
# }
```

---

## 6. 환율 필터 동작 확인

### 6.1 필터 상태 조회

```bash
# API 엔드포인트
curl https://your-server.com/fx/filter-status

# 응답 예시 (진입 허용)
{
  "current_rate": 1378.50,
  "ma_12h": 1378.00,
  "rate_ratio": 1.00036,
  "is_entry_blocked": false,
  "threshold": 1.001,
  "checked_at": "2025-12-14T10:30:00Z"
}

# 응답 예시 (진입 차단)
{
  "current_rate": 1382.50,
  "ma_12h": 1378.00,
  "rate_ratio": 1.00327,
  "is_entry_blocked": true,  # ⛔ 0.1% 초과
  "threshold": 1.001,
  "checked_at": "2025-12-14T10:30:00Z"
}
```

### 6.2 DB 직접 조회

```sql
-- 최근 환율 필터 상태
SELECT * FROM check_exchange_rate_filter();

-- 환율 필터 발동 이력 (최근 24시간)
SELECT 
    timestamp,
    rate,
    ma_12h,
    rate_ratio,
    CASE WHEN rate_ratio > 1.001 THEN '⛔ BLOCKED' ELSE '✅ OK' END as status
FROM exchange_rates_ma
WHERE timestamp > NOW() - INTERVAL '24 hours'
  AND rate_ratio > 1.0005  -- 임계값 근접 시점만
ORDER BY timestamp DESC;
```

---

## 7. 문제 해결

### 7.1 12시간 MA 데이터 부족

```sql
-- MA 계산에 필요한 데이터 확인 (720분 필요)
SELECT COUNT(*) as data_points
FROM exchange_rates
WHERE timestamp > NOW() - INTERVAL '12 hours'
  AND source LIKE 'tradingview%';

-- 720개 미만이면 MA가 부정확할 수 있음
-- → 최소 12시간 데이터 축적 후 필터 신뢰
```

### 7.2 Webhook 수신 실패

| 원인 | 해결 |
|------|------|
| HTTPS 미사용 | Let's Encrypt 인증서 설정 |
| 타임아웃 | 10초 내 응답 (Background Task 사용) |
| 방화벽 | 포트 443 열기 |

### 7.3 환율 급등 오탐지

```python
# 스파이크 필터링 (선택사항)
def is_valid_rate(current: float, previous: float, max_change: float = 0.02):
    """2% 이상 급변 시 오류로 판단"""
    if previous == 0:
        return True
    change = abs(current - previous) / previous
    return change < max_change
```

---

## 8. 비용 및 제한

### 8.1 TradingView 플랜별 제한

| 플랜 | Alert 개수 | Webhook | 만료 기간 | 가격/월 |
|------|-----------|---------|---------|--------|
| Basic | 3 | ❌ | 1개월 | $0 |
| Essential | 20 | ✅ | 2개월 | $12.95 |
| **Premium** | **400** | ✅ | **무제한** | **$56.49** |
| Ultimate | 무제한 | ✅ | 무제한 | $239.95 |

**Premium 권장 이유:**
- Alert 만료 없음 → 장기 운영 가능
- 실시간 데이터 (무료는 15분 지연)
- 12시간 MA 계산에 충분한 히스토리

---

## 9. 체크리스트 요약

### Ver 3.0 설정 완료 체크리스트

```
TradingView 설정:
□ Premium 계정 확인
□ 2FA 활성화
□ FX_IDC:USDKRW 차트 열기 (1분봉)
□ Ver 3.0 Pine Script 추가 및 저장
□ Alert 생성 (Once Per Bar Close)
□ Webhook URL 입력
□ Alert 활성화 확인
□ 12시간 MA 라인 표시 확인

서버 설정:
□ HTTPS Webhook URL 준비
□ Ver 3.0 Webhook 핸들러 배포
□ /fx/filter-status API 동작 확인
□ exchange_rates_ma 뷰 생성

모니터링:
□ 서버 로그에서 "is_entry_blocked" 확인
□ DB에서 ma_12h 필드 저장 확인
□ 환율 필터 상태 API 응답 확인
□ 최소 12시간 데이터 축적 후 필터 신뢰
```

---

*— Ver 3.0 문서 끝 —*
