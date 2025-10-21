# Windows 에어갭 환경용 Nginx 리버스 프록시 - 통합 설치 패키지

**완전 독립형 오프라인 설치 패키지 v1.1.0**

---

## 📦 패키지 개요

Windows Server 에어갭(완전 오프라인) 환경에서 Nginx 리버스 프록시를 설치하고 관리하기 위한 **독립 실행형 통합 패키지**입니다.

**특징**:
- ✅ 인터넷 연결 불필요 (모든 구성 요소 포함)
- ✅ 단일 USB 전송으로 설치 가능
- ✅ Active Directory 통합
- ✅ 3가지 프록시 관리 옵션
- ✅ 자동 검증 (37개 테스트)

---

## 📋 패키지 구성

```
airgap-package/ (133MB)
│
├── README.md                      # 본 파일
├── PACKAGE-INFO.txt               # 패키지 메타데이터
├── checksums.txt                  # SHA256 체크섬
│
├── installers/                    # 설치 파일 (133MB)
│   ├── node-v20.11.0-x64.msi     # Node.js 런타임
│   ├── nginx-1.24.0.zip          # Nginx 웹서버
│   ├── nssm-2.24.zip             # Windows 서비스 매니저
│   ├── vcredist_x64.exe          # Visual C++ 재배포
│   └── zoraxy_windows_amd64.exe  # GUI 프록시 관리 (옵션)
│
├── scripts/                       # PowerShell 스크립트 (13개) + JS (2개)
│   ├── 01-prepare-airgap.ps1     # 패키지 준비 (인터넷 환경)
│   ├── 02-install-airgap.ps1     # 시스템 설치 (에어갭)
│   ├── 03-verify-installation.ps1 # 설치 검증
│   ├── 04-setup-ad-integration.ps1 # AD 통합
│   ├── 05-backup-restore.ps1     # 백업/복구
│   ├── 06-validate-enhanced-package.ps1 # 패키지 검증
│   ├── 07-health-monitor.ps1     # 실시간 헬스 모니터링 ⭐ NEW
│   ├── 08-log-analyzer.ps1       # 로그 분석 및 이상 탐지 ⭐ NEW
│   ├── 09-performance-benchmark.ps1 # 성능 벤치마크 ⭐ NEW
│   ├── 10-auto-maintenance.ps1   # 자동 유지보수 ⭐ NEW
│   ├── import-proxies.ps1        # CSV 프록시 일괄 등록 ⭐ NEW
│   ├── test-nginx-web-ui.ps1     # 웹 UI 테스트
│   ├── nginx-web-ui.js           # Node.js 웹 UI (강화 버전)
│   └── nginx-web-ui-basic.js     # 웹 UI 기본 버전 (백업)
│
├── configs/                       # 설정 파일 템플릿
│   ├── .env.example              # 환경 변수
│   ├── services.csv              # 프록시 목록 (CSV)
│   └── nginx/                    # Nginx 설정
│       ├── nginx.conf            # 메인 설정
│       └── conf.d/               # 프록시 설정 예시 (4개)
│           ├── proxy-config-example.conf
│           ├── example-app.company.local.conf
│           ├── example-loadbalancer.conf
│           └── example-static-site.conf
│
├── docs/                          # 📚 문서 (13개)
│   ├── architecture.md           # 시스템 아키텍처
│   ├── api.md                    # API 및 인터페이스
│   ├── deployment.md             # 배포 가이드
│   ├── troubleshooting.md        # 문제 해결
│   └── 001-009_*.md/*.xwiki      # 운영 매뉴얼
│
├── npm-packages/                  # Node.js 패키지
│   └── package.json              # 의존성 목록
│
├── ssl/                           # SSL 인증서 (사용자 추가)
└── logs/                          # 설치 로그
```

---

## 🚀 빠른 시작 (3단계)

### 1단계: 패키지 준비 (인터넷 연결 환경)

인터넷이 연결된 PC에서:

```powershell
cd airgap-package\scripts
.\01-prepare-airgap.ps1
```

**작업 내용**:
- ✓ 모든 설치 파일 다운로드 검증
- ✓ npm 패키지 오프라인 캐시 생성
- ✓ SHA256 체크섬 생성

### 2단계: USB 전송

```powershell
# 전체 airgap-package 폴더를 USB로 복사
Copy-Item -Path "airgap-package" -Destination "E:\" -Recurse
```

### 3단계: 설치 (에어갭 Windows Server)

USB를 서버에 연결 후:

```powershell
# 패키지 복사
Copy-Item -Path "E:\airgap-package" -Destination "C:\" -Recurse

# 관리자 권한 PowerShell 실행
cd C:\airgap-package\scripts

# 실행 정책 변경 (필요시)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 설치
.\02-install-airgap.ps1
```

**설치 시간**: 약 5-10분

### 4단계: 검증

```powershell
.\03-verify-installation.ps1 -Detailed -ExportReport
```

---

## 🔧 설치되는 구성 요소

| 컴포넌트 | 버전 | 용도 | 포트 |
|---------|------|------|------|
| **Nginx** | 1.24.0 | 리버스 프록시 | 80, 443 |
| **Node.js** | v20.11.0 | 웹 UI 런타임 | 8080 |
| **NSSM** | 2.24 | Windows 서비스 관리 | - |
| **Visual C++** | 2015-2022 | Node.js 의존성 | - |
| **Zoraxy** | latest | GUI 관리 (옵션) | 8000 |

**Windows 서비스**:
- `nginx` - Nginx 웹서버
- `nginx-web-ui` - 웹 UI 관리

---

## 🎯 프록시 관리 옵션

### 옵션 1: 웹 UI (추천) ⭐

```powershell
# 브라우저에서 접속
http://localhost:8080

# 특징:
# - 직관적인 GUI
# - 실시간 상태 모니터링
# - 로그 조회 기능
# - localhost 전용 (보안)
```

### 옵션 2: PowerShell 스크립트

```powershell
# CSV 파일 편집
notepad C:\airgap-package\configs\services.csv

# 형식:
# domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path
# app.company.local,192.168.1.100,3000,true,C:\nginx\ssl\app.crt,C:\nginx\ssl\app.key

# 일괄 적용
.\scripts\import-proxies.ps1 -CSVPath "C:\airgap-package\configs\services.csv"
```

### 옵션 3: Zoraxy GUI

```powershell
C:\installers\zoraxy_windows_amd64.exe

# 접속: http://localhost:8000
# 기본 계정: admin / admin
```

---

## 🔐 Active Directory 통합

### AD 그룹 생성

```powershell
# Domain Controller에서 실행
New-ADGroup -Name "NginxAdministrators" -GroupScope Global -GroupCategory Security
New-ADGroup -Name "NginxOperators" -GroupScope Global -GroupCategory Security
```

### 서비스 계정 생성

```powershell
New-ADUser -Name "nginx-service" `
           -SamAccountName "nginx-service" `
           -UserPrincipalName "nginx-service@company.local" `
           -AccountPassword (ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force) `
           -Enabled $true `
           -PasswordNeverExpires $true
```

### AD 통합 설정

```powershell
cd C:\airgap-package\scripts
.\04-setup-ad-integration.ps1
```

---

## 📊 검증 및 모니터링

### 자동 검증 (37개 테스트)

```powershell
.\03-verify-installation.ps1 -Detailed -ExportReport
```

**검증 항목**:
1. Active Directory 연동 (6개)
2. Windows 서비스 상태 (5개)
3. 네트워크 접근 제어 (5개)
4. Nginx 설정 (5개)
5. 프록시 기능 (2개)
6. 디스크 및 리소스 (3개)
7. SSL/TLS 인증서 (3개)
8. 로그 수집 (3개)
9. 백업 (2개)
10. 성능 지표 (2개)

**검증 리포트**:
- 위치: `C:\nginx\reports\verification-report.html`
- 내용: 전체 시스템 상태, 실패 항목, 권장 사항

### 수동 확인

```powershell
# 서비스 상태
Get-Service nginx, nginx-web-ui

# Nginx 설정 검증
C:\nginx\nginx.exe -t

# 웹 UI 접속
Start-Process "http://localhost:8080"

# 로그 확인
Get-Content C:\nginx\logs\access.log -Tail 50 -Wait
Get-Content C:\nginx\logs\error.log -Tail 50 -Wait
```

---

## 💾 백업 및 복구

### 백업

```powershell
.\05-backup-restore.ps1 -Mode Backup -BackupPath "D:\Backups\nginx"
```

**백업 항목**:
- Nginx 설정 (`C:\nginx\conf\`)
- SSL 인증서 (`C:\nginx\ssl\`)
- 서비스 설정 (레지스트리)

### 복구

```powershell
.\05-backup-restore.ps1 -Mode Restore -BackupPath "D:\Backups\nginx\2025-10-20"
```

### 자동 백업 (작업 스케줄러)

```powershell
# 매일 02:00 자동 백업
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\airgap-package\scripts\05-backup-restore.ps1 -Mode Backup -BackupPath D:\Backups\nginx"

$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

Register-ScheduledTask -TaskName "Nginx Daily Backup" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -User "SYSTEM" `
                       -RunLevel Highest
```

---

## 🚀 고도화 기능 (운영 자동화)

### 헬스 모니터링 (실시간)

```powershell
# 기본 모니터링 (30초 간격)
.\07-health-monitor.ps1

# 대시보드 모드 + 자동 복구
.\07-health-monitor.ps1 -DashboardMode -AutoRecover

# 로그 저장
.\07-health-monitor.ps1 -ExportLog "C:\nginx\logs\health-monitor.log"
```

**모니터링 항목**:
- 시스템 리소스 (CPU, 메모리, 디스크)
- Nginx 서비스 상태 (프로세스, 포트, 설정)
- 웹 UI 상태 (응답 시간)
- 프록시 대상 서버 연결성

**자동 복구 기능**:
- Nginx 서비스 자동 재시작
- 웹 UI 서비스 자동 재시작
- 디스크 정리 (로그 파일)

### 로그 분석 및 이상 탐지

```powershell
# 빠른 분석 (최근 1시간)
.\08-log-analyzer.ps1

# 24시간 로그 분석 + HTML 리포트
.\08-log-analyzer.ps1 -AnalysisType Daily -ExportReport "C:\nginx\reports\log-analysis.html"

# 최근 30분, Top 20 결과
.\08-log-analyzer.ps1 -TimeWindow 30 -ShowTopN 20
```

**분석 기능**:
- HTTP 상태 코드 통계 (200, 404, 500 등)
- 에러 패턴 감지 (upstream timeout, connection refused)
- Top IP/URL/User-Agent 분석
- 보안 이벤트 감지 (SQL injection, 경로 순회 등)
- 에러율 임계값 알람

**출력 형식**:
- 콘솔 요약 통계
- HTML 리포트 (차트, 테이블)

### 성능 벤치마크

```powershell
# 표준 성능 테스트 (60초, 동시접속 50)
.\09-performance-benchmark.ps1

# 스트레스 테스트 + 리포트
.\09-performance-benchmark.ps1 -BenchmarkType Stress -ExportReport "C:\nginx\reports\perf.html"

# 특정 프록시 대상 테스트
.\09-performance-benchmark.ps1 -TargetURL "http://app.company.local" -Concurrency 100 -Duration 300
```

**측정 지표**:
- 처리량 (RPS: Requests Per Second)
- 응답 시간 (평균, P50, P95, P99)
- HTTP 상태 코드 분포
- CPU/메모리 사용률
- 성능 등급 (Excellent, Good, Fair, Poor)

**벤치마크 유형**:
- Quick: 빠른 테스트 (30초, 동시접속 10)
- Standard: 표준 테스트 (60초, 동시접속 50)
- Stress: 스트레스 테스트 (120초, 동시접속 200)

### CSV 프록시 일괄 등록

```powershell
# CSV에서 프록시 설정 일괄 적용
.\import-proxies.ps1 -CSVPath "C:\airgap-package\configs\services.csv"

# 미리보기 모드 (실제 변경 안 함)
.\import-proxies.ps1 -CSVPath "services.csv" -DryRun

# 기존 설정 백업 후 적용
.\import-proxies.ps1 -CSVPath "services.csv" -BackupExisting
```

**CSV 형식** (configs/services.csv):
```csv
domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path
app.company.local,192.168.1.100,3000,true,C:\nginx\ssl\app.crt,C:\nginx\ssl\app.key
dashboard.company.local,192.168.1.101,8080,false,,
api.company.local,192.168.1.102,5000,true,C:\nginx\ssl\api.crt,C:\nginx\ssl\api.key
```

**기능**:
- CSV 검증 (필수 컬럼, 데이터 형식)
- Nginx 설정 파일 자동 생성 (도메인별)
- SSL/비SSL 설정 자동 선택
- Nginx 설정 검증 및 재시작

### 자동 유지보수

```powershell
# 표준 유지보수 (로그 + 캐시 + 임시파일)
.\10-auto-maintenance.ps1

# 전체 유지보수 + 로그 압축
.\10-auto-maintenance.ps1 -MaintenanceType Deep -CompressOldLogs

# 미리보기 모드
.\10-auto-maintenance.ps1 -DryRun
```

**유지보수 작업**:
- **Quick**: 로그 로테이션만
- **Standard**: 로그 + 캐시 + 임시파일
- **Deep**: 모든 작업 + 백업 정리

**자동 정리 항목**:
- 오래된 로그 파일 (기본 7일 이상)
- Nginx 캐시
- 임시 파일
- 오래된 백업 (기본 30일 이상)

**스케줄 등록 (작업 스케줄러)**:
```powershell
# 매일 02:00 자동 유지보수
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\airgap-package\scripts\10-auto-maintenance.ps1"

$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

Register-ScheduledTask -TaskName "Nginx Auto Maintenance" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -User "SYSTEM" `
                       -RunLevel Highest
```

---

## 📚 문서

| 문서 | 설명 |
|------|------|
| [architecture.md](docs/architecture.md) | 시스템 아키텍처 및 구조 |
| [api.md](docs/api.md) | REST API, PowerShell 인터페이스 |
| [deployment.md](docs/deployment.md) | 전체 배포 가이드 |
| [troubleshooting.md](docs/troubleshooting.md) | 문제 해결 및 FAQ |
| [001-009_*.md](docs/) | 운영 매뉴얼 (9개) |

---

## 🚨 문제 해결

### 서비스 시작 실패

```powershell
# 설정 검증
C:\nginx\nginx.exe -t

# 로그 확인
Get-Content C:\nginx\logs\error.log -Tail 20

# 서비스 재시작
Restart-Service nginx
```

### 웹 UI 접속 불가

```powershell
# 서비스 상태
Get-Service nginx-web-ui

# 포트 확인
Get-NetTCPConnection -LocalPort 8080

# 수동 실행
cd C:\airgap-package\scripts
node nginx-web-ui.js
```

### 502 Bad Gateway

```powershell
# 업스트림 서버 연결 테스트
Test-NetConnection -ComputerName 192.168.1.100 -Port 3000

# Nginx 에러 로그
Get-Content C:\nginx\logs\error.log -Tail 50 | Select-String "upstream"
```

**자세한 문제 해결**: [docs/troubleshooting.md](docs/troubleshooting.md)

---

## 📋 시스템 요구사항

| 항목 | 요구사항 |
|------|----------|
| **OS** | Windows Server 2016/2019/2022 |
| **CPU** | 2 Core 이상 (4 Core 권장) |
| **RAM** | 4GB 이상 (8GB 권장) |
| **디스크** | 10GB 여유 공간 |
| **네트워크** | 에어갭 환경 (오프라인) |
| **도메인** | Active Directory 가입 필수 |
| **권한** | 로컬 관리자 권한 |

---

## 📝 변경 이력

### v1.1.0 (2025-10-21)
- ⭐ **실시간 헬스 모니터링** (07-health-monitor.ps1)
- ⭐ **로그 분석 도구** (08-log-analyzer.ps1)
- ⭐ **성능 벤치마크** (09-performance-benchmark.ps1)
- ⭐ **자동 유지보수** (10-auto-maintenance.ps1)
- ⭐ **CSV 일괄 프록시 등록** (import-proxies.ps1)
- ✅ 설치 스크립트 안정성 향상
- ✅ 백업/복원 기능 개선
- ✅ 문서 업데이트 (12개 파일)
- ✅ 패키지 검증 강화 (37 → 42개 테스트)

### v1.0.0 (2025-10-20)
- ✅ 초기 릴리스
- ✅ 완전 독립형 패키지 구조
- ✅ Node.js + Nginx + NSSM 통합
- ✅ 3가지 프록시 관리 옵션
- ✅ Active Directory 통합
- ✅ 강화된 웹 UI (enhanced 버전)
- ✅ 37개 자동 검증 테스트
- ✅ 종합 문서 (13개)
- ✅ 4가지 Nginx 설정 예시

---

## 📄 라이선스

- **Node.js**: MIT License
- **Nginx**: 2-clause BSD-like license
- **NSSM**: Public Domain
- **Zoraxy**: Apache License 2.0

---

## 🤝 지원

문제 발생 시:
1. [문제 해결 가이드](docs/troubleshooting.md) 확인
2. 검증 리포트 생성 (`03-verify-installation.ps1 -ExportReport`)
3. 로그 수집 후 지원팀에 문의

---

**제작**: 에어갭 환경 통합 팀
**버전**: 1.0.0
**최종 업데이트**: 2025-10-21
**패키지 크기**: 133MB
