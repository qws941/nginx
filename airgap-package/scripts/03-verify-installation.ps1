#Requires -RunAsAdministrator
<#
.SYNOPSIS
    에어갭 환경 설치 검증 스크립트

.DESCRIPTION
    설치된 모든 구성요소를 검증하고 상태를 보고합니다.
    - Node.js 및 npm
    - Nginx
    - NSSM
    - DNS 서버
    - 방화벽 규칙
    - SSL 인증서

.EXAMPLE
    .\03-verify-installation.ps1
    .\03-verify-installation.ps1 -Detailed
#>

param(
    [switch]$Detailed,
    [switch]$ExportReport,
    [string]$NginxPath = "C:\nginx"
)

#region Configuration

$Script:TestResults = @()
$Script:Warnings = @()
$Script:Errors = @()

#endregion

#region Helper Functions

function Write-TestResult {
    param(
        [string]$Category,
        [string]$Test,
        [bool]$Passed,
        [string]$Message = "",
        [string]$Details = ""
    )

    $status = if ($Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }

    $result = [PSCustomObject]@{
        Category = $Category
        Test = $Test
        Status = $status
        Passed = $Passed
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }

    $Script:TestResults += $result

    Write-Host "  [$status] $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "        $Message" -ForegroundColor Gray
    }
    if ($Detailed -and $Details) {
        Write-Host "        $Details" -ForegroundColor DarkGray
    }

    if (-not $Passed) {
        $Script:Errors += "$Category - $Test: $Message"
    }
}

function Write-Warning {
    param([string]$Message)

    $Script:Warnings += $Message
    Write-Host "  [⚠] $Message" -ForegroundColor Yellow
}

#endregion

#region Banner

Write-Host @"
================================================================================
              에어갭 환경 설치 검증 도구
================================================================================
  검증 항목:
    ✓ Node.js 및 npm
    ✓ Nginx 웹서버
    ✓ NSSM 서비스 관리자
    ✓ DNS 서버
    ✓ 방화벽 규칙
    ✓ SSL 인증서
    ✓ 환경변수
    ✓ 디렉토리 구조

  검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================
"@ -ForegroundColor Cyan

#endregion

#region Test 1: Node.js 및 npm

Write-Host "`n[1/8] Node.js 및 npm 검증" -ForegroundColor Yellow

try {
    $nodeCmd = Get-Command node -ErrorAction Stop
    $nodeVersion = & node --version
    Write-TestResult -Category "Node.js" -Test "Node.js 설치" -Passed $true -Message "버전: $nodeVersion" -Details "경로: $($nodeCmd.Source)"

    $npmCmd = Get-Command npm -ErrorAction Stop
    $npmVersion = & npm --version
    Write-TestResult -Category "Node.js" -Test "npm 설치" -Passed $true -Message "버전: $npmVersion" -Details "경로: $($npmCmd.Source)"

    # npm 글로벌 경로 확인
    $npmPrefix = & npm config get prefix
    Write-TestResult -Category "Node.js" -Test "npm 글로벌 경로" -Passed $true -Message $npmPrefix

    # 글로벌 패키지 확인
    $globalPackages = & npm list -g --depth=0 2>$null
    if ($globalPackages) {
        $packageCount = ($globalPackages | Select-String "├──" | Measure-Object).Count
        Write-TestResult -Category "Node.js" -Test "npm 글로벌 패키지" -Passed $true -Message "$packageCount 개 설치됨"
    }

} catch {
    Write-TestResult -Category "Node.js" -Test "Node.js 설치" -Passed $false -Message "Node.js를 찾을 수 없습니다"
}

#endregion

#region Test 2: Nginx

Write-Host "`n[2/8] Nginx 검증" -ForegroundColor Yellow

$nginxExe = Join-Path $NginxPath "nginx.exe"
if (Test-Path $nginxExe) {
    Write-TestResult -Category "Nginx" -Test "Nginx 설치" -Passed $true -Message "경로: $nginxExe"

    # 버전 확인
    try {
        $nginxVersion = & $nginxExe -v 2>&1
        $versionString = ($nginxVersion -split '/')[1]
        Write-TestResult -Category "Nginx" -Test "Nginx 버전" -Passed $true -Message $versionString
    } catch {
        Write-Warning "Nginx 버전 확인 실패"
    }

    # 설정 파일 확인
    $nginxConf = Join-Path $NginxPath "conf\nginx.conf"
    if (Test-Path $nginxConf) {
        Write-TestResult -Category "Nginx" -Test "nginx.conf" -Passed $true -Message "설정 파일 존재"

        # 설정 파일 구문 검사
        try {
            $testResult = & $nginxExe -t -c $nginxConf 2>&1
            $syntaxOk = $testResult -match "syntax is ok"
            Write-TestResult -Category "Nginx" -Test "설정 구문" -Passed $syntaxOk -Message $(if($syntaxOk){"구문 정상"}else{"구문 오류"})
        } catch {
            Write-TestResult -Category "Nginx" -Test "설정 구문" -Passed $false -Message "검사 실패"
        }
    } else {
        Write-TestResult -Category "Nginx" -Test "nginx.conf" -Passed $false -Message "설정 파일 없음"
    }

    # 필수 디렉토리 확인
    $requiredDirs = @("conf", "conf\ssl", "conf\conf.d", "logs", "temp")
    foreach ($dir in $requiredDirs) {
        $fullPath = Join-Path $NginxPath $dir
        $exists = Test-Path $fullPath
        Write-TestResult -Category "Nginx" -Test "디렉토리: $dir" -Passed $exists -Message $(if($exists){"존재"}else{"없음"})
    }

} else {
    Write-TestResult -Category "Nginx" -Test "Nginx 설치" -Passed $false -Message "nginx.exe를 찾을 수 없습니다"
}

# Nginx 서비스 확인
$nginxService = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
if ($nginxService) {
    $running = $nginxService.Status -eq "Running"
    Write-TestResult -Category "Nginx" -Test "Nginx 서비스" -Passed $true -Message "상태: $($nginxService.Status)" -Details "시작 유형: $($nginxService.StartType)"

    if (-not $running) {
        Write-Warning "Nginx 서비스가 실행 중이 아닙니다. 'Start-Service nginx' 명령으로 시작하세요."
    }
} else {
    Write-TestResult -Category "Nginx" -Test "Nginx 서비스" -Passed $false -Message "서비스 미등록"
    Write-Warning "NSSM으로 Nginx 서비스를 등록하세요."
}

#endregion

#region Test 3: NSSM

Write-Host "`n[3/8] NSSM 검증" -ForegroundColor Yellow

$nssmExe = Join-Path $NginxPath "nssm.exe"
if (Test-Path $nssmExe) {
    Write-TestResult -Category "NSSM" -Test "NSSM 설치" -Passed $true -Message "경로: $nssmExe"

    try {
        $nssmVersion = & $nssmExe version 2>&1
        Write-TestResult -Category "NSSM" -Test "NSSM 버전" -Passed $true -Message "$nssmVersion"
    } catch {
        Write-Warning "NSSM 버전 확인 실패"
    }
} else {
    Write-TestResult -Category "NSSM" -Test "NSSM 설치" -Passed $false -Message "nssm.exe를 찾을 수 없습니다"
}

#endregion

#region Test 4: DNS 서버

Write-Host "`n[4/8] DNS 서버 검증" -ForegroundColor Yellow

try {
    $dnsFeature = Get-WindowsFeature -Name DNS -ErrorAction Stop
    $installed = $dnsFeature.InstallState -eq "Installed"
    Write-TestResult -Category "DNS" -Test "DNS 서버 기능" -Passed $installed -Message $(if($installed){"설치됨"}else{"미설치"})

    if ($installed) {
        $dnsService = Get-Service -Name DNS -ErrorAction SilentlyContinue
        if ($dnsService) {
            $running = $dnsService.Status -eq "Running"
            Write-TestResult -Category "DNS" -Test "DNS 서비스" -Passed $running -Message "상태: $($dnsService.Status)"
        }
    }
} catch {
    Write-TestResult -Category "DNS" -Test "DNS 서버 기능" -Passed $false -Message "확인 불가 (Windows Server 아님)"
}

#endregion

#region Test 5: 방화벽 규칙

Write-Host "`n[5/8] 방화벽 규칙 검증" -ForegroundColor Yellow

$requiredRules = @(
    @{Name="DNS Server (TCP-In)"; Port=53},
    @{Name="DNS Server (UDP-In)"; Port=53},
    @{Name="Nginx HTTP (TCP-In)"; Port=80},
    @{Name="Nginx HTTPS (TCP-In)"; Port=443},
    @{Name="Node.js App (TCP-In)"; Port=3000}
)

foreach ($rule in $requiredRules) {
    try {
        $fwRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction Stop
        $enabled = $fwRule.Enabled -eq $true
        Write-TestResult -Category "Firewall" -Test $rule.Name -Passed $enabled -Message $(if($enabled){"활성"}else{"비활성"})
    } catch {
        Write-TestResult -Category "Firewall" -Test $rule.Name -Passed $false -Message "규칙 없음"
    }
}

#endregion

#region Test 6: SSL 인증서

Write-Host "`n[6/8] SSL 인증서 검증" -ForegroundColor Yellow

$sslPath = Join-Path $NginxPath "conf\ssl"
if (Test-Path $sslPath) {
    Write-TestResult -Category "SSL" -Test "SSL 디렉토리" -Passed $true -Message "경로: $sslPath"

    # 인증서 파일 확인
    $certFiles = @{
        "cert.crt" = "인증서 파일 (.crt)"
        "cert.pem" = "인증서 파일 (.pem)"
        "cert.key" = "개인키 파일"
    }

    $certExists = $false
    foreach ($file in $certFiles.Keys) {
        $filePath = Join-Path $sslPath $file
        $exists = Test-Path $filePath

        if ($exists) {
            $fileInfo = Get-Item $filePath
            $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
            Write-TestResult -Category "SSL" -Test $certFiles[$file] -Passed $true -Message "$file ($sizeKB KB)"

            if ($file -match "^cert\.(crt|pem)$") {
                $certExists = $true
            }
        }
    }

    if (-not $certExists) {
        Write-Warning "SSL 인증서 파일이 없습니다. cert.crt 또는 cert.pem 파일을 추가하세요."
    }

    if (-not (Test-Path (Join-Path $sslPath "cert.key"))) {
        Write-Warning "SSL 개인키 파일이 없습니다. cert.key 파일을 추가하세요."
    }

} else {
    Write-TestResult -Category "SSL" -Test "SSL 디렉토리" -Passed $false -Message "디렉토리 없음"
}

#endregion

#region Test 7: 환경변수

Write-Host "`n[7/8] 환경변수 검증" -ForegroundColor Yellow

$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

$expectedPaths = @(
    "C:\Program Files\nodejs",
    "C:\nodejs-global",
    $NginxPath
)

foreach ($path in $expectedPaths) {
    $inPath = $currentPath -like "*$path*"
    Write-TestResult -Category "Environment" -Test "PATH: $path" -Passed $inPath -Message $(if($inPath){"포함됨"}else{"없음"})
}

#endregion

#region Test 8: 포트 가용성

Write-Host "`n[8/8] 포트 가용성 검증" -ForegroundColor Yellow

$portsToCheck = @(
    @{Port=53; Name="DNS"},
    @{Port=80; Name="HTTP"},
    @{Port=443; Name="HTTPS"},
    @{Port=3000; Name="Node.js"}
)

foreach ($portCheck in $portsToCheck) {
    try {
        $listeners = Get-NetTCPConnection -LocalPort $portCheck.Port -ErrorAction SilentlyContinue
        if ($listeners) {
            $processId = $listeners[0].OwningProcess
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            $processName = if ($process) { $process.ProcessName } else { "Unknown" }
            Write-TestResult -Category "Port" -Test "포트 $($portCheck.Port) ($($portCheck.Name))" -Passed $true -Message "사용 중: $processName"
        } else {
            Write-TestResult -Category "Port" -Test "포트 $($portCheck.Port) ($($portCheck.Name))" -Passed $false -Message "사용 가능"
        }
    } catch {
        Write-TestResult -Category "Port" -Test "포트 $($portCheck.Port) ($($portCheck.Name))" -Passed $false -Message "확인 불가"
    }
}

#endregion

#region 결과 요약

Write-Host "`n" -NoNewline
Write-Host "="*80 -ForegroundColor Cyan
Write-Host "                           검증 결과 요약" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan

$passedTests = ($Script:TestResults | Where-Object { $_.Passed }).Count
$failedTests = ($Script:TestResults | Where-Object { -not $_.Passed }).Count
$totalTests = $Script:TestResults.Count

$successRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }

Write-Host "`n통과율: $successRate% ($passedTests/$totalTests 성공)" -ForegroundColor $(if($successRate -ge 80){"Green"}elseif($successRate -ge 60){"Yellow"}else{"Red"})

if ($failedTests -gt 0) {
    Write-Host "`n실패한 테스트: $failedTests 개" -ForegroundColor Red
    foreach ($error in $Script:Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
}

if ($Script:Warnings.Count -gt 0) {
    Write-Host "`n경고: $($Script:Warnings.Count) 개" -ForegroundColor Yellow
    foreach ($warning in $Script:Warnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
}

# 카테고리별 요약
Write-Host "`n카테고리별 결과:" -ForegroundColor Cyan
$categories = $Script:TestResults | Group-Object -Property Category
foreach ($cat in $categories) {
    $catPassed = ($cat.Group | Where-Object { $_.Passed }).Count
    $catTotal = $cat.Count
    $catRate = [math]::Round(($catPassed / $catTotal) * 100, 0)

    $icon = if ($catRate -eq 100) { "✓" } elseif ($catRate -ge 80) { "◐" } else { "✗" }
    $color = if ($catRate -eq 100) { "Green" } elseif ($catRate -ge 80) { "Yellow" } else { "Red" }

    Write-Host "  [$icon] $($cat.Name): $catPassed/$catTotal ($catRate%)" -ForegroundColor $color
}

#endregion

#region 권장사항

Write-Host "`n" -NoNewline
Write-Host "="*80 -ForegroundColor Cyan
Write-Host "                           권장사항" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan

$recommendations = @()

if ($failedTests -gt 0) {
    $recommendations += "실패한 테스트를 해결하세요."
}

if (-not (Get-Service -Name "nginx" -ErrorAction SilentlyContinue)) {
    $recommendations += "Nginx 서비스를 등록하세요: cd $NginxPath; .\nssm.exe install nginx `"$NginxPath\nginx.exe`""
}

$nginxService = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
if ($nginxService -and $nginxService.Status -ne "Running") {
    $recommendations += "Nginx 서비스를 시작하세요: Start-Service nginx"
}

if (-not (Test-Path "$NginxPath\conf\ssl\cert.key")) {
    $recommendations += "SSL 인증서를 설치하세요: $NginxPath\conf\ssl\"
}

if ($recommendations.Count -gt 0) {
    Write-Host "`n다음 작업을 수행하세요:" -ForegroundColor Yellow
    $i = 1
    foreach ($rec in $recommendations) {
        Write-Host "  $i. $rec" -ForegroundColor Yellow
        $i++
    }
} else {
    Write-Host "`n✓ 모든 구성요소가 정상입니다!" -ForegroundColor Green
    Write-Host "  이제 nginx-proxy-manager.ps1로 서비스를 관리할 수 있습니다." -ForegroundColor Cyan
}

#endregion

#region 보고서 내보내기

if ($ExportReport) {
    $reportPath = Join-Path $PSScriptRoot "..\logs\verification-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

    $report = @{
        Timestamp = Get-Date
        TestResults = $Script:TestResults
        Warnings = $Script:Warnings
        Errors = $Script:Errors
        Summary = @{
            Total = $totalTests
            Passed = $passedTests
            Failed = $failedTests
            SuccessRate = $successRate
        }
        Recommendations = $recommendations
    }

    $report | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
    Write-Host "`n보고서 저장: $reportPath" -ForegroundColor Green
}

#endregion

Write-Host "`n" -NoNewline
Write-Host "="*80 -ForegroundColor Cyan
Write-Host ""

# 종료 코드 설정
if ($failedTests -eq 0) {
    exit 0
} else {
    exit 1
}
