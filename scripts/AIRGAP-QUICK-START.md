# 🚀 에어갭 환경 빠른 시작 가이드

## 📌 개요

이 패키지는 **인터넷 연결이 없는 격리된 환경(Air-Gap)**에서 Node.js + Nginx 리버스 프록시 시스템을 설치하기 위한 통합 솔루션입니다.

---

## ⚡ 빠른 설치 (3단계)

### 1️⃣ 인터넷 환경에서 패키지 준비

```powershell
# 관리자 PowerShell 실행
cd scripts
.\01-prepare-airgap.ps1

# 대기 시간: 약 5-10분 (네트워크 속도에 따라)
# 패키지 크기: 약 2-3GB
```

**준비되는 항목:**
- ✅ Node.js v20.11.0 설치 파일
- ✅ Nginx v1.24.0 웹서버
- ✅ NSSM v2.24 서비스 관리자
- ✅ Visual C++ 재배포 패키지
- ✅ npm 패키지 (Express, PM2 등)

---

### 2️⃣ 에어갭 서버로 전송

```bash
# USB 드라이브 또는 내부 네트워크로 전송
전체 'airgap-package' 폴더를 복사
```

**전송 전 체크리스트:**
- [ ] 바이러스 검사 완료
- [ ] checksums.txt 파일 포함 확인
- [ ] 전체 폴더 크기 확인 (약 2-3GB)

---

### 3️⃣ 에어갭 서버에서 설치

```powershell
# 에어갭 서버에서 관리자 PowerShell 실행
cd airgap-package\scripts
.\02-install-airgap.ps1

# YES 입력하여 설치 시작
# 대기 시간: 약 5-10분
```

**설치되는 구성요소:**
1. Visual C++ 재배포 패키지
2. Node.js (자동 경로 설정)
3. npm 패키지 (오프라인 저장소)
4. Nginx 웹서버
5. NSSM 서비스 관리자
6. DNS 서버 (선택)
7. 방화벽 규칙

---

## 🔍 설치 검증

```powershell
# 설치 후 검증
.\03-verify-installation.ps1

# 상세 모드
.\03-verify-installation.ps1 -Detailed

# 보고서 내보내기
.\03-verify-installation.ps1 -ExportReport
```

**검증 항목:**
- ✓ Node.js 및 npm 버전
- ✓ Nginx 설정 구문
- ✓ NSSM 서비스 등록
- ✓ DNS 서버 상태
- ✓ 방화벽 규칙
- ✓ SSL 인증서
- ✓ 환경변수
- ✓ 포트 가용성

---

## 🔧 설치 후 작업

### 1. PowerShell 재시작
```powershell
# 환경변수 적용을 위해 필수
exit
# 새 PowerShell 창을 관리자 권한으로 실행
```

### 2. Node.js 및 npm 확인
```powershell
node --version
# v20.11.0

npm --version
# 10.2.4
```

### 3. Nginx 서비스 등록
```powershell
cd C:\nginx
.\nssm.exe install nginx "C:\nginx\nginx.exe"
.\nssm.exe set nginx AppDirectory "C:\nginx"
.\nssm.exe set nginx DisplayName "Nginx Reverse Proxy"
.\nssm.exe set nginx Start SERVICE_AUTO_START

# 서비스 시작
Start-Service nginx

# 상태 확인
Get-Service nginx
```

### 4. SSL 인증서 설치 (필수)
```powershell
# C:\nginx\conf\ssl\ 폴더에 인증서 복사
# 필요한 파일:
#   - cert.crt (또는 cert.pem)
#   - cert.key

Copy-Item "D:\ssl\cert.crt" "C:\nginx\conf\ssl\"
Copy-Item "D:\ssl\cert.key" "C:\nginx\conf\ssl\"
```

### 5. 프록시 서비스 관리
```powershell
# Nginx 프록시 관리 스크립트 실행
cd airgap-package\scripts
.\nginx-proxy-manager.ps1
```

---

## 🎯 선택적 설치 옵션

### DNS 서버 제외
```powershell
.\02-install-airgap.ps1 -SkipDNS
```

### 방화벽 규칙 제외
```powershell
.\02-install-airgap.ps1 -SkipFirewall
```

### Node.js 제외 (Nginx만 설치)
```powershell
.\02-install-airgap.ps1 -SkipNodeJS
```

### 복합 옵션
```powershell
.\02-install-airgap.ps1 -SkipDNS -SkipFirewall -Force
```

---

## 📊 npm 패키지 관리

### 포함된 npm 패키지
```
express@4.18.2       - 웹 프레임워크
pm2@5.3.0            - 프로세스 관리자
dotenv@16.3.1        - 환경변수 관리
cors@2.8.5           - CORS 미들웨어
body-parser@1.20.2   - Body 파싱
helmet@7.1.0         - 보안 헤더
```

### 추가 패키지 설치 (오프라인)
```powershell
# 글로벌 설치
npm install -g <package-name>

# 로컬 설치
cd C:\projects\myapp
npm install <package-name>
```

---

## 🔒 보안 권장사항

### 1. 파일 무결성 검증
```powershell
# checksums.txt 파일로 검증
$checksumFile = "airgap-package\checksums.txt"
Get-Content $checksumFile
```

### 2. 바이러스 검사
```powershell
# Windows Defender 스캔
Start-MpScan -ScanType FullScan -ScanPath "D:\airgap-package"
```

### 3. 접근 통제
```powershell
# 패키지 폴더 권한 설정
icacls "airgap-package" /grant "Administrators:F" /T
icacls "airgap-package" /remove "Users" /T
```

### 4. 감사 로그
```powershell
# 설치 로그 확인
Get-Content "airgap-package\logs\install-*.log"
```

---

## ⚠️ 문제 해결

### Node.js 명령어를 찾을 수 없음
```powershell
# 환경변수 수동 설정
$env:Path += ";C:\Program Files\nodejs"
[Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")

# PowerShell 재시작
```

### Nginx 서비스 시작 실패
```powershell
# 로그 확인
Get-Content "C:\nginx\logs\error.log" -Tail 20

# 설정 파일 테스트
C:\nginx\nginx.exe -t

# 포트 충돌 확인
Get-NetTCPConnection -LocalPort 80,443
```

### SSL 인증서 오류
```powershell
# 인증서 파일 권한 확인
icacls "C:\nginx\conf\ssl\cert.key"

# 올바른 형식 확인
# PEM 형식만 지원 (-----BEGIN CERTIFICATE-----)
```

### npm 패키지 설치 실패
```powershell
# 캐시 정리
npm cache clean --force

# npm 글로벌 경로 재설정
npm config set prefix "C:\nodejs-global"
```

---

## 📁 디렉토리 구조

```
airgap-package/
├── installers/                     # 설치 파일
│   ├── node-v20.11.0-x64.msi      # Node.js
│   ├── nginx-1.24.0.zip           # Nginx
│   ├── nssm-2.24.zip              # NSSM
│   └── vcredist_x64.exe           # Visual C++
├── npm-packages/                   # npm 오프라인 저장소
│   ├── node_modules.tar.gz        # 압축된 패키지
│   ├── package.json
│   └── package-lock.json
├── scripts/                        # 설치 스크립트
│   ├── 01-prepare-airgap.ps1      # 패키지 준비
│   ├── 02-install-airgap.ps1      # 통합 설치
│   ├── 03-verify-installation.ps1  # 검증
│   └── nginx-proxy-manager.ps1    # 프록시 관리
├── ssl/                            # SSL 인증서 (수동 추가)
│   ├── cert.crt
│   └── cert.key
├── configs/                        # 설정 파일 템플릿
│   ├── .env.example
│   └── services.csv.example
├── logs/                           # 로그 파일
│   ├── install-*.log
│   └── verification-*.json
├── checksums.txt                   # 파일 무결성 체크섬
└── PACKAGE-INFO.txt                # 패키지 정보
```

---

## 📞 지원 및 문의

### 로그 파일 위치
```
- 설치 로그: airgap-package\logs\install-*.log
- Nginx 로그: C:\nginx\logs\error.log
- Nginx 액세스: C:\nginx\logs\access.log
- 검증 보고서: airgap-package\logs\verification-*.json
```

### 시스템 요구사항
```
운영체제: Windows Server 2016/2019/2022
PowerShell: 5.1 이상
디스크: 최소 10GB 여유 공간
메모리: 최소 4GB RAM
권한: 관리자 권한 필수
```

### 버전 정보
```
Node.js: v20.11.0 (LTS)
Nginx: v1.24.0
NSSM: v2.24
npm: v10.2.4
```

---

## 🎓 추가 학습 자료

### Node.js 애플리케이션 예제
```javascript
// C:\projects\myapp\server.js
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from Air-Gap Environment!');
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
```

### Nginx 프록시 설정 예제
```nginx
# C:\nginx\conf\conf.d\myapp.conf
server {
    listen 443 ssl;
    server_name myapp.example.com;

    ssl_certificate ssl/cert.crt;
    ssl_certificate_key ssl/cert.key;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### PM2로 Node.js 앱 관리
```powershell
# PM2 전역 설치
npm install -g pm2

# 앱 시작
pm2 start server.js --name "myapp"

# 앱 상태 확인
pm2 list

# 앱 로그 보기
pm2 logs myapp

# 앱 재시작
pm2 restart myapp

# 서버 재부팅 시 자동 시작
pm2 startup
pm2 save
```

---

## ✅ 체크리스트

### 준비 단계
- [ ] 인터넷 환경에서 01-prepare-airgap.ps1 실행
- [ ] 패키지 크기 확인 (약 2-3GB)
- [ ] checksums.txt 파일 확인
- [ ] 바이러스 검사 완료

### 전송 단계
- [ ] USB 또는 네트워크로 전송
- [ ] 파일 무결성 확인
- [ ] 에어갭 서버 접근 권한 확인

### 설치 단계
- [ ] 관리자 PowerShell 실행
- [ ] 02-install-airgap.ps1 실행
- [ ] 설치 로그 확인
- [ ] PowerShell 재시작

### 검증 단계
- [ ] 03-verify-installation.ps1 실행
- [ ] 모든 테스트 통과 확인
- [ ] SSL 인증서 설치
- [ ] Nginx 서비스 등록 및 시작

### 운영 단계
- [ ] nginx-proxy-manager.ps1로 서비스 추가
- [ ] DNS 레코드 설정
- [ ] 방화벽 규칙 확인
- [ ] 프록시 연결 테스트

---

## 🎉 설치 완료!

모든 단계를 완료하셨다면 이제 에어갭 환경에서 Node.js와 Nginx 리버스 프록시 시스템을 사용할 수 있습니다.

**다음 단계:**
1. `nginx-proxy-manager.ps1`로 프록시 서비스 관리
2. Node.js 애플리케이션 개발 및 배포
3. PM2로 프로세스 관리
4. 모니터링 및 로그 관리

**Happy Coding! 🚀**
