# 📺 TradingView Webhook 설정 가이드

**Repository:** trading-platform-storage  
**Version:** 1.0  
**Date:** 2025-12-12  
**요구사항:** TradingView Premium 계정

---

## 1. 개요

### 1.1 왜 TradingView Webhook인가?

김프(김치 프리미엄) 차익거래에서 **정확한 환율 데이터**는 수익성 판단의 핵심입니다.

| 문제 | 영향 |
|------|------|
| 0.5% 환율 오차 | 2% 김프가 1.5~2.5%로 왜곡 |
| 데이터 지연 | 잘못된 진입/청산 타이밍 |
| API 불안정 | 거래 중단 |

**TradingView Webhook 장점:**
- ✅ 실시간 1분봉 데이터
- ✅ FX_IDC (ICE 복합) - 최고 신뢰도
- ✅ Premium 구독에 포함 (추가 비용 없음)
- ✅ 공식 기능 → ToS 위반 없음
- ✅ Alert 만료 없음 (Premium)

### 1.2 아키텍처

```
┌──────────────────┐         ┌──────────────────┐
│   TradingView    │         │   Your Server    │
│                  │         │                  │
│  ┌────────────┐  │  POST   │  ┌────────────┐  │
│  │Pine Script │──┼────────▶│  │  FastAPI   │  │
│  │  (Alert)   │  │  JSON   │  │  Webhook   │  │
│  └────────────┘  │         │  │  Receiver  │  │
│                  │         │  └─────┬──────┘  │
│  FX_IDC:USDKRW   │         │        │         │
│  1분봉 차트       │         │        ▼         │
└──────────────────┘         │  ┌────────────┐  │
                             │  │  Supabase  │  │
                             │  │    DB      │  │
                             │  └────────────┘  │
                             └──────────────────┘
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

### 2.3 Webhook URL 준비

**프로덕션:**
```
https://your-domain.com/webhook/fx
```

**테스트용 (ngrok):**
```bash
# ngrok 설치 후
ngrok http 8000

# 출력된 HTTPS URL 사용
# 예: https://abc123.ngrok.io/webhook/fx
```

---

## 3. Pine Script 설정

### 3.1 Pine Script 코드

TradingView 차트 에디터에서 다음 코드를 추가합니다:

```pinescript
//@version=6
indicator("KRW/USD Webhook Sender for Kimp Trading", overlay=true)

// ============================================
// 📊 김프 트레이딩용 환율 데이터 전송기
// 
// 사용법:
// 1. FX_IDC:USDKRW 차트 열기 (1분봉)
// 2. 이 스크립트 추가
// 3. Alert 생성 (아래 가이드 참조)
// ============================================

// 봉 마감 시에만 전송 (중복 방지)
if barstate.isconfirmed
    // JSON 페이로드 구성
    payload = '{' +
        '"symbol":"' + syminfo.ticker + '",' +
        '"exchange":"' + syminfo.prefix + '",' +
        '"time":"' + str.format("{0,date,yyyy-MM-dd'T'HH:mm:ss'Z'}", time) + '",' +
        '"open":' + str.tostring(open, "#.########") + ',' +
        '"high":' + str.tostring(high, "#.########") + ',' +
        '"low":' + str.tostring(low, "#.########") + ',' +
        '"close":' + str.tostring(close, "#.########") + ',' +
        '"source":"tradingview"' +
    '}'
    
    // Webhook으로 전송
    alert(payload, alert.freq_once_per_bar_close)

// ============================================
// 차트 시각화
// ============================================

// 현재 환율 표시
plot(close, "USD/KRW Rate", color=color.blue, linewidth=2)

// 정보 라벨 (최신 봉에만)
if barstate.islast
    label.new(
        bar_index, 
        high, 
        "현재 환율: " + str.tostring(close, "#.##") + " KRW",
        style=label.style_label_down,
        color=color.blue,
        textcolor=color.white
    )
```

### 3.2 스크립트 추가 방법

```
1. TradingView 차트 열기
   - 심볼: FX_IDC:USDKRW
   - 타임프레임: 1분 (1m)

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
   │ ▼ KRW/USD Webhook Sender...       │ ← 스크립트 선택
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
   │                                    │
   │ (Pine Script에서 JSON 생성하므로   │
   │  여기서 수정할 필요 없음)          │
   └────────────────────────────────────┘

6. Alert 생성
   - "Create" 버튼 클릭
```

### 4.2 Alert 확인

생성된 Alert은 우측 패널 "알림" 탭에서 확인할 수 있습니다:

```
┌────────────────────────────────────────┐
│ 🔔 Alerts                              │
├────────────────────────────────────────┤
│ ● KRW/USD Webhook Sender              │
│   FX_IDC:USDKRW, 1                    │
│   Status: Active                       │
│   Triggered: 12분 전                   │
│   Webhook: ✅                          │
└────────────────────────────────────────┘
```

---

## 5. 서버 설정

### 5.1 Webhook 수신 서버 실행

```bash
# Docker로 실행
cd trading-platform-storage
docker-compose up -d data-collector

# 로그 확인
docker logs -f data-collector
```

### 5.2 수동 테스트

```bash
# Webhook 엔드포인트 테스트
curl -X POST https://your-server.com/webhook/fx \
  -H "Content-Type: application/json" \
  -d '{
    "symbol": "USDKRW",
    "exchange": "FX_IDC",
    "time": "2025-12-12T10:30:00Z",
    "open": 1380.50,
    "high": 1381.20,
    "low": 1380.10,
    "close": 1380.80,
    "source": "tradingview"
  }'

# 응답 확인
# {"status": "accepted", "rate": 1380.80}
```

### 5.3 최신 환율 조회

```bash
# API 엔드포인트
curl https://your-server.com/fx/latest

# 응답 예시
{
  "rate": 1380.80,
  "last_update": "2025-12-12T10:30:00Z",
  "is_stale": false,
  "source": "tradingview:FX_IDC:USDKRW"
}
```

---

## 6. 문제 해결

### 6.1 Alert이 트리거되지 않음

| 원인 | 해결 |
|------|------|
| 차트 타임프레임 | 1분봉으로 변경 |
| 스크립트 미적용 | "차트에 추가" 확인 |
| 시장 휴장 | FX는 주말 휴장 |
| Alert 만료 | Premium에서 "Open-ended" 선택 |

### 6.2 Webhook 수신 실패

```bash
# 서버 연결 확인
curl -I https://your-server.com/health

# 방화벽 확인
sudo ufw status

# 포트 열기
sudo ufw allow 443
```

### 6.3 데이터 지연

```sql
-- DB에서 최근 환율 확인
SELECT * FROM exchange_rates 
WHERE source LIKE 'tradingview%'
ORDER BY timestamp DESC 
LIMIT 5;
```

### 6.4 백업 소스 확인

```python
# 테스트 스크립트
from collectors.exchange_rate_backup import ExchangeRateBackup

backup = ExchangeRateBackup()
rate = await backup.fetch_dunamu_rate()
print(f"Dunamu Rate: {rate}")
```

---

## 7. 모니터링

### 7.1 Webhook 수신 현황

```sql
-- 시간대별 수신 현황
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    COUNT(*) as count,
    MIN(rate) as min_rate,
    MAX(rate) as max_rate
FROM exchange_rates
WHERE source LIKE 'tradingview%'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;
```

### 7.2 Alert 통계 (TradingView)

TradingView 웹사이트에서 Alert 트리거 기록 확인:

```
1. 알림 패널 열기
2. Alert 옆 ⋮ 클릭
3. "Logs" 선택
4. 트리거 시간 및 횟수 확인
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
- 400개 Alert → 다른 용도에도 활용
- 실시간 데이터 (무료는 15분 지연)

### 8.2 Webhook 빈도 제한

```
┌─────────────────────────────────────────────────────────┐
│ TradingView Webhook 제한                                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ • 3분 내 동일 Alert 최대 15회 트리거                    │
│   → 1분마다 1회는 충분히 여유 있음 ✅                   │
│                                                         │
│ • Webhook 응답 타임아웃: 10초                           │
│   → 빠른 응답 필요 (Background Task 사용)               │
│                                                         │
│ • Webhook URL은 HTTPS 필수                              │
│   → HTTP는 지원 안 됨                                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 9. 체크리스트 요약

### 설정 완료 체크리스트

```
TradingView 설정:
□ Premium 계정 확인
□ 2FA 활성화
□ FX_IDC:USDKRW 차트 열기 (1분봉)
□ Pine Script 추가 및 저장
□ Alert 생성 (Once Per Bar Close)
□ Webhook URL 입력
□ Alert 활성화 확인

서버 설정:
□ HTTPS Webhook URL 준비
□ data-collector 컨테이너 실행
□ 방화벽 포트 443 열기
□ 테스트 요청 성공

모니터링:
□ 서버 로그에서 "FX Rate Updated" 확인
□ DB에서 exchange_rates 테이블 확인
□ /fx/latest API 응답 확인
```

---

## 10. 추가 활용

### 10.1 다른 심볼 추가 (선택)

김프 외에 다른 차익거래에도 활용:

```pinescript
// ETH 김프용
// 차트: FX_IDC:USDKRW + BINANCE:ETHUSDT + UPBIT:ETHKRW

// 또는 미국 주식 환율
// 차트: FX_IDC:USDKRW
```

### 10.2 기술적 신호 Webhook

환율 외에 기술적 신호도 Webhook으로 전송 가능:

```pinescript
// RSI 과매도 알림
if ta.rsi(close, 14) < 30
    alert('{"signal":"oversold","value":' + str.tostring(ta.rsi(close, 14)) + '}')
```

---

*— 문서 끝 —*
