<#
.SYNOPSIS
    Nginx 자동 유지보수 스크립트

.DESCRIPTION
    다음 유지보수 작업을 자동으로 수행:
    - 로그 로테이션 및 압축 (7일 이상 된 로그)
    - 임시 파일 정리
    - Nginx 캐시 정리
    - 오래된 백업 파일 삭제 (30일 이상)
    - 디스크 공간 확인 및 알람

.PARAMETER MaintenanceType
    유지보수 유형:
    - Quick: 빠른 정리 (로그 로테이션만)
    - Standard: 표준 유지보수 (로그 + 캐시 + 임시파일)
    - Deep: 전체 유지보수 (모든 작업 + 백업 정리)

.PARAMETER LogRetentionDays
    로그 보관 일수 (기본: 7일)

.PARAMETER BackupRetentionDays
    백업 보관 일수 (기본: 30일)

.PARAMETER CompressOldLogs
    오래된 로그 파일 압축

.PARAMETER DiskSpaceThresholdPercent
    디스크 공간 경고 임계값 (기본: 90%)

.PARAMETER ExportReport
    리포트 저장 경로

.PARAMETER DryRun
    실제 변경 없이 미리보기

.EXAMPLE
    .\10-auto-maintenance.ps1
    표준 유지보수 실행

.EXAMPLE
    .\10-auto-maintenance.ps1 -MaintenanceType Deep -CompressOldLogs
    전체 유지보수 + 로그 압축

.EXAMPLE
    .\10-auto-maintenance.ps1 -DryRun
    미리보기 모드
#>

[CmdletBinding()]
param(
    [ValidateSet("Quick", "Standard", "Deep")]
    [string]$MaintenanceType = "Standard",

    [int]$LogRetentionDays = 7,
    [int]$BackupRetentionDays = 30,
    [switch]$CompressOldLogs,
    [double]$DiskSpaceThresholdPercent = 90.0,
    [string]$ExportReport = "",
    [switch]$DryRun
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ============================================================================
# 설정
# ============================================================================

$Global:MaintenanceConfig = @{
    Paths = @{
        NginxRoot = "C:\nginx"
        Logs = "C:\nginx\logs"
        Cache = "C:\nginx\cache"
        Temp = "C:\nginx\temp"
        Backups = "C:\nginx\backups"
    }
    Stats = @{
        FilesDeleted = 0
        FilesCompressed = 0
        SpaceFreed = 0  # bytes
        Actions = @()
        Warnings = @()
        Errors = @()
    }
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

function Add-MaintenanceAction {
    param([string]$Action)
    $Global:MaintenanceConfig.Stats.Actions += "[$(Get-Date -Format 'HH:mm:ss')] $Action"
}

function Get-DirectorySize {
    <#
    .SYNOPSIS
        디렉토리 전체 크기 계산 (재귀)
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return 0
    }

    $size = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum

    return if ($size) { $size } else { 0 }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes bytes"
    }
}

function Test-DiskSpace {
    <#
    .SYNOPSIS
        디스크 공간 확인
    #>

    $drive = Get-PSDrive C
    $usedPercent = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 2)

    $status = @{
        Drive = "C:\"
        TotalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
        UsedGB = [math]::Round($drive.Used / 1GB, 2)
        FreeGB = [math]::Round($drive.Free / 1GB, 2)
        UsedPercent = $usedPercent
        Warning = $usedPercent -gt $DiskSpaceThresholdPercent
    }

    if ($status.Warning) {
        $message = "⚠ 디스크 공간 부족: $($status.UsedPercent)% 사용 중 (임계값: $DiskSpaceThresholdPercent%)"
        Write-ColorOutput $message -Level WARNING
        $Global:MaintenanceConfig.Stats.Warnings += $message
    } else {
        Write-ColorOutput "✓ 디스크 공간: $($status.UsedPercent)% 사용 중 (여유: $($status.FreeGB)GB)" -Level SUCCESS
    }

    return $status
}

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        로그 파일 로테이션 및 정리
    #>

    $logPath = $Global:MaintenanceConfig.Paths.Logs

    if (-not (Test-Path $logPath)) {
        Write-ColorOutput "로그 디렉토리 없음: $logPath" -Level WARNING
        return
    }

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-ColorOutput "로그 로테이션 시작..." -Level INFO

    $cutoffDate = (Get-Date).AddDays(-$LogRetentionDays)
    $oldLogs = Get-ChildItem $logPath -Filter "*.log" -Recurse |
                Where-Object { $_.LastWriteTime -lt $cutoffDate }

    if ($oldLogs.Count -eq 0) {
        Write-ColorOutput "정리할 오래된 로그 없음" -Level INFO
        return
    }

    Write-ColorOutput "$($oldLogs.Count)개 오래된 로그 발견 (보관 기간: $LogRetentionDays일)" -Level INFO

    $totalSize = ($oldLogs | Measure-Object -Property Length -Sum).Sum

    foreach ($log in $oldLogs) {
        $logName = $log.Name
        $logSize = $log.Length

        if ($CompressOldLogs) {
            # 압축
            $zipName = "$($log.FullName).$(Get-Date -Format 'yyyyMMdd').zip"

            if ($DryRun) {
                Write-ColorOutput "[DRY-RUN] 압축: $logName → $zipName" -Level WARNING
            } else {
                try {
                    Compress-Archive -Path $log.FullName -DestinationPath $zipName -Force
                    Remove-Item $log.FullName -Force

                    Write-ColorOutput "압축 완료: $logName → $zipName" -Level SUCCESS
                    $Global:MaintenanceConfig.Stats.FilesCompressed++
                    Add-MaintenanceAction "로그 압축: $logName"
                } catch {
                    $message = "압축 실패: $logName - $_"
                    Write-ColorOutput $message -Level ERROR
                    $Global:MaintenanceConfig.Stats.Errors += $message
                }
            }
        } else {
            # 삭제
            if ($DryRun) {
                Write-ColorOutput "[DRY-RUN] 삭제: $logName ($(Format-FileSize $logSize))" -Level WARNING
            } else {
                try {
                    Remove-Item $log.FullName -Force

                    Write-ColorOutput "삭제: $logName ($(Format-FileSize $logSize))" -Level SUCCESS
                    $Global:MaintenanceConfig.Stats.FilesDeleted++
                    $Global:MaintenanceConfig.Stats.SpaceFreed += $logSize
                    Add-MaintenanceAction "로그 삭제: $logName"
                } catch {
                    $message = "삭제 실패: $logName - $_"
                    Write-ColorOutput $message -Level ERROR
                    $Global:MaintenanceConfig.Stats.Errors += $message
                }
            }
        }
    }

    if (-not $DryRun) {
        Write-ColorOutput "정리 완료: $($oldLogs.Count)개 파일 ($(Format-FileSize $totalSize))" -Level SUCCESS
    }
}

function Invoke-CacheCleanup {
    <#
    .SYNOPSIS
        Nginx 캐시 정리
    #>

    $cachePath = $Global:MaintenanceConfig.Paths.Cache

    if (-not (Test-Path $cachePath)) {
        Write-ColorOutput "캐시 디렉토리 없음: $cachePath (건너뜀)" -Level INFO
        return
    }

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-ColorOutput "캐시 정리 시작..." -Level INFO

    # 캐시 파일 크기 계산
    $cacheSizeBefore = Get-DirectorySize -Path $cachePath

    if ($DryRun) {
        Write-ColorOutput "[DRY-RUN] 캐시 정리: $(Format-FileSize $cacheSizeBefore)" -Level WARNING
    } else {
        try {
            # 전체 캐시 삭제 (재생성됨)
            Remove-Item "$cachePath\*" -Recurse -Force

            $cacheSizeAfter = Get-DirectorySize -Path $cachePath
            $freedSpace = $cacheSizeBefore - $cacheSizeAfter

            Write-ColorOutput "캐시 정리 완료: $(Format-FileSize $freedSpace) 확보" -Level SUCCESS
            $Global:MaintenanceConfig.Stats.SpaceFreed += $freedSpace
            Add-MaintenanceAction "캐시 정리: $(Format-FileSize $freedSpace)"
        } catch {
            $message = "캐시 정리 실패: $_"
            Write-ColorOutput $message -Level ERROR
            $Global:MaintenanceConfig.Stats.Errors += $message
        }
    }
}

function Invoke-TempCleanup {
    <#
    .SYNOPSIS
        임시 파일 정리
    #>

    $tempPath = $Global:MaintenanceConfig.Paths.Temp

    if (-not (Test-Path $tempPath)) {
        Write-ColorOutput "임시 디렉토리 없음: $tempPath (건너뜀)" -Level INFO
        return
    }

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-ColorOutput "임시 파일 정리 시작..." -Level INFO

    $tempFiles = Get-ChildItem $tempPath -Recurse -File
    $totalSize = ($tempFiles | Measure-Object -Property Length -Sum).Sum

    if ($DryRun) {
        Write-ColorOutput "[DRY-RUN] 임시 파일 삭제: $($tempFiles.Count)개 ($(Format-FileSize $totalSize))" -Level WARNING
    } else {
        try {
            Remove-Item "$tempPath\*" -Recurse -Force

            Write-ColorOutput "임시 파일 정리 완료: $($tempFiles.Count)개 ($(Format-FileSize $totalSize))" -Level SUCCESS
            $Global:MaintenanceConfig.Stats.FilesDeleted += $tempFiles.Count
            $Global:MaintenanceConfig.Stats.SpaceFreed += $totalSize
            Add-MaintenanceAction "임시 파일 삭제: $($tempFiles.Count)개"
        } catch {
            $message = "임시 파일 정리 실패: $_"
            Write-ColorOutput $message -Level ERROR
            $Global:MaintenanceConfig.Stats.Errors += $message
        }
    }
}

function Invoke-BackupCleanup {
    <#
    .SYNOPSIS
        오래된 백업 파일 정리
    #>

    $backupPath = $Global:MaintenanceConfig.Paths.Backups

    if (-not (Test-Path $backupPath)) {
        Write-ColorOutput "백업 디렉토리 없음: $backupPath (건너뜀)" -Level INFO
        return
    }

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-ColorOutput "백업 정리 시작..." -Level INFO

    $cutoffDate = (Get-Date).AddDays(-$BackupRetentionDays)
    $oldBackups = Get-ChildItem $backupPath -Recurse -File |
                  Where-Object { $_.LastWriteTime -lt $cutoffDate }

    if ($oldBackups.Count -eq 0) {
        Write-ColorOutput "정리할 오래된 백업 없음" -Level INFO
        return
    }

    $totalSize = ($oldBackups | Measure-Object -Property Length -Sum).Sum

    Write-ColorOutput "$($oldBackups.Count)개 오래된 백업 발견 (보관 기간: $BackupRetentionDays일)" -Level INFO

    foreach ($backup in $oldBackups) {
        if ($DryRun) {
            Write-ColorOutput "[DRY-RUN] 삭제: $($backup.Name)" -Level WARNING
        } else {
            try {
                Remove-Item $backup.FullName -Force

                Write-ColorOutput "삭제: $($backup.Name)" -Level SUCCESS
                $Global:MaintenanceConfig.Stats.FilesDeleted++
            } catch {
                $message = "삭제 실패: $($backup.Name) - $_"
                Write-ColorOutput $message -Level ERROR
                $Global:MaintenanceConfig.Stats.Errors += $message
            }
        }
    }

    if (-not $DryRun) {
        $Global:MaintenanceConfig.Stats.SpaceFreed += $totalSize
        Add-MaintenanceAction "백업 삭제: $($oldBackups.Count)개 ($(Format-FileSize $totalSize))"
        Write-ColorOutput "백업 정리 완료: $($oldBackups.Count)개 ($(Format-FileSize $totalSize))" -Level SUCCESS
    }
}

function Generate-MaintenanceReport {
    <#
    .SYNOPSIS
        유지보수 리포트 생성
    #>

    $stats = $Global:MaintenanceConfig.Stats

    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
    Write-ColorOutput "📊 유지보수 완료" -Level INFO
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS

    Write-Host ""
    Write-Host "[ 통계 ]" -ForegroundColor Yellow
    Write-Host "  삭제된 파일: $($stats.FilesDeleted)개"
    Write-Host "  압축된 파일: $($stats.FilesCompressed)개"
    Write-Host "  확보된 공간: $(Format-FileSize $stats.SpaceFreed)"

    if ($stats.Actions.Count -gt 0) {
        Write-Host ""
        Write-Host "[ 수행 작업 ]" -ForegroundColor Yellow
        foreach ($action in $stats.Actions) {
            Write-Host "  $action"
        }
    }

    if ($stats.Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "[ 경고 ]" -ForegroundColor Yellow
        foreach ($warning in $stats.Warnings) {
            Write-Host "  $warning" -ForegroundColor Yellow
        }
    }

    if ($stats.Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "[ 에러 ]" -ForegroundColor Red
        foreach ($error in $stats.Errors) {
            Write-Host "  $error" -ForegroundColor Red
        }
    }
}

# ============================================================================
# 메인 실행
# ============================================================================

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
Write-ColorOutput "Nginx 자동 유지보수 v1.0" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

if ($DryRun) {
    Write-ColorOutput "모드: DRY-RUN (미리보기 전용)" -Level WARNING
}

Write-ColorOutput "유지보수 유형: $MaintenanceType" -Level INFO
Write-ColorOutput "로그 보관 기간: $LogRetentionDays일" -Level INFO
Write-ColorOutput "백업 보관 기간: $BackupRetentionDays일" -Level INFO

# 디스크 공간 확인
$diskStatus = Test-DiskSpace

# 유지보수 작업 실행
switch ($MaintenanceType) {
    "Quick" {
        Invoke-LogRotation
    }
    "Standard" {
        Invoke-LogRotation
        Invoke-CacheCleanup
        Invoke-TempCleanup
    }
    "Deep" {
        Invoke-LogRotation
        Invoke-CacheCleanup
        Invoke-TempCleanup
        Invoke-BackupCleanup
    }
}

# 최종 디스크 공간 확인
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
$diskStatusAfter = Test-DiskSpace

# 리포트 생성
Generate-MaintenanceReport

if ($DryRun) {
    Write-ColorOutput "DRY-RUN 모드 종료. 실제 적용을 원하시면 -DryRun 옵션을 제거하세요" -Level INFO
}
