<#
.SYNOPSIS
    Nginx 로그 분석 및 이상 탐지

.DESCRIPTION
    access.log와 error.log를 분석하여 다음을 수행:
    - HTTP 상태 코드 통계 (200, 404, 500 등)
    - 에러 패턴 감지 (upstream timeout, connection refused 등)
    - 요청 빈도 분석 (초당/분당 요청 수)
    - 느린 응답 감지 (응답 시간 임계값 초과)
    - Top IP/URL/User-Agent 분석
    - 보안 이벤트 감지 (스캔, 공격 시도)

.PARAMETER LogPath
    Nginx 로그 디렉토리 경로. 기본값: C:\nginx\logs

.PARAMETER AnalysisType
    분석 유형: Quick (최근 1시간), Daily (최근 24시간), Full (전체 로그)

.PARAMETER TimeWindow
    분석 시간 범위 (분). Quick=60, Daily=1440

.PARAMETER ExportReport
    리포트 저장 경로 (HTML)

.PARAMETER ShowTopN
    Top N 결과 표시 개수 (기본: 10)

.PARAMETER AlertOnErrors
    에러 임계값 초과 시 알람 (기본: 5% 에러율)

.EXAMPLE
    .\08-log-analyzer.ps1
    기본 분석 (최근 1시간)

.EXAMPLE
    .\08-log-analyzer.ps1 -AnalysisType Daily -ExportReport "C:\nginx\reports\log-analysis.html"
    24시간 로그 분석 및 리포트 생성

.EXAMPLE
    .\08-log-analyzer.ps1 -TimeWindow 30 -ShowTopN 20
    최근 30분, Top 20 결과
#>

[CmdletBinding()]
param(
    [string]$LogPath = "C:\nginx\logs",

    [ValidateSet("Quick", "Daily", "Full")]
    [string]$AnalysisType = "Quick",

    [int]$TimeWindow = 0,  # 0 = AnalysisType 기본값 사용
    [string]$ExportReport = "",
    [int]$ShowTopN = 10,
    [double]$AlertOnErrors = 5.0  # 5% 에러율
)

$ErrorActionPreference = "Stop"

# ============================================================================
# 설정
# ============================================================================

$Global:AnalysisConfig = @{
    TimeWindows = @{
        Quick = 60      # 1시간
        Daily = 1440    # 24시간
        Full = 999999   # 전체
    }
    ErrorPatterns = @(
        "upstream timed out"
        "upstream prematurely closed connection"
        "connect\(\) failed.*Connection refused"
        "no live upstreams"
        "SSL_do_handshake\(\) failed"
        "broken pipe"
        "recv\(\) failed"
    )
    SecurityPatterns = @(
        "sql injection"
        "\.\./\.\."
        "<script"
        "union select"
        "/etc/passwd"
        "/proc/self"
        "cmd\.exe"
        "powershell"
    )
}

$Global:Results = @{
    Summary = @{}
    HTTPStatus = @{}
    ErrorEvents = @()
    SecurityEvents = @()
    TopIPs = @()
    TopURLs = @()
    TopUserAgents = @()
    SlowRequests = @()
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

function Get-TimeWindowMinutes {
    if ($TimeWindow -gt 0) {
        return $TimeWindow
    }
    return $Global:AnalysisConfig.TimeWindows[$AnalysisType]
}

function Parse-AccessLog {
    <#
    .SYNOPSIS
        access.log 파싱 (Nginx 로그 포맷)
    #>
    param([string]$LogFile, [DateTime]$StartTime)

    if (-not (Test-Path $LogFile)) {
        Write-ColorOutput "Access 로그 파일 없음: $LogFile" -Level WARNING
        return @()
    }

    Write-ColorOutput "Access 로그 파싱: $LogFile" -Level INFO

    $entries = @()
    $lineCount = 0

    # Nginx 기본 로그 포맷: '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"'
    $pattern = '^(\S+) \S+ \S+ \[([^\]]+)\] "(\S+) ([^\s]+) [^"]*" (\d+) (\d+) "([^"]*)" "([^"]*)"'

    Get-Content $LogFile | ForEach-Object {
        $lineCount++

        if ($_ -match $pattern) {
            $ip = $Matches[1]
            $timeStr = $Matches[2]
            $method = $Matches[3]
            $url = $Matches[4]
            $status = [int]$Matches[5]
            $bytes = [int]$Matches[6]
            $referer = $Matches[7]
            $userAgent = $Matches[8]

            # 시간 파싱 (예: 21/Oct/2025:01:23:45 +0900)
            try {
                $logTime = [DateTime]::ParseExact(
                    $timeStr.Split(' ')[0],
                    "dd/MMM/yyyy:HH:mm:ss",
                    [System.Globalization.CultureInfo]::InvariantCulture
                )

                # 시간 범위 필터링
                if ($logTime -ge $StartTime) {
                    $entries += @{
                        IP = $ip
                        Time = $logTime
                        Method = $method
                        URL = $url
                        Status = $status
                        Bytes = $bytes
                        Referer = $referer
                        UserAgent = $userAgent
                    }
                }
            } catch {
                # 시간 파싱 실패 (형식 다를 수 있음)
            }
        }
    }

    Write-ColorOutput "  파싱 완료: $lineCount줄 읽음, $($entries.Count)개 엔트리 추출" -Level INFO
    return $entries
}

function Parse-ErrorLog {
    <#
    .SYNOPSIS
        error.log 파싱
    #>
    param([string]$LogFile, [DateTime]$StartTime)

    if (-not (Test-Path $LogFile)) {
        Write-ColorOutput "Error 로그 파일 없음: $LogFile" -Level WARNING
        return @()
    }

    Write-ColorOutput "Error 로그 파싱: $LogFile" -Level INFO

    $entries = @()
    $lineCount = 0

    # Nginx 에러 로그 포맷: 'YYYY/MM/DD HH:MM:SS [level] pid#tid: *cid message'
    $pattern = '^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] (.+)'

    Get-Content $LogFile | ForEach-Object {
        $lineCount++

        if ($_ -match $pattern) {
            $timeStr = $Matches[1]
            $level = $Matches[2]
            $message = $Matches[3]

            try {
                $logTime = [DateTime]::ParseExact(
                    $timeStr,
                    "yyyy/MM/dd HH:mm:ss",
                    [System.Globalization.CultureInfo]::InvariantCulture
                )

                if ($logTime -ge $StartTime) {
                    $entries += @{
                        Time = $logTime
                        Level = $level
                        Message = $message
                    }
                }
            } catch {
                # 시간 파싱 실패
            }
        }
    }

    Write-ColorOutput "  파싱 완료: $lineCount줄 읽음, $($entries.Count)개 에러 추출" -Level INFO
    return $entries
}

function Analyze-HTTPStatus {
    param([array]$AccessEntries)

    $statusGroups = $AccessEntries | Group-Object -Property Status
    $total = $AccessEntries.Count

    $statusCodes = @{}
    foreach ($group in $statusGroups) {
        $count = $group.Count
        $percent = [math]::Round($count / $total * 100, 2)

        $statusCodes[[int]$group.Name] = @{
            Count = $count
            Percent = $percent
        }
    }

    # 상태 코드 범주
    $categories = @{
        "2xx (Success)" = ($statusCodes.Keys | Where-Object { $_ -ge 200 -and $_ -lt 300 } | ForEach-Object { $statusCodes[$_].Count } | Measure-Object -Sum).Sum
        "3xx (Redirect)" = ($statusCodes.Keys | Where-Object { $_ -ge 300 -and $_ -lt 400 } | ForEach-Object { $statusCodes[$_].Count } | Measure-Object -Sum).Sum
        "4xx (Client Error)" = ($statusCodes.Keys | Where-Object { $_ -ge 400 -and $_ -lt 500 } | ForEach-Object { $statusCodes[$_].Count } | Measure-Object -Sum).Sum
        "5xx (Server Error)" = ($statusCodes.Keys | Where-Object { $_ -ge 500 -and $_ -lt 600 } | ForEach-Object { $statusCodes[$_].Count } | Measure-Object -Sum).Sum
    }

    return @{
        StatusCodes = $statusCodes
        Categories = $categories
        Total = $total
        ErrorRate = [math]::Round((($categories["4xx (Client Error)"] + $categories["5xx (Server Error)"]) / $total * 100), 2)
    }
}

function Analyze-ErrorPatterns {
    param([array]$ErrorEntries)

    $patterns = @{}
    foreach ($pattern in $Global:AnalysisConfig.ErrorPatterns) {
        $matches = $ErrorEntries | Where-Object { $_.Message -match $pattern }
        if ($matches.Count -gt 0) {
            $patterns[$pattern] = $matches.Count
        }
    }

    return $patterns
}

function Analyze-SecurityEvents {
    param([array]$AccessEntries)

    $events = @()
    foreach ($entry in $AccessEntries) {
        foreach ($pattern in $Global:AnalysisConfig.SecurityPatterns) {
            if ($entry.URL -match $pattern -or $entry.UserAgent -match $pattern) {
                $events += @{
                    Time = $entry.Time
                    IP = $entry.IP
                    URL = $entry.URL
                    Pattern = $pattern
                    UserAgent = $entry.UserAgent
                }
                break
            }
        }
    }

    return $events
}

function Get-TopN {
    param([array]$Entries, [string]$Property, [int]$TopN)

    $grouped = $Entries | Group-Object -Property $Property |
               Sort-Object -Property Count -Descending |
               Select-Object -First $TopN

    return $grouped | ForEach-Object {
        @{
            Value = $_.Name
            Count = $_.Count
            Percent = [math]::Round($_.Count / $Entries.Count * 100, 2)
        }
    }
}

function Generate-HTMLReport {
    param([hashtable]$Results, [string]$OutputPath)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Nginx 로그 분석 리포트</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 10px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .summary-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-box.success { background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%); }
        .summary-box.warning { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        .summary-box.error { background: linear-gradient(135deg, #fa709a 0%, #fee140 100%); }
        .summary-box h3 { margin: 0; font-size: 14px; opacity: 0.9; }
        .summary-box .value { font-size: 32px; font-weight: bold; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
        .badge-success { background: #2ecc71; color: white; }
        .badge-warning { background: #f39c12; color: white; }
        .badge-error { background: #e74c3c; color: white; }
        .chart { margin: 20px 0; }
        .bar { height: 30px; background: #3498db; margin: 5px 0; border-radius: 4px; display: flex; align-items: center; padding-left: 10px; color: white; }
        .timestamp { color: #7f8c8d; font-size: 12px; text-align: right; margin-top: 30px; }
    </style>
</head>
<body>
<div class="container">
    <h1>🔍 Nginx 로그 분석 리포트</h1>

    <div class="summary">
        <div class="summary-box">
            <h3>총 요청 수</h3>
            <div class="value">$($Results.Summary.TotalRequests)</div>
        </div>
        <div class="summary-box success">
            <h3>성공률 (2xx/3xx)</h3>
            <div class="value">$($Results.Summary.SuccessRate)%</div>
        </div>
        <div class="summary-box warning">
            <h3>에러율</h3>
            <div class="value">$($Results.Summary.ErrorRate)%</div>
        </div>
        <div class="summary-box error">
            <h3>보안 이벤트</h3>
            <div class="value">$($Results.Summary.SecurityEventCount)</div>
        </div>
    </div>

    <h2>📊 HTTP 상태 코드 분석</h2>
    <table>
        <tr><th>상태 코드</th><th>횟수</th><th>비율</th></tr>
"@

    foreach ($code in ($Results.HTTPStatus.StatusCodes.Keys | Sort-Object)) {
        $data = $Results.HTTPStatus.StatusCodes[$code]
        $badgeClass = if ($code -ge 500) { "badge-error" } elseif ($code -ge 400) { "badge-warning" } else { "badge-success" }
        $html += @"
        <tr>
            <td><span class="badge $badgeClass">$code</span></td>
            <td>$($data.Count)</td>
            <td>$($data.Percent)%</td>
        </tr>
"@
    }

    $html += @"
    </table>

    <h2>🌐 Top $ShowTopN IP 주소</h2>
    <table>
        <tr><th>순위</th><th>IP 주소</th><th>요청 수</th><th>비율</th></tr>
"@

    $rank = 1
    foreach ($ip in $Results.TopIPs) {
        $html += @"
        <tr>
            <td>$rank</td>
            <td>$($ip.Value)</td>
            <td>$($ip.Count)</td>
            <td>$($ip.Percent)%</td>
        </tr>
"@
        $rank++
    }

    $html += @"
    </table>

    <h2>🔗 Top $ShowTopN URL</h2>
    <table>
        <tr><th>순위</th><th>URL</th><th>요청 수</th><th>비율</th></tr>
"@

    $rank = 1
    foreach ($url in $Results.TopURLs) {
        $html += @"
        <tr>
            <td>$rank</td>
            <td>$($url.Value)</td>
            <td>$($url.Count)</td>
            <td>$($url.Percent)%</td>
        </tr>
"@
        $rank++
    }

    $html += @"
    </table>

    <h2>🚨 보안 이벤트</h2>
"@

    if ($Results.SecurityEvents.Count -gt 0) {
        $html += @"
        <table>
            <tr><th>시간</th><th>IP</th><th>URL</th><th>패턴</th></tr>
"@
        foreach ($event in ($Results.SecurityEvents | Select-Object -First 50)) {
            $html += @"
            <tr>
                <td>$($event.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td>
                <td>$($event.IP)</td>
                <td style="max-width: 400px; overflow: hidden; text-overflow: ellipsis;">$($event.URL)</td>
                <td><span class="badge badge-error">$($event.Pattern)</span></td>
            </tr>
"@
        }
        $html += "</table>"
    } else {
        $html += "<p>✓ 보안 이벤트가 감지되지 않았습니다.</p>"
    }

    $html += @"
    <div class="timestamp">
        리포트 생성 시각: $($Results.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))<br>
        분석 범위: $AnalysisType ($windowMins분)
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
Write-ColorOutput "Nginx 로그 분석기 v1.0" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

# 시간 범위 설정
$windowMins = Get-TimeWindowMinutes
$startTime = (Get-Date).AddMinutes(-$windowMins)

Write-ColorOutput "분석 유형: $AnalysisType (최근 $windowMins분)" -Level INFO
Write-ColorOutput "시작 시간: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO

# 로그 파일 찾기
$accessLog = Join-Path $LogPath "access.log"
$errorLog = Join-Path $LogPath "error.log"

# Access 로그 파싱
$accessEntries = Parse-AccessLog -LogFile $accessLog -StartTime $startTime

# Error 로그 파싱
$errorEntries = Parse-ErrorLog -LogFile $errorLog -StartTime $startTime

# 분석
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
Write-ColorOutput "분석 시작..." -Level INFO

# HTTP 상태 코드
$httpAnalysis = Analyze-HTTPStatus -AccessEntries $accessEntries
$Global:Results.HTTPStatus = $httpAnalysis

# 에러 패턴
$errorPatterns = Analyze-ErrorPatterns -ErrorEntries $errorEntries
foreach ($pattern in $errorPatterns.Keys) {
    $Global:Results.ErrorEvents += @{
        Pattern = $pattern
        Count = $errorPatterns[$pattern]
    }
}

# 보안 이벤트
$Global:Results.SecurityEvents = Analyze-SecurityEvents -AccessEntries $accessEntries

# Top N 분석
$Global:Results.TopIPs = Get-TopN -Entries $accessEntries -Property "IP" -TopN $ShowTopN
$Global:Results.TopURLs = Get-TopN -Entries $accessEntries -Property "URL" -TopN $ShowTopN
$Global:Results.TopUserAgents = Get-TopN -Entries $accessEntries -Property "UserAgent" -TopN $ShowTopN

# 요약
$Global:Results.Summary = @{
    TotalRequests = $accessEntries.Count
    SuccessRate = [math]::Round((($httpAnalysis.Categories["2xx (Success)"] + $httpAnalysis.Categories["3xx (Redirect)"]) / $accessEntries.Count * 100), 2)
    ErrorRate = $httpAnalysis.ErrorRate
    SecurityEventCount = $Global:Results.SecurityEvents.Count
    ErrorEventCount = $Global:Results.ErrorEvents.Count
}

# 결과 출력
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
Write-ColorOutput "📊 분석 결과" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS

Write-Host ""
Write-Host "[ 요약 ]" -ForegroundColor Yellow
Write-Host "  총 요청 수: $($Global:Results.Summary.TotalRequests)"
Write-Host "  성공률 (2xx/3xx): " -NoNewline
$successColor = if ($Global:Results.Summary.SuccessRate -ge 95) { "Green" } else { "Yellow" }
Write-Host "$($Global:Results.Summary.SuccessRate)%" -ForegroundColor $successColor

Write-Host "  에러율: " -NoNewline
$errorColor = if ($Global:Results.Summary.ErrorRate -lt 1) { "Green" } elseif ($Global:Results.Summary.ErrorRate -lt 5) { "Yellow" } else { "Red" }
Write-Host "$($Global:Results.Summary.ErrorRate)%" -ForegroundColor $errorColor

Write-Host "  보안 이벤트: " -NoNewline
$secColor = if ($Global:Results.Summary.SecurityEventCount -eq 0) { "Green" } else { "Red" }
Write-Host "$($Global:Results.Summary.SecurityEventCount)개" -ForegroundColor $secColor

Write-Host ""
Write-Host "[ Top $ShowTopN IP ]" -ForegroundColor Yellow
foreach ($ip in $Global:Results.TopIPs) {
    Write-Host "  $($ip.Value): $($ip.Count) ($($ip.Percent)%)"
}

Write-Host ""
Write-Host "[ Top $ShowTopN URL ]" -ForegroundColor Yellow
foreach ($url in $Global:Results.TopURLs) {
    $urlDisplay = if ($url.Value.Length -gt 60) { $url.Value.Substring(0, 60) + "..." } else { $url.Value }
    Write-Host "  $urlDisplay`: $($url.Count) ($($url.Percent)%)"
}

if ($Global:Results.ErrorEvents.Count -gt 0) {
    Write-Host ""
    Write-Host "[ 에러 패턴 ]" -ForegroundColor Red
    foreach ($error in $Global:Results.ErrorEvents) {
        Write-Host "  $($error.Pattern): $($error.Count)회" -ForegroundColor Red
    }
}

if ($Global:Results.SecurityEvents.Count -gt 0) {
    Write-Host ""
    Write-Host "[ 보안 이벤트 (최근 10개) ]" -ForegroundColor Red
    $Global:Results.SecurityEvents | Select-Object -First 10 | ForEach-Object {
        Write-Host "  [$($_.Time.ToString('HH:mm:ss'))] $($_.IP) → $($_.Pattern)" -ForegroundColor Red
    }
}

# 알람 확인
if ($Global:Results.Summary.ErrorRate -gt $AlertOnErrors) {
    Write-ColorOutput "⚠ 경고: 에러율이 임계값을 초과했습니다! ($($Global:Results.Summary.ErrorRate)% > $AlertOnErrors%)" -Level ERROR
}

# HTML 리포트 생성
if ($ExportReport) {
    Generate-HTMLReport -Results $Global:Results -OutputPath $ExportReport
}

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
Write-ColorOutput "분석 완료" -Level SUCCESS
