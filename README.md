# Windows 에어갭 환경용 Nginx 리버스 프록시

**완전 독립형 오프라인 설치 패키지**

![Version](https://img.shields.io/badge/version-1.1.0-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20Server-blue)
![Size](https://img.shields.io/badge/size-75MB%20(133MB%20uncompressed)-green)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📋 프로젝트 개요

Windows Server 에어갭(완전 오프라인) 환경에서 **Nginx 리버스 프록시**를 USB 하나로 설치하고 관리하기 위한 통합 패키지입니다.

### 주요 특징

- ✅ **완전 독립형 패키지**: 인터넷 연결 없이 모든 구성 요소 포함
- ✅ **단일 USB 전송**: 133MB 패키지 전체를 USB로 복사
- ✅ **Active Directory 통합**: AD 그룹 기반 권한 관리
- ✅ **3가지 관리 옵션**: 웹 UI, PowerShell, Zoraxy GUI
- ✅ **자동 검증**: 37개 테스트 항목
- ✅ **종합 문서**: 13개 기술 문서 포함

---

## 🚀 빠른 시작

### 설치 (3단계)

**1단계**: 인터넷 환경에서 패키지 준비
```powershell
cd airgap-package\scripts
.\01-prepare-airgap.ps1
```

**2단계**: USB로 전송
```powershell
Copy-Item -Path "airgap-package" -Destination "E:\" -Recurse
```

**3단계**: 에어갭 Windows Server에서 설치
```powershell
cd C:\airgap-package\scripts
.\02-install-airgap.ps1
```

**설치 시간**: 약 5-10분

---

## 📦 프로젝트 구조

```
nginx/
├── README.md                    # 본 파일
│
├── resume/                      # 📖 기술 문서 (심볼릭 링크)
│   ├── architecture.md         # 시스템 아키텍처
│   ├── api.md                  # API 및 인터페이스
│   ├── deployment.md           # 배포 가이드
│   └── troubleshooting.md      # 문제 해결
│
├── demo/                        # 🎯 예시 (심볼릭 링크)
│   ├── examples/
│   │   ├── proxy-config-example.conf
│   │   ├── example-app.company.local.conf
│   │   ├── example-loadbalancer.conf
│   │   ├── example-static-site.conf
│   │   └── services.csv
│   ├── screenshots/
│   └── videos/
│
├── xwiki/                       # 📚 운영 매뉴얼 (심볼릭 링크)
│   └── 001-009_*.md/*.xwiki    # 9개 운영 문서
│
└── airgap-package/              # 📦 독립 설치 패키지 (133MB)
    ├── README.md               # 패키지 상세 가이드
    ├── PACKAGE-INFO.txt        # 메타데이터
    ├── checksums.txt           # SHA256 체크섬
    │
    ├── installers/             # 설치 파일 (5개)
    │   ├── node-v20.11.0-x64.msi
    │   ├── nginx-1.24.0.zip
    │   ├── nssm-2.24.zip
    │   ├── vcredist_x64.exe
    │   └── zoraxy_windows_amd64.exe
    │
    ├── scripts/                # PowerShell + JS (13+2개)
    │   ├── 01-prepare-airgap.ps1
    │   ├── 02-install-airgap.ps1
    │   ├── 03-verify-installation.ps1
    │   ├── 04-setup-ad-integration.ps1
    │   ├── 05-backup-restore.ps1
    │   ├── 06-validate-enhanced-package.ps1
    │   ├── 07-health-monitor.ps1        # ⭐ 실시간 헬스 모니터링
    │   ├── 08-log-analyzer.ps1          # ⭐ 로그 분석 및 이상 탐지
    │   ├── 09-performance-benchmark.ps1 # ⭐ 성능 벤치마크
    │   ├── 10-auto-maintenance.ps1      # ⭐ 자동 유지보수
    │   ├── import-proxies.ps1           # ⭐ CSV 프록시 일괄 등록
    │   ├── test-nginx-web-ui.ps1
    │   └── nginx-web-ui.js (+ basic)
    │
    ├── configs/                # 설정 템플릿
    │   ├── .env.example
    │   ├── services.csv
    │   └── nginx/
    │       ├── nginx.conf
    │       └── conf.d/         # 4개 예시
    │
    ├── docs/                   # 원본 문서 (13개)
    │   ├── architecture.md
    │   ├── api.md
    │   ├── deployment.md
    │   ├── troubleshooting.md
    │   └── 001-009_*.md        # 운영 매뉴얼
    │
    ├── npm-packages/
    ├── ssl/
    └── logs/
```

**중요**: `resume/`, `demo/`, `xwiki/` 디렉토리는 `airgap-package/docs/` 및 `airgap-package/configs/`로의 **심볼릭 링크**입니다. 실제 파일은 `airgap-package/` 안에 있어 패키지 독립성이 보장됩니다.

---

## 🔧 설치되는 구성 요소

| 컴포넌트 | 버전 | 용도 | 포트 |
|---------|------|------|------|
| **Nginx** | 1.24.0 | 리버스 프록시 엔진 | 80, 443 |
| **Node.js** | v20.11.0 | 웹 UI 런타임 | 8080 |
| **NSSM** | 2.24 | Windows 서비스 관리 | - |
| **Visual C++** | 2015-2022 | Node.js 의존성 | - |
| **Zoraxy** | latest | GUI 관리 (옵션) | 8000 |

**Windows 서비스**:
- `nginx` - Nginx 웹서버
- `nginx-web-ui` - 웹 UI 관리

---

## 🎯 프록시 관리 옵션

### 1. 웹 UI (추천) ⭐
```
http://localhost:8080

특징:
- 직관적 GUI
- 실시간 상태 모니터링
- 로그 조회 기능
- localhost 전용 (보안)
```

### 2. PowerShell 스크립트
```powershell
# CSV 파일 편집
notepad C:\airgap-package\configs\services.csv

# 일괄 적용
.\scripts\import-proxies.ps1 -CSVPath "configs\services.csv"
```

### 3. Zoraxy GUI
```
http://localhost:8000

특징:
- Windows 네이티브 앱
- 독립 실행형
- 기본 계정: admin / admin
```

---

## 📚 문서

### 기술 문서 (resume/)

| 문서 | 설명 | 위치 |
|------|------|------|
| [architecture.md](resume/architecture.md) | 시스템 아키텍처 및 구조 | resume/ |
| [api.md](resume/api.md) | REST API, PowerShell 인터페이스 | resume/ |
| [deployment.md](resume/deployment.md) | 전체 배포 가이드 | resume/ |
| [troubleshooting.md](resume/troubleshooting.md) | 문제 해결 및 FAQ | resume/ |

### 운영 매뉴얼 (xwiki/)

| 문서 | 설명 |
|------|------|
| [001_README.md](xwiki/001_README.md) | 설치 가이드 (전체) |
| [002_PROXY-MANAGER-OPTIONS.md](xwiki/002_PROXY-MANAGER-OPTIONS.md) | 프록시 관리 3가지 방법 |
| [003_OPERATIONS-CHECKLIST.md](xwiki/003_OPERATIONS-CHECKLIST.md) | 일일/주간/월간 체크리스트 |
| [004-009_*.md/*.xwiki](xwiki/) | 상세 운영 매뉴얼 (6개) |

### 예시 파일 (demo/examples/)

| 파일 | 설명 |
|------|------|
| [proxy-config-example.conf](demo/examples/proxy-config-example.conf) | 기본 프록시 설정 |
| [example-app.company.local.conf](demo/examples/example-app.company.local.conf) | SSL 프록시 예시 |
| [example-loadbalancer.conf](demo/examples/example-loadbalancer.conf) | 로드 밸런싱 설정 |
| [example-static-site.conf](demo/examples/example-static-site.conf) | 정적 사이트 호스팅 |
| [services.csv](demo/examples/services.csv) | CSV 프록시 목록 |

---

## 🔐 Active Directory 통합

### AD 그룹 생성
```powershell
New-ADGroup -Name "NginxAdministrators" -GroupScope Global -GroupCategory Security
New-ADGroup -Name "NginxOperators" -GroupScope Global -GroupCategory Security
```

### 서비스 계정 생성
```powershell
New-ADUser -Name "nginx-service" -SamAccountName "nginx-service" ...
```

### AD 통합 설정
```powershell
cd C:\airgap-package\scripts
.\04-setup-ad-integration.ps1
```

**권한 모델**:
- **NginxAdministrators**: 전체 관리 권한
- **NginxOperators**: 읽기 + 프록시 추가만

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

**검증 리포트**: `C:\nginx\reports\verification-report.html`

### 수동 확인
```powershell
# 서비스 상태
Get-Service nginx, nginx-web-ui

# Nginx 설정 검증
C:\nginx\nginx.exe -t

# 웹 UI 접속
Start-Process "http://localhost:8080"

# 로그 모니터링
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

### 자동 백업 스케줄
```powershell
# 매일 02:00 자동 백업
Register-ScheduledTask -TaskName "Nginx Daily Backup" ...
```

---

## 🚨 문제 해결

### 서비스 시작 실패
```powershell
C:\nginx\nginx.exe -t                       # 설정 검증
Get-Content C:\nginx\logs\error.log -Tail 20
Restart-Service nginx
```

### 웹 UI 접속 불가
```powershell
Get-Service nginx-web-ui
Get-NetTCPConnection -LocalPort 8080
```

### 502 Bad Gateway
```powershell
Test-NetConnection -ComputerName 192.168.1.100 -Port 3000
Get-Content C:\nginx\logs\error.log -Tail 50 | Select-String "upstream"
```

**자세한 문제 해결**: [troubleshooting.md](resume/troubleshooting.md)

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

### v1.1.0 (2025-10-21) - 고도화 버전
- ✅ **운영 자동화 스크립트 5개 추가**
  - 실시간 헬스 모니터링 (07-health-monitor.ps1)
  - 로그 분석 및 이상 탐지 (08-log-analyzer.ps1)
  - 성능 벤치마크 (09-performance-benchmark.ps1)
  - CSV 프록시 일괄 등록 (import-proxies.ps1)
  - 자동 유지보수 (10-auto-maintenance.ps1)
- ✅ **모니터링 기능**
  - 시스템 리소스 실시간 추적 (CPU, 메모리, 디스크)
  - Nginx/웹UI 상태 감시
  - 프록시 대상 서버 연결성 체크
  - 자동 복구 기능 (서비스 재시작, 디스크 정리)
- ✅ **분석 기능**
  - HTTP 상태 코드 통계
  - 에러 패턴 자동 감지
  - 보안 이벤트 탐지 (SQL injection, 경로 순회)
  - Top IP/URL/User-Agent 분석
- ✅ **성능 측정**
  - RPS (Requests Per Second) 측정
  - 응답 시간 분석 (평균, P50, P95, P99)
  - 스트레스 테스트 (최대 200 동시접속)
- ✅ **자동화**
  - CSV 기반 대량 프록시 등록
  - 로그 로테이션 및 압축
  - 캐시/임시파일 자동 정리
  - 스케줄 등록 가능 (작업 스케줄러)

### v1.0.0 (2025-10-21)
- ✅ 완전 독립형 패키지 구조
- ✅ 중복 제거 및 통합 완료
- ✅ 루트 디렉토리 표준 구조 (resume/, demo/, xwiki/)
- ✅ 심볼릭 링크로 패키지 독립성 유지
- ✅ Node.js + Nginx + NSSM 통합
- ✅ 3가지 프록시 관리 옵션
- ✅ Active Directory 통합
- ✅ 강화된 웹 UI (46KB enhanced)
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
1. [문제 해결 가이드](resume/troubleshooting.md) 확인
2. 검증 리포트 생성 (`03-verify-installation.ps1 -ExportReport`)
3. 로그 수집 후 지원팀에 문의

---

## 🎁 패키지 정보

| 항목 | 값 |
|------|-----|
| **패키지 크기** | 133MB |
| **파일 수** | 44개 |
| **설치 시간** | 5-10분 |
| **지원 OS** | Windows Server 2016/2019/2022 |
| **버전** | v1.0.0 |
| **최종 업데이트** | 2025-10-21 |

---

**제작**: 에어갭 환경 통합 팀
**버전**: v1.1.0
**최종 업데이트**: 2025-10-21
**패키지**: nginx-airgap-package-v1.1.0.zip (75MB)
**SHA256**: 8da14a3a1175dce9839b466aba7514540f7f210a0e2ed9a51c4a4a6b6a422957
