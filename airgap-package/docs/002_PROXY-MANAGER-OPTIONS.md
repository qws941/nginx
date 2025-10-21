# 🎯 Nginx 프록시 관리 옵션 가이드

기존 **conf.d 방식**으로 Nginx 설정을 작성하신 경우, 3가지 관리 방법을 선택할 수 있습니다.

---

## 📌 옵션 비교

| 옵션 | 기존 설정 유지 | 웹 UI | Docker 필요 | 권장 대상 |
|------|--------------|-------|------------|----------|
| **옵션 1: PowerShell 스크립트** | ✅ | ❌ | ❌ | PowerShell 익숙한 사용자 |
| **옵션 2: Node.js 웹 UI** | ✅ | ✅ | ❌ | 웹 UI 원하는 사용자 |
| **옵션 3: Zoraxy** | ❌ | ✅ | ❌ | 완전히 새로 시작하는 사용자 |

---

## 옵션 1: PowerShell 스크립트 (기존 방식)

### 특징
- ✅ 기존 conf.d 설정 100% 유지
- ✅ CSV 파일 기반 관리
- ✅ DNS 자동 등록
- ❌ 웹 UI 없음 (PowerShell 직접 실행)

### 사용법

```powershell
# 프록시 추가 (CSV 기반)
cd C:\nginx
.\nginx-proxy-manager.ps1

# CSV 파일 편집
notepad services.csv

# 서비스명,ARecord,IP,Port,UseHTTPS,CustomPath,비고
# 웹서버,web1,192.168.1.10,80,N,,일반 웹서버
# API서버,api1,192.168.1.20,8080,Y,,HTTPS API
```

### 설정 파일 위치
```
C:\nginx\
├── conf\
│   └── conf.d\
│       ├── web1.conf          ← 자동 생성
│       └── api1.conf          ← 자동 생성
└── services.csv               ← 서비스 목록
```

---

## 옵션 2: Node.js 웹 UI ⭐ (권장)

### 특징
- ✅ 기존 conf.d 설정 100% 유지
- ✅ 웹 브라우저에서 관리
- ✅ 실시간 프록시 추가/삭제
- ✅ Nginx 상태 모니터링
- ❌ Node.js 필요

### 설치

```powershell
# 1. Node.js가 설치되어 있는지 확인
node --version
# v20.11.0

# 2. npm 패키지 설치 (에어갭 환경)
cd C:\airgap-package\npm-packages
npm install

# 3. 웹 UI 시작
cd C:\airgap-package\scripts
node nginx-web-ui.js
```

### 웹 UI 접속

```
브라우저에서: http://localhost:8080

╔════════════════════════════════════════╗
║  🚀 Nginx Proxy Manager Web UI        ║
║                                        ║
║  Features:                             ║
║  ✅ Add/Delete Proxy                  ║
║  ✅ Nginx Reload                      ║
║  ✅ Real-time Status                  ║
║  ✅ SSL Badge Display                 ║
╚════════════════════════════════════════╝
```

### 기능

1. **프록시 추가**: ➕ Add Proxy 버튼 클릭
   - Service Name: `웹서버`
   - A Record: `web1`
   - Backend IP: `192.168.1.10`
   - Backend Port: `80`
   - Use HTTPS: 체크박스

2. **프록시 삭제**: Delete 버튼 클릭

3. **Nginx 재로드**: 🔄 Reload Nginx 버튼

4. **상태 확인**: 자동으로 5초마다 Nginx 상태 확인

### 서비스 등록 (자동 시작)

```powershell
# NSSM으로 서비스 등록
cd C:\nginx
.\nssm.exe install nginx-web-ui "C:\Program Files\nodejs\node.exe"
.\nssm.exe set nginx-web-ui AppParameters "C:\airgap-package\scripts\nginx-web-ui.js"
.\nssm.exe set nginx-web-ui AppDirectory "C:\airgap-package\scripts"
.\nssm.exe set nginx-web-ui DisplayName "Nginx Web UI"
.\nssm.exe set nginx-web-ui Start SERVICE_AUTO_START

# 서비스 시작
Start-Service nginx-web-ui

# 상태 확인
Get-Service nginx-web-ui
```

---

## 옵션 3: Zoraxy (완전히 새로 시작)

### 특징
- ✅ 웹 UI 제공
- ✅ 실시간 설정 변경 (재시작 불필요)
- ✅ SSL 인증서 자동 관리
- ❌ **기존 conf.d 설정을 사용하지 않음**
- ❌ Nginx를 대체함 (Zoraxy가 프록시 역할)

### 설치

```powershell
# 1. Zoraxy 실행 파일 복사
Copy-Item "C:\airgap-package\installers\zoraxy_windows_amd64.exe" "C:\zoraxy\"

# 2. Zoraxy 실행
cd C:\zoraxy
.\zoraxy_windows_amd64.exe

# 웹 UI: http://localhost:8000
```

### ⚠️ 주의사항

**Zoraxy를 사용하면 기존 Nginx conf.d 설정을 사용할 수 없습니다!**

Zoraxy는 독립적인 프록시 서버이므로:
- Nginx를 중지해야 함
- 모든 프록시 설정을 Zoraxy UI에서 다시 생성해야 함

### 기존 설정 마이그레이션

```powershell
# 기존 conf.d 설정 백업
Copy-Item -Recurse "C:\nginx\conf\conf.d" "C:\nginx\conf\conf.d.backup"

# Nginx 중지
Stop-Service nginx

# Zoraxy 시작
.\zoraxy_windows_amd64.exe

# Zoraxy 웹 UI에서 수동으로 프록시 추가
# http://localhost:8000
```

---

## 🎯 권장 시나리오

### 시나리오 1: 기존 설정 유지하면서 웹 UI 원함
**→ 옵션 2 (Node.js 웹 UI)** 선택

```powershell
# 설치
cd C:\airgap-package\scripts
node nginx-web-ui.js

# 브라우저: http://localhost:8080
```

**장점**:
- ✅ 기존 conf.d 파일 그대로 사용
- ✅ 웹 UI로 편리하게 관리
- ✅ PowerShell 스크립트와 병행 사용 가능

---

### 시나리오 2: 완전히 새로 시작 + 최신 UI
**→ 옵션 3 (Zoraxy)** 선택

```powershell
# Nginx 중지
Stop-Service nginx

# Zoraxy 시작
C:\zoraxy\zoraxy_windows_amd64.exe

# 브라우저: http://localhost:8000
```

**장점**:
- ✅ 최신 웹 UI (더 직관적)
- ✅ 실시간 설정 변경 (재시작 불필요)
- ✅ SSL 자동 관리

**단점**:
- ❌ 기존 conf.d 설정 사용 불가
- ❌ 모든 프록시를 수동으로 다시 추가해야 함

---

### 시나리오 3: PowerShell에 익숙함
**→ 옵션 1 (PowerShell 스크립트)** 선택

```powershell
cd C:\nginx
.\nginx-proxy-manager.ps1
```

**장점**:
- ✅ CSV 파일로 간단하게 관리
- ✅ 웹 서버 불필요 (리소스 절약)

**단점**:
- ❌ 웹 UI 없음

---

## 📊 성능 비교

| 옵션 | 메모리 사용 | CPU 사용 | 시작 시간 | 설정 방법 |
|------|-----------|---------|----------|----------|
| PowerShell | ~50MB | 낮음 | 즉시 | CSV 편집 |
| Node.js UI | ~100MB | 낮음 | ~2초 | 웹 브라우저 |
| Zoraxy | ~80MB | 낮음 | ~3초 | 웹 브라우저 |

---

## 🔄 옵션 전환 가이드

### PowerShell → Node.js UI

```powershell
# 1. Node.js 설치 확인
node --version

# 2. npm 패키지 설치
cd C:\airgap-package\npm-packages
npm install

# 3. 웹 UI 시작
cd C:\airgap-package\scripts
node nginx-web-ui.js

# 기존 conf.d 설정이 그대로 웹 UI에 표시됨
```

### Node.js UI → Zoraxy

```powershell
# 1. 기존 설정 백업
Copy-Item -Recurse "C:\nginx\conf\conf.d" "C:\backup\"

# 2. Nginx 및 웹 UI 중지
Stop-Service nginx
Stop-Service nginx-web-ui

# 3. Zoraxy 시작
C:\zoraxy\zoraxy_windows_amd64.exe

# 4. Zoraxy UI에서 프록시 수동 추가
# http://localhost:8000
```

---

## 💡 추천 결론

기존 **conf.d 설정을 작성**하셨다면:

### ⭐ 최선의 선택: **옵션 2 (Node.js 웹 UI)**

**이유**:
1. ✅ 기존 설정 100% 활용
2. ✅ 웹 UI로 편리하게 관리
3. ✅ Nginx 그대로 사용 (안정성)
4. ✅ PowerShell 스크립트와 병행 가능

**설치 명령어**:
```powershell
cd C:\airgap-package\npm-packages
npm install express

cd C:\airgap-package\scripts
node nginx-web-ui.js

# 브라우저: http://localhost:8080
```

---

## 📞 문의

각 옵션의 상세한 설정 방법은 다음 파일을 참고하세요:

- **옵션 1**: `scripts/nginx-proxy-manager.ps1` (기존 스크립트)
- **옵션 2**: `scripts/nginx-web-ui.js` (Node.js 웹 UI)
- **옵션 3**: `installers/zoraxy_windows_amd64.exe` (Zoraxy)

**Happy Managing! 🚀**
