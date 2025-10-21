<#
.SYNOPSIS
    Nginx 리버스 프록시 실시간 헬스 모니터링

.DESCRIPTION
    시스템, Nginx, 웹 UI, 프록시 대상의 헬스 상태를 지속적으로 모니터링하고
    임계값 초과 시 알람 및 자동 복구 수행

.PARAMETER MonitorInterval
    모니터링 주기 (초). 기본값: 30초

.PARAMETER AlertThreshold
    알람 임계값 설정
    - CPUPercent: CPU 사용률 (기본 80%)
    - MemoryPercent: 메모리 사용률 (기본 85%)
    - DiskPercent: 디스크 사용률 (기본 90%)
    - ResponseTimeMs: 응답 시간 (기본 1000ms)

.PARAMETER AutoRecover
    자동 복구 활성화 (서비스 재시작, 리소스 정리)

.PARAMETER ExportLog
    모니터링 로그 저장 경로

.PARAMETER DashboardMode
    실시간 대시보드 모드 (콘솔 출력)

.EXAMPLE
    .\07-health-monitor.ps1
    기본 30초 간격 모니터링

.EXAMPLE
    .\07-health-monitor.ps1 -MonitorInterval 60 -AutoRecover -DashboardMode
    1분 간격, 자동 복구 활성화, 대시보드 모드

.EXAMPLE
    .\07-health-monitor.ps1 -ExportLog "C:\nginx\logs\health-monitor.log"
    로그 파일 저장
#>

[CmdletBinding()]
param(
    [int]$MonitorInterval = 30,

    [hashtable]$AlertThreshold = @{
        CPUPercent = 80
        MemoryPercent = 85
        DiskPercent = 90
        ResponseTimeMs = 1000
        ErrorRate = 5  # 5% 이상 에러율
    },

    [switch]$AutoRecover,
    [string]$ExportLog = "",
    [switch]$DashboardMode,
    [int]$MaxIterations = 0  # 0 = 무한 반복
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$Global:HealthData = @{
    StartTime = Get-Date
    Iterations = 0
    Alerts = @()
    Recoveries = @()
}

# ============================================================================
# 헬퍼 함수
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Level = "INFO"  # INFO, SUCCESS, WARNING, ERROR
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        INFO = "Cyan"
        SUCCESS = "Green"
        WARNING = "Yellow"
        ERROR = "Red"
    }

    $prefix = "[$timestamp] [$Level]"
    Write-Host $prefix -ForegroundColor $colorMap[$Level] -NoNewline
    Write-Host " $Message"

    if ($ExportLog) {
        Add-Content -Path $ExportLog -Value "$prefix $Message"
    }
}

function Get-SystemHealth {
    <#
    .SYNOPSIS
        시스템 리소스 상태 수집
    #>

    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 |
           Select-Object -ExpandProperty CounterSamples |
           Select-Object -ExpandProperty CookedValue

    $memory = Get-CimInstance Win32_OperatingSystem | ForEach-Object {
        [math]::Round(($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / $_.TotalVisibleMemorySize * 100, 2)
    }

    $disk = Get-PSDrive C | ForEach-Object {
        [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100, 2)
    }

    return @{
        CPU = [math]::Round($cpu, 2)
        Memory = $memory
        Disk = $disk
        Timestamp = Get-Date
    }
}

function Get-NginxHealth {
    <#
    .SYNOPSIS
        Nginx 서비스 상태 확인
    #>

    $service = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    $process = Get-Process -Name "nginx" -ErrorAction SilentlyContinue

    # Nginx 설정 검증
    $configTest = $false
    if (Test-Path "C:\nginx\nginx.exe") {
        $testResult = & "C:\nginx\nginx.exe" -t 2>&1
        $configTest = $LASTEXITCODE -eq 0
    }

    # 포트 리스닝 확인
    $port80 = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
    $port443 = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue

    return @{
        ServiceStatus = if ($service) { $service.Status } else { "NotFound" }
        ProcessCount = if ($process) { @($process).Count } else { 0 }
        ConfigValid = $configTest
        Port80Listening = $null -ne $port80
        Port443Listening = $null -ne $port443
        WorkerProcesses = @($process | Where-Object { $_.ProcessName -eq "nginx" -and $_.Id -ne $process[0].Id }).Count
        Timestamp = Get-Date
    }
}

function Get-WebUIHealth {
    <#
    .SYNOPSIS
        웹 UI 상태 확인
    #>

    $service = Get-Service -Name "nginx-web-ui" -ErrorAction SilentlyContinue
    $port = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue

    # HTTP 헬스 체크
    $httpHealthy = $false
    $responseTime = 0
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "http://localhost:8080" -TimeoutSec 5 -UseBasicParsing
        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds
        $httpHealthy = $response.StatusCode -eq 200
    } catch {
        # 웹 UI가 응답하지 않음
    }

    return @{
        ServiceStatus = if ($service) { $service.Status } else { "NotFound" }
        PortListening = $null -ne $port
        HTTPHealthy = $httpHealthy
        ResponseTimeMs = $responseTime
        Timestamp = Get-Date
    }
}

function Get-ProxyTargetHealth {
    <#
    .SYNOPSIS
        프록시 대상 서버 헬스 체크
    #>

    $targets = @()

    # Nginx 설정에서 upstream 추출
    if (Test-Path "C:\nginx\conf\conf.d\") {
        $configFiles = Get-ChildItem "C:\nginx\conf\conf.d\*.conf"
        foreach ($file in $configFiles) {
            $content = Get-Content $file.FullName -Raw

            # proxy_pass 패턴 매칭
            $matches = [regex]::Matches($content, 'proxy_pass\s+http://([^;]+)')
            foreach ($match in $matches) {
                $upstream = $match.Groups[1].Value.Trim()
                if ($upstream -match '(\d+\.\d+\.\d+\.\d+):(\d+)') {
                    $targets += @{
                        Host = $Matches[1]
                        Port = [int]$Matches[2]
                        ConfigFile = $file.Name
                    }
                }
            }
        }
    }

    # 중복 제거
    $targets = $targets | Sort-Object -Property Host, Port -Unique

    # 각 대상 테스트
    $results = @()
    foreach ($target in $targets) {
        $reachable = Test-NetConnection -ComputerName $target.Host -Port $target.Port -WarningAction SilentlyContinue -InformationLevel Quiet

        $results += @{
            Host = $target.Host
            Port = $target.Port
            ConfigFile = $target.ConfigFile
            Reachable = $reachable
            Timestamp = Get-Date
        }
    }

    return $results
}

function Test-HealthThresholds {
    <#
    .SYNOPSIS
        임계값 초과 확인 및 알람
    #>
    param(
        [hashtable]$SystemHealth,
        [hashtable]$NginxHealth,
        [hashtable]$WebUIHealth,
        [array]$ProxyHealth
    )

    $alerts = @()

    # 시스템 리소스 확인
    if ($SystemHealth.CPU -gt $AlertThreshold.CPUPercent) {
        $alerts += @{
            Type = "System"
            Severity = "WARNING"
            Message = "CPU 사용률 높음: $($SystemHealth.CPU)% (임계값: $($AlertThreshold.CPUPercent)%)"
            Value = $SystemHealth.CPU
            Threshold = $AlertThreshold.CPUPercent
        }
    }

    if ($SystemHealth.Memory -gt $AlertThreshold.MemoryPercent) {
        $alerts += @{
            Type = "System"
            Severity = "WARNING"
            Message = "메모리 사용률 높음: $($SystemHealth.Memory)% (임계값: $($AlertThreshold.MemoryPercent)%)"
            Value = $SystemHealth.Memory
            Threshold = $AlertThreshold.MemoryPercent
        }
    }

    if ($SystemHealth.Disk -gt $AlertThreshold.DiskPercent) {
        $alerts += @{
            Type = "System"
            Severity = "ERROR"
            Message = "디스크 사용률 위험: $($SystemHealth.Disk)% (임계값: $($AlertThreshold.DiskPercent)%)"
            Value = $SystemHealth.Disk
            Threshold = $AlertThreshold.DiskPercent
        }
    }

    # Nginx 상태 확인
    if ($NginxHealth.ServiceStatus -ne "Running") {
        $alerts += @{
            Type = "Nginx"
            Severity = "ERROR"
            Message = "Nginx 서비스 중지됨: $($NginxHealth.ServiceStatus)"
            Value = $NginxHealth.ServiceStatus
        }
    }

    if (-not $NginxHealth.ConfigValid) {
        $alerts += @{
            Type = "Nginx"
            Severity = "ERROR"
            Message = "Nginx 설정 오류 감지"
            Value = "ConfigInvalid"
        }
    }

    if (-not $NginxHealth.Port80Listening) {
        $alerts += @{
            Type = "Nginx"
            Severity = "ERROR"
            Message = "포트 80 리스닝 중지"
            Value = "Port80Down"
        }
    }

    # 웹 UI 상태 확인
    if ($WebUIHealth.ServiceStatus -ne "Running") {
        $alerts += @{
            Type = "WebUI"
            Severity = "WARNING"
            Message = "웹 UI 서비스 중지됨: $($WebUIHealth.ServiceStatus)"
            Value = $WebUIHealth.ServiceStatus
        }
    }

    if ($WebUIHealth.ResponseTimeMs -gt $AlertThreshold.ResponseTimeMs) {
        $alerts += @{
            Type = "WebUI"
            Severity = "WARNING"
            Message = "웹 UI 응답 지연: $($WebUIHealth.ResponseTimeMs)ms (임계값: $($AlertThreshold.ResponseTimeMs)ms)"
            Value = $WebUIHealth.ResponseTimeMs
            Threshold = $AlertThreshold.ResponseTimeMs
        }
    }

    # 프록시 대상 확인
    $unreachable = $ProxyHealth | Where-Object { -not $_.Reachable }
    if ($unreachable.Count -gt 0) {
        foreach ($target in $unreachable) {
            $alerts += @{
                Type = "ProxyTarget"
                Severity = "ERROR"
                Message = "업스트림 서버 도달 불가: $($target.Host):$($target.Port) ($($target.ConfigFile))"
                Value = "$($target.Host):$($target.Port)"
            }
        }
    }

    return $alerts
}

function Invoke-AutoRecovery {
    <#
    .SYNOPSIS
        자동 복구 실행
    #>
    param(
        [array]$Alerts
    )

    $recoveries = @()

    foreach ($alert in $Alerts) {
        switch ($alert.Type) {
            "Nginx" {
                if ($alert.Value -eq "Stopped" -or $alert.Value -eq "ConfigInvalid") {
                    try {
                        Write-ColorOutput "자동 복구: Nginx 서비스 재시작 시도" -Level WARNING

                        # 설정 검증
                        if (Test-Path "C:\nginx\nginx.exe") {
                            & "C:\nginx\nginx.exe" -t 2>&1 | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                Restart-Service nginx -Force
                                Start-Sleep -Seconds 3

                                $newStatus = (Get-Service nginx).Status
                                if ($newStatus -eq "Running") {
                                    $recoveries += "Nginx 서비스 재시작 성공"
                                    Write-ColorOutput "✓ Nginx 서비스 재시작 완료" -Level SUCCESS
                                } else {
                                    Write-ColorOutput "✗ Nginx 서비스 재시작 실패: $newStatus" -Level ERROR
                                }
                            } else {
                                Write-ColorOutput "✗ Nginx 설정 오류로 인해 재시작 불가" -Level ERROR
                            }
                        }
                    } catch {
                        Write-ColorOutput "✗ Nginx 복구 실패: $_" -Level ERROR
                    }
                }
            }

            "WebUI" {
                if ($alert.Value -eq "Stopped") {
                    try {
                        Write-ColorOutput "자동 복구: 웹 UI 서비스 재시작 시도" -Level WARNING
                        Restart-Service "nginx-web-ui" -Force
                        Start-Sleep -Seconds 3

                        $newStatus = (Get-Service "nginx-web-ui").Status
                        if ($newStatus -eq "Running") {
                            $recoveries += "웹 UI 서비스 재시작 성공"
                            Write-ColorOutput "✓ 웹 UI 서비스 재시작 완료" -Level SUCCESS
                        }
                    } catch {
                        Write-ColorOutput "✗ 웹 UI 복구 실패: $_" -Level ERROR
                    }
                }
            }

            "System" {
                if ($alert.Type -eq "System" -and $alert.Message -match "디스크") {
                    try {
                        Write-ColorOutput "자동 복구: 디스크 정리 시도" -Level WARNING

                        # 로그 파일 정리 (7일 이상 된 파일)
                        $logPath = "C:\nginx\logs"
                        if (Test-Path $logPath) {
                            $oldLogs = Get-ChildItem $logPath -Recurse |
                                       Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

                            if ($oldLogs) {
                                $oldLogs | Remove-Item -Force
                                $recoveries += "오래된 로그 파일 삭제: $($oldLogs.Count)개"
                                Write-ColorOutput "✓ 로그 파일 정리 완료: $($oldLogs.Count)개 삭제" -Level SUCCESS
                            }
                        }
                    } catch {
                        Write-ColorOutput "✗ 디스크 정리 실패: $_" -Level ERROR
                    }
                }
            }
        }
    }

    return $recoveries
}

function Show-Dashboard {
    <#
    .SYNOPSIS
        실시간 대시보드 출력
    #>
    param(
        [hashtable]$SystemHealth,
        [hashtable]$NginxHealth,
        [hashtable]$WebUIHealth,
        [array]$ProxyHealth,
        [array]$Alerts
    )

    Clear-Host

    $uptime = New-TimeSpan -Start $Global:HealthData.StartTime -End (Get-Date)

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Nginx 리버스 프록시 헬스 모니터 v1.0" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ⏱  가동 시간: $($uptime.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "  🔄 모니터링 횟수: $($Global:HealthData.Iterations)" -ForegroundColor Gray
    Write-Host "  📅 현재 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""

    # 시스템 리소스
    Write-Host "┌─ 시스템 리소스" -ForegroundColor Yellow
    $cpuColor = if ($SystemHealth.CPU -gt $AlertThreshold.CPUPercent) { "Red" } elseif ($SystemHealth.CPU -gt 60) { "Yellow" } else { "Green" }
    $memColor = if ($SystemHealth.Memory -gt $AlertThreshold.MemoryPercent) { "Red" } elseif ($SystemHealth.Memory -gt 70) { "Yellow" } else { "Green" }
    $diskColor = if ($SystemHealth.Disk -gt $AlertThreshold.DiskPercent) { "Red" } elseif ($SystemHealth.Disk -gt 80) { "Yellow" } else { "Green" }

    Write-Host "│  CPU: " -NoNewline
    Write-Host ("{0,6}%" -f $SystemHealth.CPU) -ForegroundColor $cpuColor -NoNewline
    Write-Host " │ Memory: " -NoNewline
    Write-Host ("{0,6}%" -f $SystemHealth.Memory) -ForegroundColor $memColor -NoNewline
    Write-Host " │ Disk: " -NoNewline
    Write-Host ("{0,6}%" -f $SystemHealth.Disk) -ForegroundColor $diskColor
    Write-Host ""

    # Nginx 상태
    Write-Host "┌─ Nginx 서비스" -ForegroundColor Yellow
    $nginxColor = if ($NginxHealth.ServiceStatus -eq "Running") { "Green" } else { "Red" }
    Write-Host "│  상태: " -NoNewline
    Write-Host $NginxHealth.ServiceStatus -ForegroundColor $nginxColor -NoNewline
    Write-Host " │ 워커 프로세스: $($NginxHealth.WorkerProcesses)" -NoNewline
    Write-Host " │ 설정: " -NoNewline
    if ($NginxHealth.ConfigValid) {
        Write-Host "OK" -ForegroundColor Green
    } else {
        Write-Host "ERROR" -ForegroundColor Red
    }

    Write-Host "│  포트 80: " -NoNewline
    if ($NginxHealth.Port80Listening) {
        Write-Host "리스닝" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "중지" -ForegroundColor Red -NoNewline
    }
    Write-Host " │ 포트 443: " -NoNewline
    if ($NginxHealth.Port443Listening) {
        Write-Host "리스닝" -ForegroundColor Green
    } else {
        Write-Host "중지" -ForegroundColor Red
    }
    Write-Host ""

    # 웹 UI 상태
    Write-Host "┌─ 웹 UI (관리 인터페이스)" -ForegroundColor Yellow
    $webUIColor = if ($WebUIHealth.ServiceStatus -eq "Running") { "Green" } else { "Red" }
    Write-Host "│  상태: " -NoNewline
    Write-Host $WebUIHealth.ServiceStatus -ForegroundColor $webUIColor -NoNewline
    Write-Host " │ HTTP: " -NoNewline
    if ($WebUIHealth.HTTPHealthy) {
        Write-Host "OK ($($WebUIHealth.ResponseTimeMs)ms)" -ForegroundColor Green
    } else {
        Write-Host "ERROR" -ForegroundColor Red
    }
    Write-Host ""

    # 프록시 대상
    if ($ProxyHealth.Count -gt 0) {
        Write-Host "┌─ 프록시 대상 ($($ProxyHealth.Count)개)" -ForegroundColor Yellow
        foreach ($target in $ProxyHealth) {
            $targetColor = if ($target.Reachable) { "Green" } else { "Red" }
            $status = if ($target.Reachable) { "✓" } else { "✗" }
            Write-Host "│  $status $($target.Host):$($target.Port)" -ForegroundColor $targetColor -NoNewline
            Write-Host " ($($target.ConfigFile))" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # 알람
    if ($Alerts.Count -gt 0) {
        Write-Host "┌─ 활성 알람 ($($Alerts.Count)개)" -ForegroundColor Red
        foreach ($alert in $Alerts) {
            $color = if ($alert.Severity -eq "ERROR") { "Red" } else { "Yellow" }
            Write-Host "│  [$($alert.Severity)] $($alert.Message)" -ForegroundColor $color
        }
        Write-Host ""
    } else {
        Write-Host "✓ 모든 시스템 정상" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  다음 모니터링: $MonitorInterval 초 후 | Ctrl+C로 중지" -ForegroundColor Gray
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

# ============================================================================
# 메인 실행
# ============================================================================

Write-ColorOutput "헬스 모니터 시작 (간격: $($MonitorInterval)초)" -Level INFO
if ($AutoRecover) {
    Write-ColorOutput "자동 복구 활성화됨" -Level INFO
}

try {
    while ($true) {
        $Global:HealthData.Iterations++

        # 데이터 수집
        $systemHealth = Get-SystemHealth
        $nginxHealth = Get-NginxHealth
        $webUIHealth = Get-WebUIHealth
        $proxyHealth = Get-ProxyTargetHealth

        # 임계값 확인
        $alerts = Test-HealthThresholds `
            -SystemHealth $systemHealth `
            -NginxHealth $nginxHealth `
            -WebUIHealth $webUIHealth `
            -ProxyHealth $proxyHealth

        # 알람 출력
        if ($alerts.Count -gt 0) {
            $Global:HealthData.Alerts += $alerts

            foreach ($alert in $alerts) {
                $level = if ($alert.Severity -eq "ERROR") { "ERROR" } else { "WARNING" }
                Write-ColorOutput "[$($alert.Type)] $($alert.Message)" -Level $level
            }

            # 자동 복구
            if ($AutoRecover -and $alerts.Count -gt 0) {
                $recoveries = Invoke-AutoRecovery -Alerts $alerts
                $Global:HealthData.Recoveries += $recoveries
            }
        }

        # 대시보드 출력
        if ($DashboardMode) {
            Show-Dashboard `
                -SystemHealth $systemHealth `
                -NginxHealth $nginxHealth `
                -WebUIHealth $webUIHealth `
                -ProxyHealth $proxyHealth `
                -Alerts $alerts
        }

        # 무한 반복 또는 제한 확인
        if ($MaxIterations -gt 0 -and $Global:HealthData.Iterations -ge $MaxIterations) {
            break
        }

        Start-Sleep -Seconds $MonitorInterval
    }
} catch {
    Write-ColorOutput "모니터링 중단: $_" -Level ERROR
} finally {
    # 최종 보고서
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-ColorOutput "헬스 모니터 종료" -Level INFO
    Write-ColorOutput "  총 모니터링: $($Global:HealthData.Iterations)회" -Level INFO
    Write-ColorOutput "  총 알람: $($Global:HealthData.Alerts.Count)개" -Level INFO
    if ($AutoRecover) {
        Write-ColorOutput "  자동 복구: $($Global:HealthData.Recoveries.Count)회" -Level INFO
    }
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
}
