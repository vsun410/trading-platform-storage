# 🎨 Kinetic Minimalism Design System

**Version:** 1.0  
**Date:** 2025-12-11  
**Master Location:** storage 레포 (다른 레포는 이 문서 복사본)

---

## 1. 디자인 철학

### 1.1 Kinetic Minimalism이란?

> **깨끗하고 미니멀하지만, 강렬한 방향성(direction)과 모션(motion) 에너지가 느껴지는 디자인**

트레이딩 플랫폼에 이 스타일을 선택한 이유:
- 📊 **데이터 가독성**: 불필요한 장식 없이 정보 전달에 집중
- ⚡ **역동성**: 실시간 시장의 움직임과 에너지 표현
- 🎯 **방향성**: 상승/하락, 매수/매도의 명확한 시각적 구분
- 💼 **전문성**: 깔끔하고 신뢰감 있는 인터페이스

### 1.2 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **Simplicity** | 클러터 없음, 장식적 요소 배제 |
| **Directionality** | 최소 1개의 방향성 요소 필수 |
| **Contrast** | 중립 + 강렬한 액센트의 대비 |
| **Asymmetry** | 의도적인 비대칭으로 동적 느낌 |
| **Crispness** | 날카롭고 선명한 엣지와 그림자 |

---

## 2. 색상 시스템

### 2.1 기본 팔레트 (Neutral) - 90%

```css
/* Background */
--bg-primary: #FFFFFF;      /* 메인 배경 */
--bg-secondary: #F8F9FA;    /* 섹션 배경 */
--bg-tertiary: #F1F3F4;     /* 카드 배경 */
--bg-dark: #0A0A0B;         /* 다크모드 배경 */

/* Text */
--text-primary: #0A0A0B;    /* 기본 텍스트 */
--text-secondary: #5F6368;  /* 보조 텍스트 */
--text-muted: #9AA0A6;      /* 비활성 텍스트 */
--text-inverse: #FFFFFF;    /* 반전 텍스트 */

/* Border */
--border-light: #E8EAED;    /* 연한 보더 */
--border-default: #DADCE0;  /* 기본 보더 */
--border-strong: #5F6368;   /* 강조 보더 */
```

### 2.2 액센트 컬러 (Directional Accent) - 10%

```css
/* Primary Accent - Electric Blue */
--accent-primary: #0066FF;
--accent-primary-hover: #0052CC;
--accent-primary-light: #E6F0FF;

/* Trading Colors */
--color-long: #00D4AA;      /* 상승/매수/롱 */
--color-long-bg: #E6FBF6;
--color-short: #FF3366;     /* 하락/매도/숏 */
--color-short-bg: #FFE6EC;

/* Status Colors */
--color-success: #00D4AA;
--color-warning: #FFB800;
--color-error: #FF3366;
--color-info: #0066FF;
```

### 2.3 색상 사용 비율

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   ████████████████████████████████████████░░░░░        │
│   │← ────────── Neutral 90% ──────────→│←Accent 10%→│  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 3. 타이포그래피

### 3.1 폰트 스택

```css
/* Primary Font */
--font-sans: 'Inter', 'Pretendard', -apple-system, sans-serif;

/* Monospace (숫자, 코드) */
--font-mono: 'JetBrains Mono', 'Fira Code', monospace;
```

### 3.2 타입 스케일

| Name | Size | Weight | Spacing | 용도 |
|------|------|--------|---------|------|
| `display-lg` | 48px | 700 | -0.02em | 대시보드 타이틀 |
| `display-md` | 36px | 700 | -0.02em | 섹션 타이틀 |
| `heading-lg` | 24px | 600 | -0.01em | 카드 타이틀 |
| `heading-md` | 20px | 600 | -0.01em | 서브 타이틀 |
| `body-lg` | 16px | 400 | 0 | 본문 |
| `body-md` | 14px | 400 | 0 | 일반 텍스트 |
| `body-sm` | 12px | 400 | 0.01em | 캡션 |
| `mono-lg` | 24px | 500 | -0.02em | 큰 숫자 (김프율) |
| `mono-md` | 16px | 500 | 0 | 일반 숫자 |

### 3.3 규칙

- ✅ **타이트한 자간** (-0.02em ~ 0)
- ✅ **숫자는 Monospace** (정렬, 가독성)
- ❌ 장식적 폰트 사용 금지
- ❌ 과도한 볼드 남용 금지

---

## 4. 방향성 요소 (★ 핵심)

> ⚠️ **Kinetic Minimalism의 핵심!** 모든 주요 컴포넌트에 최소 1개 이상의 방향성 요소를 포함해야 합니다.

### 4.1 방향성 표현 방법

```
1. Diagonal Edge (대각선 엣지)
   ╱─────────────────────────╲
  ╱                           ╲
 ╱  Content Area               ╲

2. Angled Divider (기울어진 구분선)
   ━━━━━━━━━━━━╱
              ╱
             ╱━━━━━━━━━━━━━━━━━━

3. Motion Streak (모션 스트릭)
   ▬▬▬▶
       ▬▬▬▬▬▶
            ▬▬▬▶

4. Directional Gradient
   ░░░▒▒▒▓▓▓███►
   (좌→우 또는 대각선 방향)
```

### 4.2 CSS 구현

```css
/* Diagonal Edge - 카드 모서리 */
.card-diagonal {
  clip-path: polygon(0 0, 100% 0, 100% calc(100% - 20px), 0 100%);
}

/* Angled Accent Bar - 카드 하단 */
.accent-bar::after {
  content: '';
  position: absolute;
  left: 24px;
  bottom: 0;
  width: 60px;
  height: 4px;
  background: var(--accent-primary);
  transform: skewX(-20deg);
}

/* Directional Gradient - 배경 */
.gradient-flow {
  background: linear-gradient(
    135deg,
    var(--bg-secondary) 0%,
    var(--bg-primary) 50%,
    var(--accent-primary-light) 100%
  );
}

/* Motion Streak - 우측 장식 */
.motion-streak::after {
  content: '';
  position: absolute;
  right: -20px;
  top: 50%;
  width: 40px;
  height: 2px;
  background: linear-gradient(90deg, var(--accent-primary), transparent);
}
```

### 4.3 컴포넌트별 적용

| 컴포넌트 | 권장 방향성 요소 |
|----------|------------------|
| Hero 섹션 | 대각선 그라디언트 배경 |
| 카드 | 하단 액센트 바 (skewed) |
| 버튼 | 호버 시 방향성 그라디언트 |
| 차트 영역 | 모서리 대각선 컷 |
| 테이블 헤더 | 기울어진 구분선 |
| 배지/태그 | `transform: skewX(-6deg)` |

---

## 5. 그림자 시스템

### 5.1 방향성 그림자 (우하단 방향)

```css
/* 기본 그림자 */
--shadow-sm: 2px 4px 8px rgba(0, 0, 0, 0.06);
--shadow-md: 4px 8px 16px rgba(0, 0, 0, 0.08);
--shadow-lg: 8px 16px 32px rgba(0, 0, 0, 0.10);

/* 액센트 그림자 */
--shadow-accent: 4px 8px 24px rgba(0, 102, 255, 0.20);
--shadow-long: 4px 8px 24px rgba(0, 212, 170, 0.20);
--shadow-short: 4px 8px 24px rgba(255, 51, 102, 0.20);
```

### 5.2 금지 사항

- ❌ `box-shadow: 0 0 20px ...` (확산형 소프트 그림자)
- ❌ 다중 그림자 레이어
- ❌ 내부 그림자 (inset)
- ❌ 전방향 균일 그림자

---

## 6. 모서리 & 형태

### 6.1 Border Radius

```css
--radius-none: 0;
--radius-sm: 4px;      /* 작은 요소 */
--radius-md: 8px;      /* 버튼, 인풋 */
--radius-lg: 12px;     /* 카드 */
--radius-xl: 16px;     /* 모달 */
```

### 6.2 형태 규칙

- ✅ 날카롭거나 약간 둥근 모서리
- ✅ 의도적인 비대칭
- ❌ 과도하게 둥근 형태 남용 금지
- ❌ 풍선처럼 부풀어 오른 형태 금지

---

## 7. 금지 사항 (STRICT FORBIDDEN)

| 금지 항목 | 이유 | 대안 |
|-----------|------|------|
| 글래시/글라스모피즘 | 다른 스타일 | 플랫 표면 |
| 소프트 그림자 | 뉴모피즘화 | 방향성 크리스프 그림자 |
| 부풀어오른 형태 | 클레이모피즘화 | 플랫 형태 |
| 텍스처/노이즈 | 복잡성 증가 | 클린 표면 |
| 파스텔/뮤트 컬러 | 에너지 감소 | 선명한 액센트 |
| 완전 대칭 | 정적인 느낌 | 의도적 비대칭 |

---

## 8. 다크 모드

```css
[data-theme="dark"] {
  --bg-primary: #0A0A0B;
  --bg-secondary: #141416;
  --bg-tertiary: #1C1C1F;
  
  --text-primary: #FFFFFF;
  --text-secondary: #A1A1AA;
  --text-muted: #71717A;
  
  --border-light: #27272A;
  --border-default: #3F3F46;
  
  /* 액센트는 동일하게 유지 */
  --accent-primary: #0066FF;
  --color-long: #00D4AA;
  --color-short: #FF3366;
}
```

---

## 9. 레포별 UI 역할

| 레포 | UI 기능 | 주요 컴포넌트 |
|------|---------|---------------|
| **storage** | 마스터 디자인 시스템, DB 관리 UI | 데이터 테이블, 로그 뷰어 |
| **research** | 백테스트 대시보드 | 차트, 성과 지표 카드 |
| **portfolio** | 포트폴리오 분석 UI | 상관관계 히트맵, 배분 차트 |
| **order** | 실시간 모니터링 | 포지션 카드, 주문 현황 |

---

## 10. 적용 체크리스트

컴포넌트 개발 시 확인:

- [ ] 방향성 요소가 1개 이상 포함되어 있는가?
- [ ] 그림자가 단일 방향으로 설정되어 있는가?
- [ ] 색상이 중립 + 액센트 조합인가?
- [ ] 글래스/뉴모피즘 요소가 없는가?
- [ ] 텍스처나 노이즈가 없는가?
- [ ] 의도적인 비대칭이 적용되어 있는가?
- [ ] 타이포그래피가 타이트한 자간을 사용하는가?

---

*— 문서 끝 —*
