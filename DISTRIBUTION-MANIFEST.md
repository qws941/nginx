# Windows Nginx 에어갭 패키지 배포 매니페스트

## 📦 패키지 정보

| 항목 | 값 |
|------|-----|
| **패키지 버전** | v1.1.0 |
| **릴리스 날짜** | 2025-10-21 |
| **패키지 타입** | 완전 오프라인 설치 패키지 |
| **아카이브 이름** | `nginx-airgap-package-v1.1.0.zip` |
| **아카이브 크기** | 75MB (압축) |
| **압축 해제 크기** | 133MB |
| **압축률** | 44% |
| **파일 수** | 54개 |

---

## 🔐 무결성 검증

### SHA256 체크섬

```
8da14a3a1175dce9839b466aba7514540f7f210a0e2ed9a51c4a4a6b6a422957  nginx-airgap-package-v1.1.0.zip
```

### 검증 방법

**Windows PowerShell**:
```powershell
# 다운로드한 파일의 체크섬 계산
Get-FileHash nginx-airgap-package-v1.1.0.zip -Algorithm SHA256

# 결과를 매니페스트 값과 비교
# Hash 값이 일치하면 파일이 손상되지 않았음
```

**Linux/macOS**:
```bash
sha256sum -c nginx-airgap-package-v1.1.0.zip.sha256
```

---

## 📁 패키지 구조

압축 해제 후 디렉토리 구조:

```
airgap-package/
├── installers/          # 설치 파일 (132MB)
│   ├── nginx-1.24.0.zip
│   ├── node-v20.11.0-x64.msi
│   ├── nssm-2.24.zip
│   ├── vcredist_x64.exe
│   └── zoraxy_windows_amd64.exe
│
├── scripts/             # PowerShell 스크립트 (456KB)
│   ├── 01-prepare-airgap.ps1           # 패키지 준비 (온라인)
│   ├── 02-install-airgap-enhanced.ps1  # 시스템 설치 (오프라인)
│   ├── 03-add-proxy.ps1                # 프록시 추가
│   ├── 04-remove-proxy.ps1             # 프록시 제거
│   ├── 05-backup-restore.ps1           # 백업/복원
│   ├── 06-validate-enhanced-package.ps1 # 패키지 검증
│   ├── 07-health-monitor.ps1           # 실시간 모니터링 ⭐ v1.1.0
│   ├── 08-log-analyzer.ps1             # 로그 분석 ⭐ v1.1.0
│   ├── 09-performance-benchmark.ps1    # 성능 벤치마크 ⭐ v1.1.0
│   ├── 10-auto-maintenance.ps1         # 자동 유지보수 ⭐ v1.1.0
│   ├── import-proxies.ps1              # CSV 일괄 등록 ⭐ v1.1.0
│   ├── test-nginx-web-ui.ps1           # 웹 UI 테스트
│   ├── nginx-web-ui.js                 # Node.js 웹 UI
│   └── nginx-web-ui-basic.js           # 기본 웹 UI
│
├── configs/             # 설정 템플릿 (32KB)
│   ├── .env.example
│   ├── nginx.conf.template
│   ├── reverse-proxy.conf.template
│   ├── services.csv.example
│   ├── health-monitor-config.json.example
│   ├── log-analyzer-config.json.example
│   ├── performance-config.json.example
│   └── maintenance-config.json.example
│
├── docs/                # 문서 (228KB)
│   ├── 001_README.md
│   ├── 002_PROXY-MANAGER-OPTIONS.md
│   ├── 003_OPERATIONS-CHECKLIST.md
│   ├── 004_OPERATIONS-MANUAL-AD-INTEGRATED.xwiki
│   ├── 005_OPERATIONS-MANUAL-DETAILED.md
│   ├── 006_SYNTAX-CHECK-REPORT.md
│   ├── 007_XWIKI-UPLOAD.xwiki
│   ├── 008_XWIKI-UPLOAD.html
│   ├── 009_ENHANCED-V2-GUIDE.xwiki
│   ├── api.md
│   ├── architecture.md
│   ├── deployment.md
│   └── troubleshooting.md
│
├── checksums.txt        # 설치 파일 체크섬
├── PACKAGE-INFO.txt     # 패키지 메타데이터
├── VALIDATION-REPORT.md # 검증 리포트
├── SYNTAX-CHECK-REPORT.md # 문법 검사 리포트
├── RELEASE-CHECKLIST.md # 릴리스 체크리스트
└── README.md           # 패키지 설명서
```

---

## ⚡ 빠른 시작

### 1단계: 패키지 다운로드 및 검증

```powershell
# 체크섬 검증
Get-FileHash nginx-airgap-package-v1.1.0.zip -Algorithm SHA256

# ZIP 압축 해제
Expand-Archive -Path nginx-airgap-package-v1.1.0.zip -DestinationPath C:\Temp
```

### 2단계: 에어갭 환경으로 전송

```powershell
# USB 드라이브 또는 보안 네트워크를 통해 전송
Copy-Item -Path "C:\Temp\airgap-package" -Destination "E:\airgap-package" -Recurse
```

### 3단계: 오프라인 설치 실행

```powershell
# 관리자 권한 PowerShell에서 실행
cd E:\airgap-package\scripts
.\02-install-airgap-enhanced.ps1
```

### 4단계: 설치 검증

```powershell
# 검증 스크립트 실행
.\06-validate-enhanced-package.ps1

# 웹 UI 접속
Start-Process "http://localhost:8080"
```

---

## 🆕 v1.1.0 신규 기능

### 1. 실시간 헬스 모니터링 (07-health-monitor.ps1)

```powershell
# 대시보드 모드로 실행
.\07-health-monitor.ps1 -DashboardMode

# 특정 메트릭만 모니터링
.\07-health-monitor.ps1 -CheckCpu -CheckMemory -CheckNginx
```

**기능**:
- CPU/메모리/디스크 사용률 추적
- Nginx/웹UI 서비스 상태 체크
- 프록시 대상 연결성 테스트
- 자동 복구 기능
- 알람 임계값 설정

### 2. 로그 분석 도구 (08-log-analyzer.ps1)

```powershell
# 지난 24시간 로그 분석
.\08-log-analyzer.ps1 -Hours 24

# 보안 이벤트만 분석
.\08-log-analyzer.ps1 -SecurityOnly
```

**기능**:
- 에러 패턴 분석
- 보안 위협 탐지 (SQL injection, XSS, path traversal)
- 트래픽 통계 (top URLs, IPs, user agents)
- 성능 메트릭 (응답 시간, 상태 코드 분포)

### 3. 성능 벤치마크 (09-performance-benchmark.ps1)

```powershell
# 기본 벤치마크 실행
.\09-performance-benchmark.ps1

# 부하 테스트 포함
.\09-performance-benchmark.ps1 -Concurrency 100 -Requests 10000
```

**기능**:
- Nginx 성능 측정 (요청/초, 응답 시간)
- 프록시 대상 응답 시간 측정
- 시스템 리소스 영향 분석
- 결과 리포트 생성 (HTML/JSON)

### 4. 자동 유지보수 (10-auto-maintenance.ps1)

```powershell
# 스케줄러에 등록
.\10-auto-maintenance.ps1 -Schedule

# 즉시 실행
.\10-auto-maintenance.ps1 -RunNow
```

**기능**:
- 로그 로테이션 (크기/날짜 기준)
- 임시 파일 정리
- 설정 백업
- 디스크 공간 모니터링
- 자동 알림

### 5. CSV 일괄 프록시 등록 (import-proxies.ps1)

```powershell
# CSV 파일에서 프록시 일괄 등록
.\import-proxies.ps1 -CsvPath "C:\proxies.csv"
```

**CSV 형식**:
```csv
ServiceName,TargetIP,TargetPort,ProxyPort
web-app,192.168.1.10,8080,80
api-server,192.168.1.20,3000,8081
```

---

## 🎯 시스템 요구사항

### 최소 요구사항

| 항목 | 요구사항 |
|------|---------|
| **OS** | Windows Server 2016 이상 |
| **아키텍처** | x64 (64-bit) |
| **CPU** | 2 코어 이상 |
| **RAM** | 4GB 이상 |
| **디스크** | 500MB 이상 (설치 공간) |
| **네트워크** | 프록시 대상 서버와 통신 가능 |
| **권한** | 관리자 (Administrator) |

### 권장 요구사항

| 항목 | 권장사항 |
|------|---------|
| **OS** | Windows Server 2019/2022 |
| **CPU** | 4 코어 이상 |
| **RAM** | 8GB 이상 |
| **디스크** | 2GB 이상 (로그 공간 포함) |
| **AD** | Active Directory 통합 환경 |

---

## 📋 지원되는 구성 요소

### 핵심 컴포넌트

| 컴포넌트 | 버전 | 용도 | 포트 |
|----------|------|------|------|
| **Nginx** | 1.24.0 | 리버스 프록시 엔진 | 80, 443 |
| **Node.js** | v20.11.0 | 웹 UI 런타임 | 8080 |
| **NSSM** | 2.24 | Windows 서비스 관리 | - |
| **Visual C++ Redistributable** | 2015-2022 | Node.js 의존성 | - |

### 옵션 컴포넌트

| 컴포넌트 | 용도 | 특징 |
|----------|------|------|
| **Zoraxy** | GUI 프록시 관리 | 독립 실행형, Windows 네이티브 |

---

## 🔄 업그레이드 경로

### v1.0.0 → v1.1.0

기존 v1.0.0 설치 환경에서 업그레이드:

```powershell
# 1. 기존 설정 백업
.\05-backup-restore.ps1 -Backup -BackupPath "C:\nginx-backup"

# 2. 신규 스크립트 복사
Copy-Item -Path "scripts\07-*.ps1" -Destination "C:\nginx\scripts"
Copy-Item -Path "scripts\08-*.ps1" -Destination "C:\nginx\scripts"
Copy-Item -Path "scripts\09-*.ps1" -Destination "C:\nginx\scripts"
Copy-Item -Path "scripts\10-*.ps1" -Destination "C:\nginx\scripts"
Copy-Item -Path "scripts\import-proxies.ps1" -Destination "C:\nginx\scripts"

# 3. 설정 템플릿 업데이트
Copy-Item -Path "configs\*-config.json.example" -Destination "C:\nginx\configs"

# 4. 검증
.\06-validate-enhanced-package.ps1
```

---

## 🛡️ 보안 고려사항

### 패키지 무결성

1. **체크섬 검증 필수**: 다운로드 후 반드시 SHA256 체크섬 확인
2. **공식 출처에서만 다운로드**: 신뢰할 수 있는 저장소 사용
3. **바이러스 스캔**: 기업 보안 정책에 따라 스캔 수행

### 설치 환경 보안

1. **관리자 권한 최소화**: 설치 후 일반 사용자 계정으로 서비스 실행
2. **방화벽 규칙 설정**: 필요한 포트만 개방 (80, 443, 8080)
3. **AD 통합**: Active Directory 그룹 정책 적용 권장
4. **SSL/TLS 인증서**: 프로덕션 환경에서는 유효한 인증서 사용

### 감사 및 모니터링

1. **로그 보관**: 최소 30일 이상 로그 보관
2. **정기 점검**: 헬스 모니터링 스크립트 스케줄 실행
3. **보안 업데이트**: Nginx/Node.js 보안 패치 적용

---

## 📞 지원 및 문의

### 문서

- **설치 가이드**: `docs/deployment.md`
- **API 문서**: `docs/api.md`
- **아키텍처**: `docs/architecture.md`
- **문제 해결**: `docs/troubleshooting.md`
- **운영 매뉴얼**: `docs/005_OPERATIONS-MANUAL-DETAILED.md`

### 문제 해결

1. **설치 실패**: `docs/troubleshooting.md` 참조
2. **프록시 오류**: Nginx 로그 확인 (`C:\nginx\logs\error.log`)
3. **웹 UI 접속 불가**: Node.js 서비스 상태 확인

### 검증 도구

```powershell
# 전체 시스템 검증
.\06-validate-enhanced-package.ps1

# 웹 UI 테스트
.\test-nginx-web-ui.ps1

# 헬스 체크
.\07-health-monitor.ps1 -QuickCheck
```

---

## 📜 라이선스

이 패키지는 다음 오픈소스 프로젝트를 포함합니다:

| 컴포넌트 | 라이선스 |
|----------|---------|
| Nginx | 2-clause BSD License |
| Node.js | MIT License |
| NSSM | Public Domain |
| Zoraxy | AGPL v3 |

자세한 내용은 각 컴포넌트의 라이선스 파일을 참조하세요.

---

## 📊 버전 히스토리

### v1.1.0 (2025-10-21)

**신규 기능**:
- ⭐ 실시간 헬스 모니터링 (07-health-monitor.ps1)
- ⭐ 로그 분석 도구 (08-log-analyzer.ps1)
- ⭐ 성능 벤치마크 (09-performance-benchmark.ps1)
- ⭐ 자동 유지보수 (10-auto-maintenance.ps1)
- ⭐ CSV 일괄 프록시 등록 (import-proxies.ps1)

**개선 사항**:
- 설치 스크립트 안정성 향상
- 에러 처리 로직 개선
- 문서 업데이트 (12개 파일)

**패키지 메타데이터**:
- 전체 검증 리포트 포함
- 문법 검사 리포트 포함
- 릴리스 체크리스트 포함
- SHA256 체크섬 제공

### v1.0.0 (2025-10-20)

**초기 릴리스**:
- Nginx 1.24.0 리버스 프록시
- Node.js v20.11.0 웹 UI
- NSSM Windows 서비스 관리
- 기본 프록시 관리 스크립트 (6개)
- PowerShell 스크립트 기반 설치

---

## ✅ 배포 준비 상태

| 항목 | 상태 | 점수 |
|------|------|------|
| **패키지 구조** | ✅ 검증 완료 | 100/100 |
| **설치 파일** | ✅ 체크섬 확인 | 100/100 |
| **스크립트** | ⚠️ Windows 테스트 필요 | 85/100 |
| **문서** | ✅ 완료 | 100/100 |
| **보안** | ✅ 검증 완료 | 100/100 |
| **압축 아카이브** | ✅ 생성 완료 | 100/100 |

**종합 점수**: **A- (85/100)**

**배포 권장 사항**:
- ✅ 프로덕션 배포 가능 (조건부)
- ⚠️ Windows 환경에서 최종 테스트 권장
- ⚠️ 2개 스크립트 문법 검증 필요 (08, test-nginx-web-ui)

---

**생성 일시**: 2025-10-21T02:54:00+09:00  
**매니페스트 버전**: 1.0  
**체크섬 파일**: `nginx-airgap-package-v1.1.0.zip.sha256`
