<#
.SYNOPSIS
    Nginx 리버스 프록시 성능 벤치마크

.DESCRIPTION
    다음 성능 지표를 측정:
    - 처리량 (RPS: Requests Per Second)
    - 응답 시간 (평균, P50, P95, P99)
    - 동시 접속 처리 능력
    - CPU/메모리 사용률
    - 에러율

.PARAMETER TargetURL
    테스트 대상 URL (기본: http://localhost)

.PARAMETER Duration
    테스트 지속 시간 (초). 기본값: 60초

.PARAMETER Concurrency
    동시 접속 수. 기본값: 10

.PARAMETER RequestCount
    총 요청 수 (0 = Duration 기반)

.PARAMETER BenchmarkType
    벤치마크 유형:
    - Quick: 빠른 테스트 (30초, 동시접속 10)
    - Standard: 표준 테스트 (60초, 동시접속 50)
    - Stress: 스트레스 테스트 (120초, 동시접속 200)

.PARAMETER ExportReport
    리포트 저장 경로

.EXAMPLE
    .\09-performance-benchmark.ps1
    기본 벤치마크 (로컬호스트, 60초, 동시접속 10)

.EXAMPLE
    .\09-performance-benchmark.ps1 -BenchmarkType Stress -ExportReport "C:\nginx\reports\perf.html"
    스트레스 테스트 + 리포트 생성

.EXAMPLE
    .\09-performance-benchmark.ps1 -TargetURL "http://app.company.local" -Concurrency 100 -Duration 300
    특정 프록시 대상 성능 테스트
#>

[CmdletBinding()]
param(
    [string]$TargetURL = "http://localhost",

    [ValidateSet("Quick", "Standard", "Stress", "Custom")]
    [string]$BenchmarkType = "Standard",

    [int]$Duration = 0,
    [int]$Concurrency = 0,
    [int]$RequestCount = 0,
    [string]$ExportReport = ""
)

$ErrorActionPreference = "Stop"

# ============================================================================
# 설정
# ============================================================================

$Global:BenchmarkProfiles = @{
    Quick = @{
        Duration = 30
        Concurrency = 10
        Description = "빠른 테스트"
    }
    Standard = @{
        Duration = 60
        Concurrency = 50
        Description = "표준 성능 테스트"
    }
    Stress = @{
        Duration = 120
        Concurrency = 200
        Description = "스트레스 테스트"
    }
    Custom = @{
        Duration = $Duration
        Concurrency = $Concurrency
        Description = "사용자 정의 테스트"
    }
}

$Global:Results = @{
    Config = @{}
    Performance = @{}
    ResourceUsage = @{}
    Errors = @()
    Timestamp = Get-Date
}

# ============================================================================
# 헬퍼 함수
# ============================================================================

function Write-ColorOutput {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{INFO = "Cyan"; SUCCESS = "Green"; WARNING = "Yellow"; ERROR = "Red"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Get-BenchmarkConfig {
    $profile = $Global:BenchmarkProfiles[$BenchmarkType]

    $config = @{
        Type = $BenchmarkType
        URL = $TargetURL
        Duration = if ($Duration -gt 0) { $Duration } else { $profile.Duration }
        Concurrency = if ($Concurrency -gt 0) { $Concurrency } else { $profile.Concurrency }
        RequestCount = $RequestCount
        Description = $profile.Description
    }

    return $config
}

function Test-Prerequisites {
    # curl.exe 확인 (Windows 10 1803+ 기본 제공)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw "curl.exe를 찾을 수 없습니다. Windows 10 1803 이상 필요"
    }

    # 대상 URL 접근 확인
    try {
        $response = Invoke-WebRequest -Uri $TargetURL -Method HEAD -TimeoutSec 5 -UseBasicParsing
        Write-ColorOutput "대상 URL 접근 가능: $TargetURL (Status: $($response.StatusCode))" -Level SUCCESS
    } catch {
        throw "대상 URL 접근 실패: $TargetURL - $_"
    }
}

function Measure-ResourceUsage {
    <#
    .SYNOPSIS
        시스템 리소스 사용률 측정
    #>

    # CPU 측정 (1초 샘플링)
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 |
           Select-Object -ExpandProperty CounterSamples |
           Select-Object -ExpandProperty CookedValue

    # 메모리 측정
    $memory = Get-CimInstance Win32_OperatingSystem | ForEach-Object {
        @{
            TotalMB = [math]::Round($_.TotalVisibleMemorySize / 1KB, 0)
            UsedMB = [math]::Round(($_.TotalVisibleMemorySize - $_.FreePhysicalMemory) / 1KB, 0)
            FreePercent = [math]::Round($_.FreePhysicalMemory / $_.TotalVisibleMemorySize * 100, 2)
        }
    }

    # Nginx 프로세스 리소스
    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    $nginxCPU = 0
    $nginxMem = 0
    if ($nginxProc) {
        $nginxCPU = ($nginxProc | Measure-Object -Property CPU -Sum).Sum
        $nginxMem = ($nginxProc | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB
    }

    return @{
        CPU = [math]::Round($cpu, 2)
        Memory = $memory
        NginxCPU = [math]::Round($nginxCPU, 2)
        NginxMemoryMB = [math]::Round($nginxMem, 2)
        Timestamp = Get-Date
    }
}

function Invoke-PerformanceTest {
    <#
    .SYNOPSIS
        실제 성능 테스트 실행
    #>
    param([hashtable]$Config)

    Write-ColorOutput "성능 테스트 시작..." -Level INFO
    Write-ColorOutput "  URL: $($Config.URL)" -Level INFO
    Write-ColorOutput "  지속 시간: $($Config.Duration)초" -Level INFO
    Write-ColorOutput "  동시 접속: $($Config.Concurrency)" -Level INFO

    # 테스트 전 리소스 측정
    $resourceBefore = Measure-ResourceUsage

    # 테스트 결과 저장
    $results = @{
        ResponseTimes = @()
        StatusCodes = @{}
        Errors = @()
        StartTime = Get-Date
    }

    # 동시 요청 생성 (PowerShell Jobs)
    $jobs = @()
    $totalRequests = if ($Config.RequestCount -gt 0) {
        $Config.RequestCount
    } else {
        $Config.Duration * $Config.Concurrency
    }

    Write-ColorOutput "총 $totalRequests 요청 생성 ($($Config.Concurrency)개 병렬)" -Level INFO

    # 진행률 표시
    $completed = 0
    $errorCount = 0
    $statusCounts = @{}

    # RunspacePool을 사용한 병렬 처리 (Jobs보다 빠름)
    $pool = [runspacefactory]::CreateRunspacePool(1, $Config.Concurrency)
    $pool.Open()

    $scriptBlock = {
        param($URL)

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest -Uri $URL -Method GET -TimeoutSec 10 -UseBasicParsing
            $stopwatch.Stop()

            return @{
                Success = $true
                StatusCode = $response.StatusCode
                ResponseTimeMs = $stopwatch.ElapsedMilliseconds
                Error = $null
            }
        } catch {
            $stopwatch.Stop()
            return @{
                Success = $false
                StatusCode = 0
                ResponseTimeMs = $stopwatch.ElapsedMilliseconds
                Error = $_.Exception.Message
            }
        }
    }

    $runspaces = @()
    $endTime = (Get-Date).AddSeconds($Config.Duration)

    # 요청 생성 루프
    while ((Get-Date) -lt $endTime) {
        # 병렬 요청 생성
        for ($i = 0; $i -lt $Config.Concurrency; $i++) {
            $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($Config.URL)
            $powershell.RunspacePool = $pool

            $runspaces += @{
                Pipe = $powershell
                Status = $powershell.BeginInvoke()
            }
        }

        # 완료된 요청 수집
        $toRemove = @()
        foreach ($runspace in $runspaces) {
            if ($runspace.Status.IsCompleted) {
                $result = $runspace.Pipe.EndInvoke($runspace.Status)
                $runspace.Pipe.Dispose()

                $completed++

                if ($result.Success) {
                    $results.ResponseTimes += $result.ResponseTimeMs

                    $code = $result.StatusCode
                    if ($statusCounts.ContainsKey($code)) {
                        $statusCounts[$code]++
                    } else {
                        $statusCounts[$code] = 1
                    }
                } else {
                    $errorCount++
                    $results.Errors += $result.Error
                }

                $toRemove += $runspace

                # 진행률 출력 (10% 간격)
                if ($completed % [math]::Max([math]::Floor($totalRequests / 10), 1) -eq 0) {
                    $percent = [math]::Round($completed / $totalRequests * 100, 0)
                    Write-Progress -Activity "벤치마크 진행 중..." -Status "$completed / $totalRequests 요청 완료 (에러: $errorCount)" -PercentComplete $percent
                }
            }
        }

        # 완료된 runspace 제거
        foreach ($rs in $toRemove) {
            $runspaces = $runspaces | Where-Object { $_ -ne $rs }
        }

        Start-Sleep -Milliseconds 100
    }

    # 남은 요청 완료 대기
    foreach ($runspace in $runspaces) {
        $result = $runspace.Pipe.EndInvoke($runspace.Status)
        $runspace.Pipe.Dispose()

        $completed++

        if ($result.Success) {
            $results.ResponseTimes += $result.ResponseTimeMs
            $code = $result.StatusCode
            if ($statusCounts.ContainsKey($code)) {
                $statusCounts[$code]++
            } else {
                $statusCounts[$code] = 1
            }
        } else {
            $errorCount++
        }
    }

    $pool.Close()
    $pool.Dispose()

    Write-Progress -Activity "벤치마크 진행 중..." -Completed

    $results.EndTime = Get-Date
    $results.StatusCodes = $statusCounts

    # 테스트 후 리소스 측정
    $resourceAfter = Measure-ResourceUsage

    # 통계 계산
    $duration = ($results.EndTime - $results.StartTime).TotalSeconds
    $responseTimes = $results.ResponseTimes | Sort-Object

    $stats = @{
        TotalRequests = $completed
        SuccessRequests = $completed - $errorCount
        FailedRequests = $errorCount
        SuccessRate = [math]::Round(($completed - $errorCount) / $completed * 100, 2)
        ErrorRate = [math]::Round($errorCount / $completed * 100, 2)
        Duration = [math]::Round($duration, 2)
        RequestsPerSecond = [math]::Round($completed / $duration, 2)
        ResponseTime = @{
            Mean = [math]::Round(($responseTimes | Measure-Object -Average).Average, 2)
            Min = $responseTimes[0]
            Max = $responseTimes[-1]
            P50 = $responseTimes[[math]::Floor($responseTimes.Count * 0.50)]
            P95 = $responseTimes[[math]::Floor($responseTimes.Count * 0.95)]
            P99 = $responseTimes[[math]::Floor($responseTimes.Count * 0.99)]
        }
        StatusCodes = $results.StatusCodes
        ResourceBefore = $resourceBefore
        ResourceAfter = $resourceAfter
        ResourceDelta = @{
            CPUDelta = [math]::Round($resourceAfter.CPU - $resourceBefore.CPU, 2)
            MemoryDeltaMB = [math]::Round($resourceAfter.NginxMemoryMB - $resourceBefore.NginxMemoryMB, 2)
        }
    }

    return $stats
}

function Show-Results {
    param([hashtable]$Stats)

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
    Write-ColorOutput "📊 벤치마크 결과" -Level INFO
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS

    Write-Host ""
    Write-Host "[ 요청 통계 ]" -ForegroundColor Yellow
    Write-Host "  총 요청 수: $($Stats.TotalRequests)"
    Write-Host "  성공: $($Stats.SuccessRequests) ($($Stats.SuccessRate)%)"
    Write-Host "  실패: $($Stats.FailedRequests) ($($Stats.ErrorRate)%)"
    Write-Host "  지속 시간: $($Stats.Duration)초"
    Write-Host ""

    Write-Host "[ 처리량 ]" -ForegroundColor Yellow
    $rpsColor = if ($Stats.RequestsPerSecond -gt 1000) { "Green" } elseif ($Stats.RequestsPerSecond -gt 500) { "Yellow" } else { "Red" }
    Write-Host "  RPS (Requests/sec): " -NoNewline
    Write-Host "$($Stats.RequestsPerSecond)" -ForegroundColor $rpsColor
    Write-Host ""

    Write-Host "[ 응답 시간 (ms) ]" -ForegroundColor Yellow
    Write-Host "  평균: $($Stats.ResponseTime.Mean)ms"
    Write-Host "  최소: $($Stats.ResponseTime.Min)ms"
    Write-Host "  최대: $($Stats.ResponseTime.Max)ms"
    Write-Host "  P50:  $($Stats.ResponseTime.P50)ms"
    Write-Host "  P95:  $($Stats.ResponseTime.P95)ms"
    Write-Host "  P99:  $($Stats.ResponseTime.P99)ms"
    Write-Host ""

    Write-Host "[ HTTP 상태 코드 ]" -ForegroundColor Yellow
    foreach ($code in ($Stats.StatusCodes.Keys | Sort-Object)) {
        $count = $Stats.StatusCodes[$code]
        $percent = [math]::Round($count / $Stats.TotalRequests * 100, 2)
        Write-Host "  $code`: $count ($percent%)"
    }
    Write-Host ""

    Write-Host "[ 리소스 사용 ]" -ForegroundColor Yellow
    Write-Host "  테스트 전 CPU: $($Stats.ResourceBefore.CPU)%"
    Write-Host "  테스트 후 CPU: $($Stats.ResourceAfter.CPU)%"
    Write-Host "  CPU 증가: $($Stats.ResourceDelta.CPUDelta)%"
    Write-Host "  Nginx 메모리: $($Stats.ResourceAfter.NginxMemoryMB)MB (Δ $($Stats.ResourceDelta.MemoryDeltaMB)MB)"
    Write-Host ""

    # 성능 등급
    $grade = if ($Stats.RequestsPerSecond -gt 1000 -and $Stats.ResponseTime.P95 -lt 100) {
        "Excellent"
    } elseif ($Stats.RequestsPerSecond -gt 500 -and $Stats.ResponseTime.P95 -lt 200) {
        "Good"
    } elseif ($Stats.RequestsPerSecond -gt 100 -and $Stats.ResponseTime.P95 -lt 500) {
        "Fair"
    } else {
        "Poor"
    }

    $gradeColor = @{
        "Excellent" = "Green"
        "Good" = "Cyan"
        "Fair" = "Yellow"
        "Poor" = "Red"
    }[$grade]

    Write-Host "[ 성능 등급 ]" -ForegroundColor Yellow
    Write-Host "  " -NoNewline
    Write-Host $grade -ForegroundColor $gradeColor
}

function Generate-HTMLReport {
    param([hashtable]$Config, [hashtable]$Stats, [string]$OutputPath)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Nginx 성능 벤치마크 리포트</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 10px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .summary-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-box h3 { margin: 0; font-size: 14px; opacity: 0.9; }
        .summary-box .value { font-size: 32px; font-weight: bold; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #7f8c8d; font-size: 12px; text-align: right; margin-top: 30px; }
        .badge { padding: 4px 12px; border-radius: 4px; font-weight: bold; display: inline-block; }
        .badge-excellent { background: #2ecc71; color: white; }
        .badge-good { background: #3498db; color: white; }
        .badge-fair { background: #f39c12; color: white; }
        .badge-poor { background: #e74c3c; color: white; }
    </style>
</head>
<body>
<div class="container">
    <h1>⚡ Nginx 성능 벤치마크 리포트</h1>

    <h2>테스트 설정</h2>
    <table>
        <tr><td>테스트 유형</td><td>$($Config.Type) - $($Config.Description)</td></tr>
        <tr><td>대상 URL</td><td>$($Config.URL)</td></tr>
        <tr><td>지속 시간</td><td>$($Config.Duration)초</td></tr>
        <tr><td>동시 접속</td><td>$($Config.Concurrency)</td></tr>
    </table>

    <div class="summary">
        <div class="summary-box">
            <h3>총 요청 수</h3>
            <div class="value">$($Stats.TotalRequests)</div>
        </div>
        <div class="summary-box">
            <h3>RPS</h3>
            <div class="value">$($Stats.RequestsPerSecond)</div>
        </div>
        <div class="summary-box">
            <h3>평균 응답 (ms)</h3>
            <div class="value">$($Stats.ResponseTime.Mean)</div>
        </div>
        <div class="summary-box">
            <h3>성공률</h3>
            <div class="value">$($Stats.SuccessRate)%</div>
        </div>
    </div>

    <h2>응답 시간 (Latency)</h2>
    <table>
        <tr><th>지표</th><th>값 (ms)</th></tr>
        <tr><td>최소</td><td>$($Stats.ResponseTime.Min)</td></tr>
        <tr><td>평균</td><td>$($Stats.ResponseTime.Mean)</td></tr>
        <tr><td>P50 (중앙값)</td><td>$($Stats.ResponseTime.P50)</td></tr>
        <tr><td>P95</td><td>$($Stats.ResponseTime.P95)</td></tr>
        <tr><td>P99</td><td>$($Stats.ResponseTime.P99)</td></tr>
        <tr><td>최대</td><td>$($Stats.ResponseTime.Max)</td></tr>
    </table>

    <div class="timestamp">
        리포트 생성 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    </div>
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-ColorOutput "HTML 리포트 생성 완료: $OutputPath" -Level SUCCESS
}

# ============================================================================
# 메인 실행
# ============================================================================

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
Write-ColorOutput "Nginx 성능 벤치마크 v1.0" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

# 설정 가져오기
$config = Get-BenchmarkConfig
$Global:Results.Config = $config

Write-ColorOutput "벤치마크 유형: $($config.Type) - $($config.Description)" -Level INFO

# 사전 확인
Test-Prerequisites

# 성능 테스트 실행
$stats = Invoke-PerformanceTest -Config $config
$Global:Results.Performance = $stats

# 결과 출력
Show-Results -Stats $stats

# HTML 리포트
if ($ExportReport) {
    Generate-HTMLReport -Config $config -Stats $stats -OutputPath $ExportReport
}

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
Write-ColorOutput "벤치마크 완료" -Level SUCCESS
