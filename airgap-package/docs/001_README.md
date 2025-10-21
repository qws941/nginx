# 🚀 에어갭 환경 통합 설치 패키지

> **완전 오프라인 설치 패키지** - 인터넷 연결 없이 Windows Server에 Node.js + Nginx 리버스 프록시 시스템 구축

---

## 📦 패키지 정보

**생성 일시**: 2025-10-20
**패키지 크기**: 132MB (Zoraxy 포함)
**대상 환경**: Windows Server 2016/2019/2022 (에어갭)

---

## ✅ 포함된 구성요소

| 구성요소 | 버전 | 크기 | 용도 |
|---------|------|------|------|
| **Node.js** | v20.11.0 | 26MB | JavaScript 런타임 |
| **Nginx** | v1.24.0 | 1.7MB | 리버스 프록시 웹서버 |
| **Zoraxy** | latest | 80MB | 웹 UI 프록시 관리자 (옵션) |
| **NSSM** | v2.24 | 344KB | Windows 서비스 관리자 |
| **Visual C++** | 2022 | 25MB | 런타임 라이브러리 |

**모든 파일의 SHA256 체크섬이 포함되어 있습니다.**

### 🎯 프록시 관리 옵션 3가지

기존 **conf.d** 설정을 작성하신 경우, 다음 중 선택하세요:

1. **PowerShell 스크립트** - CSV 파일 기반, 웹 UI 없음
2. **Node.js 웹 UI** ⭐ - 기존 설정 유지 + 웹 UI (권장)
3. **Zoraxy** - 독립형 웹 UI, Nginx 대체

자세한 내용은 **`PROXY-MANAGER-OPTIONS.md`** 파일을 참조하세요.

---

## 🔥 빠른 설치 (3단계)

### 1️⃣ 패키지 전송
```bash
# USB 또는 내부 네트워크로 전송
# 전체 airgap-package 폴더를 Windows Server로 복사
```

### 2️⃣ 설치 실행
```powershell
# Windows Server에서 관리자 PowerShell 실행
cd airgap-package\scripts
.\02-install-airgap.ps1

# 자동으로 설치됩니다:
# ✓ Visual C++ 재배포 패키지
# ✓ Node.js v20.11.0
# ✓ Nginx v1.24.0
# ✓ NSSM 서비스 관리자
# ✓ DNS 서버 (선택)
# ✓ 방화벽 규칙
```

### 3️⃣ 검증
```powershell
.\03-verify-installation.ps1

# 설치 확인
node --version
npm --version
```

---

## 📂 패키지 구조

```
airgap-package/
├── installers/                     # 설치 파일 (53MB)
│   ├── node-v20.11.0-x64.msi      # Node.js 설치 파일
│   ├── nginx-1.24.0.zip           # Nginx 웹서버
│   ├── nssm-2.24.zip              # NSSM 서비스 관리자
│   └── vcredist_x64.exe           # Visual C++ 재배포
├── scripts/                        # 설치 스크립트
│   ├── 02-install-airgap.ps1      # ★ 메인 설치 스크립트
│   ├── 03-verify-installation.ps1  # 설치 검증
│   └── download-packages.sh        # [Linux] 패키지 수집 스크립트
├── configs/                        # 설정 템플릿
│   ├── .env.example               # 환경변수 템플릿
│   └── services.csv.example       # 서비스 목록 예제
├── ssl/                            # SSL 인증서 (수동 추가 필요)
│   ├── cert.crt (또는 cert.pem)   # 인증서 파일
│   └── cert.key                    # 개인키 파일
├── npm-packages/                   # npm 패키지 (선택)
├── logs/                           # 설치 로그
├── checksums.txt                   # ★ 파일 무결성 체크섬
├── PACKAGE-INFO.txt                # 패키지 정보
└── README.md                       # 이 파일
```

---

## 🔒 보안 검증

### 파일 무결성 확인
```powershell
# PowerShell에서 체크섬 검증
Get-FileHash installers\node-v20.11.0-x64.msi -Algorithm SHA256

# checksums.txt와 비교
Get-Content checksums.txt
```

**체크섬 값**:
```
node-v20.11.0-x64.msi    9a8c2e99b1fca559e1a1a393d6be4a23781b0c66883a9d6e5584272d9bf49dc2
nginx-1.24.0.zip         69a36bfd2a61d7a736fafd392708bd0fb6cf15d741f8028fe6d8bb5ebd670eb9
nssm-2.24.zip            727d1e42275c605e0f04aba98095c38a8e1e46def453cdffce42869428aa6743
vcredist_x64.exe         cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b
```

---

## 🛠️ 설치 후 작업

### 1. PowerShell 재시작
```powershell
# 환경변수 적용을 위해 필수
exit
# 새 PowerShell 창을 관리자 권한으로 재실행
```

### 2. Nginx 서비스 등록
```powershell
cd C:\nginx
.\nssm.exe install nginx "C:\nginx\nginx.exe"
Start-Service nginx
Get-Service nginx
```

### 3. SSL 인증서 설치 (필수)
```powershell
# ssl/ 폴더에 인증서 복사
Copy-Item cert.crt C:\nginx\conf\ssl\
Copy-Item cert.key C:\nginx\conf\ssl\

# 또는 패키지의 ssl/ 폴더에 미리 넣어두기
```

### 4. Node.js 애플리케이션 예제
```javascript
// C:\projects\myapp\server.js
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello from Air-Gap Environment!');
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
});
```

---

## ⚙️ 선택적 설치 옵션

```powershell
# DNS 서버 제외
.\02-install-airgap.ps1 -SkipDNS

# 방화벽 규칙 제외
.\02-install-airgap.ps1 -SkipFirewall

# Node.js 제외 (Nginx만)
.\02-install-airgap.ps1 -SkipNodeJS

# 강제 설치 (확인 없이)
.\02-install-airgap.ps1 -Force

# 복합 옵션
.\02-install-airgap.ps1 -SkipDNS -SkipFirewall -Force
```

---

## 🔍 설치 검증

```powershell
# 기본 검증
.\03-verify-installation.ps1

# 상세 모드 (디버깅)
.\03-verify-installation.ps1 -Detailed

# 보고서 내보내기 (JSON)
.\03-verify-installation.ps1 -ExportReport
```

**검증 항목** (총 8개 카테고리):
- ✓ Node.js 및 npm 버전
- ✓ Nginx 설정 파일 및 구문
- ✓ NSSM 서비스 관리자
- ✓ DNS 서버 상태
- ✓ 방화벽 규칙
- ✓ SSL 인증서
- ✓ 환경변수 (PATH)
- ✓ 포트 가용성 (80, 443, 3000)

---

## 📊 시스템 요구사항

| 항목 | 요구사항 |
|-----|---------|
| **운영체제** | Windows Server 2016/2019/2022 |
| **PowerShell** | 5.1 이상 |
| **디스크 공간** | 최소 10GB 여유 |
| **메모리** | 최소 4GB RAM |
| **권한** | 관리자 권한 필수 |
| **네트워크** | 인터넷 불필요 (오프라인 설치) |

---

## ⚠️ 문제 해결

### Node.js 명령어를 찾을 수 없음
```powershell
# 환경변수 수동 설정
$env:Path += ";C:\Program Files\nodejs"
[Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")

# PowerShell 재시작 필수
```

### Nginx 서비스 시작 실패
```powershell
# 로그 확인
Get-Content C:\nginx\logs\error.log -Tail 20

# 설정 파일 테스트
C:\nginx\nginx.exe -t

# 포트 충돌 확인
Get-NetTCPConnection -LocalPort 80,443
```

### SSL 인증서 오류
```powershell
# 인증서 파일 권한 확인
icacls C:\nginx\conf\ssl\cert.key

# PEM 형식 확인 (-----BEGIN CERTIFICATE-----)
Get-Content C:\nginx\conf\ssl\cert.crt | Select-Object -First 1
```

### 체크섬 불일치
```powershell
# 파일 재다운로드 필요
# checksums.txt와 실제 파일 해시값 비교
Get-FileHash installers\*.* -Algorithm SHA256
```

---

## 📝 로그 파일

설치 및 검증 로그는 다음 위치에 저장됩니다:

```
logs/
├── install-YYYYMMDD-HHMMSS.log      # 설치 로그
├── verification-YYYYMMDD-HHMMSS.json # 검증 보고서
└── download-YYYYMMDD-HHMMSS.log     # 다운로드 로그 (Linux)
```

---

## 🎯 추가 기능

### npm 패키지 추가 (선택)

패키지에 포함되지 않은 추가 npm 패키지가 필요한 경우:

```bash
# [인터넷 환경] Linux에서 패키지 수집
cd airgap-package/scripts
./download-packages.sh

# 또는 Windows에서 PowerShell 스크립트 실행
.\01-prepare-airgap.ps1
```

---

## 📞 지원 및 문의

### 설치 실패 시
1. `logs/install-*.log` 확인
2. `checksums.txt`로 파일 무결성 검증
3. 관리자 권한 확인
4. Windows 버전 호환성 확인

### 버전 정보
- **Node.js**: v20.11.0 (LTS)
- **npm**: v10.2.4
- **Nginx**: v1.24.0
- **NSSM**: v2.24
- **Visual C++**: 2022 Redistributable

---

## 🎉 설치 완료!

모든 단계를 완료하셨다면 다음을 실행할 수 있습니다:

```powershell
# Node.js 확인
node --version
npm --version

# Nginx 상태 확인
Get-Service nginx

# 프록시 관리 (기존 스크립트 사용)
.\nginx-proxy-manager.ps1
```

**Happy Coding! 🚀**

---

## 📚 참고 자료

- [Node.js 공식 문서](https://nodejs.org/docs/)
- [Nginx 공식 문서](https://nginx.org/en/docs/)
- [NSSM 사용 가이드](https://nssm.cc/usage)
- [PowerShell 스크립팅](https://docs.microsoft.com/powershell/)

---

## 📄 라이선스

이 패키지에 포함된 각 소프트웨어는 해당 라이선스를 따릅니다:
- Node.js: MIT License
- Nginx: 2-clause BSD License
- NSSM: Public Domain
- Visual C++: Microsoft License

---

**Version**: 1.0.0
**Last Updated**: 2025-10-20
**Package Hash**: SHA256 verified
