#Requires -RunAsAdministrator
<#
.SYNOPSIS
    nginx-web-ui-enhanced.js 기능 테스트 스크립트

.DESCRIPTION
    Web UI의 모든 기능을 자동으로 테스트하고 검증합니다.

    테스트 항목:
    - API 엔드포인트 (15개)
    - localhost 바인딩 보안
    - 로깅 기능
    - 에러 처리
    - 백업 기능
    - 입력 검증
    - 서비스 통합

.EXAMPLE
    .\test-nginx-web-ui.ps1
    .\test-nginx-web-ui.ps1 -Detailed
    .\test-nginx-web-ui.ps1 -ExportReport
#>

param(
    [string]$WebUIUrl = "http://127.0.0.1:8080",
    [string]$NginxPath = "C:\nginx",
    [switch]$Detailed,
    [switch]$ExportReport
)

#region Configuration

$Script:Config = @{
    WebUIUrl = $WebUIUrl
    NginxPath = $NginxPath
    LogPath = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
    TestDataPath = Join-Path $PSScriptRoot "test-data"
}

$Script:TestResults = @{
    Timestamp = Get-Date
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    Tests = @()
}

#endregion

#region Helper Functions

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [string]$Details = ""
    )

    $Script:TestResults.TotalTests++

    if ($Passed) {
        $Script:TestResults.PassedTests++
        $status = "PASS"
        $color = "Green"
        $icon = "✓"
    } else {
        $Script:TestResults.FailedTests++
        $status = "FAIL"
        $color = "Red"
        $icon = "✗"
    }

    $result = @{
        Name = $TestName
        Status = $status
        Passed = $Passed
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }

    $Script:TestResults.Tests += $result

    Write-Host "  [$icon] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "      $Message" -ForegroundColor Gray
    }
    if ($Detailed -and $Details) {
        Write-Host "      Details: $Details" -ForegroundColor DarkGray
    }
}

function Invoke-WebUIRequest {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    $uri = "$($Script:Config.WebUIUrl)$Endpoint"

    try {
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $Headers
            UseBasicParsing = $true
            TimeoutSec = 10
            ErrorAction = "Stop"
        }

        if ($Body -and $Method -ne "GET") {
            $params.Body = ($Body | ConvertTo-Json -Compress)
            $params.ContentType = "application/json"
        }

        $response = Invoke-WebRequest @params

        return @{
            Success = $true
            StatusCode = $response.StatusCode
            Content = $response.Content
            Headers = $response.Headers
        }
    } catch {
        return @{
            Success = $false
            StatusCode = $_.Exception.Response.StatusCode.value__
            Error = $_.Exception.Message
            Content = $null
        }
    }
}

function Test-ServiceRunning {
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return $service.Status -eq "Running"
    } catch {
        return $false
    }
}

function Test-PortListening {
    param([int]$Port)

    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        return $connection -ne $null
    } catch {
        return $false
    }
}

#endregion

#region Test Suites

function Test-ServiceStatus {
    Write-Host "`n=== Test Suite 1: Service Status ===" -ForegroundColor Cyan

    # Test 1.1: Web UI 서비스 실행 여부
    $serviceRunning = Test-ServiceRunning -ServiceName "nginx-web-ui"
    Write-TestResult -TestName "Web UI Service Running" `
                     -Passed $serviceRunning `
                     -Message $(if($serviceRunning){"Service is active"}else{"Service not running"})

    # Test 1.2: Nginx 서비스 실행 여부
    $nginxRunning = Test-ServiceRunning -ServiceName "nginx"
    Write-TestResult -TestName "Nginx Service Running" `
                     -Passed $nginxRunning `
                     -Message $(if($nginxRunning){"Nginx is active"}else{"Nginx not running"})

    # Test 1.3: 포트 8080 리스닝
    $portListening = Test-PortListening -Port 8080
    Write-TestResult -TestName "Port 8080 Listening" `
                     -Passed $portListening `
                     -Message $(if($portListening){"Port is open"}else{"Port not listening"})

    # Test 1.4: Nginx 경로 존재
    $nginxExists = Test-Path $Script:Config.NginxPath
    Write-TestResult -TestName "Nginx Directory Exists" `
                     -Passed $nginxExists `
                     -Message $Script:Config.NginxPath
}

function Test-SecurityBinding {
    Write-Host "`n=== Test Suite 2: Security - Localhost Binding ===" -ForegroundColor Cyan

    # Test 2.1: localhost (127.0.0.1) 접근 가능
    $localhostAccess = Invoke-WebUIRequest -Endpoint "/"
    Write-TestResult -TestName "Localhost Access (127.0.0.1:8080)" `
                     -Passed $localhostAccess.Success `
                     -Message $(if($localhostAccess.Success){"HTTP $($localhostAccess.StatusCode)"}else{"Failed: $($localhostAccess.Error)"})

    # Test 2.2: 외부 IP 접근 차단 (0.0.0.0 바인딩이 아닌지 확인)
    try {
        $networkInfo = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1
        $isLocalhostOnly = $networkInfo.LocalAddress -eq "127.0.0.1"

        Write-TestResult -TestName "Localhost-Only Binding" `
                         -Passed $isLocalhostOnly `
                         -Message $(if($isLocalhostOnly){"Bound to 127.0.0.1 only"}else{"Warning: Bound to $($networkInfo.LocalAddress))"}) `
                         -Details "Security: External access $(if($isLocalhostOnly){'blocked'}else{'allowed'})"
    } catch {
        Write-TestResult -TestName "Localhost-Only Binding" `
                         -Passed $false `
                         -Message "Could not verify binding"
    }
}

function Test-APIEndpoints {
    Write-Host "`n=== Test Suite 3: API Endpoints ===" -ForegroundColor Cyan

    # Test 3.1: GET / (Web UI 홈페이지)
    $home = Invoke-WebUIRequest -Endpoint "/"
    Write-TestResult -TestName "GET / (Home Page)" `
                     -Passed ($home.Success -and $home.StatusCode -eq 200) `
                     -Message "HTTP $($home.StatusCode)" `
                     -Details "Response size: $($home.Content.Length) bytes"

    # Test 3.2: GET /api/status
    $status = Invoke-WebUIRequest -Endpoint "/api/status"
    $statusPassed = $false
    if ($status.Success -and $status.StatusCode -eq 200) {
        try {
            $statusData = $status.Content | ConvertFrom-Json
            $statusPassed = $statusData.success -eq $true
        } catch {}
    }
    Write-TestResult -TestName "GET /api/status" `
                     -Passed $statusPassed `
                     -Message $(if($statusPassed){"API responding"}else{"Failed"})

    # Test 3.3: GET /api/proxies
    $proxies = Invoke-WebUIRequest -Endpoint "/api/proxies"
    $proxiesPassed = $false
    if ($proxies.Success -and $proxies.StatusCode -eq 200) {
        try {
            $proxiesData = $proxies.Content | ConvertFrom-Json
            $proxiesPassed = $proxiesData.PSObject.Properties.Name -contains "proxies"
        } catch {}
    }
    Write-TestResult -TestName "GET /api/proxies" `
                     -Passed $proxiesPassed `
                     -Message $(if($proxiesPassed){"Proxy list retrieved"}else{"Failed"})

    # Test 3.4: GET /api/system
    $system = Invoke-WebUIRequest -Endpoint "/api/system"
    $systemPassed = $false
    if ($system.Success -and $system.StatusCode -eq 200) {
        try {
            $systemData = $system.Content | ConvertFrom-Json
            $systemPassed = $systemData.success -eq $true -and $systemData.system.hostname -ne $null
        } catch {}
    }
    Write-TestResult -TestName "GET /api/system (with AD info)" `
                     -Passed $systemPassed `
                     -Message $(if($systemPassed){"System info retrieved"}else{"Failed"})

    # Test 3.5: GET /api/logs/access
    $logsAccess = Invoke-WebUIRequest -Endpoint "/api/logs/access?lines=10"
    Write-TestResult -TestName "GET /api/logs/access" `
                     -Passed ($logsAccess.Success -and $logsAccess.StatusCode -eq 200) `
                     -Message $(if($logsAccess.Success){"Access logs retrieved"}else{"Failed"})

    # Test 3.6: GET /api/logs/error
    $logsError = Invoke-WebUIRequest -Endpoint "/api/logs/error?lines=10"
    Write-TestResult -TestName "GET /api/logs/error" `
                     -Passed ($logsError.Success -and $logsError.StatusCode -eq 200) `
                     -Message $(if($logsError.Success){"Error logs retrieved"}else{"Failed"})

    # Test 3.7: GET /api/backups
    $backups = Invoke-WebUIRequest -Endpoint "/api/backups"
    Write-TestResult -TestName "GET /api/backups" `
                     -Passed ($backups.Success -and $backups.StatusCode -eq 200) `
                     -Message $(if($backups.Success){"Backup list retrieved"}else{"Failed"})
}

function Test-InputValidation {
    Write-Host "`n=== Test Suite 4: Input Validation ===" -ForegroundColor Cyan

    # Test 4.1: 잘못된 IP 주소 (형식 오류)
    $invalidIP = @{
        serverName = "test.local"
        ip = "999.999.999.999"
        port = 8080
    }
    $response = Invoke-WebUIRequest -Endpoint "/api/proxies" -Method "POST" -Body $invalidIP
    Write-TestResult -TestName "Invalid IP Address Rejection" `
                     -Passed ($response.StatusCode -eq 400) `
                     -Message $(if($response.StatusCode -eq 400){"Correctly rejected"}else{"Should return 400"})

    # Test 4.2: 잘못된 포트 번호 (범위 초과)
    $invalidPort = @{
        serverName = "test.local"
        ip = "192.168.1.100"
        port = 99999
    }
    $response = Invoke-WebUIRequest -Endpoint "/api/proxies" -Method "POST" -Body $invalidPort
    Write-TestResult -TestName "Invalid Port Number Rejection" `
                     -Passed ($response.StatusCode -eq 400) `
                     -Message $(if($response.StatusCode -eq 400){"Correctly rejected"}else{"Should return 400"})

    # Test 4.3: 누락된 필수 필드
    $missingFields = @{
        serverName = "test.local"
        # ip and port missing
    }
    $response = Invoke-WebUIRequest -Endpoint "/api/proxies" -Method "POST" -Body $missingFields
    Write-TestResult -TestName "Missing Required Fields Rejection" `
                     -Passed ($response.StatusCode -eq 400) `
                     -Message $(if($response.StatusCode -eq 400){"Correctly rejected"}else{"Should return 400"})
}

function Test-ProxyManagement {
    Write-Host "`n=== Test Suite 5: Proxy Management ===" -ForegroundColor Cyan

    $testProxyName = "test-proxy-$(Get-Random -Maximum 9999).conf"
    $testServerName = "test-$(Get-Random -Maximum 9999).local"

    # Test 5.1: 프록시 추가 (유효한 데이터)
    $validProxy = @{
        serverName = $testServerName
        ip = "192.168.1.100"
        port = 8080
    }
    $addResponse = Invoke-WebUIRequest -Endpoint "/api/proxies" -Method "POST" -Body $validProxy
    $proxyAdded = $addResponse.Success -and $addResponse.StatusCode -eq 200

    Write-TestResult -TestName "Add Proxy (Valid Data)" `
                     -Passed $proxyAdded `
                     -Message $(if($proxyAdded){"Proxy created"}else{"Failed: $($addResponse.Error)"})`
                     -Details "Server: $testServerName"

    # Test 5.2: 추가된 프록시 존재 확인
    if ($proxyAdded) {
        Start-Sleep -Seconds 2
        $proxies = Invoke-WebUIRequest -Endpoint "/api/proxies"
        $proxyExists = $false

        if ($proxies.Success) {
            try {
                $proxiesData = $proxies.Content | ConvertFrom-Json
                $proxyExists = $proxiesData.proxies | Where-Object { $_.serverName -eq $testServerName }
            } catch {}
        }

        Write-TestResult -TestName "Verify Proxy Exists in List" `
                         -Passed ($proxyExists -ne $null) `
                         -Message $(if($proxyExists){"Found in proxy list"}else{"Not found"})

        # Test 5.3: Nginx 설정 파일 존재 확인
        $confPath = Join-Path $Script:Config.NginxPath "conf\conf.d\$testServerName.conf"
        $confExists = Test-Path $confPath

        Write-TestResult -TestName "Nginx Config File Created" `
                         -Passed $confExists `
                         -Message $confPath

        # Test 5.4: 프록시 삭제
        if ($confExists) {
            $deleteResponse = Invoke-WebUIRequest -Endpoint "/api/proxies/$testServerName.conf" -Method "DELETE"
            $proxyDeleted = $deleteResponse.Success -and $deleteResponse.StatusCode -eq 200

            Write-TestResult -TestName "Delete Proxy" `
                             -Passed $proxyDeleted `
                             -Message $(if($proxyDeleted){"Proxy deleted"}else{"Failed"})

            # Test 5.5: 삭제 후 백업 존재 확인
            Start-Sleep -Seconds 1
            $backupPath = Join-Path $Script:Config.NginxPath "conf\backups"
            if (Test-Path $backupPath) {
                $backupFiles = Get-ChildItem -Path $backupPath -Filter "$testServerName.conf.*.backup" -ErrorAction SilentlyContinue
                $backupCreated = $backupFiles.Count -gt 0

                Write-TestResult -TestName "Backup Created Before Delete" `
                                 -Passed $backupCreated `
                                 -Message $(if($backupCreated){"Backup found: $($backupFiles[0].Name)"}else{"No backup"})
            } else {
                Write-TestResult -TestName "Backup Created Before Delete" `
                                 -Passed $false `
                                 -Message "Backup directory not found"
            }
        }
    }
}

function Test-BackupFeatures {
    Write-Host "`n=== Test Suite 6: Backup Features ===" -ForegroundColor Cyan

    # Test 6.1: 수동 백업 생성
    $backupResponse = Invoke-WebUIRequest -Endpoint "/api/backup" -Method "POST"
    $backupCreated = $backupResponse.Success -and $backupResponse.StatusCode -eq 200

    Write-TestResult -TestName "Manual Backup Creation" `
                     -Passed $backupCreated `
                     -Message $(if($backupCreated){"Backup created"}else{"Failed: $($backupResponse.Error)"})

    # Test 6.2: 백업 목록 조회
    if ($backupCreated) {
        Start-Sleep -Seconds 2
        $backupList = Invoke-WebUIRequest -Endpoint "/api/backups"
        $listRetrieved = $false

        if ($backupList.Success) {
            try {
                $backupData = $backupList.Content | ConvertFrom-Json
                $listRetrieved = $backupData.backups.Count -gt 0
            } catch {}
        }

        Write-TestResult -TestName "Backup List Retrieved" `
                         -Passed $listRetrieved `
                         -Message $(if($listRetrieved){"Found $($backupData.backups.Count) backups"}else{"No backups"})
    }
}

function Test-LoggingSystem {
    Write-Host "`n=== Test Suite 7: Logging System ===" -ForegroundColor Cyan

    $webUILogPath = Join-Path $Script:Config.NginxPath "logs\web-ui.log"

    # Test 7.1: Web UI 로그 파일 존재
    $logExists = Test-Path $webUILogPath
    Write-TestResult -TestName "Web UI Log File Exists" `
                     -Passed $logExists `
                     -Message $webUILogPath

    # Test 7.2: 로그 파일에 내용 있음
    if ($logExists) {
        $logContent = Get-Content $webUILogPath -ErrorAction SilentlyContinue
        $hasContent = $logContent.Count -gt 0

        Write-TestResult -TestName "Log File Has Content" `
                         -Passed $hasContent `
                         -Message $(if($hasContent){"$($logContent.Count) log entries"}else{"Empty log"})

        # Test 7.3: 로그 포맷 검증 (JSON 형식)
        if ($hasContent) {
            try {
                $lastLog = $logContent | Select-Object -Last 1
                $logJson = $lastLog | ConvertFrom-Json
                $validFormat = $logJson.PSObject.Properties.Name -contains "timestamp" -and
                              $logJson.PSObject.Properties.Name -contains "level" -and
                              $logJson.PSObject.Properties.Name -contains "message"

                Write-TestResult -TestName "Log Format Valid (JSON)" `
                                 -Passed $validFormat `
                                 -Message $(if($validFormat){"Structured JSON format"}else{"Invalid format"})
            } catch {
                Write-TestResult -TestName "Log Format Valid (JSON)" `
                                 -Passed $false `
                                 -Message "Failed to parse log as JSON"
            }
        }
    }

    # Test 7.4: Nginx access.log 존재
    $nginxAccessLog = Join-Path $Script:Config.NginxPath "logs\access.log"
    $accessLogExists = Test-Path $nginxAccessLog
    Write-TestResult -TestName "Nginx Access Log Exists" `
                     -Passed $accessLogExists `
                     -Message $nginxAccessLog

    # Test 7.5: Nginx error.log 존재
    $nginxErrorLog = Join-Path $Script:Config.NginxPath "logs\error.log"
    $errorLogExists = Test-Path $nginxErrorLog
    Write-TestResult -TestName "Nginx Error Log Exists" `
                     -Passed $errorLogExists `
                     -Message $nginxErrorLog
}

function Test-ErrorHandling {
    Write-Host "`n=== Test Suite 8: Error Handling ===" -ForegroundColor Cyan

    # Test 8.1: 존재하지 않는 엔드포인트
    $notFound = Invoke-WebUIRequest -Endpoint "/api/nonexistent"
    Write-TestResult -TestName "404 for Non-existent Endpoint" `
                     -Passed ($notFound.StatusCode -eq 404) `
                     -Message $(if($notFound.StatusCode -eq 404){"Correctly returns 404"}else{"Got: $($notFound.StatusCode)"})

    # Test 8.2: 잘못된 HTTP 메서드
    $wrongMethod = Invoke-WebUIRequest -Endpoint "/api/status" -Method "DELETE"
    Write-TestResult -TestName "Method Not Allowed Handling" `
                     -Passed ($wrongMethod.StatusCode -in @(404, 405)) `
                     -Message "Status: $($wrongMethod.StatusCode)"

    # Test 8.3: 존재하지 않는 프록시 삭제
    $deleteNonExistent = Invoke-WebUIRequest -Endpoint "/api/proxies/nonexistent-proxy.conf" -Method "DELETE"
    Write-TestResult -TestName "Delete Non-existent Proxy" `
                     -Passed ($deleteNonExistent.StatusCode -in @(404, 500)) `
                     -Message "Status: $($deleteNonExistent.StatusCode)"

    # Test 8.4: 잘못된 로그 타입
    $invalidLogType = Invoke-WebUIRequest -Endpoint "/api/logs/invalid"
    Write-TestResult -TestName "Invalid Log Type Rejection" `
                     -Passed ($invalidLogType.StatusCode -eq 400) `
                     -Message $(if($invalidLogType.StatusCode -eq 400){"Correctly rejected"}else{"Got: $($invalidLogType.StatusCode)"})
}

function Test-PerformanceMetrics {
    Write-Host "`n=== Test Suite 9: Performance Metrics ===" -ForegroundColor Cyan

    # Test 9.1: 응답 시간 (API 호출)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebUIRequest -Endpoint "/api/status"
    $stopwatch.Stop()

    $responseTime = $stopwatch.ElapsedMilliseconds
    $performanceOK = $responseTime -lt 1000  # 1초 이내

    Write-TestResult -TestName "API Response Time" `
                     -Passed $performanceOK `
                     -Message "$responseTime ms $(if($performanceOK){'(Good)'}else{'(Slow)'})" `
                     -Details "Target: < 1000ms"

    # Test 9.2: 메모리 사용량 (node.exe 프로세스)
    $nodeProcesses = Get-Process -Name node -ErrorAction SilentlyContinue
    if ($nodeProcesses) {
        $totalMemoryMB = ($nodeProcesses | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB
        $memoryOK = $totalMemoryMB -lt 500  # 500MB 이내

        Write-TestResult -TestName "Memory Usage" `
                         -Passed $memoryOK `
                         -Message "$([math]::Round($totalMemoryMB, 2)) MB $(if($memoryOK){'(Normal)'}else{'(High)'})" `
                         -Details "Target: < 500MB"
    } else {
        Write-TestResult -TestName "Memory Usage" `
                         -Passed $false `
                         -Message "Node.js process not found"
    }

    # Test 9.3: CPU 사용률 (평균)
    $nodeProcesses = Get-Process -Name node -ErrorAction SilentlyContinue
    if ($nodeProcesses) {
        $cpuPercent = ($nodeProcesses | Measure-Object -Property CPU -Average).Average
        $cpuOK = $cpuPercent -lt 50  # 50% 이내

        Write-TestResult -TestName "CPU Usage" `
                         -Passed $cpuOK `
                         -Message "$([math]::Round($cpuPercent, 2))% $(if($cpuOK){'(Normal)'}else{'(High)'})" `
                         -Details "Target: < 50%"
    }
}

#endregion

#region Report Generation

function Export-TestReport {
    $reportPath = Join-Path $Script:Config.LogPath "test-nginx-web-ui-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    $passRate = if ($Script:TestResults.TotalTests -gt 0) {
        [math]::Round(($Script:TestResults.PassedTests / $Script:TestResults.TotalTests) * 100, 2)
    } else { 0 }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>nginx-web-ui-enhanced.js Test Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { display: flex; justify-content: space-around; margin: 30px 0; }
        .summary-box { text-align: center; padding: 20px; border-radius: 5px; flex: 1; margin: 0 10px; }
        .summary-box.total { background: #ecf0f1; }
        .summary-box.passed { background: #d5f4e6; }
        .summary-box.failed { background: #fadbd8; }
        .summary-box h3 { margin: 0; font-size: 36px; }
        .summary-box p { margin: 5px 0; color: #7f8c8d; }
        .pass-rate { font-size: 48px; font-weight: bold; color: $(if($passRate -ge 90){'#27ae60'}elseif($passRate -ge 70){'#f39c12'}else{'#e74c3c'}); text-align: center; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        tr:hover { background: #f8f9fa; }
        .status-pass { color: #27ae60; font-weight: bold; }
        .status-fail { color: #e74c3c; font-weight: bold; }
        .details { color: #7f8c8d; font-size: 0.9em; font-style: italic; }
        .timestamp { color: #95a5a6; font-size: 0.9em; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ecf0f1; text-align: center; color: #95a5a6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 nginx-web-ui-enhanced.js Test Report</h1>
        <p class="timestamp">Generated: $($Script:TestResults.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))</p>

        <div class="pass-rate">$passRate% Pass Rate</div>

        <div class="summary">
            <div class="summary-box total">
                <h3>$($Script:TestResults.TotalTests)</h3>
                <p>Total Tests</p>
            </div>
            <div class="summary-box passed">
                <h3>$($Script:TestResults.PassedTests)</h3>
                <p>Passed</p>
            </div>
            <div class="summary-box failed">
                <h3>$($Script:TestResults.FailedTests)</h3>
                <p>Failed</p>
            </div>
        </div>

        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Test Name</th>
                    <th>Status</th>
                    <th>Message</th>
                    <th>Details</th>
                    <th>Time</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($test in $Script:TestResults.Tests) {
        $statusClass = if ($test.Passed) { "status-pass" } else { "status-fail" }
        $html += @"
                <tr>
                    <td>$($test.Name)</td>
                    <td class="$statusClass">$($test.Status)</td>
                    <td>$($test.Message)</td>
                    <td class="details">$($test.Details)</td>
                    <td class="timestamp">$($test.Timestamp.ToString('HH:mm:ss'))</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>

        <div class="footer">
            <p>nginx-web-ui-enhanced.js Test Suite v2.0</p>
            <p>Airgap Installation Package</p>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8 -Force
    Write-Host "`n✅ Test report exported: $reportPath" -ForegroundColor Green

    return $reportPath
}

#endregion

#region Main Execution

function Start-Testing {
    Write-Host @"
================================================================================
          nginx-web-ui-enhanced.js Automated Test Suite
================================================================================
  Web UI URL: $($Script:Config.WebUIUrl)
  Nginx Path: $($Script:Config.NginxPath)

  Test Coverage:
  - Service Status (4 tests)
  - Security Binding (2 tests)
  - API Endpoints (7 tests)
  - Input Validation (3 tests)
  - Proxy Management (5 tests)
  - Backup Features (2 tests)
  - Logging System (5 tests)
  - Error Handling (4 tests)
  - Performance Metrics (3 tests)

  Total: ~35 automated tests
================================================================================

"@ -ForegroundColor Cyan

    # 로그 디렉토리 생성
    if (-not (Test-Path $Script:Config.LogPath)) {
        New-Item -ItemType Directory -Path $Script:Config.LogPath -Force | Out-Null
    }

    $startTime = Get-Date

    # 테스트 실행
    Test-ServiceStatus
    Test-SecurityBinding
    Test-APIEndpoints
    Test-InputValidation
    Test-ProxyManagement
    Test-BackupFeatures
    Test-LoggingSystem
    Test-ErrorHandling
    Test-PerformanceMetrics

    $duration = (Get-Date) - $startTime

    # 결과 요약
    Write-Host "`n================================================================================`n" -ForegroundColor Cyan
    Write-Host "                        Test Summary" -ForegroundColor Cyan
    Write-Host "================================================================================`n" -ForegroundColor Cyan

    $passRate = [math]::Round(($Script:TestResults.PassedTests / $Script:TestResults.TotalTests) * 100, 2)

    Write-Host "  Total Tests:  $($Script:TestResults.TotalTests)" -ForegroundColor White
    Write-Host "  Passed:       $($Script:TestResults.PassedTests)" -ForegroundColor Green
    Write-Host "  Failed:       $($Script:TestResults.FailedTests)" -ForegroundColor $(if($Script:TestResults.FailedTests -gt 0){"Red"}else{"Green"})
    Write-Host "  Pass Rate:    $passRate%" -ForegroundColor $(if($passRate -ge 90){"Green"}elseif($passRate -ge 70){"Yellow"}else{"Red"})
    Write-Host "  Duration:     $($duration.ToString('mm\:ss'))" -ForegroundColor White

    Write-Host "`n================================================================================`n" -ForegroundColor Cyan

    # 실패한 테스트 상세
    if ($Script:TestResults.FailedTests -gt 0) {
        Write-Host "Failed Tests:" -ForegroundColor Red
        foreach ($test in $Script:TestResults.Tests | Where-Object { -not $_.Passed }) {
            Write-Host "  - $($test.Name): $($test.Message)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # 보고서 생성
    if ($ExportReport) {
        $reportPath = Export-TestReport
        Write-Host "📄 HTML report: $reportPath" -ForegroundColor Cyan

        # 브라우저로 열기 (선택)
        $openReport = Read-Host "Open report in browser? (Y/N)"
        if ($openReport -eq 'Y') {
            Start-Process $reportPath
        }
    }

    # 종료 코드
    if ($Script:TestResults.FailedTests -eq 0) {
        Write-Host "✅ All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "❌ Some tests failed." -ForegroundColor Red
        exit 1
    }
}

# 실행
Start-Testing

#endregion
