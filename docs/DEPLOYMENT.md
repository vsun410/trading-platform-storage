# 🚀 Vultr 배포 가이드

김프 데이터 수집기를 Vultr 클라우드에 배포하는 가이드입니다.

---

## 1. Vultr 서버 요구사항

### 1.1 권장 플랜

| 항목 | 최소 ($5/월) | 권장 ($10/월) |
|:---|:---|:---|
| vCPU | 1 | 2 |
| RAM | 1GB | 2GB |
| Storage | 25GB SSD | 50GB SSD |
| Bandwidth | 1TB | 2TB |

**예상 리소스 사용량 (3개월 기준):**
- 디스크: ~3GB (데이터 + 로그)
- 메모리: ~300MB
- CPU: 평균 5% 미만

### 1.2 OS 선택

- **Ubuntu 22.04 LTS** (권장)
- Debian 12도 가능

---

## 2. 서버 초기 설정

### 2.1 Vultr 인스턴스 생성

1. [Vultr Console](https://my.vultr.com/) 접속
2. **Deploy New Server** 클릭
3. 설정:
   - Type: Cloud Compute (Shared CPU)
   - Location: 서울 (Tokyo도 가능)
   - Image: Ubuntu 22.04 LTS
   - Plan: $5/월 (1 vCPU, 1GB RAM)
4. **Deploy Now** 클릭

### 2.2 서버 접속

```bash
# SSH 접속
ssh root@YOUR_SERVER_IP

# 패스워드 입력 (Vultr 콘솔에서 확인)
```

### 2.3 기본 설정

```bash
# 시스템 업데이트
apt update && apt upgrade -y

# 타임존 설정
timedatectl set-timezone UTC

# 필수 패키지 설치
apt install -y curl git
```

---

## 3. Docker 설치

```bash
# Docker 공식 설치 스크립트
curl -fsSL https://get.docker.com | sh

# Docker Compose 설치 (이미 포함됨)
docker --version
docker compose version

# Docker 서비스 자동 시작
systemctl enable docker
systemctl start docker
```

---

## 4. 데이터 수집기 배포

### 4.1 레포지토리 클론

```bash
# 홈 디렉토리로 이동
cd ~

# 레포 클론
git clone https://github.com/vsun410/trading-platform-storage.git
cd trading-platform-storage
```

### 4.2 환경 변수 설정

```bash
# 예시 파일 복사
cp .env.example .env

# 환경 변수 편집
nano .env
```

**필수 설정:**
```env
# Supabase 설정 (필수!)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key-here

# 수집 설정
COLLECT_INTERVAL_SECONDS=60
SYMBOLS=BTC

# 로그 레벨
LOG_LEVEL=INFO
```

### 4.3 빌드 및 실행

```bash
# 빌드 & 백그라운드 실행
docker compose up -d --build

# 상태 확인
docker compose ps

# 로그 확인 (실시간)
docker compose logs -f

# 최근 로그만 확인
docker compose logs --tail=50
```

---

## 5. 운영 관리

### 5.1 일반 명령어

```bash
# 컨테이너 상태 확인
docker compose ps

# 컨테이너 재시작
docker compose restart

# 컨테이너 중지
docker compose down

# 컨테이너 중지 + 볼륨 삭제
docker compose down -v

# 이미지 재빌드 (코드 업데이트 후)
git pull
docker compose up -d --build
```

### 5.2 로그 관리

```bash
# 실시간 로그 확인
docker compose logs -f

# 특정 시간 이후 로그
docker compose logs --since="2025-01-01T00:00:00"

# 로그 파일 직접 확인
ls -la logs/
tail -f logs/collector_*.log
```

### 5.3 자동 재시작 확인

Docker Compose에 `restart: unless-stopped` 설정이 있어서:
- 서버 재부팅 시 자동 시작
- 컨테이너 크래시 시 자동 재시작
- `docker compose down`으로 명시적 중지 시에만 종료

---

## 6. 모니터링

### 6.1 데이터 수집 확인 (Supabase)

```sql
-- 최근 1시간 수집 현황
SELECT 
    DATE_TRUNC('minute', timestamp) AS minute,
    COUNT(*) AS count
FROM kimp_1m
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute DESC;

-- 오늘 총 수집량
SELECT COUNT(*) FROM kimp_1m 
WHERE timestamp > CURRENT_DATE;
```

### 6.2 서버 리소스 모니터링

```bash
# Docker 리소스 사용량
docker stats

# 디스크 사용량
df -h

# 메모리 사용량
free -h
```

### 6.3 간단 헬스체크 스크립트

```bash
# scripts/health_check.sh 생성
cat << 'EOF' > ~/health_check.sh
#!/bin/bash
echo "=== Docker Status ==="
docker compose -f ~/trading-platform-storage/docker-compose.yml ps

echo ""
echo "=== Last 10 Logs ==="
docker compose -f ~/trading-platform-storage/docker-compose.yml logs --tail=10

echo ""
echo "=== Disk Usage ==="
df -h /

echo ""
echo "=== Memory ==="
free -h
EOF

chmod +x ~/health_check.sh

# 실행
~/health_check.sh
```

---

## 7. 문제 해결

### 7.1 컨테이너가 시작되지 않음

```bash
# 상세 로그 확인
docker compose logs

# 컨테이너 상태 확인
docker compose ps -a

# 재빌드
docker compose down
docker compose up -d --build
```

### 7.2 환율 데이터 수집 실패

tvDatafeed 관련 문제일 수 있음:
```bash
# 컨테이너 내부 접속
docker compose exec data-collector bash

# 테스트
python -c "from tvDatafeed import TvDatafeed; tv = TvDatafeed(); print(tv.get_hist('USDKRW', 'FX_IDC', n_bars=1))"
```

### 7.3 Supabase 연결 실패

```bash
# 환경 변수 확인
docker compose exec data-collector env | grep SUPABASE

# 연결 테스트
docker compose exec data-collector python -c "
from supabase import create_client
import os
client = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_KEY'))
print('Connected!')
"
```

### 7.4 메모리 부족

```bash
# 불필요한 이미지 정리
docker system prune -a

# 로그 파일 정리
rm -f ~/trading-platform-storage/logs/*.log
```

---

## 8. 코드 업데이트

```bash
cd ~/trading-platform-storage

# 최신 코드 가져오기
git pull origin main

# 재빌드 & 재시작
docker compose down
docker compose up -d --build

# 로그 확인
docker compose logs -f
```

---

## 9. 백업 (선택)

### 9.1 수동 백업

```bash
# 로그 백업
tar -czvf logs_backup_$(date +%Y%m%d).tar.gz ~/trading-platform-storage/logs/
```

### 9.2 Supabase 백업

Supabase Dashboard에서:
1. Settings → Database
2. Backups → Download backup

---

## 10. 체크리스트

배포 전 확인사항:

- [ ] Vultr 서버 생성 완료
- [ ] Docker 설치 완료
- [ ] 레포 클론 완료
- [ ] `.env` 파일 설정 완료 (Supabase URL/KEY)
- [ ] Supabase 마이그레이션 실행 완료
- [ ] `docker compose up -d --build` 실행
- [ ] 로그에서 정상 수집 확인
- [ ] Supabase에서 데이터 저장 확인

---

**예상 비용**: $5~10/월 (Vultr) + $0 (Supabase Free Tier)

**문의**: GitHub Issues 또는 Telegram
