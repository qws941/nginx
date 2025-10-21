#Requires -RunAsAdministrator
<#
.SYNOPSIS
    에어갭 환경 통합 설치 스크립트 v2.0 (고도화 버전)

.DESCRIPTION
    인터넷 연결 없이 사전 준비된 패키지로 전체 시스템을 설치합니다.

    주요 개선사항:
    - 향상된 에러 처리 및 롤백 기능
    - 트랜잭션 기반 설치 상태 추적
    - 진행률 표시 및 상세 로깅
    - 자동 서비스 등록 (Nginx, Web UI)
    - 설치 전 백업 및 복구 기능
    - 설치 검증 자동화
    - Nginx 기본 설정 자동 구성

    설치 구성요소:
    - Node.js v20.11.0
    - Nginx 1.24.0
    - NSSM 2.24 (서비스 관리)
    - Visual C++ 재배포 패키지
    - npm 패키지 (오프라인)
    - 방화벽 규칙 자동 구성

.EXAMPLE
    .\02-install-airgap-enhanced.ps1
    .\02-install-airgap-enhanced.ps1 -SkipDNS -SkipFirewall
    .\02-install-airgap-enhanced.ps1 -Force -AutoService
    .\02-install-airgap-enhanced.ps1 -Rollback

.PARAMETER Rollback
    이전 설치를 롤백합니다.

.PARAMETER AutoService
    Nginx 및 Web UI 서비스를 자동으로 등록하고 시작합니다.
#>

param(
    [string]$PackageRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$NginxPath = "C:\nginx",
    [string]$NodePath = "C:\Program Files\nodejs",
    [switch]$SkipDNS,
    [switch]$SkipFirewall,
    [switch]$SkipNodeJS,
    [switch]$Force,
    [switch]$AutoService,
    [switch]$Rollback
)

#region Configuration

$Script:Config = @{
    Version = "2.0.0"
    PackageRoot = $PackageRoot
    InstallerPath = Join-Path $PackageRoot "installers"
    ScriptsPath = Join-Path $PackageRoot "scripts"
    NpmPackagesPath = Join-Path $PackageRoot "npm-packages"
    SSLPath = Join-Path $PackageRoot "ssl"
    LogPath = Join-Path $PackageRoot "logs"
    BackupPath = Join-Path $PackageRoot "backups"
    StatePath = Join-Path $PackageRoot ".install-state"
    NginxPath = $NginxPath
    NodePath = $NodePath
    NodeJSGlobalPath = "C:\nodejs-global"
}

# 설치 상태 추적
$Script:InstallState = @{
    TaskId = [guid]::NewGuid().ToString()
    StartTime = Get-Date
    CurrentStep = 0
    TotalSteps = 12
    CompletedSteps = @()
    FailedSteps = @()
    BackupCreated = $false
    BackupPath = $null
}

# 타임스탬프 및 로그 파일
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $Script:Config.LogPath "install-enhanced-$timestamp.log"
$errorLogFile = Join-Path $Script:Config.LogPath "install-errors-$timestamp.log"

#endregion

#region Enhanced Logger Class

class EnhancedLogger {
    static [string]$LogFile
    static [string]$ErrorLogFile
    static [string]$TaskId

    static [void] Init([string]$logPath, [string]$errorPath, [string]$taskId) {
        [EnhancedLogger]::LogFile = $logPath
        [EnhancedLogger]::ErrorLogFile = $errorPath
        [EnhancedLogger]::TaskId = $taskId
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
        $logEntry = "[$timestamp] [${Level}] [TaskId: $([EnhancedLogger]::TaskId)] $Message"

        Write-Host $logEntry -ForegroundColor $color

        # 파일에 기록
        try {
            Add-Content -Path ([EnhancedLogger]::LogFile) -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue

            # 에러는 별도 파일에도 기록
            if ($Level -eq "ERROR") {
                $errorEntry = @{
                    timestamp = Get-Date -Format "o"
                    taskId = [EnhancedLogger]::TaskId
                    level = $Level
                    message = $Message
                    stackTrace = (Get-PSCallStack | Select-Object -Skip 1 | Format-Table | Out-String)
                } | ConvertTo-Json -Compress

                Add-Content -Path ([EnhancedLogger]::ErrorLogFile) -Value $errorEntry -Encoding UTF8 -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "Failed to write log: $_" -ForegroundColor Red
        }
    }

    static [void] Info([string]$Message) { [EnhancedLogger]::Log($Message, "INFO") }
    static [void] Success([string]$Message) { [EnhancedLogger]::Log($Message, "SUCCESS") }
    static [void] Warn([string]$Message) { [EnhancedLogger]::Log($Message, "WARN") }
    static [void] Error([string]$Message) { [EnhancedLogger]::Log($Message, "ERROR") }
    static [void] Debug([string]$Message) { [EnhancedLogger]::Log($Message, "DEBUG") }
    static [void] Progress([string]$Message) { [EnhancedLogger]::Log($Message, "PROGRESS") }
}

#endregion

#region Helper Functions

function Save-InstallState {
    param([string]$FilePath = $Script:Config.StatePath)

    try {
        $Script:InstallState | ConvertTo-Json -Depth 10 | Out-File -FilePath $FilePath -Encoding UTF8 -Force
        [EnhancedLogger]::Debug("Installation state saved to $FilePath")
    } catch {
        [EnhancedLogger]::Warn("Failed to save install state: $($_.Exception.Message)")
    }
}

function Load-InstallState {
    param([string]$FilePath = $Script:Config.StatePath)

    if (Test-Path $FilePath) {
        try {
            $state = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
            [EnhancedLogger]::Info("Previous install state loaded from $FilePath")
            return $state
        } catch {
            [EnhancedLogger]::Warn("Failed to load install state: $($_.Exception.Message)")
        }
    }
    return $null
}

function Update-Progress {
    param(
        [int]$Step,
        [string]$Activity,
        [string]$Status = "진행 중..."
    )

    $Script:InstallState.CurrentStep = $Step
    $percentComplete = [math]::Round(($Step / $Script:InstallState.TotalSteps) * 100)

    Write-Progress -Activity $Activity `
                   -Status "$Status ($Step/$($Script:InstallState.TotalSteps))" `
                   -PercentComplete $percentComplete

    [EnhancedLogger]::Progress("[$percentComplete%] Step $Step/$($Script:InstallState.TotalSteps): $Activity")
}

function Complete-Step {
    param(
        [int]$StepNumber,
        [string]$StepName,
        [bool]$Success = $true
    )

    if ($Success) {
        $Script:InstallState.CompletedSteps += @{
            Number = $StepNumber
            Name = $StepName
            CompletedAt = Get-Date
        }
        [EnhancedLogger]::Success("✓ Step $StepNumber completed: $StepName")
    } else {
        $Script:InstallState.FailedSteps += @{
            Number = $StepNumber
            Name = $StepName
            FailedAt = Get-Date
        }
        [EnhancedLogger]::Error("✗ Step $StepNumber failed: $StepName")
    }

    Save-InstallState
}

function Test-Checksum {
    param([string]$FilePath, [string]$ExpectedHash)

    if (-not (Test-Path $FilePath)) {
        [EnhancedLogger]::Error("File not found: $FilePath")
        return $false
    }

    try {
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

        if ($actualHash -eq $ExpectedHash) {
            [EnhancedLogger]::Success("Checksum verified: $(Split-Path $FilePath -Leaf)")
            return $true
        } else {
            [EnhancedLogger]::Error("Checksum mismatch: $(Split-Path $FilePath -Leaf)")
            [EnhancedLogger]::Debug("  Expected: $ExpectedHash")
            [EnhancedLogger]::Debug("  Actual: $actualHash")
            return $false
        }
    } catch {
        [EnhancedLogger]::Error("Checksum calculation failed: $($_.Exception.Message)")
        return $false
    }
}

function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-MSI {
    param(
        [string]$MsiPath,
        [string]$LogPath,
        [string]$Arguments = "/quiet /norestart"
    )

    [EnhancedLogger]::Info("Installing MSI: $(Split-Path $MsiPath -Leaf)")

    try {
        $process = Start-Process -FilePath "msiexec.exe" `
                                 -ArgumentList "/i `"$MsiPath`" $Arguments /log `"$LogPath`"" `
                                 -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            [EnhancedLogger]::Success("MSI installation successful (Exit Code: $($process.ExitCode))")
            return $true
        } else {
            [EnhancedLogger]::Error("MSI installation failed (Exit Code: $($process.ExitCode))")
            [EnhancedLogger]::Debug("See log: $LogPath")
            return $false
        }
    } catch {
        [EnhancedLogger]::Error("MSI installation exception: $($_.Exception.Message)")
        return $false
    }
}

function Backup-ExistingInstallation {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        [EnhancedLogger]::Debug("No existing installation to backup at $Path")
        return $null
    }

    try {
        $backupName = "backup-$(Split-Path $Path -Leaf)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $backupPath = Join-Path $Script:Config.BackupPath $backupName

        [EnhancedLogger]::Info("Creating backup: $backupName")

        # 백업 디렉토리 생성
        if (-not (Test-Path $Script:Config.BackupPath)) {
            New-Item -ItemType Directory -Path $Script:Config.BackupPath -Force | Out-Null
        }

        # 복사
        Copy-Item -Path $Path -Destination $backupPath -Recurse -Force -ErrorAction Stop

        # 압축 (선택적)
        $zipPath = "$backupPath.zip"
        Compress-Archive -Path $backupPath -DestinationPath $zipPath -Force
        Remove-Item -Path $backupPath -Recurse -Force

        $backupSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        [EnhancedLogger]::Success("Backup created: $zipPath ($backupSize MB)")

        return $zipPath
    } catch {
        [EnhancedLogger]::Error("Backup failed: $($_.Exception.Message)")
        return $null
    }
}

function Restore-FromBackup {
    param([string]$BackupPath, [string]$TargetPath)

    if (-not (Test-Path $BackupPath)) {
        [EnhancedLogger]::Error("Backup not found: $BackupPath")
        return $false
    }

    try {
        [EnhancedLogger]::Info("Restoring from backup: $BackupPath")

        # 현재 설치 제거
        if (Test-Path $TargetPath) {
            Remove-Item -Path $TargetPath -Recurse -Force -ErrorAction Stop
        }

        # 압축 해제
        $tempPath = "$env:TEMP\restore_temp_$(Get-Random)"
        Expand-Archive -Path $BackupPath -DestinationPath $tempPath -Force

        # 복원할 폴더 찾기
        $backupFolder = Get-ChildItem -Path $tempPath -Directory | Select-Object -First 1

        if ($backupFolder) {
            Move-Item -Path $backupFolder.FullName -Destination $TargetPath -Force
            [EnhancedLogger]::Success("Restore completed: $TargetPath")
            return $true
        } else {
            [EnhancedLogger]::Error("No folder found in backup")
            return $false
        }
    } catch {
        [EnhancedLogger]::Error("Restore failed: $($_.Exception.Message)")
        return $false
    } finally {
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-Prerequisites {
    [EnhancedLogger]::Info("Checking prerequisites...")

    $issues = @()

    # 관리자 권한
    if (-not (Test-AdminRights)) {
        $issues += "Administrator rights required"
    }

    # 패키지 디렉토리
    if (-not (Test-Path $Script:Config.PackageRoot)) {
        $issues += "Package directory not found: $($Script:Config.PackageRoot)"
    }

    # 설치 파일 디렉토리
    if (-not (Test-Path $Script:Config.InstallerPath)) {
        $issues += "Installers directory not found: $($Script:Config.InstallerPath)"
    }

    # 디스크 공간 (최소 10GB)
    $drive = Split-Path $Script:Config.NginxPath -Qualifier
    $freeSpace = (Get-PSDrive $drive.TrimEnd(':')).Free / 1GB
    if ($freeSpace -lt 10) {
        $issues += "Insufficient disk space: $([math]::Round($freeSpace, 2)) GB free (10 GB required)"
    }

    # Windows Server 버전
    $os = Get-WmiObject -Class Win32_OperatingSystem
    if ($os.Caption -notlike "*Server*") {
        [EnhancedLogger]::Warn("Not running on Windows Server: $($os.Caption)")
    }

    if ($issues.Count -gt 0) {
        [EnhancedLogger]::Error("Prerequisites check failed:")
        foreach ($issue in $issues) {
            [EnhancedLogger]::Error("  - $issue")
        }
        return $false
    }

    [EnhancedLogger]::Success("All prerequisites satisfied")
    return $true
}

function Register-NginxService {
    param([string]$NginxPath)

    $nssmPath = Join-Path $NginxPath "nssm.exe"
    $nginxExe = Join-Path $NginxPath "nginx.exe"

    if (-not (Test-Path $nssmPath)) {
        [EnhancedLogger]::Error("NSSM not found: $nssmPath")
        return $false
    }

    if (-not (Test-Path $nginxExe)) {
        [EnhancedLogger]::Error("Nginx executable not found: $nginxExe")
        return $false
    }

    try {
        # 기존 서비스 확인
        $existingService = Get-Service -Name "nginx" -ErrorAction SilentlyContinue

        if ($existingService) {
            [EnhancedLogger]::Info("Nginx service already exists, removing...")
            Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
            & $nssmPath remove nginx confirm | Out-Null
            Start-Sleep -Seconds 2
        }

        # 서비스 설치
        [EnhancedLogger]::Info("Installing Nginx service...")
        & $nssmPath install nginx $nginxExe | Out-Null
        & $nssmPath set nginx AppDirectory $NginxPath | Out-Null
        & $nssmPath set nginx DisplayName "Nginx Reverse Proxy" | Out-Null
        & $nssmPath set nginx Description "High-performance HTTP and reverse proxy server" | Out-Null
        & $nssmPath set nginx Start SERVICE_AUTO_START | Out-Null
        & $nssmPath set nginx AppStdout (Join-Path $NginxPath "logs\service-stdout.log") | Out-Null
        & $nssmPath set nginx AppStderr (Join-Path $NginxPath "logs\service-stderr.log") | Out-Null

        [EnhancedLogger]::Success("Nginx service registered")

        # 서비스 시작
        Start-Sleep -Seconds 1
        Start-Service -Name "nginx"
        [EnhancedLogger]::Success("Nginx service started")

        return $true
    } catch {
        [EnhancedLogger]::Error("Failed to register Nginx service: $($_.Exception.Message)")
        return $false
    }
}

function Register-WebUIService {
    param([string]$ScriptsPath, [string]$NginxPath)

    $nssmPath = Join-Path $NginxPath "nssm.exe"
    $nodeExe = Join-Path $Script:Config.NodePath "node.exe"
    $webUIScript = Join-Path $ScriptsPath "nginx-web-ui-enhanced.js"

    # Fallback to original if enhanced doesn't exist
    if (-not (Test-Path $webUIScript)) {
        $webUIScript = Join-Path $ScriptsPath "nginx-web-ui.js"
    }

    if (-not (Test-Path $nssmPath)) {
        [EnhancedLogger]::Error("NSSM not found: $nssmPath")
        return $false
    }

    if (-not (Test-Path $nodeExe)) {
        [EnhancedLogger]::Warn("Node.exe not found: $nodeExe, using system node")
        $nodeExe = "node"
    }

    if (-not (Test-Path $webUIScript)) {
        [EnhancedLogger]::Error("Web UI script not found: $webUIScript")
        return $false
    }

    try {
        # 기존 서비스 확인
        $existingService = Get-Service -Name "nginx-web-ui" -ErrorAction SilentlyContinue

        if ($existingService) {
            [EnhancedLogger]::Info("Web UI service already exists, removing...")
            Stop-Service -Name "nginx-web-ui" -Force -ErrorAction SilentlyContinue
            & $nssmPath remove nginx-web-ui confirm | Out-Null
            Start-Sleep -Seconds 2
        }

        # 서비스 설치
        [EnhancedLogger]::Info("Installing Web UI service...")
        & $nssmPath install nginx-web-ui $nodeExe $webUIScript | Out-Null
        & $nssmPath set nginx-web-ui AppDirectory $ScriptsPath | Out-Null
        & $nssmPath set nginx-web-ui DisplayName "Nginx Web UI" | Out-Null
        & $nssmPath set nginx-web-ui Description "Web-based management interface for Nginx" | Out-Null
        & $nssmPath set nginx-web-ui Start SERVICE_AUTO_START | Out-Null
        & $nssmPath set nginx-web-ui AppStdout (Join-Path $NginxPath "logs\web-ui-stdout.log") | Out-Null
        & $nssmPath set nginx-web-ui AppStderr (Join-Path $NginxPath "logs\web-ui-stderr.log") | Out-Null

        [EnhancedLogger]::Success("Web UI service registered")

        # 서비스 시작
        Start-Sleep -Seconds 1
        Start-Service -Name "nginx-web-ui"
        [EnhancedLogger]::Success("Web UI service started (http://127.0.0.1:8080)")

        return $true
    } catch {
        [EnhancedLogger]::Error("Failed to register Web UI service: $($_.Exception.Message)")
        return $false
    }
}

function Initialize-NginxConfig {
    param([string]$NginxPath)

    $confPath = Join-Path $NginxPath "conf\nginx.conf"

    if (-not (Test-Path $confPath)) {
        [EnhancedLogger]::Warn("nginx.conf not found, creating default configuration...")

        $defaultConfig = @"
worker_processes  auto;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  logs/access.log  main;
    error_log   logs/error.log   warn;

    # Performance
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    # Security
    server_tokens off;
    client_max_body_size 100M;

    # Gzip
    gzip  on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Virtual Host Configs
    include conf.d/*.conf;

    # Default server
    server {
        listen       80;
        server_name  localhost;

        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
"@

        try {
            $defaultConfig | Out-File -FilePath $confPath -Encoding UTF8 -Force
            [EnhancedLogger]::Success("Default nginx.conf created")
            return $true
        } catch {
            [EnhancedLogger]::Error("Failed to create nginx.conf: $($_.Exception.Message)")
            return $false
        }
    } else {
        [EnhancedLogger]::Info("nginx.conf already exists")
        return $true
    }
}

function Test-NginxConfig {
    param([string]$NginxPath)

    $nginxExe = Join-Path $NginxPath "nginx.exe"

    if (-not (Test-Path $nginxExe)) {
        [EnhancedLogger]::Error("Nginx executable not found: $nginxExe")
        return $false
    }

    try {
        $testResult = & $nginxExe -t 2>&1
        $testOutput = $testResult | Out-String

        if ($LASTEXITCODE -eq 0) {
            [EnhancedLogger]::Success("Nginx configuration is valid")
            [EnhancedLogger]::Debug($testOutput.Trim())
            return $true
        } else {
            [EnhancedLogger]::Error("Nginx configuration test failed:")
            [EnhancedLogger]::Error($testOutput.Trim())
            return $false
        }
    } catch {
        [EnhancedLogger]::Error("Failed to test Nginx config: $($_.Exception.Message)")
        return $false
    }
}

#endregion

#region Rollback Function

function Invoke-Rollback {
    [EnhancedLogger]::Info("=== ROLLBACK MODE ===")

    # 상태 파일 로드
    $state = Load-InstallState

    if (-not $state) {
        [EnhancedLogger]::Error("No installation state found. Cannot rollback.")
        return
    }

    if (-not $state.BackupCreated -or -not $state.BackupPath) {
        [EnhancedLogger]::Error("No backup found. Cannot rollback.")
        return
    }

    [EnhancedLogger]::Info("Backup found: $($state.BackupPath)")
    $confirm = Read-Host "Restore from this backup? (YES to confirm)"

    if ($confirm -ne "YES") {
        [EnhancedLogger]::Info("Rollback cancelled by user")
        return
    }

    # 서비스 중지
    [EnhancedLogger]::Info("Stopping services...")
    Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "nginx-web-ui" -Force -ErrorAction SilentlyContinue

    # 복원
    if (Restore-FromBackup -BackupPath $state.BackupPath -TargetPath $Script:Config.NginxPath) {
        [EnhancedLogger]::Success("Rollback completed successfully")

        # 상태 파일 삭제
        if (Test-Path $Script:Config.StatePath) {
            Remove-Item -Path $Script:Config.StatePath -Force
        }
    } else {
        [EnhancedLogger]::Error("Rollback failed")
    }
}

#endregion

#region Main Installation Flow

function Start-Installation {
    try {
        # 디렉토리 생성
        $requiredDirs = @($Script:Config.LogPath, $Script:Config.BackupPath)
        foreach ($dir in $requiredDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        # 로거 초기화
        [EnhancedLogger]::Init($logFile, $errorLogFile, $Script:InstallState.TaskId)

        [EnhancedLogger]::Info("==========================================================")
        [EnhancedLogger]::Info("  Airgap Installation System v$($Script:Config.Version)")
        [EnhancedLogger]::Info("  Task ID: $($Script:InstallState.TaskId)")
        [EnhancedLogger]::Info("==========================================================")

        # Step 0: 사전 검사
        Update-Progress -Step 0 -Activity "Checking prerequisites" -Status "Validating system requirements"

        if (-not (Test-Prerequisites)) {
            throw "Prerequisites check failed. Cannot proceed with installation."
        }

        Complete-Step -StepNumber 0 -StepName "Prerequisites Check" -Success $true

        # 확인 메시지
        if (-not $Force) {
            Write-Host @"

================================================================================
Installation Configuration:
================================================================================
  Paths:
    - Nginx: $($Script:Config.NginxPath)
    - Node.js: $($Script:Config.NodePath)
    - Package: $($Script:Config.PackageRoot)

  Options:
    - DNS Server: $(if($SkipDNS){"Skip"}else{"Install"})
    - Firewall: $(if($SkipFirewall){"Skip"}else{"Configure"})
    - Node.js: $(if($SkipNodeJS){"Skip"}else{"Install"})
    - Auto Service: $(if($AutoService){"Yes"}else{"No"})

  ⚠️  WARNING: This will modify your system!
================================================================================

"@ -ForegroundColor Yellow

            $confirm = Read-Host "Continue with installation? (YES to proceed)"
            if ($confirm -ne "YES") {
                [EnhancedLogger]::Info("Installation cancelled by user")
                return
            }
        }

        # Step 1: 백업 생성
        Update-Progress -Step 1 -Activity "Creating backup" -Status "Backing up existing installation"

        if (Test-Path $Script:Config.NginxPath) {
            $backupPath = Backup-ExistingInstallation -Path $Script:Config.NginxPath
            if ($backupPath) {
                $Script:InstallState.BackupCreated = $true
                $Script:InstallState.BackupPath = $backupPath
                Save-InstallState
            }
        }

        Complete-Step -StepNumber 1 -StepName "Backup Creation" -Success $true

        # Step 2: 체크섬 검증
        Update-Progress -Step 2 -Activity "Verifying file integrity" -Status "Checking SHA256 checksums"

        $checksumFile = Join-Path $Script:Config.PackageRoot "checksums.txt"
        $verificationSuccess = $true

        if (Test-Path $checksumFile) {
            $checksums = Get-Content $checksumFile | Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' }

            foreach ($line in $checksums) {
                $parts = $line -split '\t'
                if ($parts.Count -eq 2) {
                    $fileName = $parts[0]
                    $expectedHash = $parts[1]

                    $filePath = $null
                    if ($fileName -like "*.msi" -or $fileName -like "*.zip" -or $fileName -like "*.exe") {
                        $filePath = Join-Path $Script:Config.InstallerPath $fileName
                    } elseif ($fileName -like "*.tar.gz" -or $fileName -eq "node_modules.zip") {
                        $filePath = Join-Path $Script:Config.NpmPackagesPath $fileName
                    }

                    if ($filePath -and (Test-Path $filePath)) {
                        if (-not (Test-Checksum -FilePath $filePath -ExpectedHash $expectedHash)) {
                            $verificationSuccess = $false
                            if (-not $Force) {
                                throw "Checksum verification failed for $fileName. Use -Force to skip."
                            }
                        }
                    }
                }
            }
        } else {
            [EnhancedLogger]::Warn("checksums.txt not found, skipping verification")
        }

        Complete-Step -StepNumber 2 -StepName "Checksum Verification" -Success $verificationSuccess

        # Step 3: Visual C++ 설치
        Update-Progress -Step 3 -Activity "Installing Visual C++ Redistributable" -Status "Installing dependencies"

        $vcredistPath = Join-Path $Script:Config.InstallerPath "vcredist_x64.exe"
        $vcSuccess = $false

        if (Test-Path $vcredistPath) {
            $vcLogPath = Join-Path $Script:Config.LogPath "vcredist-install.log"
            $process = Start-Process -FilePath $vcredistPath `
                                     -ArgumentList "/install /quiet /norestart /log `"$vcLogPath`"" `
                                     -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1638) {
                [EnhancedLogger]::Success("Visual C++ installed successfully")
                $vcSuccess = $true
            } else {
                [EnhancedLogger]::Warn("Visual C++ installation returned exit code: $($process.ExitCode)")
                $vcSuccess = $true  # Continue anyway
            }
        } else {
            [EnhancedLogger]::Warn("vcredist_x64.exe not found, skipping")
            $vcSuccess = $true
        }

        Complete-Step -StepNumber 3 -StepName "Visual C++ Installation" -Success $vcSuccess

        # Step 4: Node.js 설치
        Update-Progress -Step 4 -Activity "Installing Node.js" -Status "Installing Node.js runtime"

        $nodeSuccess = $true
        if (-not $SkipNodeJS) {
            $existingNode = Get-Command node -ErrorAction SilentlyContinue
            $shouldInstall = $true

            if ($existingNode -and -not $Force) {
                [EnhancedLogger]::Info("Node.js already installed: $(node --version)")
                $shouldInstall = $false
            }

            if ($shouldInstall) {
                $nodeMsi = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "node-*.msi" | Select-Object -First 1

                if ($nodeMsi) {
                    $nodeLogPath = Join-Path $Script:Config.LogPath "nodejs-install.log"
                    $nodeSuccess = Install-MSI -MsiPath $nodeMsi.FullName -LogPath $nodeLogPath

                    if ($nodeSuccess) {
                        # 환경변수 새로고침
                        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                                   [System.Environment]::GetEnvironmentVariable("Path", "User")

                        Start-Sleep -Seconds 3
                        $node = Get-Command node -ErrorAction SilentlyContinue
                        if ($node) {
                            [EnhancedLogger]::Success("Node.js version: $(& node --version)")
                            [EnhancedLogger]::Success("npm version: $(& npm --version)")
                        }
                    }
                } else {
                    [EnhancedLogger]::Error("Node.js MSI file not found")
                    $nodeSuccess = $false
                }
            }
        }

        Complete-Step -StepNumber 4 -StepName "Node.js Installation" -Success $nodeSuccess

        # Step 5: npm 패키지 설치 (오프라인)
        Update-Progress -Step 5 -Activity "Installing npm packages" -Status "Extracting offline npm packages"

        $npmSuccess = $true
        $npmArchive = $null
        $archiveType = $null

        if (Test-Path (Join-Path $Script:Config.NpmPackagesPath "node_modules.tar.gz")) {
            $npmArchive = Join-Path $Script:Config.NpmPackagesPath "node_modules.tar.gz"
            $archiveType = "tar.gz"
        } elseif (Test-Path (Join-Path $Script:Config.NpmPackagesPath "node_modules.zip")) {
            $npmArchive = Join-Path $Script:Config.NpmPackagesPath "node_modules.zip"
            $archiveType = "zip"
        }

        if ($npmArchive) {
            [EnhancedLogger]::Info("npm archive found: $(Split-Path $npmArchive -Leaf)")

            $globalNpmPath = $Script:Config.NodeJSGlobalPath
            if (-not (Test-Path $globalNpmPath)) {
                New-Item -ItemType Directory -Path $globalNpmPath -Force | Out-Null
            }

            try {
                if ($archiveType -eq "tar.gz") {
                    $tarExe = Get-Command tar -ErrorAction SilentlyContinue
                    if ($tarExe) {
                        & tar -xzf $npmArchive -C $globalNpmPath 2>&1 | Out-Null
                        [EnhancedLogger]::Success("npm packages extracted with tar")
                    } else {
                        [EnhancedLogger]::Warn("tar not available, skipping npm packages")
                    }
                } else {
                    Expand-Archive -Path $npmArchive -DestinationPath $globalNpmPath -Force
                    [EnhancedLogger]::Success("npm packages extracted with Expand-Archive")
                }

                # npm config
                if (Get-Command npm -ErrorAction SilentlyContinue) {
                    & npm config set prefix $globalNpmPath 2>&1 | Out-Null
                    [EnhancedLogger]::Success("npm global path configured: $globalNpmPath")
                }
            } catch {
                [EnhancedLogger]::Error("npm package installation failed: $($_.Exception.Message)")
                $npmSuccess = $false
            }
        } else {
            [EnhancedLogger]::Warn("npm archive not found, skipping")
        }

        Complete-Step -StepNumber 5 -StepName "npm Package Installation" -Success $npmSuccess

        # Step 6: Nginx 설치
        Update-Progress -Step 6 -Activity "Installing Nginx" -Status "Extracting Nginx files"

        $nginxSuccess = $false
        $skipNginx = $false

        if (Test-Path $Script:Config.NginxPath) {
            [EnhancedLogger]::Warn("Nginx path already exists: $($Script:Config.NginxPath)")
            if ($Force) {
                Remove-Item $Script:Config.NginxPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                $skipNginx = $true
                [EnhancedLogger]::Info("Skipping Nginx installation (already exists)")
            }
        }

        if (-not $skipNginx) {
            $nginxZip = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "nginx-*.zip" | Select-Object -First 1

            if ($nginxZip) {
                try {
                    $tempPath = "$env:TEMP\nginx_temp_$(Get-Random)"
                    Expand-Archive -Path $nginxZip.FullName -DestinationPath $tempPath -Force

                    $nginxFolder = Get-ChildItem -Path $tempPath -Directory | Where-Object { $_.Name -like "nginx*" } | Select-Object -First 1

                    if ($nginxFolder) {
                        Move-Item -Path $nginxFolder.FullName -Destination $Script:Config.NginxPath -Force
                        [EnhancedLogger]::Success("Nginx installed: $($Script:Config.NginxPath)")

                        # 디렉토리 구조 생성
                        $dirs = @("conf\ssl", "conf\conf.d", "logs", "temp", "html")
                        foreach ($dir in $dirs) {
                            $fullPath = Join-Path $Script:Config.NginxPath $dir
                            if (-not (Test-Path $fullPath)) {
                                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                            }
                        }
                        [EnhancedLogger]::Success("Nginx directory structure created")

                        $nginxSuccess = $true
                    } else {
                        [EnhancedLogger]::Error("Nginx folder not found in archive")
                    }

                    Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    [EnhancedLogger]::Error("Nginx installation failed: $($_.Exception.Message)")
                }
            } else {
                [EnhancedLogger]::Error("Nginx ZIP file not found")
            }
        } else {
            $nginxSuccess = $true
        }

        Complete-Step -StepNumber 6 -StepName "Nginx Installation" -Success $nginxSuccess

        # Step 7: NSSM 설치
        Update-Progress -Step 7 -Activity "Installing NSSM" -Status "Extracting service manager"

        $nssmSuccess = $false
        $nssmZip = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "nssm-*.zip" | Select-Object -First 1

        if ($nssmZip) {
            try {
                $nssmPath = Join-Path $Script:Config.NginxPath "nssm.exe"
                $tempPath = "$env:TEMP\nssm_temp_$(Get-Random)"

                Expand-Archive -Path $nssmZip.FullName -DestinationPath $tempPath -Force

                $nssmExe = Get-ChildItem -Path $tempPath -Recurse -Filter "nssm.exe" |
                          Where-Object { $_.Directory.Name -eq "win64" } |
                          Select-Object -First 1

                if (-not $nssmExe) {
                    $nssmExe = Get-ChildItem -Path $tempPath -Recurse -Filter "nssm.exe" | Select-Object -First 1
                }

                if ($nssmExe) {
                    Copy-Item $nssmExe.FullName $nssmPath -Force
                    [EnhancedLogger]::Success("NSSM installed: $nssmPath")
                    $nssmSuccess = $true
                } else {
                    [EnhancedLogger]::Error("NSSM executable not found in archive")
                }

                Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                [EnhancedLogger]::Error("NSSM installation failed: $($_.Exception.Message)")
            }
        } else {
            [EnhancedLogger]::Error("NSSM ZIP file not found")
        }

        Complete-Step -StepNumber 7 -StepName "NSSM Installation" -Success $nssmSuccess

        # Step 8: SSL 인증서 복사
        Update-Progress -Step 8 -Activity "Copying SSL certificates" -Status "Installing SSL certificates"

        $sslSuccess = $true
        $sslSourcePath = $Script:Config.SSLPath
        $sslDestPath = Join-Path $Script:Config.NginxPath "conf\ssl"

        if (Test-Path $sslSourcePath) {
            $certFiles = Get-ChildItem -Path $sslSourcePath -Include "*.crt","*.pem","*.key" -Recurse

            if ($certFiles.Count -gt 0) {
                if (-not (Test-Path $sslDestPath)) {
                    New-Item -ItemType Directory -Path $sslDestPath -Force | Out-Null
                }

                foreach ($file in $certFiles) {
                    Copy-Item $file.FullName $sslDestPath -Force
                    [EnhancedLogger]::Success("SSL cert copied: $($file.Name)")
                }
            } else {
                [EnhancedLogger]::Warn("No SSL certificate files found")
            }
        } else {
            [EnhancedLogger]::Warn("SSL directory not found: $sslSourcePath")
        }

        Complete-Step -StepNumber 8 -StepName "SSL Certificate Installation" -Success $sslSuccess

        # Step 9: Nginx 설정 초기화
        Update-Progress -Step 9 -Activity "Configuring Nginx" -Status "Creating default configuration"

        $configSuccess = Initialize-NginxConfig -NginxPath $Script:Config.NginxPath
        Complete-Step -StepNumber 9 -StepName "Nginx Configuration" -Success $configSuccess

        # Step 10: DNS 서버 설치 (선택)
        Update-Progress -Step 10 -Activity "Installing DNS Server" -Status "Installing DNS feature"

        $dnsSuccess = $true
        if (-not $SkipDNS) {
            try {
                $dnsFeature = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue

                if ($dnsFeature -and $dnsFeature.InstallState -ne "Installed") {
                    [EnhancedLogger]::Info("Installing DNS Server feature...")
                    Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
                    [EnhancedLogger]::Success("DNS Server installed")
                } else {
                    [EnhancedLogger]::Info("DNS Server already installed")
                }
            } catch {
                [EnhancedLogger]::Error("DNS installation failed: $($_.Exception.Message)")
                $dnsSuccess = $false
            }
        } else {
            [EnhancedLogger]::Info("DNS Server installation skipped")
        }

        Complete-Step -StepNumber 10 -StepName "DNS Server Installation" -Success $dnsSuccess

        # Step 11: 방화벽 규칙
        Update-Progress -Step 11 -Activity "Configuring firewall" -Status "Adding firewall rules"

        $firewallSuccess = $true
        if (-not $SkipFirewall) {
            $firewallRules = @(
                @{Name="DNS Server (TCP-In)"; Port=53; Protocol="TCP"},
                @{Name="DNS Server (UDP-In)"; Port=53; Protocol="UDP"},
                @{Name="Nginx HTTP (TCP-In)"; Port=80; Protocol="TCP"},
                @{Name="Nginx HTTPS (TCP-In)"; Port=443; Protocol="TCP"},
                @{Name="Web UI (TCP-In)"; Port=8080; Protocol="TCP"}
            )

            foreach ($rule in $firewallRules) {
                try {
                    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
                    if (-not $existing) {
                        New-NetFirewallRule -DisplayName $rule.Name `
                                           -Direction Inbound `
                                           -Protocol $rule.Protocol `
                                           -LocalPort $rule.Port `
                                           -Action Allow `
                                           -ErrorAction Stop | Out-Null
                        [EnhancedLogger]::Success("Firewall rule added: $($rule.Name)")
                    } else {
                        [EnhancedLogger]::Info("Firewall rule exists: $($rule.Name)")
                    }
                } catch {
                    [EnhancedLogger]::Warn("Firewall rule failed: $($rule.Name)")
                }
            }
        } else {
            [EnhancedLogger]::Info("Firewall configuration skipped")
        }

        Complete-Step -StepNumber 11 -StepName "Firewall Configuration" -Success $firewallSuccess

        # Step 12: 환경변수 설정
        Update-Progress -Step 12 -Activity "Configuring environment" -Status "Updating PATH variables"

        $envSuccess = $true
        try {
            $pathsToAdd = @(
                $Script:Config.NodePath,
                $Script:Config.NodeJSGlobalPath,
                $Script:Config.NginxPath
            )

            $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $modified = $false

            foreach ($path in $pathsToAdd) {
                if ((Test-Path $path) -and ($currentPath -notlike "*$path*")) {
                    $currentPath = "$currentPath;$path"
                    $modified = $true
                    [EnhancedLogger]::Success("PATH added: $path")
                }
            }

            if ($modified) {
                [Environment]::SetEnvironmentVariable("Path", $currentPath, "Machine")
                [EnhancedLogger]::Success("Environment variables updated")
            } else {
                [EnhancedLogger]::Info("PATH already configured")
            }
        } catch {
            [EnhancedLogger]::Error("Environment variable update failed: $($_.Exception.Message)")
            $envSuccess = $false
        }

        Complete-Step -StepNumber 12 -StepName "Environment Variables" -Success $envSuccess

        # Optional: 자동 서비스 등록
        if ($AutoService) {
            [EnhancedLogger]::Info("`n=== Auto Service Registration ===")

            # Nginx config 테스트
            if (Test-NginxConfig -NginxPath $Script:Config.NginxPath) {
                # Nginx 서비스 등록
                if (Register-NginxService -NginxPath $Script:Config.NginxPath) {
                    [EnhancedLogger]::Success("Nginx service registered and started")
                }

                # Web UI 서비스 등록
                if (Register-WebUIService -ScriptsPath $Script:Config.ScriptsPath -NginxPath $Script:Config.NginxPath) {
                    [EnhancedLogger]::Success("Web UI service registered and started")
                }
            } else {
                [EnhancedLogger]::Warn("Nginx config test failed, skipping service registration")
            }
        }

        Write-Progress -Activity "Installation Complete" -Completed

        # 완료 요약
        $completedCount = $Script:InstallState.CompletedSteps.Count
        $failedCount = $Script:InstallState.FailedSteps.Count
        $duration = (Get-Date) - $Script:InstallState.StartTime

        [EnhancedLogger]::Success("`n==========================================================")
        [EnhancedLogger]::Success("  Installation Complete!")
        [EnhancedLogger]::Success("==========================================================")
        [EnhancedLogger]::Info("  Completed Steps: $completedCount")
        if ($failedCount -gt 0) {
            [EnhancedLogger]::Warn("  Failed Steps: $failedCount")
        }
        [EnhancedLogger]::Info("  Duration: $($duration.ToString('mm\:ss'))")
        [EnhancedLogger]::Info("  Task ID: $($Script:InstallState.TaskId)")

        Write-Host @"

================================================================================
                    Installation Summary
================================================================================

✅ Installed Components:
  - Node.js: $(if(Get-Command node -ErrorAction SilentlyContinue){"$(node --version)"}else{"Not installed"})
  - npm: $(if(Get-Command npm -ErrorAction SilentlyContinue){"$(npm --version)"}else{"Not installed"})
  - Nginx: $($Script:Config.NginxPath)
  - NSSM: $(if(Test-Path (Join-Path $Script:Config.NginxPath "nssm.exe")){"Installed"}else{"Not installed"})

📋 Next Steps:
  1. Restart PowerShell to apply environment variables
  2. Run .\03-verify-installation.ps1 to verify installation
  3. $(if($AutoService){"Services are already running"}else{"Register services with .\nssm.exe"})
  $(if($AutoService){"4. Access Web UI at http://127.0.0.1:8080"}else{""})

📁 Important Paths:
  - Nginx: $($Script:Config.NginxPath)
  - SSL: $(Join-Path $Script:Config.NginxPath "conf\ssl")
  - Logs: $(Join-Path $Script:Config.NginxPath "logs")
  - npm Global: $($Script:Config.NodeJSGlobalPath)
  - Backup: $($Script:Config.BackupPath)

$(if($Script:InstallState.BackupCreated){
"💾 Backup Created: $($Script:InstallState.BackupPath)
   Rollback with: .\02-install-airgap-enhanced.ps1 -Rollback
"
}else{""})

🔧 Service Management:
  $(if($AutoService){
"✅ Services are running:
  - Nginx: Get-Service nginx
  - Web UI: Get-Service nginx-web-ui

  Web UI: http://127.0.0.1:8080"
  }else{
"Manual service registration:
  cd $($Script:Config.NginxPath)
  .\nssm.exe install nginx `"$($Script:Config.NginxPath)\nginx.exe`"
  Start-Service nginx"
  })

📄 Logs:
  - Installation: $logFile
  - Errors: $errorLogFile

================================================================================
"@ -ForegroundColor Green

        # 상태 파일 정리
        if (Test-Path $Script:Config.StatePath) {
            Remove-Item -Path $Script:Config.StatePath -Force -ErrorAction SilentlyContinue
        }

    } catch {
        [EnhancedLogger]::Error("Installation failed: $($_.Exception.Message)")
        [EnhancedLogger]::Error("Stack Trace: $($_.ScriptStackTrace)")

        Write-Host @"

================================================================================
                    Installation Failed
================================================================================

❌ Error: $($_.Exception.Message)

📋 Troubleshooting:
  1. Check logs: $logFile
  2. Check error log: $errorLogFile
  3. Run with -Force to skip some checks
  $(if($Script:InstallState.BackupCreated){
"4. Rollback: .\02-install-airgap-enhanced.ps1 -Rollback"
  }else{""})

================================================================================
"@ -ForegroundColor Red

        exit 1
    }
}

#endregion

#region Entry Point

# Rollback 모드
if ($Rollback) {
    Invoke-Rollback
    exit 0
}

# 일반 설치 모드
Start-Installation

#endregion
