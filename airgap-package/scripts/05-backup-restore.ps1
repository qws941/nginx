#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Nginx 백업 및 복구 자동화 스크립트

.DESCRIPTION
    Nginx 설정, 로그, SSL 인증서를 자동으로 백업하고 복구합니다.

    주요 기능:
    - 전체 백업 (Full Backup)
    - 증분 백업 (Incremental Backup)
    - 예약된 백업 (Scheduled Backup via Task Scheduler)
    - 백업 검증 (Verification)
    - 복원 (Restore)
    - 백업 로테이션 (Retention Policy)
    - 원격 저장소 지원 (Network Share)

.EXAMPLE
    # 전체 백업 생성
    .\05-backup-restore.ps1 -Action Backup

    # 증분 백업
    .\05-backup-restore.ps1 -Action Backup -Incremental

    # 복원
    .\05-backup-restore.ps1 -Action Restore -BackupFile "C:\Backups\nginx-backup-20250120-153045.zip"

    # 백업 검증
    .\05-backup-restore.ps1 -Action Verify -BackupFile "C:\Backups\nginx-backup-20250120-153045.zip"

    # 예약된 백업 설정
    .\05-backup-restore.ps1 -Action Schedule -ScheduleType Daily -ScheduleTime "02:00"

    # 백업 정리 (30일 이상 된 백업 삭제)
    .\05-backup-restore.ps1 -Action Cleanup -RetentionDays 30
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Backup", "Restore", "Verify", "Schedule", "Cleanup", "List")]
    [string]$Action = "Backup",

    [string]$NginxPath = "C:\nginx",
    [string]$BackupPath = "C:\Backups\Nginx",
    [string]$BackupFile = "",
    [string]$NetworkShare = "",  # 원격 백업 경로 (예: \\server\backups)

    [switch]$Incremental,
    [switch]$IncludeData,  # 로그 파일 포함 (용량이 클 수 있음)
    [switch]$Force,

    # 스케줄링 옵션
    [ValidateSet("Daily", "Weekly", "Monthly")]
    [string]$ScheduleType = "Daily",
    [string]$ScheduleTime = "02:00",  # HH:mm 형식

    # 보존 정책
    [int]$RetentionDays = 30,
    [int]$RetentionCount = 10  # 최대 백업 개수
)

#region Configuration

$Script:Config = @{
    Version = "2.0.0"
    NginxPath = $NginxPath
    BackupPath = $BackupPath
    NetworkShare = $NetworkShare
    LogPath = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"

    # 백업 대상
    BackupItems = @(
        @{ Path = "conf"; Include = $true; Required = $true },
        @{ Path = "logs"; Include = $IncludeData; Required = $false },
        @{ Path = "html"; Include = $true; Required = $false },
        @{ Path = "nginx.exe"; Include = $true; Required = $true },
        @{ Path = "nssm.exe"; Include = $true; Required = $false }
    )

    # 메타데이터
    MetadataFile = "backup-metadata.json"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $Script:Config.LogPath "backup-restore-$timestamp.log"

#endregion

#region Logger

class BackupLogger {
    static [string]$LogFile

    static [void] Init([string]$logPath) {
        [BackupLogger]::LogFile = $logPath
    }

    static [void] Log([string]$Message, [string]$Level) {
        $color = @{
            INFO = "Cyan"
            SUCCESS = "Green"
            WARN = "Yellow"
            ERROR = "Red"
            DEBUG = "Gray"
            PROGRESS = "Magenta"
        }[$Level]

        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $logEntry = "[$timestamp] [$Level] $Message"

        Write-Host $logEntry -ForegroundColor $color

        if ([BackupLogger]::LogFile) {
            Add-Content -Path ([BackupLogger]::LogFile) -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }

    static [void] Info([string]$Message) { [BackupLogger]::Log($Message, "INFO") }
    static [void] Success([string]$Message) { [BackupLogger]::Log($Message, "SUCCESS") }
    static [void] Warn([string]$Message) { [BackupLogger]::Log($Message, "WARN") }
    static [void] Error([string]$Message) { [BackupLogger]::Log($Message, "ERROR") }
    static [void] Debug([string]$Message) { [BackupLogger]::Log($Message, "DEBUG") }
    static [void] Progress([string]$Message) { [BackupLogger]::Log($Message, "PROGRESS") }
}

#endregion

#region Helper Functions

function New-BackupMetadata {
    param(
        [string]$BackupType,
        [string]$SourcePath,
        [hashtable]$AdditionalInfo = @{}
    )

    $metadata = @{
        Version = $Script:Config.Version
        Timestamp = Get-Date -Format "o"
        BackupType = $BackupType
        SourcePath = $SourcePath
        Hostname = $env:COMPUTERNAME
        User = $env:USERNAME
        Items = @()
    }

    # 백업 항목 정보 수집
    foreach ($item in $Script:Config.BackupItems) {
        if ($item.Include) {
            $itemPath = Join-Path $SourcePath $item.Path
            if (Test-Path $itemPath) {
                $itemInfo = Get-Item $itemPath -ErrorAction SilentlyContinue

                $metadata.Items += @{
                    Path = $item.Path
                    Type = if ($itemInfo.PSIsContainer) { "Directory" } else { "File" }
                    SizeMB = if ($itemInfo.PSIsContainer) {
                        [math]::Round((Get-ChildItem -Path $itemPath -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
                    } else {
                        [math]::Round($itemInfo.Length / 1MB, 2)
                    }
                    FileCount = if ($itemInfo.PSIsContainer) {
                        (Get-ChildItem -Path $itemPath -Recurse -File).Count
                    } else { 1 }
                }
            }
        }
    }

    # 추가 정보 병합
    foreach ($key in $AdditionalInfo.Keys) {
        $metadata[$key] = $AdditionalInfo[$key]
    }

    # 통계 계산
    $metadata.TotalSizeMB = [math]::Round(($metadata.Items | Measure-Object -Property SizeMB -Sum).Sum, 2)
    $metadata.TotalFiles = ($metadata.Items | Measure-Object -Property FileCount -Sum).Sum

    return $metadata
}

function Save-BackupMetadata {
    param(
        [string]$BackupDir,
        [hashtable]$Metadata
    )

    try {
        $metadataPath = Join-Path $BackupDir $Script:Config.MetadataFile
        $Metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8 -Force
        [BackupLogger]::Debug("Metadata saved: $metadataPath")
        return $true
    } catch {
        [BackupLogger]::Warn("Failed to save metadata: $($_.Exception.Message)")
        return $false
    }
}

function Get-BackupMetadata {
    param([string]$BackupPath)

    try {
        # ZIP 파일이면 임시로 압축 해제
        if ($BackupPath -like "*.zip") {
            $tempDir = "$env:TEMP\backup_verify_$(Get-Random)"
            Expand-Archive -Path $BackupPath -DestinationPath $tempDir -Force

            $metadataPath = Join-Path $tempDir $Script:Config.MetadataFile
            if (Test-Path $metadataPath) {
                $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                return $metadata
            }

            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $metadataPath = Join-Path $BackupPath $Script:Config.MetadataFile
            if (Test-Path $metadataPath) {
                return Get-Content $metadataPath -Raw | ConvertFrom-Json
            }
        }

        return $null
    } catch {
        [BackupLogger]::Error("Failed to read metadata: $($_.Exception.Message)")
        return $null
    }
}

function Test-BackupIntegrity {
    param([string]$BackupPath)

    [BackupLogger]::Info("Verifying backup integrity...")

    try {
        # ZIP 파일 압축 테스트
        if ($BackupPath -like "*.zip") {
            $tempDir = "$env:TEMP\backup_test_$(Get-Random)"

            try {
                Expand-Archive -Path $BackupPath -DestinationPath $tempDir -Force -ErrorAction Stop
                [BackupLogger]::Success("✓ ZIP file extraction successful")

                # 메타데이터 검증
                $metadata = Get-BackupMetadata -BackupPath $BackupPath

                if ($metadata) {
                    [BackupLogger]::Success("✓ Metadata found and readable")
                    [BackupLogger]::Info("  Backup Date: $($metadata.Timestamp)")
                    [BackupLogger]::Info("  Backup Type: $($metadata.BackupType)")
                    [BackupLogger]::Info("  Total Size: $($metadata.TotalSizeMB) MB")
                    [BackupLogger]::Info("  Total Files: $($metadata.TotalFiles)")

                    # 필수 항목 검증
                    $requiredItems = $Script:Config.BackupItems | Where-Object { $_.Required }
                    $missingItems = @()

                    foreach ($required in $requiredItems) {
                        $itemPath = Join-Path $tempDir $required.Path
                        if (-not (Test-Path $itemPath)) {
                            $missingItems += $required.Path
                        }
                    }

                    if ($missingItems.Count -gt 0) {
                        [BackupLogger]::Error("✗ Missing required items: $($missingItems -join ', ')")
                        return $false
                    } else {
                        [BackupLogger]::Success("✓ All required items present")
                    }

                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                    return $true
                } else {
                    [BackupLogger]::Warn("⚠ Metadata not found (old backup format?)")
                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                    return $true  # 메타데이터 없어도 ZIP이 정상이면 OK
                }
            } catch {
                [BackupLogger]::Error("✗ ZIP extraction failed: $($_.Exception.Message)")
                if (Test-Path $tempDir) {
                    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                return $false
            }
        } else {
            [BackupLogger]::Warn("Not a ZIP file, skipping integrity check")
            return $true
        }
    } catch {
        [BackupLogger]::Error("Integrity check failed: $($_.Exception.Message)")
        return $false
    }
}

function Get-IncrementalChanges {
    param(
        [string]$SourcePath,
        [string]$LastBackupMetadataPath
    )

    try {
        if (-not (Test-Path $LastBackupMetadataPath)) {
            [BackupLogger]::Warn("No previous backup found, performing full backup")
            return $null
        }

        $lastMetadata = Get-Content $LastBackupMetadataPath -Raw | ConvertFrom-Json
        $lastBackupDate = [datetime]$lastMetadata.Timestamp

        [BackupLogger]::Info("Last backup: $($lastBackupDate.ToString('yyyy-MM-dd HH:mm:ss'))")

        # 변경된 파일 찾기
        $changedFiles = @()
        $confPath = Join-Path $SourcePath "conf"

        if (Test-Path $confPath) {
            $files = Get-ChildItem -Path $confPath -Recurse -File

            foreach ($file in $files) {
                if ($file.LastWriteTime -gt $lastBackupDate) {
                    $changedFiles += $file.FullName
                }
            }
        }

        [BackupLogger]::Info("Found $($changedFiles.Count) changed files since last backup")
        return $changedFiles
    } catch {
        [BackupLogger]::Error("Failed to detect incremental changes: $($_.Exception.Message)")
        return $null
    }
}

function Stop-NginxServices {
    [BackupLogger]::Info("Stopping Nginx services...")

    $services = @("nginx", "nginx-web-ui")
    $stoppedServices = @()

    foreach ($serviceName in $services) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -eq "Running") {
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $stoppedServices += $serviceName
                [BackupLogger]::Success("  ✓ Stopped: $serviceName")
            } catch {
                [BackupLogger]::Warn("  ⚠ Failed to stop: $serviceName")
            }
        }
    }

    return $stoppedServices
}

function Start-NginxServices {
    param([array]$ServiceNames)

    [BackupLogger]::Info("Starting Nginx services...")

    foreach ($serviceName in $ServiceNames) {
        try {
            Start-Service -Name $serviceName -ErrorAction Stop
            [BackupLogger]::Success("  ✓ Started: $serviceName")
        } catch {
            [BackupLogger]::Error("  ✗ Failed to start: $serviceName")
        }
    }
}

#endregion

#region Backup Functions

function Invoke-FullBackup {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    [BackupLogger]::Info("=== Full Backup ===")
    [BackupLogger]::Info("Source: $SourcePath")
    [BackupLogger]::Info("Destination: $DestinationPath")

    try {
        # 백업 디렉토리 생성
        if (-not (Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }

        $backupName = "nginx-full-backup-$timestamp"
        $tempBackupDir = Join-Path $env:TEMP $backupName
        $finalBackupZip = Join-Path $DestinationPath "$backupName.zip"

        # 임시 디렉토리 생성
        if (Test-Path $tempBackupDir) {
            Remove-Item $tempBackupDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempBackupDir -Force | Out-Null

        [BackupLogger]::Progress("Copying files...")

        # 백업 항목 복사
        $copiedItems = 0
        foreach ($item in $Script:Config.BackupItems) {
            if ($item.Include) {
                $sourcePath = Join-Path $SourcePath $item.Path
                $destPath = Join-Path $tempBackupDir $item.Path

                if (Test-Path $sourcePath) {
                    $sourceItem = Get-Item $sourcePath

                    if ($sourceItem.PSIsContainer) {
                        Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force -ErrorAction Stop
                        $fileCount = (Get-ChildItem -Path $destPath -Recurse -File).Count
                        [BackupLogger]::Success("  ✓ Copied: $($item.Path) ($fileCount files)")
                    } else {
                        $destDir = Split-Path $destPath -Parent
                        if (-not (Test-Path $destDir)) {
                            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                        }
                        Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
                        [BackupLogger]::Success("  ✓ Copied: $($item.Path)")
                    }

                    $copiedItems++
                } else {
                    if ($item.Required) {
                        [BackupLogger]::Warn("  ⚠ Required item not found: $($item.Path)")
                    } else {
                        [BackupLogger]::Debug("  - Skipped (not found): $($item.Path)")
                    }
                }
            }
        }

        if ($copiedItems -eq 0) {
            throw "No items were copied. Backup failed."
        }

        # 메타데이터 생성
        [BackupLogger]::Progress("Generating metadata...")
        $metadata = New-BackupMetadata -BackupType "Full" -SourcePath $SourcePath
        Save-BackupMetadata -BackupDir $tempBackupDir -Metadata $metadata

        # 압축
        [BackupLogger]::Progress("Compressing backup...")
        Compress-Archive -Path "$tempBackupDir\*" -DestinationPath $finalBackupZip -Force -ErrorAction Stop

        # 백업 크기
        $backupSize = [math]::Round((Get-Item $finalBackupZip).Length / 1MB, 2)
        [BackupLogger]::Success("✓ Backup compressed: $backupSize MB")

        # 임시 디렉토리 정리
        Remove-Item $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue

        # 네트워크 공유로 복사 (옵션)
        if ($Script:Config.NetworkShare) {
            [BackupLogger]::Info("Copying to network share: $($Script:Config.NetworkShare)")

            if (Test-Path $Script:Config.NetworkShare) {
                $networkBackupPath = Join-Path $Script:Config.NetworkShare (Split-Path $finalBackupZip -Leaf)
                Copy-Item -Path $finalBackupZip -Destination $networkBackupPath -Force -ErrorAction Stop
                [BackupLogger]::Success("✓ Backup copied to network share")
            } else {
                [BackupLogger]::Warn("⚠ Network share not accessible: $($Script:Config.NetworkShare)")
            }
        }

        [BackupLogger]::Success("`n=== Backup Complete ===")
        [BackupLogger]::Info("Backup File: $finalBackupZip")
        [BackupLogger]::Info("Size: $backupSize MB")
        [BackupLogger]::Info("Files: $($metadata.TotalFiles)")

        return $finalBackupZip
    } catch {
        [BackupLogger]::Error("Backup failed: $($_.Exception.Message)")

        # 정리
        if (Test-Path $tempBackupDir) {
            Remove-Item $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        throw
    }
}

function Invoke-IncrementalBackup {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    [BackupLogger]::Info("=== Incremental Backup ===")

    try {
        # 마지막 전체 백업 찾기
        $lastFullBackup = Get-ChildItem -Path $DestinationPath -Filter "nginx-full-backup-*.zip" -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1

        if (-not $lastFullBackup) {
            [BackupLogger]::Warn("No full backup found. Performing full backup instead.")
            return Invoke-FullBackup -SourcePath $SourcePath -DestinationPath $DestinationPath
        }

        [BackupLogger]::Info("Base backup: $($lastFullBackup.Name)")

        # 변경 파일 감지
        $lastMetadata = Get-BackupMetadata -BackupPath $lastFullBackup.FullName

        if (-not $lastMetadata) {
            [BackupLogger]::Warn("Cannot read metadata from last backup. Performing full backup.")
            return Invoke-FullBackup -SourcePath $SourcePath -DestinationPath $DestinationPath
        }

        $lastBackupDate = [datetime]$lastMetadata.Timestamp
        [BackupLogger]::Info("Last backup date: $($lastBackupDate.ToString('yyyy-MM-dd HH:mm:ss'))")

        # 변경된 파일 찾기
        $changedFiles = @()
        $confPath = Join-Path $SourcePath "conf"

        if (Test-Path $confPath) {
            Get-ChildItem -Path $confPath -Recurse -File | ForEach-Object {
                if ($_.LastWriteTime -gt $lastBackupDate) {
                    $changedFiles += $_
                }
            }
        }

        if ($changedFiles.Count -eq 0) {
            [BackupLogger]::Info("No changes detected since last backup.")
            return $null
        }

        [BackupLogger]::Info("Changed files: $($changedFiles.Count)")

        # 증분 백업 생성
        $backupName = "nginx-incremental-backup-$timestamp"
        $tempBackupDir = Join-Path $env:TEMP $backupName
        $finalBackupZip = Join-Path $DestinationPath "$backupName.zip"

        if (Test-Path $tempBackupDir) {
            Remove-Item $tempBackupDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempBackupDir -Force | Out-Null

        # 변경된 파일 복사
        foreach ($file in $changedFiles) {
            $relativePath = $file.FullName.Replace($SourcePath, "").TrimStart('\')
            $destPath = Join-Path $tempBackupDir $relativePath
            $destDir = Split-Path $destPath -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -Path $file.FullName -Destination $destPath -Force
            [BackupLogger]::Debug("  • $relativePath")
        }

        # 메타데이터
        $metadata = New-BackupMetadata -BackupType "Incremental" -SourcePath $SourcePath -AdditionalInfo @{
            BaseBackup = $lastFullBackup.Name
            BaseBackupDate = $lastBackupDate.ToString("o")
            ChangedFiles = $changedFiles.Count
        }
        Save-BackupMetadata -BackupDir $tempBackupDir -Metadata $metadata

        # 압축
        Compress-Archive -Path "$tempBackupDir\*" -DestinationPath $finalBackupZip -Force

        $backupSize = [math]::Round((Get-Item $finalBackupZip).Length / 1MB, 2)

        Remove-Item $tempBackupDir -Recurse -Force -ErrorAction SilentlyContinue

        [BackupLogger]::Success("`n=== Incremental Backup Complete ===")
        [BackupLogger]::Info("Backup File: $finalBackupZip")
        [BackupLogger]::Info("Size: $backupSize MB")
        [BackupLogger]::Info("Changed Files: $($changedFiles.Count)")

        return $finalBackupZip
    } catch {
        [BackupLogger]::Error("Incremental backup failed: $($_.Exception.Message)")
        throw
    }
}

#endregion

#region Restore Functions

function Invoke-Restore {
    param(
        [string]$BackupFilePath,
        [string]$TargetPath,
        [switch]$Force
    )

    [BackupLogger]::Info("=== Restore from Backup ===")
    [BackupLogger]::Info("Backup: $BackupFilePath")
    [BackupLogger]::Info("Target: $TargetPath")

    if (-not (Test-Path $BackupFilePath)) {
        throw "Backup file not found: $BackupFilePath"
    }

    # 백업 검증
    [BackupLogger]::Info("`nVerifying backup...")
    if (-not (Test-BackupIntegrity -BackupPath $BackupFilePath)) {
        throw "Backup integrity check failed. Cannot restore."
    }

    # 확인
    if (-not $Force) {
        Write-Host "`n⚠️  WARNING: This will overwrite existing Nginx installation!" -ForegroundColor Yellow
        $confirm = Read-Host "Continue with restore? (YES to confirm)"

        if ($confirm -ne "YES") {
            [BackupLogger]::Info("Restore cancelled by user")
            return
        }
    }

    try {
        # 서비스 중지
        $stoppedServices = Stop-NginxServices

        # 기존 설치본 백업
        if (Test-Path $TargetPath) {
            [BackupLogger]::Info("Creating safety backup of current installation...")
            $safetyBackup = Join-Path $Script:Config.BackupPath "pre-restore-backup-$timestamp.zip"

            if (-not (Test-Path $Script:Config.BackupPath)) {
                New-Item -ItemType Directory -Path $Script:Config.BackupPath -Force | Out-Null
            }

            Compress-Archive -Path $TargetPath -DestinationPath $safetyBackup -Force
            [BackupLogger]::Success("✓ Safety backup created: $safetyBackup")
        }

        # 복원
        [BackupLogger]::Progress("Extracting backup...")
        $tempRestoreDir = "$env:TEMP\nginx_restore_$(Get-Random)"

        Expand-Archive -Path $BackupFilePath -DestinationPath $tempRestoreDir -Force

        # 메타데이터 확인
        $metadata = Get-BackupMetadata -BackupPath $BackupFilePath

        if ($metadata) {
            [BackupLogger]::Info("Backup Info:")
            [BackupLogger]::Info("  Date: $($metadata.Timestamp)")
            [BackupLogger]::Info("  Type: $($metadata.BackupType)")
            [BackupLogger]::Info("  Source: $($metadata.SourcePath)")
        }

        # 대상 경로로 복사
        [BackupLogger]::Progress("Restoring files...")

        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force -ErrorAction Stop
        }

        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

        Copy-Item -Path "$tempRestoreDir\*" -Destination $TargetPath -Recurse -Force -ErrorAction Stop

        Remove-Item $tempRestoreDir -Recurse -Force -ErrorAction SilentlyContinue

        [BackupLogger]::Success("✓ Files restored")

        # Nginx config 테스트
        $nginxExe = Join-Path $TargetPath "nginx.exe"
        if (Test-Path $nginxExe) {
            [BackupLogger]::Info("Testing Nginx configuration...")
            $testResult = & $nginxExe -t 2>&1

            if ($LASTEXITCODE -eq 0) {
                [BackupLogger]::Success("✓ Nginx configuration is valid")
            } else {
                [BackupLogger]::Warn("⚠ Nginx configuration test failed:")
                [BackupLogger]::Warn("  $testResult")
            }
        }

        # 서비스 시작
        Start-NginxServices -ServiceNames $stoppedServices

        [BackupLogger]::Success("`n=== Restore Complete ===")
        [BackupLogger]::Info("Restored from: $BackupFilePath")
        [BackupLogger]::Info("Target: $TargetPath")
        [BackupLogger]::Info("`nPlease verify the installation:")
        [BackupLogger]::Info("  1. Check Nginx config: nginx.exe -t")
        [BackupLogger]::Info("  2. Check services: Get-Service nginx, nginx-web-ui")
        [BackupLogger]::Info("  3. Test proxies: Test access to configured domains")

    } catch {
        [BackupLogger]::Error("Restore failed: $($_.Exception.Message)")

        # 서비스 재시작 시도
        if ($stoppedServices) {
            Start-NginxServices -ServiceNames $stoppedServices
        }

        throw
    }
}

#endregion

#region Schedule Functions

function New-BackupSchedule {
    param(
        [string]$ScheduleType,
        [string]$ScheduleTime,
        [string]$ScriptPath
    )

    [BackupLogger]::Info("=== Creating Backup Schedule ===")
    [BackupLogger]::Info("Type: $ScheduleType")
    [BackupLogger]::Info("Time: $ScheduleTime")

    try {
        $taskName = "Nginx-Auto-Backup-$ScheduleType"

        # 기존 태스크 확인
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        if ($existingTask) {
            [BackupLogger]::Warn("Task already exists: $taskName")
            $overwrite = Read-Host "Overwrite existing task? (Y/N)"

            if ($overwrite -ne 'Y') {
                [BackupLogger]::Info("Operation cancelled")
                return
            }

            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        # 트리거 생성
        $timeParts = $ScheduleTime -split ':'
        $triggerTime = Get-Date -Hour $timeParts[0] -Minute $timeParts[1] -Second 0

        switch ($ScheduleType) {
            "Daily" {
                $trigger = New-ScheduledTaskTrigger -Daily -At $triggerTime
            }
            "Weekly" {
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $triggerTime
            }
            "Monthly" {
                $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At $triggerTime
            }
        }

        # 액션 생성
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
                                          -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action Backup"

        # 설정
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable

        # 사용자 (SYSTEM 계정으로 실행)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        # 태스크 등록
        Register-ScheduledTask -TaskName $taskName `
                              -Trigger $trigger `
                              -Action $action `
                              -Settings $settings `
                              -Principal $principal `
                              -Description "Automated Nginx backup ($ScheduleType at $ScheduleTime)" | Out-Null

        [BackupLogger]::Success("✓ Scheduled task created: $taskName")
        [BackupLogger]::Info("  Schedule: $ScheduleType at $ScheduleTime")
        [BackupLogger]::Info("  Next Run: $((Get-ScheduledTask -TaskName $taskName).Triggers[0].StartBoundary)")

        return $true
    } catch {
        [BackupLogger]::Error("Failed to create scheduled task: $($_.Exception.Message)")
        return $false
    }
}

#endregion

#region Cleanup Functions

function Invoke-BackupCleanup {
    param(
        [string]$BackupPath,
        [int]$RetentionDays,
        [int]$RetentionCount
    )

    [BackupLogger]::Info("=== Backup Cleanup ===")
    [BackupLogger]::Info("Path: $BackupPath")
    [BackupLogger]::Info("Retention: $RetentionDays days, max $RetentionCount backups")

    try {
        if (-not (Test-Path $BackupPath)) {
            [BackupLogger]::Warn("Backup path not found: $BackupPath")
            return
        }

        $backups = Get-ChildItem -Path $BackupPath -Filter "nginx-*-backup-*.zip" |
                  Sort-Object LastWriteTime -Descending

        [BackupLogger]::Info("Found $($backups.Count) backups")

        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $deleted = 0

        # 1. 보존 기간 초과 삭제
        foreach ($backup in $backups) {
            if ($backup.LastWriteTime -lt $cutoffDate) {
                [BackupLogger]::Info("  Deleting (expired): $($backup.Name)")
                Remove-Item $backup.FullName -Force
                $deleted++
            }
        }

        # 2. 최대 개수 초과 삭제
        $backups = Get-ChildItem -Path $BackupPath -Filter "nginx-*-backup-*.zip" |
                  Sort-Object LastWriteTime -Descending

        if ($backups.Count -gt $RetentionCount) {
            $toDelete = $backups | Select-Object -Skip $RetentionCount

            foreach ($backup in $toDelete) {
                [BackupLogger]::Info("  Deleting (count limit): $($backup.Name)")
                Remove-Item $backup.FullName -Force
                $deleted++
            }
        }

        [BackupLogger]::Success("✓ Cleanup complete: $deleted backups deleted")

        # 남은 백업 목록
        $remaining = Get-ChildItem -Path $BackupPath -Filter "nginx-*-backup-*.zip" |
                    Sort-Object LastWriteTime -Descending

        [BackupLogger]::Info("Remaining backups: $($remaining.Count)")

    } catch {
        [BackupLogger]::Error("Cleanup failed: $($_.Exception.Message)")
    }
}

#endregion

#region List Function

function Show-BackupList {
    param([string]$BackupPath)

    [BackupLogger]::Info("=== Backup List ===")
    [BackupLogger]::Info("Path: $BackupPath")

    if (-not (Test-Path $BackupPath)) {
        [BackupLogger]::Warn("Backup path not found: $BackupPath")
        return
    }

    $backups = Get-ChildItem -Path $BackupPath -Filter "nginx-*-backup-*.zip" |
              Sort-Object LastWriteTime -Descending

    if ($backups.Count -eq 0) {
        [BackupLogger]::Info("No backups found")
        return
    }

    Write-Host "`n$($backups.Count) backups found:`n" -ForegroundColor Cyan

    $table = @()

    foreach ($backup in $backups) {
        $metadata = Get-BackupMetadata -BackupPath $backup.FullName
        $sizeMB = [math]::Round($backup.Length / 1MB, 2)

        $table += [PSCustomObject]@{
            Name = $backup.Name
            Type = if ($metadata) { $metadata.BackupType } else { "Unknown" }
            Date = $backup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            "Size (MB)" = $sizeMB
            Files = if ($metadata) { $metadata.TotalFiles } else { "N/A" }
            Valid = if (Test-BackupIntegrity -BackupPath $backup.FullName) { "✓" } else { "✗" }
        }
    }

    $table | Format-Table -AutoSize

    Write-Host "`nTo restore a backup, run:" -ForegroundColor Yellow
    Write-Host "  .\05-backup-restore.ps1 -Action Restore -BackupFile `"<backup-file>`"`n" -ForegroundColor Gray
}

#endregion

#region Main Execution

function Start-BackupRestore {
    try {
        # 로그 디렉토리 생성
        if (-not (Test-Path $Script:Config.LogPath)) {
            New-Item -ItemType Directory -Path $Script:Config.LogPath -Force | Out-Null
        }

        [BackupLogger]::Init($logFile)

        Write-Host @"
================================================================================
          Nginx Backup & Restore System v$($Script:Config.Version)
================================================================================
  Action: $Action
  Nginx Path: $($Script:Config.NginxPath)
  Backup Path: $($Script:Config.BackupPath)

================================================================================

"@ -ForegroundColor Cyan

        switch ($Action) {
            "Backup" {
                if ($Incremental) {
                    $result = Invoke-IncrementalBackup -SourcePath $Script:Config.NginxPath `
                                                       -DestinationPath $Script:Config.BackupPath
                } else {
                    $result = Invoke-FullBackup -SourcePath $Script:Config.NginxPath `
                                                -DestinationPath $Script:Config.BackupPath
                }

                if ($result) {
                    [BackupLogger]::Info("`nBackup saved to: $result")
                }
            }

            "Restore" {
                if (-not $BackupFile) {
                    throw "BackupFile parameter is required for restore operation"
                }

                Invoke-Restore -BackupFilePath $BackupFile `
                              -TargetPath $Script:Config.NginxPath `
                              -Force:$Force
            }

            "Verify" {
                if (-not $BackupFile) {
                    throw "BackupFile parameter is required for verify operation"
                }

                $isValid = Test-BackupIntegrity -BackupPath $BackupFile

                if ($isValid) {
                    [BackupLogger]::Success("`n✓ Backup is valid and can be restored")
                } else {
                    [BackupLogger]::Error("`n✗ Backup is corrupted or invalid")
                    exit 1
                }
            }

            "Schedule" {
                $scriptPath = $PSCommandPath
                New-BackupSchedule -ScheduleType $ScheduleType `
                                  -ScheduleTime $ScheduleTime `
                                  -ScriptPath $scriptPath
            }

            "Cleanup" {
                Invoke-BackupCleanup -BackupPath $Script:Config.BackupPath `
                                    -RetentionDays $RetentionDays `
                                    -RetentionCount $RetentionCount
            }

            "List" {
                Show-BackupList -BackupPath $Script:Config.BackupPath
            }
        }

        [BackupLogger]::Info("`n📄 Log file: $logFile")

    } catch {
        [BackupLogger]::Error("Operation failed: $($_.Exception.Message)")
        [BackupLogger]::Error("Stack Trace: $($_.ScriptStackTrace)")
        exit 1
    }
}

# Entry Point
Start-BackupRestore

#endregion
