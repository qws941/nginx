# 배포 가이드

## 배포 개요

Windows 에어갭 환경에서 Nginx 리버스 프록시를 완전 오프라인으로 설치하는 전체 프로세스입니다.

---

## 사전 준비

### 시스템 요구사항

| 항목 | 요구사항 |
|------|----------|
| **OS** | Windows Server 2016/2019/2022 |
| **CPU** | 2 Core 이상 (4 Core 권장) |
| **RAM** | 4GB 이상 (8GB 권장) |
| **디스크** | 10GB 여유 공간 |
| **네트워크** | 에어갭 환경 (오프라인) |
| **도메인** | Active Directory 가입 필수 |
| **권한** | 로컬 관리자 권한 |

### Active Directory 사전 설정

**1. 보안 그룹 생성**

```powershell
# Domain Controller에서 실행
New-ADGroup -Name "NginxAdministrators" `
            -GroupScope Global `
            -GroupCategory Security `
            -Description "Nginx 전체 관리 권한"

New-ADGroup -Name "NginxOperators" `
            -GroupScope Global `
            -GroupCategory Security `
            -Description "Nginx 운영 권한 (읽기 전용)"
```

**2. 서비스 계정 생성**

```powershell
New-ADUser -Name "nginx-service" `
           -SamAccountName "nginx-service" `
           -UserPrincipalName "nginx-service@company.local" `
           -AccountPassword (ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force) `
           -Enabled $true `
           -PasswordNeverExpires $true `
           -CannotChangePassword $true `
           -Description "Nginx 서비스 실행 계정"
```

**3. 사용자 권한 할당**

```powershell
# 관리자 추가
Add-ADGroupMember -Identity "NginxAdministrators" -Members "domain-admin-user"

# 운영자 추가
Add-ADGroupMember -Identity "NginxOperators" -Members "operator-user1", "operator-user2"
```

---

## 1단계: 패키지 준비 (인터넷 연결 환경)

### 1.1 패키지 다운로드

```powershell
# Git 클론
git clone https://github.com/your-org/nginx-airgap-package.git
cd nginx-airgap-package

# 준비 스크립트 실행
cd scripts
.\01-prepare-airgap.ps1
```

**스크립트 동작**:
1. Node.js v20.11.0 다운로드
2. Nginx 1.24.0 다운로드
3. NSSM 2.24 다운로드
4. Visual C++ Redistributable 다운로드
5. Zoraxy 다운로드
6. NPM 패키지 오프라인 캐시 생성
7. SHA256 체크섬 생성

### 1.2 패키지 검증

```powershell
# 체크섬 검증
.\06-validate-enhanced-package.ps1

# 예상 출력:
# ✓ 모든 파일 존재 확인 완료
# ✓ 체크섬 검증 완료
# ✓ 패키지 준비 완료
```

### 1.3 USB 전송

```powershell
# 전체 패키지를 USB로 복사
Copy-Item -Path "airgap-package" -Destination "E:\" -Recurse
```

---

## 2단계: 설치 (에어갭 환경)

### 2.1 패키지 전송

USB를 에어갭 Windows Server에 연결하고 패키지를 복사합니다.

```powershell
# C 드라이브로 복사
Copy-Item -Path "E:\airgap-package" -Destination "C:\" -Recurse
cd C:\airgap-package\scripts
```

### 2.2 설치 실행

```powershell
# 관리자 권한으로 PowerShell 실행
# 실행 정책 변경 (필요시)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 설치 스크립트 실행
.\02-install-airgap.ps1
```

**설치 프로세스**:
1. ✓ Visual C++ Redistributable 설치
2. ✓ Node.js v20.11.0 설치
3. ✓ Nginx 압축 해제 → `C:\nginx`
4. ✓ NSSM 압축 해제 → `C:\nssm`
5. ✓ NPM 패키지 설치 (오프라인 캐시)
6. ✓ Nginx 기본 설정 생성
7. ✓ Windows 서비스 등록 (nginx, nginx-web-ui)
8. ✓ 방화벽 규칙 추가
9. ✓ 파일 권한 설정

### 2.3 서비스 시작

```powershell
# 서비스 시작
Start-Service nginx
Start-Service nginx-web-ui

# 상태 확인
Get-Service nginx, nginx-web-ui
```

---

## 3단계: 검증

### 3.1 자동 검증

```powershell
.\03-verify-installation.ps1 -Detailed -ExportReport
```

**검증 항목 (37개 테스트)**:
- ✓ Active Directory 연동 (6개)
- ✓ Windows 서비스 상태 (5개)
- ✓ 네트워크 접근 제어 (5개)
- ✓ Nginx 설정 (5개)
- ✓ 프록시 기능 (2개)
- ✓ 디스크 및 리소스 (3개)
- ✓ SSL/TLS 인증서 (3개)
- ✓ 로그 수집 (3개)
- ✓ 백업 (2개)
- ✓ 성능 지표 (2개)

### 3.2 수동 검증

**Nginx 상태 확인**:
```powershell
# 프로세스 확인
Get-Process nginx

# 포트 리스닝 확인
Get-NetTCPConnection -LocalPort 80, 443
```

**웹 UI 접속**:
```powershell
# 브라우저에서 접속
Start-Process "http://localhost:8080"

# 또는 curl로 테스트
Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing
```

**Nginx 설정 검증**:
```powershell
C:\nginx\nginx.exe -t

# 예상 출력:
# nginx: the configuration file C:\nginx/conf/nginx.conf syntax is ok
# nginx: configuration file C:\nginx/conf/nginx.conf test is successful
```

---

## 4단계: 프록시 설정

### 4.1 첫 번째 프록시 추가

**옵션 1: 웹 UI (추천)**

1. 브라우저에서 `http://localhost:8080` 접속
2. "프록시 추가" 버튼 클릭
3. 정보 입력:
   - 도메인: `app.company.local`
   - 업스트림 호스트: `192.168.1.100`
   - 업스트림 포트: `3000`
   - SSL 활성화: ☑
4. "저장" 클릭 → Nginx 자동 재시작

**옵션 2: PowerShell 스크립트**

```powershell
.\add-proxy.ps1 -DomainName "app.company.local" `
                -UpstreamHost "192.168.1.100" `
                -UpstreamPort 3000 `
                -EnableSSL `
                -SSLCertPath "C:\nginx\ssl\app.crt" `
                -SSLKeyPath "C:\nginx\ssl\app.key"
```

**옵션 3: CSV 일괄 추가**

```powershell
# configs/services.csv 편집
# domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path
# app.company.local,192.168.1.100,3000,true,C:\nginx\ssl\app.crt,C:\nginx\ssl\app.key

.\import-proxies.ps1 -CSVPath "..\configs\services.csv"
```

### 4.2 프록시 테스트

```powershell
# DNS 레코드 확인 (AD DNS에 등록 필요)
Resolve-DnsName app.company.local

# HTTP 테스트
Invoke-WebRequest -Uri "http://app.company.local" -UseBasicParsing

# HTTPS 테스트
Invoke-WebRequest -Uri "https://app.company.local" -UseBasicParsing
```

---

## 5단계: Active Directory 통합

### 5.1 서비스 계정 설정

```powershell
# Nginx 서비스 계정 변경
.\04-setup-ad-integration.ps1
```

**스크립트 동작**:
1. `nginx-service` 계정으로 서비스 실행 변경
2. 로컬 권한 부여 (SeServiceLogonRight)
3. 파일 시스템 권한 설정
4. 서비스 재시작

### 5.2 파일 권한 설정

```powershell
# Administrators 그룹에 전체 권한
icacls "C:\nginx" /grant "NginxAdministrators:(OI)(CI)F" /T

# Operators 그룹에 읽기 권한
icacls "C:\nginx" /grant "NginxOperators:(OI)(CI)RX" /T

# SSL 디렉토리는 Admins만
icacls "C:\nginx\ssl" /inheritance:r
icacls "C:\nginx\ssl" /grant "NginxAdministrators:(OI)(CI)F"
```

---

## 6단계: 백업 설정

### 6.1 백업 스크립트 설정

```powershell
.\05-backup-restore.ps1 -Mode Backup -BackupPath "D:\Backups\nginx"
```

**백업 항목**:
- `C:\nginx\conf\` (전체 설정)
- `C:\nginx\ssl\` (SSL 인증서)
- 서비스 설정 (레지스트리 내보내기)

### 6.2 자동 백업 스케줄

```powershell
# 작업 스케줄러 등록 (매일 02:00)
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\airgap-package\scripts\05-backup-restore.ps1 -Mode Backup -BackupPath D:\Backups\nginx"

$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "Nginx Daily Backup" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -Principal $Principal `
                       -Description "Nginx 설정 및 SSL 인증서 백업"
```

---

## 7단계: 모니터링 설정

### 7.1 로그 확인

```powershell
# 접속 로그
Get-Content C:\nginx\logs\access.log -Tail 50 -Wait

# 에러 로그
Get-Content C:\nginx\logs\error.log -Tail 50 -Wait
```

### 7.2 성능 카운터

```powershell
# CPU 사용률
Get-Counter '\Process(nginx)\% Processor Time' -Continuous

# 메모리 사용량
Get-Counter '\Process(nginx)\Working Set - Private' -Continuous

# 네트워크 연결 수
Get-NetTCPConnection -OwningProcess (Get-Process nginx).Id | Measure-Object
```

---

## 고급 설정

### SSL/TLS 인증서 설정

**자체 서명 인증서 생성**:
```powershell
# OpenSSL (별도 설치 필요) 또는 PowerShell 스크립트 사용
$cert = New-SelfSignedCertificate -DnsName "app.company.local" `
                                   -CertStoreLocation "Cert:\LocalMachine\My" `
                                   -KeyLength 2048 `
                                   -NotAfter (Get-Date).AddYears(2)

# PEM 형식 내보내기
$certPath = "C:\nginx\ssl\app.crt"
$keyPath = "C:\nginx\ssl\app.key"

Export-Certificate -Cert $cert -FilePath $certPath -Type CERT
# 키 내보내기 (추가 스크립트 필요)
```

**내부 CA 인증서 사용** (권장):
```powershell
# AD CS에서 인증서 요청
# 또는 내부 PKI 팀에서 발급받은 인증서 사용
Copy-Item "\\fileserver\certs\app.company.local.crt" -Destination "C:\nginx\ssl\"
Copy-Item "\\fileserver\certs\app.company.local.key" -Destination "C:\nginx\ssl\"
```

### 로드 밸런싱

여러 업스트림 서버가 있을 경우:

**nginx.conf 수정**:
```nginx
upstream app_backend {
    least_conn;  # 연결 수 기반 로드 밸런싱
    server 192.168.1.100:3000 weight=3;
    server 192.168.1.101:3000 weight=2;
    server 192.168.1.102:3000 backup;
}

server {
    listen 443 ssl http2;
    server_name app.company.local;

    location / {
        proxy_pass http://app_backend;
        # ... 프록시 설정 ...
    }
}
```

### 헬스 체크

```nginx
upstream app_backend {
    server 192.168.1.100:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.101:3000 max_fails=3 fail_timeout=30s;
}
```

---

## 문제 해결

### 설치 실패

```powershell
# 로그 확인
Get-Content C:\airgap-package\logs\install-*.log

# 수동 재시도
.\02-install-airgap.ps1 -Verbose
```

### 서비스 시작 실패

```powershell
# 이벤트 로그 확인
Get-EventLog -LogName Application -Source "nginx" -Newest 10

# 수동 시작
C:\nginx\nginx.exe -t  # 설정 검증
C:\nginx\nginx.exe     # 수동 시작
```

### 권한 오류

```powershell
# 서비스 계정 권한 재설정
.\04-setup-ad-integration.ps1 -Force
```

---

## 롤백

설치를 롤백해야 할 경우:

```powershell
# 서비스 중지 및 삭제
Stop-Service nginx, nginx-web-ui
C:\nssm\nssm.exe remove nginx confirm
C:\nssm\nssm.exe remove nginx-web-ui confirm

# 파일 삭제
Remove-Item -Path "C:\nginx" -Recurse -Force
Remove-Item -Path "C:\nssm" -Recurse -Force
Remove-Item -Path "C:\Program Files\nodejs" -Recurse -Force

# 방화벽 규칙 삭제
Remove-NetFirewallRule -DisplayName "Nginx HTTP"
Remove-NetFirewallRule -DisplayName "Nginx HTTPS"
```

---

## 참고 문서

- [아키텍처](architecture.md)
- [API 문서](api.md)
- [문제 해결](troubleshooting.md)
- [상세 설치 가이드](../airgap-package/reverse_proxy/001_README.md)
