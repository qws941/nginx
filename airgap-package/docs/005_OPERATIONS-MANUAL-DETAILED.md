#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    에어갭 환경 Nginx 시스템 기능별 검증 스크립트

.DESCRIPTION
    모든 기능을 상세하게 검증하고 결과를 리포트합니다.
    - AD 연동
    - 서비스 상태
    - 네트워크 접근
    - 프록시 기능
    - 로그 수집
    - 성능 지표

.EXAMPLE
    .\function-validation.ps1
    .\function-validation.ps1 -Detailed
    .\function-validation.ps1 -ExportReport
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Detailed,

    [Parameter()]
    [switch]$ExportReport,

    [Parameter()]
    [string]$ReportPath = "C:\nginx\logs"
)

# 색상 정의
$script:Colors = @{
    Success = "Green"
    Info    = "Cyan"
    Warning = "Yellow"
    Error   = "Red"
}

# 검증 결과 저장
$script:ValidationResults = @{
    Timestamp = Get-Date
    TotalTests = 0
    Passed = 0
    Failed = 0
    Warnings = 0
    Tests = @()
}

#region Helper Functions

function Write-ValidationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "SUCCESS" { $script:Colors.Success }
        "INFO"    { $script:Colors.Info }
        "WARN"    { $script:Colors.Warning }
        "ERROR"   { $script:Colors.Error }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Function {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$TestName,

        [Parameter(Mandatory)]
        [scriptblock]$TestScript,

        [Parameter()]
        [string]$ExpectedResult = "정상",

        [Parameter()]
        [string]$FailureAction = "수동 점검 필요"
    )

    $script:ValidationResults.TotalTests++

    Write-ValidationLog -Level INFO -Message "테스트: $Category - $TestName"

    $result = @{
        Category = $Category
        TestName = $TestName
        StartTime = Get-Date
        Status = "UNKNOWN"
        ActualResult = ""
        ExpectedResult = $ExpectedResult
        ErrorMessage = ""
        FailureAction = $FailureAction
    }

    try {
        $testResult = & $TestScript
        $result.ActualResult = $testResult
        $result.EndTime = Get-Date
        $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds

        if ($testResult -match "성공|정상|OK|PASS") {
            $result.Status = "PASSED"
            $script:ValidationResults.Passed++
            Write-ValidationLog -Level SUCCESS -Message "  ✅ 통과: $testResult"
        }
        elseif ($testResult -match "경고|WARNING") {
            $result.Status = "WARNING"
            $script:ValidationResults.Warnings++
            Write-ValidationLog -Level WARN -Message "  ⚠️  경고: $testResult"
        }
        else {
            $result.Status = "FAILED"
            $script:ValidationResults.Failed++
            Write-ValidationLog -Level ERROR -Message "  ❌ 실패: $testResult"
        }
    }
    catch {
        $result.Status = "FAILED"
        $result.ErrorMessage = $_.Exception.Message
        $result.EndTime = Get-Date
        $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds
        $script:ValidationResults.Failed++
        Write-ValidationLog -Level ERROR -Message "  ❌ 오류: $($_.Exception.Message)"
    }

    $script:ValidationResults.Tests += $result

    if ($Detailed) {
        Write-Host "    예상 결과: $ExpectedResult" -ForegroundColor Gray
        Write-Host "    실제 결과: $($result.ActualResult)" -ForegroundColor Gray
        Write-Host "    소요 시간: $($result.Duration) 초" -ForegroundColor Gray
        Write-Host ""
    }
}

#endregion

#region Banner

Write-Host @"

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        Nginx 에어갭 환경 기능별 검증 스크립트               ║
║                                                            ║
║  버전: 1.0.0                                               ║
║  검증 일시: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

#endregion

#region 1. Active Directory 연동 검증

Write-Host "`n═══ [1/10] Active Directory 연동 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "AD" -TestName "도메인 가입 상태" -TestScript {
    $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
    if ($computerSystem.PartOfDomain) {
        return "정상: 도메인 $($computerSystem.Domain)에 가입됨"
    }
    else {
        return "실패: 도메인 미가입 (워크그룹: $($computerSystem.Workgroup))"
    }
} -ExpectedResult "도메인 가입" -FailureAction "도메인 가입 필요"

Test-Function -Category "AD" -TestName "도메인 컨트롤러 연결" -TestScript {
    try {
        $dc = (Get-ADDomainController -Discover -ErrorAction Stop).HostName
        Test-Connection -ComputerName $dc -Count 1 -Quiet | Out-Null
        return "정상: DC $dc 연결 가능"
    }
    catch {
        return "실패: 도메인 컨트롤러 연결 실패"
    }
} -ExpectedResult "DC 연결" -FailureAction "네트워크 연결 확인"

Test-Function -Category "AD" -TestName "Nginx 관리자 그룹 존재" -TestScript {
    try {
        $group = Get-ADGroup -Identity "NginxAdministrators" -ErrorAction Stop
        $memberCount = (Get-ADGroupMember -Identity $group).Count
        return "정상: 그룹 존재 (멤버 $memberCount 명)"
    }
    catch {
        return "실패: NginxAdministrators 그룹 없음"
    }
} -ExpectedResult "그룹 존재" -FailureAction "AD 그룹 생성 필요"

Test-Function -Category "AD" -TestName "Nginx 운영자 그룹 존재" -TestScript {
    try {
        $group = Get-ADGroup -Identity "NginxOperators" -ErrorAction Stop
        $memberCount = (Get-ADGroupMember -Identity $group).Count
        return "정상: 그룹 존재 (멤버 $memberCount 명)"
    }
    catch {
        return "실패: NginxOperators 그룹 없음"
    }
} -ExpectedResult "그룹 존재" -FailureAction "AD 그룹 생성 필요"

Test-Function -Category "AD" -TestName "서비스 계정 존재" -TestScript {
    try {
        $user = Get-ADUser -Identity "nginx-service" -ErrorAction Stop
        if ($user.Enabled) {
            return "정상: 서비스 계정 활성화됨"
        }
        else {
            return "경고: 서비스 계정 비활성화됨"
        }
    }
    catch {
        return "실패: nginx-service 계정 없음"
    }
} -ExpectedResult "계정 활성화" -FailureAction "서비스 계정 생성 필요"

Test-Function -Category "AD" -TestName "AD 인증 설정 파일" -TestScript {
    if (Test-Path "C:\nginx\ad-config.json") {
        $config = Get-Content "C:\nginx\ad-config.json" | ConvertFrom-Json
        if ($config.url -and $config.baseDN) {
            return "정상: AD 설정 파일 존재 및 유효"
        }
        else {
            return "경고: AD 설정 파일 내용 불완전"
        }
    }
    else {
        return "실패: AD 설정 파일 없음"
    }
} -ExpectedResult "설정 파일 존재" -FailureAction "ad-config.json 생성 필요"

#endregion

#region 2. 서비스 상태 검증

Write-Host "`n═══ [2/10] Windows 서비스 상태 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Service" -TestName "Nginx 서비스 실행" -TestScript {
    $service = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        return "정상: Nginx 서비스 실행 중"
    }
    elseif ($service) {
        return "실패: Nginx 서비스 중지됨 (상태: $($service.Status))"
    }
    else {
        return "실패: Nginx 서비스 미등록"
    }
} -ExpectedResult "Running" -FailureAction "서비스 시작: Start-Service nginx"

Test-Function -Category "Service" -TestName "Nginx 서비스 자동 시작" -TestScript {
    $service = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($service -and $service.StartType -eq "Automatic") {
        return "정상: 자동 시작 설정됨"
    }
    else {
        return "경고: 자동 시작 미설정 (현재: $($service.StartType))"
    }
} -ExpectedResult "Automatic" -FailureAction "Set-Service nginx -StartupType Automatic"

Test-Function -Category "Service" -TestName "웹 UI 서비스 실행" -TestScript {
    $service = Get-Service -Name "nginx-web-ui" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        return "정상: 웹 UI 서비스 실행 중"
    }
    elseif ($service) {
        return "실패: 웹 UI 서비스 중지됨 (상태: $($service.Status))"
    }
    else {
        return "실패: 웹 UI 서비스 미등록"
    }
} -ExpectedResult "Running" -FailureAction "서비스 시작: Start-Service nginx-web-ui"

Test-Function -Category "Service" -TestName "Nginx 프로세스 메모리" -TestScript {
    $process = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($process) {
        $memoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
        if ($memoryMB -lt 500) {
            return "정상: 메모리 사용 ${memoryMB}MB"
        }
        else {
            return "경고: 메모리 사용 ${memoryMB}MB (높음)"
        }
    }
    else {
        return "실패: Nginx 프로세스 없음"
    }
} -ExpectedResult "< 500MB" -FailureAction "메모리 사용량 점검"

Test-Function -Category "Service" -TestName "Node.js 프로세스 메모리" -TestScript {
    $process = Get-Process -Name "node" -ErrorAction SilentlyContinue
    if ($process) {
        $memoryMB = [math]::Round(($process | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 2)
        if ($memoryMB -lt 200) {
            return "정상: 메모리 사용 ${memoryMB}MB"
        }
        else {
            return "경고: 메모리 사용 ${memoryMB}MB (높음)"
        }
    }
    else {
        return "실패: Node.js 프로세스 없음"
    }
} -ExpectedResult "< 200MB" -FailureAction "메모리 사용량 점검"

#endregion

#region 3. 네트워크 접근 제어 검증

Write-Host "`n═══ [3/10] 네트워크 접근 제어 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Network" -TestName "localhost 웹 UI 접속" -TestScript {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8080" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            return "정상: localhost 접속 가능 (HTTP 200)"
        }
        else {
            return "경고: 응답 코드 $($response.StatusCode)"
        }
    }
    catch {
        return "실패: localhost 접속 불가"
    }
} -ExpectedResult "HTTP 200" -FailureAction "웹 UI 서비스 확인"

Test-Function -Category "Network" -TestName "외부 IP 차단 확인" -TestScript {
    $externalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notmatch "^127\."} | Select-Object -First 1).IPAddress
    if ($externalIP) {
        try {
            $response = Invoke-WebRequest -Uri "http://${externalIP}:8080" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            return "실패: 외부 IP($externalIP)에서 접속 가능 (보안 위험!)"
        }
        catch {
            return "정상: 외부 IP($externalIP) 접속 차단됨"
        }
    }
    else {
        return "경고: 외부 IP 확인 불가"
    }
} -ExpectedResult "접속 차단" -FailureAction "방화벽 규칙 확인"

Test-Function -Category "Network" -TestName "포트 80 오픈" -TestScript {
    $listening = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        return "정상: 포트 80 리스닝 중"
    }
    else {
        return "실패: 포트 80 리스닝 안 함"
    }
} -ExpectedResult "리스닝" -FailureAction "Nginx 설정 확인"

Test-Function -Category "Network" -TestName "포트 443 오픈" -TestScript {
    $listening = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        return "정상: 포트 443 리스닝 중"
    }
    else {
        return "경고: 포트 443 리스닝 안 함 (SSL 미설정)"
    }
} -ExpectedResult "리스닝" -FailureAction "SSL 설정 확인"

Test-Function -Category "Network" -TestName "방화벽 규칙 - 웹 UI" -TestScript {
    $rule = Get-NetFirewallRule -DisplayName "Nginx Web UI*" -ErrorAction SilentlyContinue
    if ($rule) {
        $blockRule = $rule | Where-Object {$_.Action -eq "Block" -and $_.DisplayName -like "*External*"}
        if ($blockRule -and $blockRule.Enabled -eq $true) {
            return "정상: 외부 접속 차단 규칙 활성화"
        }
        else {
            return "경고: 차단 규칙 미활성화"
        }
    }
    else {
        return "실패: 방화벽 규칙 없음"
    }
} -ExpectedResult "차단 규칙 활성화" -FailureAction "방화벽 규칙 생성"

#endregion

#region 4. Nginx 설정 검증

Write-Host "`n═══ [4/10] Nginx 설정 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Nginx" -TestName "설정 파일 구문 검사" -TestScript {
    $testResult = & "C:\nginx\nginx.exe" -t 2>&1
    if ($testResult -match "successful") {
        return "정상: 설정 파일 구문 오류 없음"
    }
    else {
        return "실패: 설정 파일 구문 오류 - $testResult"
    }
} -ExpectedResult "구문 오류 없음" -FailureAction "nginx.conf 수정 필요"

Test-Function -Category "Nginx" -TestName "conf.d 디렉토리 존재" -TestScript {
    if (Test-Path "C:\nginx\conf\conf.d") {
        $confCount = (Get-ChildItem "C:\nginx\conf\conf.d\*.conf" -ErrorAction SilentlyContinue).Count
        return "정상: conf.d 디렉토리 존재 ($confCount 개 설정 파일)"
    }
    else {
        return "실패: conf.d 디렉토리 없음"
    }
} -ExpectedResult "디렉토리 존재" -FailureAction "conf.d 디렉토리 생성"

Test-Function -Category "Nginx" -TestName "SSL 설정 확인" -TestScript {
    $nginxConf = Get-Content "C:\nginx\conf\nginx.conf" -Raw
    if ($nginxConf -match "ssl_certificate") {
        return "정상: SSL 설정 포함"
    }
    else {
        return "경고: SSL 설정 없음"
    }
} -ExpectedResult "SSL 설정 포함" -FailureAction "SSL 인증서 설정"

Test-Function -Category "Nginx" -TestName "로그 디렉토리" -TestScript {
    if (Test-Path "C:\nginx\logs") {
        $logSize = [math]::Round((Get-ChildItem "C:\nginx\logs" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($logSize -lt 1000) {
            return "정상: 로그 디렉토리 존재 (${logSize}MB)"
        }
        else {
            return "경고: 로그 크기 ${logSize}MB (정리 필요)"
        }
    }
    else {
        return "실패: 로그 디렉토리 없음"
    }
} -ExpectedResult "디렉토리 존재" -FailureAction "로그 디렉토리 생성"

Test-Function -Category "Nginx" -TestName "에러 로그 확인" -TestScript {
    if (Test-Path "C:\nginx\logs\error.log") {
        $errors = Get-Content "C:\nginx\logs\error.log" -Tail 100 | Select-String "\[error\]|\[crit\]|\[alert\]|\[emerg\]"
        if ($errors.Count -eq 0) {
            return "정상: 최근 에러 로그 없음"
        }
        elseif ($errors.Count -lt 10) {
            return "경고: 최근 에러 $($errors.Count) 건"
        }
        else {
            return "실패: 최근 에러 $($errors.Count) 건 (과다)"
        }
    }
    else {
        return "경고: 에러 로그 파일 없음"
    }
} -ExpectedResult "에러 없음" -FailureAction "에러 로그 분석"

#endregion

#region 5. 프록시 기능 검증

Write-Host "`n═══ [5/10] 프록시 기능 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Proxy" -TestName "프록시 설정 개수" -TestScript {
    $confFiles = Get-ChildItem "C:\nginx\conf\conf.d\*.conf" -ErrorAction SilentlyContinue
    if ($confFiles) {
        return "정상: $($confFiles.Count) 개 프록시 설정"
    }
    else {
        return "경고: 프록시 설정 없음"
    }
} -ExpectedResult "설정 존재" -FailureAction "프록시 설정 추가"

Test-Function -Category "Proxy" -TestName "업스트림 서버 연결" -TestScript {
    $confFiles = Get-ChildItem "C:\nginx\conf\conf.d\*.conf" -ErrorAction SilentlyContinue
    $failedUpstreams = @()

    foreach ($file in $confFiles) {
        $content = Get-Content $file.FullName -Raw
        if ($content -match "proxy_pass\s+http://([^:]+):(\d+)") {
            $host = $Matches[1]
            $port = $Matches[2]

            $connection = Test-NetConnection -ComputerName $host -Port $port -WarningAction SilentlyContinue
            if (-not $connection.TcpTestSucceeded) {
                $failedUpstreams += "${host}:${port}"
            }
        }
    }

    if ($failedUpstreams.Count -eq 0) {
        return "정상: 모든 업스트림 서버 연결 가능"
    }
    else {
        return "경고: 연결 실패 - $($failedUpstreams -join ', ')"
    }
} -ExpectedResult "모두 연결 가능" -FailureAction "업스트림 서버 상태 확인"

#endregion

#region 6. 디스크 및 리소스 검증

Write-Host "`n═══ [6/10] 디스크 및 리소스 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Resource" -TestName "C 드라이브 여유 공간" -TestScript {
    $drive = Get-PSDrive C
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGB -gt 20) {
        return "정상: 여유 공간 ${freeGB}GB"
    }
    elseif ($freeGB -gt 10) {
        return "경고: 여유 공간 ${freeGB}GB (여유 공간 부족)"
    }
    else {
        return "실패: 여유 공간 ${freeGB}GB (위험 수준)"
    }
} -ExpectedResult "> 20GB" -FailureAction "디스크 정리 필요"

Test-Function -Category "Resource" -TestName "CPU 사용률" -TestScript {
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $cpuPercent = [math]::Round($cpu, 2)
    if ($cpuPercent -lt 50) {
        return "정상: CPU ${cpuPercent}%"
    }
    elseif ($cpuPercent -lt 80) {
        return "경고: CPU ${cpuPercent}% (높음)"
    }
    else {
        return "실패: CPU ${cpuPercent}% (과부하)"
    }
} -ExpectedResult "< 50%" -FailureAction "프로세스 점검"

Test-Function -Category "Resource" -TestName "메모리 사용률" -TestScript {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $totalMemory = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemory = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedPercent = [math]::Round((($totalMemory - $freeMemory) / $totalMemory) * 100, 2)

    if ($usedPercent -lt 70) {
        return "정상: 메모리 ${usedPercent}% 사용 중"
    }
    elseif ($usedPercent -lt 85) {
        return "경고: 메모리 ${usedPercent}% 사용 중 (높음)"
    }
    else {
        return "실패: 메모리 ${usedPercent}% 사용 중 (과부하)"
    }
} -ExpectedResult "< 70%" -FailureAction "메모리 증설 고려"

#endregion

#region 7. SSL/TLS 검증

Write-Host "`n═══ [7/10] SSL/TLS 인증서 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "SSL" -TestName "SSL 인증서 파일 존재" -TestScript {
    $certPath = "C:\nginx\conf\ssl\cert.crt"
    $keyPath = "C:\nginx\conf\ssl\cert.key"

    if ((Test-Path $certPath) -and (Test-Path $keyPath)) {
        return "정상: 인증서 및 키 파일 존재"
    }
    elseif (Test-Path $certPath) {
        return "실패: 키 파일 없음"
    }
    elseif (Test-Path $keyPath) {
        return "실패: 인증서 파일 없음"
    }
    else {
        return "실패: 인증서 및 키 파일 모두 없음"
    }
} -ExpectedResult "파일 존재" -FailureAction "SSL 인증서 설치"

Test-Function -Category "SSL" -TestName "인증서 만료일" -TestScript {
    $certPath = "C:\nginx\conf\ssl\cert.crt"
    if (Test-Path $certPath) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
            $daysLeft = ($cert.NotAfter - (Get-Date)).Days

            if ($daysLeft -gt 30) {
                return "정상: 만료까지 ${daysLeft}일 남음"
            }
            elseif ($daysLeft -gt 7) {
                return "경고: 만료까지 ${daysLeft}일 남음 (갱신 필요)"
            }
            else {
                return "실패: 만료까지 ${daysLeft}일 남음 (긴급 갱신 필요)"
            }
        }
        catch {
            return "실패: 인증서 읽기 실패"
        }
    }
    else {
        return "실패: 인증서 파일 없음"
    }
} -ExpectedResult "> 30일" -FailureAction "인증서 갱신"

Test-Function -Category "SSL" -TestName "키 파일 권한" -TestScript {
    $keyPath = "C:\nginx\conf\ssl\cert.key"
    if (Test-Path $keyPath) {
        $acl = Get-Acl $keyPath
        $adminOnly = $acl.Access | Where-Object {$_.IdentityReference -notmatch "Administrators|SYSTEM"}

        if ($adminOnly.Count -eq 0) {
            return "정상: 키 파일 권한 안전 (관리자만 접근)"
        }
        else {
            return "경고: 불필요한 권한 존재 (보안 위험)"
        }
    }
    else {
        return "실패: 키 파일 없음"
    }
} -ExpectedResult "관리자만 접근" -FailureAction "키 파일 권한 수정"

#endregion

#region 8. 로그 수집 및 분석

Write-Host "`n═══ [8/10] 로그 수집 및 분석 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Logging" -TestName "액세스 로그 생성" -TestScript {
    $accessLog = "C:\nginx\logs\access.log"
    if (Test-Path $accessLog) {
        $lastWrite = (Get-Item $accessLog).LastWriteTime
        $hoursSince = ((Get-Date) - $lastWrite).TotalHours

        if ($hoursSince -lt 1) {
            return "정상: 액세스 로그 최근 업데이트 ($(  [math]::Round($hoursSince, 1))시간 전)"
        }
        elseif ($hoursSince -lt 24) {
            return "경고: 액세스 로그 업데이트 $(  [math]::Round($hoursSince, 1))시간 전"
        }
        else {
            return "실패: 액세스 로그 업데이트 $(  [math]::Round($hoursSince, 1))시간 전 (접속 없음)"
        }
    }
    else {
        return "실패: 액세스 로그 파일 없음"
    }
} -ExpectedResult "최근 업데이트" -FailureAction "로그 설정 확인"

Test-Function -Category "Logging" -TestName "로그 로테이션 설정" -TestScript {
    # 간단한 체크: 7일 이상 된 로그 파일 존재 여부
    $oldLogs = Get-ChildItem "C:\nginx\logs\*.log" -ErrorAction SilentlyContinue |
        Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)}

    if ($oldLogs.Count -gt 10) {
        return "경고: 7일 이상 된 로그 $($oldLogs.Count)개 (로테이션 필요)"
    }
    elseif ($oldLogs.Count -gt 0) {
        return "정상: 7일 이상 된 로그 $($oldLogs.Count)개"
    }
    else {
        return "정상: 오래된 로그 없음"
    }
} -ExpectedResult "로그 정리됨" -FailureAction "로그 로테이션 스크립트 실행"

Test-Function -Category "Logging" -TestName "에러 발생률" -TestScript {
    $errorLog = "C:\nginx\logs\error.log"
    if (Test-Path $errorLog) {
        $recentErrors = Get-Content $errorLog -Tail 1000 | Select-String "\[error\]"
        $errorCount = $recentErrors.Count

        if ($errorCount -eq 0) {
            return "정상: 최근 1000줄 에러 없음"
        }
        elseif ($errorCount -lt 10) {
            return "정상: 최근 1000줄 에러 $errorCount 건"
        }
        else {
            return "경고: 최근 1000줄 에러 $errorCount 건 (높음)"
        }
    }
    else {
        return "경고: 에러 로그 파일 없음"
    }
} -ExpectedResult "< 10건" -FailureAction "에러 원인 분석"

#endregion

#region 9. 백업 검증

Write-Host "`n═══ [9/10] 백업 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Backup" -TestName "백업 디렉토리 존재" -TestScript {
    if (Test-Path "C:\backup") {
        return "정상: 백업 디렉토리 존재"
    }
    else {
        return "경고: 백업 디렉토리 없음"
    }
} -ExpectedResult "디렉토리 존재" -FailureAction "백업 디렉토리 생성"

Test-Function -Category "Backup" -TestName "최근 설정 백업" -TestScript {
    $backupFiles = Get-ChildItem "C:\backup\nginx-config-*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($backupFiles) {
        $latestBackup = $backupFiles[0]
        $daysSince = ((Get-Date) - $latestBackup.LastWriteTime).Days

        if ($daysSince -eq 0) {
            return "정상: 오늘 백업 완료"
        }
        elseif ($daysSince -lt 7) {
            return "정상: ${daysSince}일 전 백업"
        }
        else {
            return "경고: ${daysSince}일 전 백업 (백업 필요)"
        }
    }
    else {
        return "실패: 백업 파일 없음"
    }
} -ExpectedResult "< 7일 전" -FailureAction "설정 백업 실행"

#endregion

#region 10. 성능 지표

Write-Host "`n═══ [10/10] 성능 지표 검증 ═══`n" -ForegroundColor Yellow

Test-Function -Category "Performance" -TestName "평균 응답 시간" -TestScript {
    $accessLog = "C:\nginx\logs\access.log"
    if (Test-Path $accessLog) {
        $recentLogs = Get-Content $accessLog -Tail 100
        $responseTimes = $recentLogs | ForEach-Object {
            if ($_ -match "(\d+\.\d+)$") {
                [double]$Matches[1]
            }
        } | Where-Object {$_ -ne $null}

        if ($responseTimes.Count -gt 0) {
            $avgTime = [math]::Round(($responseTimes | Measure-Object -Average).Average, 3)

            if ($avgTime -lt 0.5) {
                return "정상: 평균 응답 ${avgTime}초"
            }
            elseif ($avgTime -lt 1) {
                return "경고: 평균 응답 ${avgTime}초 (느림)"
            }
            else {
                return "실패: 평균 응답 ${avgTime}초 (매우 느림)"
            }
        }
        else {
            return "경고: 응답 시간 데이터 없음"
        }
    }
    else {
        return "경고: 액세스 로그 없음"
    }
} -ExpectedResult "< 0.5초" -FailureAction "성능 최적화 필요"

Test-Function -Category "Performance" -TestName "동시 연결 수" -TestScript {
    $connections = Get-NetTCPConnection -State Established |
        Where-Object {$_.LocalPort -in @(80, 443, 8080)}

    $count = $connections.Count
    if ($count -lt 100) {
        return "정상: 동시 연결 ${count}개"
    }
    elseif ($count -lt 500) {
        return "경고: 동시 연결 ${count}개 (높음)"
    }
    else {
        return "실패: 동시 연결 ${count}개 (과부하)"
    }
} -ExpectedResult "< 100개" -FailureAction "워커 프로세스 증가 고려"

#endregion

#region Summary

Write-Host "`n═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
Write-Host "검증 완료 요약" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$passRate = if ($script:ValidationResults.TotalTests -gt 0) {
    [math]::Round(($script:ValidationResults.Passed / $script:ValidationResults.TotalTests) * 100, 2)
} else { 0 }

Write-Host "총 테스트: $($script:ValidationResults.TotalTests)" -ForegroundColor White
Write-Host "통과: $($script:ValidationResults.Passed)" -ForegroundColor Green
Write-Host "실패: $($script:ValidationResults.Failed)" -ForegroundColor Red
Write-Host "경고: $($script:ValidationResults.Warnings)" -ForegroundColor Yellow
Write-Host "통과율: ${passRate}%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })

# 등급 산정
$grade = if ($passRate -ge 95 -and $script:ValidationResults.Failed -eq 0) {
    "A+"
} elseif ($passRate -ge 90) {
    "A"
} elseif ($passRate -ge 80) {
    "B"
} elseif ($passRate -ge 70) {
    "C"
} else {
    "F"
}

Write-Host "`n종합 등급: $grade" -ForegroundColor $(if ($grade -match "A") { "Green" } elseif ($grade -eq "B") { "Yellow" } else { "Red" })

# 실패한 테스트 상세
if ($script:ValidationResults.Failed -gt 0) {
    Write-Host "`n실패한 테스트:" -ForegroundColor Red
    $script:ValidationResults.Tests | Where-Object {$_.Status -eq "FAILED"} | ForEach-Object {
        Write-Host "  ❌ [$($_.Category)] $($_.TestName)" -ForegroundColor Red
        Write-Host "     조치 필요: $($_.FailureAction)" -ForegroundColor Yellow
    }
}

# 경고 테스트 상세
if ($script:ValidationResults.Warnings -gt 0) {
    Write-Host "`n경고 테스트:" -ForegroundColor Yellow
    $script:ValidationResults.Tests | Where-Object {$_.Status -eq "WARNING"} | ForEach-Object {
        Write-Host "  ⚠️  [$($_.Category)] $($_.TestName)" -ForegroundColor Yellow
        Write-Host "     권장 조치: $($_.FailureAction)" -ForegroundColor Gray
    }
}

#endregion

#region Export Report

if ($ExportReport) {
    $reportFile = Join-Path $ReportPath "validation-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:ValidationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportFile -Encoding UTF8
    Write-ValidationLog -Level SUCCESS -Message "검증 보고서 저장: $reportFile"
}

#endregion

# Exit code
if ($script:ValidationResults.Failed -gt 0) {
    exit 1
} elseif ($script:ValidationResults.Warnings -gt 0) {
    exit 2
} else {
    exit 0
}
