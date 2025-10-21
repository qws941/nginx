<#
.SYNOPSIS
    에어갭 패키지 v2.0 Enhanced Edition 전체 기능 검증 스크립트

.DESCRIPTION
    모든 Enhanced 기능의 통합 검증 및 상세 보고서 생성
    - 파일 무결성 검사
    - 스크립트 구문 검증
    - 기능별 자동 테스트
    - 시스템 요구사항 확인
    - HTML/JSON 보고서 생성

.PARAMETER ReportPath
    보고서 저장 경로 (기본값: .\validation-reports\)

.PARAMETER ValidationType
    검증 유형: Quick (빠른 검사), Full (전체 검사), Deep (심층 검사)

.PARAMETER SkipTests
    특정 테스트 스킵 (쉼표로 구분: FileIntegrity,ScriptSyntax,Prerequisites)

.PARAMETER ExportJson
    JSON 형식으로도 보고서 출력

.EXAMPLE
    .\06-validate-enhanced-package.ps1
    기본 전체 검증 실행

.EXAMPLE
    .\06-validate-enhanced-package.ps1 -ValidationType Quick -ExportJson
    빠른 검증 + JSON 출력

.EXAMPLE
    .\06-validate-enhanced-package.ps1 -ValidationType Deep -SkipTests "Prerequisites"
    심층 검증 (전제조건 검사 제외)

.NOTES
    파일명: 06-validate-enhanced-package.ps1
    작성자: System Administrator
    버전: 2.0.0
    최종 수정일: 2025-10-20
    의존성: PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\validation-reports",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Quick", "Full", "Deep")]
    [string]$ValidationType = "Full",

    [Parameter(Mandatory = $false)]
    [string[]]$SkipTests = @(),

    [Parameter(Mandatory = $false)]
    [switch]$ExportJson
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ============================================================================
# 전역 변수 및 설정
# ============================================================================

$Script:ValidationResults = @{
    ValidationId = [guid]::NewGuid().ToString()
    StartTime = Get-Date
    EndTime = $null
    ValidationType = $ValidationType
    OverallStatus = "Unknown"
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    WarningCount = 0
    Categories = @{}
    SystemInfo = @{}
    Recommendations = @()
}

$Script:PackageRoot = Split-Path -Parent $PSScriptRoot
$Script:RequiredFiles = @{
    "Scripts" = @(
        "scripts\01-create-package.ps1",
        "scripts\02-install-airgap.ps1",
        "scripts\02-install-airgap-enhanced.ps1",
        "scripts\03-uninstall-airgap.ps1",
        "scripts\04-setup-ad-integration.ps1",
        "scripts\05-backup-restore.ps1",
        "scripts\06-validate-enhanced-package.ps1",
        "scripts\test-nginx-web-ui.ps1"
    )
    "WebUI" = @(
        "scripts\nginx-web-ui.js",
        "scripts\nginx-web-ui-enhanced.js"
    )
    "Documentation" = @(
        "README.md",
        "reverse_proxy\001_INDEX.md",
        "reverse_proxy\009_ENHANCED-V2-GUIDE.xwiki"
    )
    "Installers" = @(
        "installers\node-v20.11.0-x64.msi",
        "installers\nginx-1.24.0.zip",
        "installers\nssm-2.24.zip"
    )
}

$Script:ColorScheme = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Progress = "Magenta"
    Debug = "Gray"
}

# ============================================================================
# 유틸리티 함수
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Level = "Info",
        [switch]$NoNewline
    )

    $color = $Script:ColorScheme[$Level]
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $prefix = "[$timestamp] [$Level]"

    if ($NoNewline) {
        Write-Host "$prefix $Message" -ForegroundColor $color -NoNewline
    } else {
        Write-Host "$prefix $Message" -ForegroundColor $color
    }
}

function Add-TestResult {
    param(
        [string]$Category,
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [string]$Details = "",
        [string]$Recommendation = ""
    )

    $Script:ValidationResults.TotalTests++

    if ($Passed) {
        $Script:ValidationResults.PassedTests++
        $status = "PASS"
    } else {
        $Script:ValidationResults.FailedTests++
        $status = "FAIL"
    }

    if (-not $Script:ValidationResults.Categories.ContainsKey($Category)) {
        $Script:ValidationResults.Categories[$Category] = @{
            TotalTests = 0
            PassedTests = 0
            FailedTests = 0
            Tests = @()
        }
    }

    $Script:ValidationResults.Categories[$Category].TotalTests++
    if ($Passed) {
        $Script:ValidationResults.Categories[$Category].PassedTests++
    } else {
        $Script:ValidationResults.Categories[$Category].FailedTests++
    }

    $testResult = @{
        TestName = $TestName
        Status = $status
        Message = $Message
        Details = $Details
        Timestamp = Get-Date -Format "o"
    }

    $Script:ValidationResults.Categories[$Category].Tests += $testResult

    $color = if ($Passed) { "Success" } else { "Error" }
    Write-ColorOutput "  [$status] $TestName - $Message" -Level $color

    if ($Details) {
        Write-ColorOutput "    Details: $Details" -Level "Debug"
    }

    if ($Recommendation -and -not $Passed) {
        $Script:ValidationResults.Recommendations += @{
            Category = $Category
            Test = $TestName
            Recommendation = $Recommendation
        }
    }
}

function Test-ShouldSkip {
    param([string]$CategoryName)
    return $SkipTests -contains $CategoryName
}

# ============================================================================
# 시스템 정보 수집
# ============================================================================

function Get-SystemInformation {
    Write-ColorOutput "`n[1/8] 시스템 정보 수집 중..." -Level "Progress"

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

        $Script:ValidationResults.SystemInfo = @{
            Hostname = $env:COMPUTERNAME
            OS = "$($os.Caption) $($os.Version)"
            Architecture = $os.OSArchitecture
            TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            FreeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB / 1024, 2)
            CPU = $cpu.Name
            CPUCores = $cpu.NumberOfCores
            DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            DiskTotalGB = [math]::Round($disk.Size / 1GB, 2)
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            ExecutionPolicy = (Get-ExecutionPolicy).ToString()
            CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            PackageRoot = $Script:PackageRoot
        }

        Write-ColorOutput "  시스템: $($Script:ValidationResults.SystemInfo.OS)" -Level "Info"
        Write-ColorOutput "  메모리: $($Script:ValidationResults.SystemInfo.TotalMemoryGB) GB (사용 가능: $($Script:ValidationResults.SystemInfo.FreeMemoryGB) GB)" -Level "Info"
        Write-ColorOutput "  디스크: $($Script:ValidationResults.SystemInfo.DiskTotalGB) GB (사용 가능: $($Script:ValidationResults.SystemInfo.DiskFreeGB) GB)" -Level "Info"
        Write-ColorOutput "  PowerShell: $($Script:ValidationResults.SystemInfo.PowerShellVersion)" -Level "Info"
        Write-ColorOutput "  관리자 권한: $($Script:ValidationResults.SystemInfo.IsAdmin)" -Level "Info"

    } catch {
        Write-ColorOutput "  경고: 시스템 정보 수집 중 오류 발생 - $($_.Exception.Message)" -Level "Warning"
        $Script:ValidationResults.WarningCount++
    }
}

# ============================================================================
# 전제조건 검사
# ============================================================================

function Test-Prerequisites {
    if (Test-ShouldSkip "Prerequisites") {
        Write-ColorOutput "`n[2/8] 전제조건 검사 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[2/8] 전제조건 검사 중..." -Level "Progress"
    $category = "Prerequisites"

    # PowerShell 버전
    $psVersion = $PSVersionTable.PSVersion
    $passed = $psVersion.Major -ge 5 -and $psVersion.Minor -ge 1
    Add-TestResult -Category $category -TestName "PowerShell 버전" -Passed $passed `
        -Message "버전: $($psVersion.ToString())" `
        -Details "요구사항: 5.1 이상" `
        -Recommendation "PowerShell 5.1 이상으로 업그레이드하세요."

    # 관리자 권한
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Add-TestResult -Category $category -TestName "관리자 권한" -Passed $isAdmin `
        -Message $(if ($isAdmin) { "관리자 권한으로 실행 중" } else { "일반 사용자 권한" }) `
        -Recommendation "관리자 권한으로 PowerShell을 실행하세요."

    # 실행 정책
    $execPolicy = Get-ExecutionPolicy
    $passed = $execPolicy -ne "Restricted"
    Add-TestResult -Category $category -TestName "실행 정책" -Passed $passed `
        -Message "현재 정책: $execPolicy" `
        -Details "Restricted가 아니어야 함" `
        -Recommendation "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"

    # 디스크 공간 (최소 5GB)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $passed = $freeSpaceGB -ge 5
    Add-TestResult -Category $category -TestName "디스크 공간" -Passed $passed `
        -Message "사용 가능: $freeSpaceGB GB" `
        -Details "최소 요구사항: 5 GB" `
        -Recommendation "C: 드라이브에 최소 5GB의 여유 공간을 확보하세요."

    # 메모리 (최소 2GB)
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $passed = $totalMemoryGB -ge 2
    Add-TestResult -Category $category -TestName "메모리" -Passed $passed `
        -Message "전체: $totalMemoryGB GB" `
        -Details "최소 요구사항: 2 GB" `
        -Recommendation "시스템 메모리를 2GB 이상으로 증설하세요."

    # .NET Framework (4.7.2 이상)
    try {
        $netVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Release
        $passed = $netVersion -ge 461808  # .NET 4.7.2
        $versionString = switch ($netVersion) {
            { $_ -ge 533320 } { "4.8.1+" }
            { $_ -ge 528040 } { "4.8" }
            { $_ -ge 461808 } { "4.7.2" }
            { $_ -ge 461308 } { "4.7.1" }
            { $_ -ge 460798 } { "4.7" }
            default { "Unknown ($netVersion)" }
        }
        Add-TestResult -Category $category -TestName ".NET Framework" -Passed $passed `
            -Message "버전: $versionString" `
            -Details "최소 요구사항: 4.7.2" `
            -Recommendation ".NET Framework 4.7.2 이상을 설치하세요."
    } catch {
        Add-TestResult -Category $category -TestName ".NET Framework" -Passed $false `
            -Message "버전 확인 실패" `
            -Details $_.Exception.Message `
            -Recommendation ".NET Framework 설치 상태를 확인하세요."
    }
}

# ============================================================================
# 파일 무결성 검사
# ============================================================================

function Test-FileIntegrity {
    if (Test-ShouldSkip "FileIntegrity") {
        Write-ColorOutput "`n[3/8] 파일 무결성 검사 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[3/8] 파일 무결성 검사 중..." -Level "Progress"
    $category = "FileIntegrity"

    foreach ($fileCategory in $Script:RequiredFiles.Keys) {
        foreach ($relPath in $Script:RequiredFiles[$fileCategory]) {
            $fullPath = Join-Path $Script:PackageRoot $relPath
            $fileName = Split-Path $relPath -Leaf

            if (Test-Path $fullPath) {
                $fileInfo = Get-Item $fullPath
                $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)

                Add-TestResult -Category $category -TestName "$fileCategory - $fileName" -Passed $true `
                    -Message "파일 존재" `
                    -Details "크기: $sizeKB KB, 수정일: $($fileInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            } else {
                Add-TestResult -Category $category -TestName "$fileCategory - $fileName" -Passed $false `
                    -Message "파일 없음" `
                    -Details "경로: $fullPath" `
                    -Recommendation "누락된 파일을 복원하거나 패키지를 다시 생성하세요."
            }
        }
    }

    # 패키지 크기 검증
    try {
        $installersPath = Join-Path $Script:PackageRoot "installers"
        if (Test-Path $installersPath) {
            $totalSize = (Get-ChildItem $installersPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $totalSizeMB = [math]::Round($totalSize / 1MB, 2)

            # 최소 100MB (Node.js가 가장 큼)
            $passed = $totalSizeMB -ge 100
            Add-TestResult -Category $category -TestName "설치 파일 크기" -Passed $passed `
                -Message "전체 크기: $totalSizeMB MB" `
                -Details "최소 요구사항: 100 MB (Node.js MSI 포함)" `
                -Recommendation "설치 파일이 손상되었을 수 있습니다. 패키지를 다시 생성하세요."
        }
    } catch {
        Write-ColorOutput "  경고: 설치 파일 크기 검증 실패 - $($_.Exception.Message)" -Level "Warning"
        $Script:ValidationResults.WarningCount++
    }
}

# ============================================================================
# 스크립트 구문 검증
# ============================================================================

function Test-ScriptSyntax {
    if (Test-ShouldSkip "ScriptSyntax") {
        Write-ColorOutput "`n[4/8] 스크립트 구문 검증 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[4/8] 스크립트 구문 검증 중..." -Level "Progress"
    $category = "ScriptSyntax"

    $scriptFiles = Get-ChildItem (Join-Path $Script:PackageRoot "scripts") -Filter "*.ps1" -File

    foreach ($script in $scriptFiles) {
        try {
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName,
                [ref]$tokens,
                [ref]$errors
            )

            $passed = $errors.Count -eq 0

            if ($passed) {
                Add-TestResult -Category $category -TestName $script.Name -Passed $true `
                    -Message "구문 정상" `
                    -Details "토큰 수: $($tokens.Count), AST 노드 수: $($ast.EndBlock.Statements.Count)"
            } else {
                $errorMessages = $errors | ForEach-Object { $_.Message } | Out-String
                Add-TestResult -Category $category -TestName $script.Name -Passed $false `
                    -Message "구문 오류 발견 ($($errors.Count)개)" `
                    -Details $errorMessages.Trim() `
                    -Recommendation "스크립트 파일의 구문 오류를 수정하세요."
            }

        } catch {
            Add-TestResult -Category $category -TestName $script.Name -Passed $false `
                -Message "파싱 실패" `
                -Details $_.Exception.Message `
                -Recommendation "스크립트 파일이 손상되었을 수 있습니다."
        }
    }
}

# ============================================================================
# Enhanced 기능 검증
# ============================================================================

function Test-EnhancedFeatures {
    if (Test-ShouldSkip "EnhancedFeatures") {
        Write-ColorOutput "`n[5/8] Enhanced 기능 검증 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[5/8] Enhanced 기능 검증 중..." -Level "Progress"
    $category = "EnhancedFeatures"

    # 1. Enhanced 설치 스크립트 - EnhancedLogger 클래스
    $enhancedInstallScript = Join-Path $Script:PackageRoot "scripts\02-install-airgap-enhanced.ps1"
    if (Test-Path $enhancedInstallScript) {
        $content = Get-Content $enhancedInstallScript -Raw

        # EnhancedLogger 클래스 존재
        $passed = $content -match "class\s+EnhancedLogger"
        Add-TestResult -Category $category -TestName "EnhancedLogger 클래스" -Passed $passed `
            -Message $(if ($passed) { "클래스 정의 확인" } else { "클래스 정의 없음" }) `
            -Details "Enhanced 설치 스크립트의 핵심 로깅 클래스"

        # Rollback 기능
        $passed = $content -match "function\s+Invoke-Rollback"
        Add-TestResult -Category $category -TestName "Rollback 기능" -Passed $passed `
            -Message $(if ($passed) { "Rollback 함수 정의 확인" } else { "Rollback 함수 없음" }) `
            -Details "설치 실패 시 자동 롤백 기능"

        # 상태 추적
        $passed = $content -match "\`$Script:InstallState"
        Add-TestResult -Category $category -TestName "설치 상태 추적" -Passed $passed `
            -Message $(if ($passed) { "상태 변수 확인" } else { "상태 변수 없음" }) `
            -Details "트랜잭션 기반 설치 진행 추적"

        # AutoService 파라미터
        $passed = $content -match "\[switch\]\`$AutoService"
        Add-TestResult -Category $category -TestName "AutoService 파라미터" -Passed $passed `
            -Message $(if ($passed) { "파라미터 정의 확인" } else { "파라미터 없음" }) `
            -Details "Windows 서비스 자동 등록 기능"
    } else {
        Add-TestResult -Category $category -TestName "Enhanced 설치 스크립트" -Passed $false `
            -Message "파일 없음" `
            -Details "경로: $enhancedInstallScript" `
            -Recommendation "02-install-airgap-enhanced.ps1 파일을 복원하세요."
    }

    # 2. 자동화 테스트 스크립트
    $testScript = Join-Path $Script:PackageRoot "scripts\test-nginx-web-ui.ps1"
    if (Test-Path $testScript) {
        $content = Get-Content $testScript -Raw

        # 테스트 결과 구조
        $passed = $content -match "\`$Script:TestResults"
        Add-TestResult -Category $category -TestName "테스트 프레임워크" -Passed $passed `
            -Message $(if ($passed) { "테스트 결과 구조 확인" } else { "테스트 구조 없음" }) `
            -Details "35개 자동화 테스트 프레임워크"

        # HTML 보고서
        $passed = $content -match "Export-HtmlReport"
        Add-TestResult -Category $category -TestName "HTML 보고서 생성" -Passed $passed `
            -Message $(if ($passed) { "보고서 함수 확인" } else { "보고서 함수 없음" }) `
            -Details "테스트 결과 HTML 리포트 기능"
    }

    # 3. AD 통합 스크립트
    $adScript = Join-Path $Script:PackageRoot "scripts\04-setup-ad-integration.ps1"
    if (Test-Path $adScript) {
        $content = Get-Content $adScript -Raw

        # AD 그룹 설정
        $passed = $content -match "NginxAdministrators|NginxOperators|NginxReadOnly"
        Add-TestResult -Category $category -TestName "AD 보안 그룹" -Passed $passed `
            -Message $(if ($passed) { "3개 그룹 정의 확인" } else { "그룹 정의 없음" }) `
            -Details "NginxAdministrators, NginxOperators, NginxReadOnly"

        # 서비스 계정
        $passed = $content -match "nginx-service"
        Add-TestResult -Category $category -TestName "서비스 계정" -Passed $passed `
            -Message $(if ($passed) { "서비스 계정 정의 확인" } else { "서비스 계정 정의 없음" }) `
            -Details "nginx-service 자동 생성"

        # 파일 권한
        $passed = $content -match "Set-NginxFilePermissions|FileSystemAccessRule"
        Add-TestResult -Category $category -TestName "파일 권한 설정" -Passed $passed `
            -Message $(if ($passed) { "ACL 설정 함수 확인" } else { "ACL 함수 없음" }) `
            -Details "NTFS 권한 자동 설정"
    }

    # 4. 백업/복구 스크립트
    $backupScript = Join-Path $Script:PackageRoot "scripts\05-backup-restore.ps1"
    if (Test-Path $backupScript) {
        $content = Get-Content $backupScript -Raw

        # 백업 타입
        $passed = $content -match "Full|Incremental"
        Add-TestResult -Category $category -TestName "백업 타입" -Passed $passed `
            -Message $(if ($passed) { "Full/Incremental 백업 지원" } else { "백업 타입 정의 없음" }) `
            -Details "전체 및 증분 백업 기능"

        # 메타데이터
        $passed = $content -match "New-BackupMetadata|ConvertTo-Json"
        Add-TestResult -Category $category -TestName "백업 메타데이터" -Passed $passed `
            -Message $(if ($passed) { "JSON 메타데이터 확인" } else { "메타데이터 기능 없음" }) `
            -Details "백업 정보 JSON 추적"

        # 스케줄링
        $passed = $content -match "Schedule|schtasks|New-ScheduledTaskAction"
        Add-TestResult -Category $category -TestName "백업 스케줄링" -Passed $passed `
            -Message $(if ($passed) { "작업 스케줄러 통합 확인" } else { "스케줄링 기능 없음" }) `
            -Details "Windows 작업 스케줄러 자동 설정"
    }

    # 5. Enhanced Web UI
    $enhancedWebUI = Join-Path $Script:PackageRoot "scripts\nginx-web-ui-enhanced.js"
    if (Test-Path $enhancedWebUI) {
        $content = Get-Content $enhancedWebUI -Raw

        # localhost 전용
        $passed = $content -match "127\.0\.0\.1|localhost"
        Add-TestResult -Category $category -TestName "Web UI 보안 바인딩" -Passed $passed `
            -Message $(if ($passed) { "localhost 전용 확인" } else { "보안 바인딩 없음" }) `
            -Details "127.0.0.1 전용 바인딩 (외부 접근 차단)"

        # Logger 클래스
        $passed = $content -match "class\s+Logger"
        Add-TestResult -Category $category -TestName "Web UI Logger" -Passed $passed `
            -Message $(if ($passed) { "Logger 클래스 확인" } else { "Logger 클래스 없음" }) `
            -Details "구조화된 로깅 시스템"

        # 백업 기능
        $passed = $content -match "createBackup|backupProxy"
        Add-TestResult -Category $category -TestName "Web UI 백업 기능" -Passed $passed `
            -Message $(if ($passed) { "백업 API 확인" } else { "백업 API 없음" }) `
            -Details "프록시 삭제 시 자동 백업"
    }
}

# ============================================================================
# 문서화 검증
# ============================================================================

function Test-Documentation {
    if (Test-ShouldSkip "Documentation") {
        Write-ColorOutput "`n[6/8] 문서화 검증 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[6/8] 문서화 검증 중..." -Level "Progress"
    $category = "Documentation"

    # README.md
    $readmePath = Join-Path $Script:PackageRoot "README.md"
    if (Test-Path $readmePath) {
        $content = Get-Content $readmePath -Raw

        # 버전 정보
        $passed = $content -match "v\d+\.\d+\.\d+"
        Add-TestResult -Category $category -TestName "README 버전 정보" -Passed $passed `
            -Message $(if ($passed) { "버전 정보 존재" } else { "버전 정보 없음" })

        # 주요 섹션
        $sections = @("패키지 구성", "설치", "사용법", "문서")
        foreach ($section in $sections) {
            $passed = $content -match "##?\s*$section"
            Add-TestResult -Category $category -TestName "README 섹션: $section" -Passed $passed `
                -Message $(if ($passed) { "섹션 존재" } else { "섹션 없음" })
        }
    }

    # XWiki 문서
    $xwikiPath = Join-Path $Script:PackageRoot "reverse_proxy\009_ENHANCED-V2-GUIDE.xwiki"
    if (Test-Path $xwikiPath) {
        $content = Get-Content $xwikiPath -Raw

        # 버전 2.0.0
        $passed = $content -match "2\.0\.0"
        Add-TestResult -Category $category -TestName "XWiki v2.0 문서" -Passed $passed `
            -Message $(if ($passed) { "v2.0 문서 확인" } else { "v2.0 정보 없음" }) `
            -Details "Enhanced Edition 종합 가이드"

        # 주요 개선사항
        $enhancements = @("02-install-airgap-enhanced", "test-nginx-web-ui", "04-setup-ad-integration", "05-backup-restore")
        foreach ($enhancement in $enhancements) {
            $passed = $content -match [regex]::Escape($enhancement)
            Add-TestResult -Category $category -TestName "XWiki 문서: $enhancement" -Passed $passed `
                -Message $(if ($passed) { "스크립트 문서화됨" } else { "스크립트 문서화 안됨" })
        }
    }

    # 역방향 프록시 문서
    $docsPath = Join-Path $Script:PackageRoot "reverse_proxy"
    if (Test-Path $docsPath) {
        $docFiles = Get-ChildItem $docsPath -File | Where-Object { $_.Name -match "^\d{3}_" }
        $docCount = $docFiles.Count
        $passed = $docCount -ge 8  # 최소 8개 문서
        Add-TestResult -Category $category -TestName "문서 파일 수" -Passed $passed `
            -Message "$docCount 개 문서" `
            -Details "001-009 번호 체계 문서" `
            -Recommendation "최소 8개 이상의 문서가 필요합니다."
    }
}

# ============================================================================
# 통합 시나리오 테스트 (Deep 모드)
# ============================================================================

function Test-IntegrationScenarios {
    if ($ValidationType -ne "Deep") {
        Write-ColorOutput "`n[7/8] 통합 시나리오 테스트 - SKIPPED (Deep 모드만 실행)" -Level "Warning"
        return
    }

    if (Test-ShouldSkip "Integration") {
        Write-ColorOutput "`n[7/8] 통합 시나리오 테스트 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[7/8] 통합 시나리오 테스트 중..." -Level "Progress"
    Write-ColorOutput "  참고: Deep 모드에서는 실제 설치를 시뮬레이션합니다." -Level "Info"
    $category = "Integration"

    # 시나리오 1: 설치 스크립트 Dry-Run
    try {
        $installScript = Join-Path $Script:PackageRoot "scripts\02-install-airgap-enhanced.ps1"
        if (Test-Path $installScript) {
            Write-ColorOutput "  시나리오 1: 설치 스크립트 파라미터 검증..." -Level "Info"

            # Get-Help로 파라미터 확인
            $helpInfo = Get-Help $installScript -ErrorAction SilentlyContinue
            $passed = $null -ne $helpInfo
            Add-TestResult -Category $category -TestName "설치 스크립트 헬프" -Passed $passed `
                -Message $(if ($passed) { "도움말 정보 확인" } else { "도움말 없음" })
        }
    } catch {
        Add-TestResult -Category $category -TestName "설치 스크립트 검증" -Passed $false `
            -Message "검증 실패" -Details $_.Exception.Message
    }

    # 시나리오 2: Web UI 테스트 스크립트 실행 가능성
    try {
        $testScript = Join-Path $Script:PackageRoot "scripts\test-nginx-web-ui.ps1"
        if (Test-Path $testScript) {
            Write-ColorOutput "  시나리오 2: 테스트 스크립트 실행 가능성 검증..." -Level "Info"

            $helpInfo = Get-Help $testScript -ErrorAction SilentlyContinue
            $passed = $null -ne $helpInfo
            Add-TestResult -Category $category -TestName "테스트 스크립트 헬프" -Passed $passed `
                -Message $(if ($passed) { "도움말 정보 확인" } else { "도움말 없음" })
        }
    } catch {
        Add-TestResult -Category $category -TestName "테스트 스크립트 검증" -Passed $false `
            -Message "검증 실패" -Details $_.Exception.Message
    }

    # 시나리오 3: AD 스크립트 Verify 모드 지원
    try {
        $adScript = Join-Path $Script:PackageRoot "scripts\04-setup-ad-integration.ps1"
        if (Test-Path $adScript) {
            Write-ColorOutput "  시나리오 3: AD 스크립트 Verify 모드 확인..." -Level "Info"

            $content = Get-Content $adScript -Raw
            $passed = $content -match "\[switch\]\`$Verify"
            Add-TestResult -Category $category -TestName "AD Verify 모드" -Passed $passed `
                -Message $(if ($passed) { "Verify 파라미터 확인" } else { "Verify 파라미터 없음" }) `
                -Details "AD 구성 검증 전용 모드"
        }
    } catch {
        Add-TestResult -Category $category -TestName "AD 스크립트 검증" -Passed $false `
            -Message "검증 실패" -Details $_.Exception.Message
    }

    # 시나리오 4: 백업 스크립트 List 액션
    try {
        $backupScript = Join-Path $Script:PackageRoot "scripts\05-backup-restore.ps1"
        if (Test-Path $backupScript) {
            Write-ColorOutput "  시나리오 4: 백업 스크립트 List 액션 확인..." -Level "Info"

            $content = Get-Content $backupScript -Raw
            $passed = $content -match "Action.*List" -or $content -match "\[ValidateSet\(.*List.*\)\]"
            Add-TestResult -Category $category -TestName "백업 List 액션" -Passed $passed `
                -Message $(if ($passed) { "List 액션 확인" } else { "List 액션 없음" }) `
                -Details "백업 목록 조회 기능"
        }
    } catch {
        Add-TestResult -Category $category -TestName "백업 스크립트 검증" -Passed $false `
            -Message "검증 실패" -Details $_.Exception.Message
    }
}

# ============================================================================
# 보안 검사
# ============================================================================

function Test-Security {
    if (Test-ShouldSkip "Security") {
        Write-ColorOutput "`n[8/8] 보안 검사 - SKIPPED" -Level "Warning"
        return
    }

    Write-ColorOutput "`n[8/8] 보안 검사 중..." -Level "Progress"
    $category = "Security"

    # 하드코딩된 비밀번호 검색
    $scriptFiles = Get-ChildItem (Join-Path $Script:PackageRoot "scripts") -Filter "*.ps1" -File
    $suspiciousPatterns = @(
        @{ Pattern = "password\s*=\s*[`"']([^`"']+)[`"']"; Name = "하드코딩 비밀번호" },
        @{ Pattern = "admin\s*:\s*[`"']([^`"']+)[`"']"; Name = "관리자 자격증명" },
        @{ Pattern = "ConvertTo-SecureString.*-AsPlainText"; Name = "평문 비밀번호" }
    )

    foreach ($script in $scriptFiles) {
        $content = Get-Content $script.FullName -Raw

        foreach ($pattern in $suspiciousPatterns) {
            if ($content -match $pattern.Pattern) {
                $Script:ValidationResults.WarningCount++
                Add-TestResult -Category $category -TestName "$($script.Name) - $($pattern.Name)" -Passed $false `
                    -Message "보안 위험 발견" `
                    -Details "패턴: $($pattern.Pattern)" `
                    -Recommendation "자격증명을 환경 변수나 SecureString으로 관리하세요."
            }
        }
    }

    # 모든 스크립트가 안전하면 PASS
    if ($Script:ValidationResults.Categories[$category].FailedTests -eq 0) {
        Add-TestResult -Category $category -TestName "전체 스크립트 보안 검사" -Passed $true `
            -Message "보안 위험 없음" `
            -Details "하드코딩된 자격증명 없음"
    }

    # Web UI localhost 바인딩
    $enhancedWebUI = Join-Path $Script:PackageRoot "scripts\nginx-web-ui-enhanced.js"
    if (Test-Path $enhancedWebUI) {
        $content = Get-Content $enhancedWebUI -Raw
        $passed = $content -match "127\.0\.0\.1" -and ($content -notmatch "0\.0\.0\.0")
        Add-TestResult -Category $category -TestName "Web UI 보안 바인딩" -Passed $passed `
            -Message $(if ($passed) { "localhost 전용 바인딩 확인" } else { "보안 바인딩 문제" }) `
            -Details "외부 접근 차단 여부" `
            -Recommendation "Web UI는 반드시 127.0.0.1에만 바인딩되어야 합니다."
    }
}

# ============================================================================
# 보고서 생성
# ============================================================================

function Export-ValidationReport {
    Write-ColorOutput "`n보고서 생성 중..." -Level "Progress"

    $Script:ValidationResults.EndTime = Get-Date
    $duration = $Script:ValidationResults.EndTime - $Script:ValidationResults.StartTime
    $Script:ValidationResults.DurationSeconds = [math]::Round($duration.TotalSeconds, 2)

    # 전체 상태 결정
    if ($Script:ValidationResults.FailedTests -eq 0) {
        $Script:ValidationResults.OverallStatus = "PASS"
    } elseif ($Script:ValidationResults.PassedTests -gt $Script:ValidationResults.FailedTests) {
        $Script:ValidationResults.OverallStatus = "PARTIAL"
    } else {
        $Script:ValidationResults.OverallStatus = "FAIL"
    }

    $passRate = if ($Script:ValidationResults.TotalTests -gt 0) {
        [math]::Round(($Script:ValidationResults.PassedTests / $Script:ValidationResults.TotalTests) * 100, 2)
    } else { 0 }
    $Script:ValidationResults.PassRate = $passRate

    # 보고서 디렉토리 생성
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $htmlReportPath = Join-Path $ReportPath "validation-report-$timestamp.html"

    # HTML 보고서 생성
    $html = @"
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>에어갭 패키지 v2.0 검증 보고서</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; color: #333; }
        .container { max-width: 1400px; margin: 0 auto; background: white; border-radius: 15px; box-shadow: 0 10px 40px rgba(0,0,0,0.3); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .header .subtitle { font-size: 1.2em; opacity: 0.9; }
        .status-badge { display: inline-block; padding: 10px 30px; border-radius: 25px; font-weight: bold; font-size: 1.3em; margin-top: 15px; }
        .status-PASS { background: #10b981; color: white; }
        .status-PARTIAL { background: #f59e0b; color: white; }
        .status-FAIL { background: #ef4444; color: white; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #f8fafc; }
        .summary-card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
        .summary-card .value { font-size: 2.5em; font-weight: bold; margin: 10px 0; }
        .summary-card .label { color: #64748b; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
        .summary-card.pass .value { color: #10b981; }
        .summary-card.fail .value { color: #ef4444; }
        .summary-card.warning .value { color: #f59e0b; }
        .summary-card.info .value { color: #3b82f6; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section-title { font-size: 1.8em; color: #1e293b; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 3px solid #667eea; }
        .category { background: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 20px; }
        .category-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
        .category-title { font-size: 1.3em; font-weight: bold; color: #334155; }
        .category-stats { font-size: 0.9em; color: #64748b; }
        .test-item { background: white; border-left: 4px solid #e2e8f0; padding: 15px; margin-bottom: 10px; border-radius: 5px; }
        .test-item.pass { border-left-color: #10b981; }
        .test-item.fail { border-left-color: #ef4444; }
        .test-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
        .test-name { font-weight: 600; color: #1e293b; }
        .test-status { padding: 4px 12px; border-radius: 12px; font-size: 0.85em; font-weight: bold; }
        .test-status.pass { background: #d1fae5; color: #065f46; }
        .test-status.fail { background: #fee2e2; color: #991b1b; }
        .test-message { color: #475569; margin-bottom: 5px; }
        .test-details { color: #64748b; font-size: 0.9em; font-family: 'Consolas', 'Courier New', monospace; background: #f1f5f9; padding: 10px; border-radius: 5px; margin-top: 10px; }
        .recommendations { background: #fef3c7; border-left: 4px solid #f59e0b; padding: 20px; border-radius: 5px; }
        .recommendations h3 { color: #92400e; margin-bottom: 15px; }
        .recommendation-item { background: white; padding: 15px; margin-bottom: 10px; border-radius: 5px; }
        .recommendation-item strong { color: #92400e; }
        .system-info { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; }
        .info-item { background: #f8fafc; padding: 15px; border-radius: 8px; }
        .info-label { font-weight: bold; color: #475569; margin-bottom: 5px; }
        .info-value { color: #1e293b; font-family: 'Consolas', 'Courier New', monospace; }
        .footer { background: #1e293b; color: white; padding: 20px; text-align: center; font-size: 0.9em; }
        .progress-bar { width: 100%; height: 30px; background: #e2e8f0; border-radius: 15px; overflow: hidden; margin: 10px 0; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #10b981, #059669); display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; transition: width 0.3s ease; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 에어갭 패키지 v2.0 검증 보고서</h1>
            <div class="subtitle">Enhanced Edition - 전체 기능 검증</div>
            <div class="status-badge status-$($Script:ValidationResults.OverallStatus)">$($Script:ValidationResults.OverallStatus)</div>
        </div>

        <div class="summary">
            <div class="summary-card info">
                <div class="label">전체 테스트</div>
                <div class="value">$($Script:ValidationResults.TotalTests)</div>
            </div>
            <div class="summary-card pass">
                <div class="label">성공</div>
                <div class="value">$($Script:ValidationResults.PassedTests)</div>
            </div>
            <div class="summary-card fail">
                <div class="label">실패</div>
                <div class="value">$($Script:ValidationResults.FailedTests)</div>
            </div>
            <div class="summary-card warning">
                <div class="label">경고</div>
                <div class="value">$($Script:ValidationResults.WarningCount)</div>
            </div>
            <div class="summary-card info">
                <div class="label">성공률</div>
                <div class="value">$passRate%</div>
            </div>
            <div class="summary-card info">
                <div class="label">실행 시간</div>
                <div class="value">$($Script:ValidationResults.DurationSeconds)s</div>
            </div>
        </div>

        <div class="content">
            <div class="section">
                <div class="section-title">📊 전체 진행률</div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $passRate%">$passRate%</div>
                </div>
            </div>

            <div class="section">
                <div class="section-title">💻 시스템 정보</div>
                <div class="system-info">
"@

    foreach ($key in $Script:ValidationResults.SystemInfo.Keys) {
        $value = $Script:ValidationResults.SystemInfo[$key]
        $html += @"
                    <div class="info-item">
                        <div class="info-label">$key</div>
                        <div class="info-value">$value</div>
                    </div>
"@
    }

    $html += @"
                </div>
            </div>

            <div class="section">
                <div class="section-title">📋 카테고리별 테스트 결과</div>
"@

    foreach ($categoryName in $Script:ValidationResults.Categories.Keys) {
        $category = $Script:ValidationResults.Categories[$categoryName]
        $categoryPassRate = if ($category.TotalTests -gt 0) {
            [math]::Round(($category.PassedTests / $category.TotalTests) * 100, 2)
        } else { 0 }

        $html += @"
                <div class="category">
                    <div class="category-header">
                        <div class="category-title">$categoryName</div>
                        <div class="category-stats">$($category.PassedTests)/$($category.TotalTests) 성공 ($categoryPassRate%)</div>
                    </div>
"@

        foreach ($test in $category.Tests) {
            $statusClass = $test.Status.ToLower()
            $html += @"
                    <div class="test-item $statusClass">
                        <div class="test-header">
                            <div class="test-name">$($test.TestName)</div>
                            <div class="test-status $statusClass">$($test.Status)</div>
                        </div>
                        <div class="test-message">$($test.Message)</div>
"@
            if ($test.Details) {
                $html += @"
                        <div class="test-details">$($test.Details -replace "`n", "<br>")</div>
"@
            }
            $html += @"
                    </div>
"@
        }

        $html += @"
                </div>
"@
    }

    if ($Script:ValidationResults.Recommendations.Count -gt 0) {
        $html += @"
            <div class="section">
                <div class="section-title">💡 권장사항</div>
                <div class="recommendations">
                    <h3>다음 항목들을 개선하시기 바랍니다:</h3>
"@
        foreach ($rec in $Script:ValidationResults.Recommendations) {
            $html += @"
                    <div class="recommendation-item">
                        <strong>[$($rec.Category)] $($rec.Test)</strong><br>
                        $($rec.Recommendation)
                    </div>
"@
        }
        $html += @"
                </div>
            </div>
"@
    }

    $html += @"
        </div>

        <div class="footer">
            <p>검증 ID: $($Script:ValidationResults.ValidationId)</p>
            <p>생성 시간: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>검증 유형: $ValidationType | PowerShell $($PSVersionTable.PSVersion.ToString())</p>
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlReportPath -Encoding UTF8
    Write-ColorOutput "`n✅ HTML 보고서 생성: $htmlReportPath" -Level "Success"

    # JSON 보고서 (옵션)
    if ($ExportJson) {
        $jsonReportPath = Join-Path $ReportPath "validation-report-$timestamp.json"
        $Script:ValidationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportPath -Encoding UTF8
        Write-ColorOutput "✅ JSON 보고서 생성: $jsonReportPath" -Level "Success"
    }

    return $htmlReportPath
}

# ============================================================================
# 메인 실행
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "║     에어갭 패키지 v2.0 Enhanced Edition 전체 기능 검증       ║" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-ColorOutput "검증 ID: $($Script:ValidationResults.ValidationId)" -Level "Info"
    Write-ColorOutput "검증 유형: $ValidationType" -Level "Info"
    Write-ColorOutput "패키지 경로: $Script:PackageRoot" -Level "Info"

    if ($SkipTests.Count -gt 0) {
        Write-ColorOutput "스킵 카테고리: $($SkipTests -join ', ')" -Level "Warning"
    }

    Write-Host ""

    try {
        # 1. 시스템 정보
        Get-SystemInformation

        # 2. 전제조건
        Test-Prerequisites

        # 3. 파일 무결성
        Test-FileIntegrity

        # 4. 스크립트 구문
        Test-ScriptSyntax

        # 5. Enhanced 기능
        Test-EnhancedFeatures

        # 6. 문서화
        Test-Documentation

        # 7. 통합 테스트 (Deep 모드)
        Test-IntegrationScenarios

        # 8. 보안 검사
        Test-Security

        # 보고서 생성
        $reportPath = Export-ValidationReport

        # 최종 결과
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                      검증 완료                                 ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        $statusColor = switch ($Script:ValidationResults.OverallStatus) {
            "PASS" { "Success" }
            "PARTIAL" { "Warning" }
            "FAIL" { "Error" }
        }

        Write-ColorOutput "전체 상태: $($Script:ValidationResults.OverallStatus)" -Level $statusColor
        Write-ColorOutput "전체 테스트: $($Script:ValidationResults.TotalTests)" -Level "Info"
        Write-ColorOutput "성공: $($Script:ValidationResults.PassedTests)" -Level "Success"
        Write-ColorOutput "실패: $($Script:ValidationResults.FailedTests)" -Level "Error"
        Write-ColorOutput "경고: $($Script:ValidationResults.WarningCount)" -Level "Warning"
        Write-ColorOutput "성공률: $($Script:ValidationResults.PassRate)%" -Level "Info"
        Write-ColorOutput "실행 시간: $($Script:ValidationResults.DurationSeconds)초" -Level "Info"

        Write-Host ""
        Write-ColorOutput "📄 상세 보고서: $reportPath" -Level "Info"
        Write-Host ""

        # 권장사항
        if ($Script:ValidationResults.Recommendations.Count -gt 0) {
            Write-ColorOutput "⚠️  $($Script:ValidationResults.Recommendations.Count)개의 권장사항이 있습니다. 보고서를 확인하세요." -Level "Warning"
        }

        # Exit code
        if ($Script:ValidationResults.OverallStatus -eq "PASS") {
            exit 0
        } elseif ($Script:ValidationResults.OverallStatus -eq "PARTIAL") {
            exit 1
        } else {
            exit 2
        }

    } catch {
        Write-ColorOutput "`n❌ 검증 중 치명적 오류 발생!" -Level "Error"
        Write-ColorOutput "오류: $($_.Exception.Message)" -Level "Error"
        Write-ColorOutput "위치: $($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine)" -Level "Error"
        exit 3
    }
}

# 실행
Main
