# 문제 해결 가이드

## 일반 문제 해결 프로세스

```
1. 증상 확인
   ↓
2. 로그 확인 (Nginx, Windows Event Log)
   ↓
3. 서비스 상태 확인
   ↓
4. 설정 검증
   ↓
5. 네트워크 연결 확인
   ↓
6. 해결 또는 에스컬레이션
```

---

## 서비스 관련 문제

### 문제: Nginx 서비스가 시작되지 않음

**증상**:
```powershell
Start-Service nginx
# 오류: 서비스를 시작할 수 없습니다
```

**진단**:
```powershell
# 1. 설정 파일 검증
C:\nginx\nginx.exe -t

# 2. 이벤트 로그 확인
Get-EventLog -LogName Application -Source "nginx" -Newest 10

# 3. 에러 로그 확인
Get-Content C:\nginx\logs\error.log -Tail 20
```

**해결 방법**:

1. **설정 오류인 경우**:
```powershell
# nginx -t 명령어 출력에서 오류 라인 확인
# 예: nginx: [emerg] invalid number of arguments in "server_name"

# 해당 파일 편집
notepad C:\nginx\conf\conf.d\problematic.conf

# 수정 후 재검증
C:\nginx\nginx.exe -t
```

2. **포트 충돌인 경우**:
```powershell
# 포트 80/443 사용 중인 프로세스 확인
Get-NetTCPConnection -LocalPort 80, 443

# 예: IIS가 실행 중이라면
Stop-Service W3SVC
Set-Service W3SVC -StartupType Disabled
```

3. **권한 문제인 경우**:
```powershell
# 서비스 실행 계정 확인
Get-WmiObject Win32_Service -Filter "Name='nginx'" | Select Name, StartName

# 파일 권한 재설정
icacls "C:\nginx" /grant "nginx-service:(OI)(CI)F" /T
```

---

### 문제: 웹 UI (포트 8080) 접속 불가

**증상**:
- `http://localhost:8080` 접속 시 연결 거부

**진단**:
```powershell
# 1. 서비스 상태 확인
Get-Service nginx-web-ui

# 2. 포트 리스닝 확인
Get-NetTCPConnection -LocalPort 8080

# 3. 프로세스 확인
Get-Process node
```

**해결 방법**:

1. **서비스가 중지된 경우**:
```powershell
Start-Service nginx-web-ui

# 자동 시작 설정
Set-Service nginx-web-ui -StartupType Automatic
```

2. **Node.js 오류인 경우**:
```powershell
# 로그 확인
Get-Content C:\airgap-package\logs\nginx-web-ui.log -Tail 50

# 수동 실행으로 오류 확인
cd C:\airgap-package\scripts
node nginx-web-ui.js
```

3. **방화벽 차단인 경우** (외부 접속 시):
```powershell
# localhost는 방화벽 영향 없음
# 외부 접속을 허용하려면 (권장하지 않음):
New-NetFirewallRule -DisplayName "Nginx Web UI" `
                    -Direction Inbound `
                    -LocalPort 8080 `
                    -Protocol TCP `
                    -Action Allow
```

---

## 프록시 관련 문제

### 문제: 502 Bad Gateway

**증상**:
- 브라우저에서 도메인 접속 시 "502 Bad Gateway" 오류

**진단**:
```powershell
# 1. Nginx 에러 로그 확인
Get-Content C:\nginx\logs\error.log -Tail 50 | Select-String "upstream"

# 예상 오류:
# [error] 1234#5678: *1 connect() failed (10061: No connection could be made because the target machine actively refused it)

# 2. 업스트림 서버 연결 테스트
Test-NetConnection -ComputerName 192.168.1.100 -Port 3000

# 3. 프록시 설정 확인
Get-Content C:\nginx\conf\conf.d\app.company.local.conf
```

**해결 방법**:

1. **업스트림 서버가 중지된 경우**:
```powershell
# 업스트림 서버에서 서비스 시작
ssh admin@192.168.1.100
sudo systemctl start your-app

# 또는 Windows 서버라면
Invoke-Command -ComputerName 192.168.1.100 -ScriptBlock {
    Start-Service YourAppService
}
```

2. **방화벽이 차단하는 경우**:
```powershell
# 업스트림 서버에서 방화벽 규칙 확인
# Linux:
sudo firewall-cmd --list-all

# Windows:
Get-NetFirewallRule | Where-Object {$_.LocalPort -eq 3000}
```

3. **잘못된 업스트림 주소인 경우**:
```powershell
# 설정 파일 수정
notepad C:\nginx\conf\conf.d\app.company.local.conf

# proxy_pass http://192.168.1.100:3000; 확인
# 수정 후 재시작
Restart-Service nginx
```

---

### 문제: 504 Gateway Timeout

**증상**:
- 요청이 오래 걸려 타임아웃 발생

**진단**:
```powershell
# Nginx 타임아웃 설정 확인
Get-Content C:\nginx\conf\conf.d\app.company.local.conf | Select-String "timeout"
```

**해결 방법**:

타임아웃 값 증가:
```nginx
location / {
    proxy_pass http://192.168.1.100:3000;

    # 타임아웃 증가
    proxy_connect_timeout 120s;  # 기본 60s → 120s
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
}
```

```powershell
# 설정 검증 및 재시작
C:\nginx\nginx.exe -t
Restart-Service nginx
```

---

### 문제: 프록시 추가 후 반영 안 됨

**증상**:
- 웹 UI나 PowerShell로 프록시 추가했는데 접속 안 됨

**진단**:
```powershell
# 1. 설정 파일 생성 확인
ls C:\nginx\conf\conf.d\

# 2. nginx.conf에서 include 확인
Get-Content C:\nginx\conf\nginx.conf | Select-String "include.*conf.d"

# 3. Nginx가 설정 리로드했는지 확인
Get-EventLog -LogName Application -Source "nginx" -Newest 5
```

**해결 방법**:

1. **설정 파일이 없는 경우**:
```powershell
# 수동 프록시 추가
.\add-proxy.ps1 -DomainName "app.company.local" `
                -UpstreamHost "192.168.1.100" `
                -UpstreamPort 3000
```

2. **Nginx 재시작 필요**:
```powershell
Restart-Service nginx

# 또는 리로드만 (다운타임 없음, Windows에서는 지원 안 될 수 있음)
C:\nginx\nginx.exe -s reload
```

3. **DNS 레코드 누락**:
```powershell
# AD DNS에 레코드 추가
Add-DnsServerResourceRecordA -Name "app" `
                              -ZoneName "company.local" `
                              -IPv4Address "192.168.1.50"  # Nginx 서버 IP

# 확인
Resolve-DnsName app.company.local
```

---

## SSL/TLS 관련 문제

### 문제: SSL 인증서 오류

**증상**:
- "Your connection is not private" (Chrome)
- "SEC_ERROR_UNKNOWN_ISSUER" (Firefox)

**진단**:
```powershell
# 1. 인증서 파일 존재 확인
Test-Path C:\nginx\ssl\app.crt
Test-Path C:\nginx\ssl\app.key

# 2. 인증서 정보 확인
openssl x509 -in C:\nginx\ssl\app.crt -text -noout

# 3. Nginx 설정 확인
Get-Content C:\nginx\conf\conf.d\app.company.local.conf | Select-String "ssl_certificate"
```

**해결 방법**:

1. **자체 서명 인증서인 경우**:
```powershell
# 브라우저에서 예외 추가 또는
# 내부 CA 인증서 사용 (권장)

# 루트 CA를 클라이언트에 설치
certutil -addstore -enterprise Root C:\nginx\ssl\company-root-ca.crt
```

2. **인증서 만료**:
```powershell
# 만료일 확인
openssl x509 -in C:\nginx\ssl\app.crt -noout -enddate

# 새 인증서 발급 및 교체
# (내부 PKI 팀에 요청)
```

3. **경로 오류**:
```nginx
# 올바른 경로 (Windows 스타일)
ssl_certificate     C:/nginx/ssl/app.crt;
ssl_certificate_key C:/nginx/ssl/app.key;

# 잘못된 경로 (Linux 스타일은 작동 안 함)
# ssl_certificate     /nginx/ssl/app.crt;
```

---

### 문제: Mixed Content 경고

**증상**:
- HTTPS 페이지에서 일부 리소스가 HTTP로 로드

**해결 방법**:

강제 HTTPS 리다이렉트:
```nginx
server {
    listen 80;
    server_name app.company.local;

    # 모든 HTTP 요청을 HTTPS로 리다이렉트
    return 301 https://$server_name$request_uri;
}
```

또는 HSTS 헤더 추가:
```nginx
server {
    listen 443 ssl http2;
    server_name app.company.local;

    # HSTS 헤더
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

---

## Active Directory 관련 문제

### 문제: AD 인증 실패

**증상**:
- 서비스가 "nginx-service" 계정으로 시작 안 됨

**진단**:
```powershell
# 1. 도메인 연결 확인
Test-ComputerSecureChannel -Verbose

# 2. 서비스 계정 확인
Get-ADUser -Identity "nginx-service"

# 3. 서비스 로그온 권한 확인
secedit /export /cfg C:\temp\secpol.cfg
Get-Content C:\temp\secpol.cfg | Select-String "SeServiceLogonRight"
```

**해결 방법**:

1. **도메인 연결 끊김**:
```powershell
# 채널 복구
Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
```

2. **서비스 로그온 권한 누락**:
```powershell
# AD 통합 스크립트 재실행
.\04-setup-ad-integration.ps1 -Force
```

3. **계정 잠금**:
```powershell
# 계정 잠금 해제
Unlock-ADAccount -Identity "nginx-service"

# 비밀번호 재설정
Set-ADAccountPassword -Identity "nginx-service" -Reset
```

---

### 문제: 권한 부족

**증상**:
- "Access Denied" 오류로 설정 파일 수정 불가

**진단**:
```powershell
# 1. 현재 사용자 그룹 확인
whoami /groups

# 2. 파일 권한 확인
icacls C:\nginx\conf\nginx.conf

# 3. AD 그룹 멤버십 확인
Get-ADGroupMember -Identity "NginxAdministrators"
```

**해결 방법**:

1. **그룹 추가 필요**:
```powershell
# AD 관리자에게 요청
# 또는 직접 추가 (Domain Admin 권한 필요)
Add-ADGroupMember -Identity "NginxAdministrators" -Members "your-username"

# 로그아웃 후 다시 로그인 (그룹 토큰 갱신)
```

2. **파일 권한 재설정**:
```powershell
# 관리자 권한 PowerShell에서
icacls "C:\nginx" /grant "NginxAdministrators:(OI)(CI)F" /T
```

---

## 네트워크 관련 문제

### 문제: 외부에서 접속 불가

**증상**:
- localhost에서는 접속되지만 다른 PC에서 접속 안 됨

**진단**:
```powershell
# 1. 방화벽 규칙 확인
Get-NetFirewallRule -DisplayName "Nginx*"

# 2. 포트 리스닝 확인
Get-NetTCPConnection -LocalPort 80, 443

# 3. 원격 연결 테스트 (다른 PC에서)
Test-NetConnection -ComputerName nginx-server -Port 80
```

**해결 방법**:

1. **방화벽 규칙 추가**:
```powershell
New-NetFirewallRule -DisplayName "Nginx HTTP" `
                    -Direction Inbound `
                    -LocalPort 80 `
                    -Protocol TCP `
                    -Action Allow

New-NetFirewallRule -DisplayName "Nginx HTTPS" `
                    -Direction Inbound `
                    -LocalPort 443 `
                    -Protocol TCP `
                    -Action Allow
```

2. **바인딩 주소 확인**:
```nginx
# nginx.conf에서
http {
    server {
        listen 80;  # 모든 인터페이스
        # listen 127.0.0.1:80;  ← 이렇게 되어 있으면 localhost만
    }
}
```

---

### 문제: DNS 해석 실패

**증상**:
- 도메인으로 접속 시 "사이트에 연결할 수 없음"

**진단**:
```powershell
# 1. DNS 해석 확인
Resolve-DnsName app.company.local

# 2. nslookup 테스트
nslookup app.company.local

# 3. DNS 캐시 확인
Get-DnsClientCache | Where-Object {$_.Name -like "*company.local"}
```

**해결 방법**:

1. **DNS 레코드 추가**:
```powershell
# DNS 서버에서 (Domain Controller)
Add-DnsServerResourceRecordA -Name "app" `
                              -ZoneName "company.local" `
                              -IPv4Address "192.168.1.50"

# 확인
Get-DnsServerResourceRecord -ZoneName "company.local" -Name "app"
```

2. **DNS 캐시 초기화** (클라이언트):
```powershell
Clear-DnsClientCache
ipconfig /flushdns
```

3. **임시 hosts 파일 사용**:
```powershell
# C:\Windows\System32\drivers\etc\hosts 편집
notepad C:\Windows\System32\drivers\etc\hosts

# 추가
192.168.1.50  app.company.local
```

---

## 성능 관련 문제

### 문제: 응답 속도 느림

**증상**:
- 페이지 로딩이 느림

**진단**:
```powershell
# 1. CPU/메모리 사용률 확인
Get-Counter '\Process(nginx)\% Processor Time'
Get-Counter '\Process(nginx)\Working Set - Private'

# 2. 연결 수 확인
(Get-NetTCPConnection | Where-Object {$_.OwningProcess -eq (Get-Process nginx).Id}).Count

# 3. 디스크 I/O 확인
Get-Counter '\PhysicalDisk(_Total)\% Disk Time'
```

**해결 방법**:

1. **Worker 프로세스 증가**:
```nginx
# nginx.conf
worker_processes 4;  # CPU 코어 수에 맞춤
```

2. **연결 수 증가**:
```nginx
events {
    worker_connections 2048;  # 기본 1024에서 증가
}
```

3. **캐싱 활성화**:
```nginx
http {
    proxy_cache_path C:/nginx/cache levels=1:2 keys_zone=my_cache:10m max_size=1g inactive=60m;

    server {
        location / {
            proxy_cache my_cache;
            proxy_cache_valid 200 10m;
        }
    }
}
```

---

## 로그 관련 문제

### 문제: 로그 파일이 너무 큼

**증상**:
- `access.log` 파일이 수 GB

**해결 방법**:

로그 로테이션 설정:

```powershell
# 로그 로테이션 스크립트 생성
# C:\scripts\rotate-nginx-logs.ps1

$LogPath = "C:\nginx\logs"
$ArchivePath = "C:\nginx\logs\archive"

# 아카이브 디렉토리 생성
if (!(Test-Path $ArchivePath)) {
    New-Item -Path $ArchivePath -ItemType Directory
}

# 현재 로그 압축
$Date = Get-Date -Format "yyyy-MM-dd"
Compress-Archive -Path "$LogPath\access.log" -DestinationPath "$ArchivePath\access-$Date.zip"
Compress-Archive -Path "$LogPath\error.log" -DestinationPath "$ArchivePath\error-$Date.zip"

# 로그 초기화
Clear-Content "$LogPath\access.log"
Clear-Content "$LogPath\error.log"

# Nginx 리로드 (로그 파일 핸들 재오픈)
Restart-Service nginx

# 30일 이상 된 아카이브 삭제
Get-ChildItem $ArchivePath -Filter "*.zip" | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | Remove-Item
```

작업 스케줄러 등록:
```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\scripts\rotate-nginx-logs.ps1"

$Trigger = New-ScheduledTaskTrigger -Daily -At 1:00AM

Register-ScheduledTask -TaskName "Nginx Log Rotation" `
                       -Action $Action `
                       -Trigger $Trigger `
                       -User "SYSTEM" `
                       -RunLevel Highest
```

---

## 긴급 복구

### 시스템 롤백

설정 오류로 Nginx가 완전히 다운된 경우:

```powershell
# 1. 백업에서 설정 복구
.\05-backup-restore.ps1 -Mode Restore -BackupPath "D:\Backups\nginx\2025-10-20"

# 2. 설정 검증
C:\nginx\nginx.exe -t

# 3. 서비스 재시작
Restart-Service nginx
```

### 강제 재설치

모든 방법이 실패한 경우:

```powershell
# 1. 서비스 중지
Stop-Service nginx, nginx-web-ui

# 2. 기존 설정 백업
Copy-Item -Path "C:\nginx\conf" -Destination "C:\nginx-backup\conf" -Recurse

# 3. Nginx 재설치
cd C:\airgap-package\scripts
.\02-install-airgap.ps1 -Force

# 4. 설정 복원
Copy-Item -Path "C:\nginx-backup\conf\conf.d\*" -Destination "C:\nginx\conf\conf.d\" -Recurse

# 5. 서비스 시작
Start-Service nginx
```

---

## 자주 묻는 질문 (FAQ)

### Q1: Nginx를 다른 포트(예: 8080)로 변경하려면?

**A**:
```nginx
# nginx.conf 수정
http {
    server {
        listen 8080;  # 80 → 8080
        # ...
    }
}
```

```powershell
# 방화벽 규칙 추가
New-NetFirewallRule -DisplayName "Nginx Custom Port" `
                    -Direction Inbound `
                    -LocalPort 8080 `
                    -Protocol TCP `
                    -Action Allow

# Nginx 재시작
Restart-Service nginx
```

### Q2: 프록시 설정을 수동으로 백업하려면?

**A**:
```powershell
# 전체 conf 디렉토리 백업
Copy-Item -Path "C:\nginx\conf" -Destination "D:\Backups\nginx-conf-$(Get-Date -Format 'yyyy-MM-dd')" -Recurse

# 또는 스크립트 사용
.\05-backup-restore.ps1 -Mode Backup -BackupPath "D:\Backups\nginx"
```

### Q3: 업스트림 서버 여러 개를 어떻게 설정하나요?

**A**:
```nginx
upstream app_backend {
    server 192.168.1.100:3000;
    server 192.168.1.101:3000;
    server 192.168.1.102:3000;
}

server {
    location / {
        proxy_pass http://app_backend;
    }
}
```

---

## 에스컬레이션

문제가 해결되지 않을 경우:

1. **로그 수집**:
```powershell
# 진단 정보 수집
.\03-verify-installation.ps1 -Detailed -ExportReport
# → C:\nginx\reports\verification-report.html
```

2. **지원 요청**:
   - 수집된 리포트 첨부
   - 오류 메시지 전체 복사
   - 재현 단계 기술

---

## 참고 문서

- [아키텍처](architecture.md)
- [API 문서](api.md)
- [배포 가이드](deployment.md)
- [Nginx 공식 문서](https://nginx.org/en/docs/)
