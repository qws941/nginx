# 에어갭 환경 설치 가이드

## 📦 패키지 구성

```
airgap-package/
├── installers/                    # 설치 파일
│   ├── node-v20.11.0-x64.msi     # Node.js 설치 파일
│   ├── nginx-1.24.0.zip          # Nginx 압축 파일
│   ├── nssm-2.24.zip             # NSSM (서비스 관리)
│   └── vcredist_x64.exe          # Visual C++ 재배포 패키지
├── npm-packages/                  # npm 패키지 오프라인 저장소
│   └── *.tgz                     # 압축된 npm 패키지들
├── scripts/                       # 설치 스크립트
│   ├── 01-prepare-airgap.ps1     # [인터넷 환경] 패키지 수집
│   ├── 02-install-airgap.ps1     # [에어갭 환경] 통합 설치
│   ├── 03-verify-installation.ps1 # 설치 검증
│   └── nginx-proxy-manager.ps1   # 기존 Nginx 관리 스크립트
├── ssl/                           # SSL 인증서 (선택)
│   ├── cert.crt
│   └── cert.key
├── configs/                       # 설정 파일 템플릿
│   ├── .env.example
│   └── services.csv.example
└── checksums.txt                  # 파일 무결성 검증

```

## 🔄 설치 프로세스

### Step 1: 인터넷 환경에서 패키지 수집
```powershell
# 관리자 PowerShell 실행
cd airgap-package/scripts
.\01-prepare-airgap.ps1
```

### Step 2: USB/네트워크로 에어갭 서버에 전송
```
전체 airgap-package 폴더를 복사
```

### Step 3: 에어갭 환경에서 설치
```powershell
# 에어갭 서버에서 관리자 PowerShell 실행
cd airgap-package/scripts
.\02-install-airgap.ps1
```

### Step 4: 설치 검증
```powershell
.\03-verify-installation.ps1
```

## 📋 사전 요구사항

### 인터넷 환경 (패키지 수집용)
- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+
- 관리자 권한
- 인터넷 연결

### 에어갭 환경 (설치 대상)
- Windows Server 2016/2019/2022
- PowerShell 5.1+
- 관리자 권한
- 최소 10GB 여유 공간

## 🔒 보안 고려사항

1. **파일 무결성**: checksums.txt로 검증
2. **디지털 서명**: 가능한 경우 서명된 파일 사용
3. **바이러스 검사**: 패키지 전송 전 검사 수행
4. **접근 통제**: 패키지 전송 경로 통제

## 📞 문제 해결

### 설치 실패 시
1. `logs/install-*.log` 확인
2. `checksums.txt` 무결성 검증
3. 관리자 권한 확인
4. Windows 버전 호환성 확인
