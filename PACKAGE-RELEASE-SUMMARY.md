# Windows Nginx Air-Gap Package v1.1.0 - 릴리스 요약

**릴리스 날짜**: 2025-10-21
**패키지 버전**: v1.1.0
**빌드 상태**: ✅ 배포 준비 완료

---

## 📦 배포 파일

### 주 배포 파일
| 파일명 | 크기 | SHA256 체크섬 |
|--------|------|---------------|
| nginx-airgap-package-v1.1.0.zip | 75MB | 8da14a3a1175dce9839b466aba7514540f7f210a0e2ed9a51c4a4a6b6a422957 |
| nginx-airgap-package-v1.1.0.zip.sha256 | 98B | - |

### 압축 효율
- **원본 크기**: 133MB
- **압축 크기**: 75MB
- **압축률**: 44% 절감
- **파일 수**: 54개

---

## 🆕 v1.1.0 주요 변경사항

### 신규 운영 자동화 스크립트 (5개)

1. **07-health-monitor.ps1** (22KB)
   - 실시간 시스템 리소스 모니터링 (CPU, 메모리, 디스크)
   - Nginx/웹UI 서비스 상태 체크
   - 프록시 대상 서버 연결성 테스트
   - 자동 복구 기능 (서비스 재시작, 디스크 정리)
   - 대시보드 모드 지원

2. **08-log-analyzer.ps1** (21KB)
   - HTTP 상태 코드 통계 (200, 404, 500 등)
   - 에러 패턴 자동 감지
   - 보안 이벤트 탐지 (SQL injection, 경로 순회)
   - Top IP/URL/User-Agent 분석
   - HTML 리포트 생성

3. **09-performance-benchmark.ps1** (19KB)
   - RPS (Requests Per Second) 측정
   - 응답 시간 분석 (평균, P50, P95, P99)
   - 3가지 프로파일 (Quick, Standard, Stress)
   - CPU/메모리 사용률 추적
   - 성능 등급 평가

4. **import-proxies.ps1** (16KB)
   - CSV 기반 대량 프록시 등록
   - SSL/비SSL 자동 설정
   - Dry-run 모드 (미리보기)
   - Nginx 설정 자동 검증 및 재시작

5. **10-auto-maintenance.ps1** (16KB)
   - 로그 로테이션 및 압축
   - 캐시/임시파일 자동 정리
   - 백업 보관 정책 관리
   - 디스크 공간 모니터링
   - 작업 스케줄러 통합

### 개선 사항
- ✅ 설치 스크립트 안정성 향상
- ✅ 에러 처리 로직 개선
- ✅ 문서 업데이트 (10개 파일)
- ✅ 패키지 검증 강화

---

## 📊 패키지 구성

### 설치 파일 (installers/) - 132MB
| 파일 | 크기 | 버전 | SHA256 |
|------|------|------|--------|
| nginx-1.24.0.zip | 1.7MB | 1.24.0 | 69a36bfd2a61d7a736fafd392708bd0fb6cf15d741f8028fe6d8bb5ebd670eb9 |
| node-v20.11.0-x64.msi | 26MB | v20.11.0 | 9a8c2e99b1fca559e1a1a393d6be4a23781b0c66883a9d6e5584272d9bf49dc2 |
| nssm-2.24.zip | 344KB | 2.24 | 727d1e42275c605e0f04aba98095c38a8e1e46def453cdffce42869428aa6743 |
| vcredist_x64.exe | 25MB | 2015-2022 | cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b |
| zoraxy_windows_amd64.exe | 80MB | latest | 6aea6329574559decb54cbd5b4481be06e260e99fcf0427caf83e0239841a374 |

### PowerShell 스크립트 (scripts/) - 456KB
- **설치 및 검증**: 6개 스크립트
- **운영 자동화**: 5개 스크립트 ⭐ NEW
- **웹 UI**: 2개 JavaScript 파일

### 설정 템플릿 (configs/) - 32KB
- 환경 변수 (.env.example)
- Nginx 메인 설정 (nginx.conf)
- 프록시 설정 예시 (4개)
- CSV 템플릿 (services.csv)

### 문서 (docs/) - 228KB
- **기술 문서**: 4개 (architecture, api, deployment, troubleshooting)
- **운영 매뉴얼**: 6개 (001-009)

---

## 🚀 빠른 배포 가이드

### 1단계: 패키지 다운로드 및 검증
\`\`\`powershell
# SHA256 검증
Get-FileHash nginx-airgap-package-v1.1.0.zip -Algorithm SHA256

# 예상 값: 8da14a3a1175dce9839b466aba7514540f7f210a0e2ed9a51c4a4a6b6a422957
\`\`\`

### 2단계: 압축 해제
\`\`\`powershell
Expand-Archive -Path nginx-airgap-package-v1.1.0.zip -DestinationPath C:\Temp
\`\`\`

### 3단계: USB 전송
\`\`\`powershell
Copy-Item -Path "C:\Temp\airgap-package" -Destination "E:\" -Recurse
\`\`\`

### 4단계: 에어갭 서버 설치
\`\`\`powershell
# USB에서 서버로 복사
Copy-Item -Path "E:\airgap-package" -Destination "C:\" -Recurse

# 관리자 권한 PowerShell 실행
cd C:\airgap-package\scripts
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 설치
.\02-install-airgap.ps1
\`\`\`

### 5단계: 검증
\`\`\`powershell
.\03-verify-installation.ps1 -Detailed -ExportReport
\`\`\`

**예상 설치 시간**: 5-10분

---

## 📋 시스템 요구사항

### 최소 요구사항
- **OS**: Windows Server 2016 이상
- **CPU**: 2 Core
- **RAM**: 4GB
- **디스크**: 10GB 여유 공간
- **도메인**: Active Directory 도메인 가입
- **권한**: 로컬 관리자 권한

### 권장 요구사항
- **OS**: Windows Server 2019/2022
- **CPU**: 4 Core 이상
- **RAM**: 8GB 이상
- **디스크**: SSD, 20GB 여유 공간

---

## 🎯 운영 자동화 활용 예시

### 실시간 모니터링 (대시보드 모드)
\`\`\`powershell
.\07-health-monitor.ps1 -DashboardMode -AutoRecover
\`\`\`

### 24시간 로그 분석
\`\`\`powershell
.\08-log-analyzer.ps1 -AnalysisType Daily -ExportReport
\`\`\`

### 성능 벤치마크
\`\`\`powershell
.\09-performance-benchmark.ps1 -Profile Standard -GenerateReport
\`\`\`

### CSV 프록시 일괄 등록
\`\`\`powershell
.\import-proxies.ps1 -CSVPath "configs\services.csv" -Apply
\`\`\`

### 자동 유지보수 (스케줄 등록)
\`\`\`powershell
Register-ScheduledTask -TaskName "Nginx Auto Maintenance" \
    -Action (New-ScheduledTaskAction -Execute "PowerShell.exe" \
        -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\airgap-package\scripts\10-auto-maintenance.ps1") \
    -Trigger (New-ScheduledTaskTrigger -Daily -At 2:00AM) \
    -User "SYSTEM" -RunLevel Highest
\`\`\`

---

## 🔐 보안 검증

### 패키지 무결성
- ✅ SHA256 체크섬 제공
- ✅ 모든 설치 파일 체크섬 검증 (checksums.txt)
- ✅ 공식 출처에서 다운로드

### 설치 환경 보안
- ✅ localhost-only 웹 UI (127.0.0.1:8080)
- ✅ Active Directory 통합 지원
- ✅ 역할 기반 권한 관리
- ✅ 로그 분석 및 보안 이벤트 탐지

---

## 📞 지원 및 문의

### 문서
- **배포 가이드**: DISTRIBUTION-MANIFEST.md
- **설치 매뉴얼**: airgap-package/docs/deployment.md
- **문제 해결**: airgap-package/docs/troubleshooting.md
- **운영 체크리스트**: airgap-package/docs/003_OPERATIONS-CHECKLIST.md

### 검증 도구
\`\`\`powershell
# 전체 패키지 검증
.\06-validate-enhanced-package.ps1

# 설치 검증 (37개 테스트)
.\03-verify-installation.ps1 -Detailed -ExportReport
\`\`\`

---

## 📝 변경 이력

### v1.1.0 (2025-10-21) - 운영 자동화 릴리스
- ⭐ 실시간 헬스 모니터링
- ⭐ 로그 분석 및 보안 이벤트 탐지
- ⭐ 성능 벤치마크
- ⭐ CSV 프록시 일괄 등록
- ⭐ 자동 유지보수
- ✅ 설치 스크립트 안정성 향상
- ✅ 문서 업데이트

### v1.0.0 (2025-10-20) - 초기 릴리스
- ✅ 완전 독립형 오프라인 패키지
- ✅ Nginx 1.24.0 + Node.js v20.11.0
- ✅ 3가지 프록시 관리 옵션
- ✅ Active Directory 통합
- ✅ 37개 자동 검증 테스트

---

## ✅ 배포 체크리스트

- [x] 패키지 구조 검증
- [x] 설치 파일 체크섬 생성
- [x] 스크립트 문법 검증
- [x] 문서 완성도 확인
- [x] 압축 아카이브 생성
- [x] SHA256 체크섬 생성
- [x] 배포 매니페스트 작성
- [x] README 업데이트

**배포 상태**: ✅ **프로덕션 배포 가능**

---

**릴리스 담당**: Air-Gap Integration Team
**빌드 일시**: 2025-10-21T08:23:00+09:00
**배포 환경**: Windows Server 2016/2019/2022
**지원 기간**: 2025-10-21 ~ 2026-10-21 (1년)
