# 📋 운영 체크리스트

**시스템**: Nginx + Node.js 에어갭 환경
**패키지 버전**: 1.0.0
**마지막 업데이트**: 2025-10-20

---

## 📅 일일 점검 (Daily Checklist)

### 서비스 상태 확인

```powershell
# 실행 시각: 매일 오전 9시

# 1. Nginx 서비스 상태
Get-Service nginx
# ✅ 예상 결과: Status = Running

# 2. Nginx 웹 UI 서비스 상태
Get-Service nginx-web-ui
# ✅ 예상 결과: Status = Running

# 3. 서비스 자동 시작 설정 확인
Get-Service nginx, nginx-web-ui | Select-Object Name, StartType
# ✅ 예상 결과: StartType = Automatic
```

**체크리스트**:
- [ ] Nginx 서비스 Running
- [ ] Nginx 웹 UI Running
- [ ] 자동 시작 설정 확인

---

### 디스크 공간 확인

```powershell
# 디스크 여유 공간 확인
Get-PSDrive C | Select-Object Used, Free

# 로그 폴더 크기
Get-ChildItem C:\nginx\logs -Recurse | Measure-Object -Property Length -Sum |
    Select-Object @{Name="Size(MB)";Expression={[math]::Round($_.Sum / 1MB, 2)}}
```

**체크리스트**:
- [ ] C 드라이브 여유 공간 > 10GB
- [ ] 로그 폴더 크기 < 1GB

---

### 에러 로그 확인

```powershell
# 최근 에러 로그 확인 (최근 24시간)
Get-Content C:\nginx\logs\error.log -Tail 50 | Where-Object {$_ -match "error"}

# 에러 발생 횟수
(Get-Content C:\nginx\logs\error.log | Select-String "error").Count
```

**체크리스트**:
- [ ] 치명적 에러 없음
- [ ] 에러 발생 횟수 < 10개/일

---

### 웹 UI 접속 테스트

```powershell
# localhost 접속 테스트
Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing | Select-Object StatusCode
# ✅ 예상 결과: StatusCode = 200

# Nginx 설정 테스트
C:\nginx\nginx.exe -t
# ✅ 예상 결과: test is successful
```

**체크리스트**:
- [ ] 웹 UI 접속 가능 (http://localhost:8080)
- [ ] Nginx 설정 구문 오류 없음

---

## 📆 주간 점검 (Weekly Checklist)

### SSL 인증서 확인

```powershell
# 인증서 만료일 확인
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("C:\nginx\conf\ssl\cert.crt")
$cert.NotAfter
$daysLeft = ($cert.NotAfter - (Get-Date)).Days
Write-Host "인증서 만료까지: $daysLeft 일"

# ⚠️ 30일 이내: 갱신 필요
# ✅ 30일 이상: 정상
```

**체크리스트**:
- [ ] SSL 인증서 만료일 확인
- [ ] 만료일 > 30일
- [ ] 인증서 갱신 필요 시 계획 수립

---

### Windows 업데이트

```powershell
# Windows 업데이트 확인
Get-WindowsUpdate -MicrosoftUpdate

# 보류 중인 재부팅 확인
Get-PendingReboot
```

**체크리스트**:
- [ ] Windows 업데이트 확인
- [ ] 중요 업데이트 설치 계획
- [ ] 재부팅 필요 시 점검 시간 계획

---

### 로그 관리

```powershell
# 7일 이상 된 로그 백업 및 삭제
$logPath = "C:\nginx\logs"
$backupPath = "C:\backup\logs"
$date = Get-Date -Format "yyyyMMdd"

# 백업
New-Item -ItemType Directory -Path $backupPath -Force
Get-ChildItem $logPath\*.log |
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} |
    Compress-Archive -DestinationPath "$backupPath\nginx-logs-$date.zip"

# 삭제
Get-ChildItem $logPath\*.log |
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} |
    Remove-Item -Force
```

**체크리스트**:
- [ ] 7일 이상 된 로그 백업
- [ ] 백업 후 로그 삭제
- [ ] 로그 폴더 크기 < 500MB

---

### 설정 백업

```powershell
# Nginx 설정 백업
$backupDate = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "C:\backup\nginx-config-$backupDate"

# 디렉토리 생성
New-Item -ItemType Directory -Path $backupPath -Force

# 설정 파일 복사
Copy-Item -Recurse C:\nginx\conf $backupPath\conf
Copy-Item -Recurse C:\nginx\conf\conf.d $backupPath\conf.d
Copy-Item C:\nginx\services.csv $backupPath\services.csv -ErrorAction SilentlyContinue

# 압축
Compress-Archive -Path $backupPath -DestinationPath "$backupPath.zip"

# 원본 폴더 삭제
Remove-Item -Recurse -Force $backupPath
```

**체크리스트**:
- [ ] Nginx 설정 백업
- [ ] conf.d 폴더 백업
- [ ] services.csv 백업
- [ ] 백업 압축 파일 생성

---

### 프록시 설정 검증

```powershell
# 모든 conf.d 설정 파일 테스트
Get-ChildItem C:\nginx\conf\conf.d\*.conf | ForEach-Object {
    Write-Host "Testing: $($_.Name)"
    C:\nginx\nginx.exe -t -c $_.FullName
}

# 프록시 개수 확인
$proxyCount = (Get-ChildItem C:\nginx\conf\conf.d\*.conf).Count
Write-Host "총 프록시 설정: $proxyCount 개"
```

**체크리스트**:
- [ ] 모든 프록시 설정 구문 오류 없음
- [ ] 프록시 개수 기록 (변경사항 추적)

---

## 🗓️ 월간 점검 (Monthly Checklist)

### 패키지 버전 확인

```powershell
# 현재 설치된 버전
node --version
npm --version
C:\nginx\nginx.exe -v

# 버전 기록
@"
Node.js: $(node --version)
npm: $(npm --version)
Nginx: $(C:\nginx\nginx.exe -v 2>&1)
Date: $(Get-Date -Format 'yyyy-MM-dd')
"@ | Out-File -Append C:\logs\version-history.txt
```

**체크리스트**:
- [ ] Node.js 버전 기록
- [ ] Nginx 버전 기록
- [ ] 업그레이드 필요 여부 확인

---

### 성능 모니터링

```powershell
# CPU 및 메모리 사용량
Get-Process nginx, node | Select-Object Name, CPU,
    @{Name="Memory(MB)";Expression={[math]::Round($_.WorkingSet / 1MB, 2)}}

# 평균 응답 시간 (최근 1시간 로그 분석)
Get-Content C:\nginx\logs\access.log -Tail 1000 |
    Select-String -Pattern "\d+\.\d+$" |
    ForEach-Object { [double]($_.Matches[0].Value) } |
    Measure-Object -Average |
    Select-Object @{Name="AvgResponseTime(s)";Expression={$_.Average}}
```

**체크리스트**:
- [ ] Nginx CPU 사용량 < 50%
- [ ] Nginx 메모리 사용량 < 500MB
- [ ] Node.js 메모리 사용량 < 200MB
- [ ] 평균 응답 시간 < 1초

---

### 보안 점검

```powershell
# 방화벽 규칙 확인
Get-NetFirewallRule | Where-Object {
    $_.DisplayName -like "*Nginx*" -or
    $_.DisplayName -like "*Node*"
} | Select-Object DisplayName, Enabled, Direction, Action

# SSL 설정 확인
Get-Content C:\nginx\conf\nginx.conf | Select-String "ssl"

# 인증서 파일 권한
icacls C:\nginx\conf\ssl\cert.key
```

**체크리스트**:
- [ ] 방화벽 규칙 활성화 확인
- [ ] SSL 설정 검증
- [ ] 인증서 파일 권한 확인 (Administrators만 읽기)

---

### 전체 시스템 검증

```powershell
# 검증 스크립트 실행
cd C:\airgap-package\scripts
.\03-verify-installation.ps1 -Detailed -ExportReport

# 검증 결과 확인
$reportPath = Get-ChildItem C:\airgap-package\logs\verification-*.json |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Get-Content $reportPath.FullName | ConvertFrom-Json | Format-List
```

**체크리스트**:
- [ ] 검증 스크립트 실행
- [ ] 8개 카테고리 모두 통과
- [ ] 검증 보고서 저장

---

## 🚨 긴급 상황 대응

### Nginx 서비스 중단

```powershell
# 1. 서비스 재시작
Restart-Service nginx

# 2. 로그 확인
Get-Content C:\nginx\logs\error.log -Tail 100

# 3. 설정 복원 (백업에서)
$latestBackup = Get-ChildItem C:\backup\nginx-config-*.zip |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Expand-Archive -Path $latestBackup.FullName -DestinationPath "C:\nginx\conf" -Force

# 4. 서비스 재시작
Restart-Service nginx
```

---

### 웹 UI 응답 없음

```powershell
# 1. Node.js 프로세스 확인
Get-Process node -ErrorAction SilentlyContinue

# 2. 포트 사용 확인
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

# 3. 서비스 재시작
Restart-Service nginx-web-ui

# 4. 수동 실행 (테스트)
cd C:\airgap-package\scripts
node nginx-web-ui.js
```

---

### 디스크 공간 부족

```powershell
# 1. 로그 정리
Get-ChildItem C:\nginx\logs\*.log |
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-1)} |
    Remove-Item -Force

# 2. 임시 파일 정리
Remove-Item C:\Windows\Temp\* -Recurse -Force -ErrorAction SilentlyContinue

# 3. 디스크 공간 재확인
Get-PSDrive C
```

---

## 📊 성능 기준

### 정상 범위

| 지표 | 정상 범위 | 경고 | 위험 |
|------|----------|------|------|
| **CPU 사용률** | < 30% | 30-50% | > 50% |
| **메모리 (Nginx)** | < 300MB | 300-500MB | > 500MB |
| **메모리 (Node.js)** | < 150MB | 150-200MB | > 200MB |
| **디스크 여유** | > 20GB | 10-20GB | < 10GB |
| **응답 시간** | < 0.5초 | 0.5-1초 | > 1초 |
| **에러 발생률** | < 0.1% | 0.1-1% | > 1% |

---

## 📞 에스컬레이션

### 연락처

| 역할 | 이름 | 연락처 | 대응 시간 |
|------|------|--------|----------|
| **1차 담당자** | _________ | _________ | 24시간 |
| **2차 담당자** | _________ | _________ | 업무시간 |
| **시스템 관리자** | _________ | _________ | 긴급시 |

### 에스컬레이션 기준

1. **즉시 에스컬레이션**:
   - Nginx 서비스 30분 이상 중단
   - 데이터 손실 위험
   - 보안 침해 의심

2. **1시간 내 에스컬레이션**:
   - 웹 UI 접속 불가
   - 성능 저하 (응답 시간 > 5초)
   - SSL 인증서 만료 임박 (7일 이내)

3. **다음 업무일 에스컬레이션**:
   - 로그 증가 추세
   - 경고 수준 성능 지표
   - 업데이트 필요

---

## 📝 변경 이력

### 변경 로그 템플릿

```
날짜: YYYY-MM-DD
작업자: [이름]
작업 내용: [상세 설명]
변경 파일:
  - [파일 경로]
백업 위치: [백업 파일 경로]
테스트 결과: [성공/실패]
롤백 필요: [예/아니오]

---
```

### 최근 변경 이력

```
날짜: 2025-10-20
작업자: 초기 설치
작업 내용: 에어갭 패키지 초기 설치
변경 파일:
  - 모든 시스템 파일
백업 위치: 해당 없음
테스트 결과: 성공
롤백 필요: 아니오

---
```

---

## ✅ 점검 완료 서명

### 일일 점검

| 날짜 | 점검자 | 이상 여부 | 서명 |
|------|--------|----------|------|
| 2025-01-__ | ______ | 정상 / 이상 | ____ |
| 2025-01-__ | ______ | 정상 / 이상 | ____ |

### 주간 점검

| 주차 | 점검자 | 백업 완료 | 이상 여부 | 서명 |
|------|--------|----------|----------|------|
| 2025-W01 | ______ | ✓ | 정상 / 이상 | ____ |
| 2025-W02 | ______ | ✓ | 정상 / 이상 | ____ |

### 월간 점검

| 월 | 점검자 | 성능 검증 | 보안 검증 | 이상 여부 | 서명 |
|----|--------|----------|----------|----------|------|
| 2025-01 | ______ | ✓ | ✓ | 정상 / 이상 | ____ |

---

**문서 버전**: 1.0
**최종 업데이트**: 2025-10-20
**다음 검토 예정**: 2025-11-20
