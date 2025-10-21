#Requires -RunAsAdministrator
<#
.SYNOPSIS
    에어갭 환경 통합 설치 스크립트 (오프라인 환경에서 실행)

.DESCRIPTION
    인터넷 연결 없이 사전 준비된 패키지로 전체 시스템을 설치합니다.
    - Node.js
    - Nginx
    - NSSM (서비스 관리)
    - npm 패키지 (오프라인)
    - DNS 서버 구성
    - 방화벽 규칙

.EXAMPLE
    .\02-install-airgap.ps1
    .\02-install-airgap.ps1 -SkipDNS -SkipFirewall
#>

param(
    [string]$PackageRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$NginxPath = "C:\nginx",
    [string]$NodePath = "C:\Program Files\nodejs",
    [switch]$SkipDNS,
    [switch]$SkipFirewall,
    [switch]$SkipNodeJS,
    [switch]$Force
)

#region Configuration

$Script:Config = @{
    PackageRoot = $PackageRoot
    InstallerPath = Join-Path $PackageRoot "installers"
    NpmPackagesPath = Join-Path $PackageRoot "npm-packages"
    SSLPath = Join-Path $PackageRoot "ssl"
    LogPath = Join-Path $PackageRoot "logs"
    NginxPath = $NginxPath
    NodePath = $NodePath
}

# 설치 로그
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $Script:Config.LogPath "install-$timestamp.log"

#endregion

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $color = @{
        INFO = "Cyan"
        SUCCESS = "Green"
        WARN = "Yellow"
        ERROR = "Red"
    }[$Level]

    $timestamp = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    Write-Host $logMessage -ForegroundColor $color

    # 파일에도 기록
    if (Test-Path $Script:Config.LogPath) {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    }
}

function Test-Checksum {
    param([string]$FilePath, [string]$ExpectedHash)

    if (-not (Test-Path $FilePath)) {
        Write-Log "파일이 존재하지 않습니다: $FilePath" "ERROR"
        return $false
    }

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

    if ($actualHash -eq $ExpectedHash) {
        Write-Log "체크섬 검증 성공: $(Split-Path $FilePath -Leaf)" "SUCCESS"
        return $true
    } else {
        Write-Log "체크섬 불일치: $(Split-Path $FilePath -Leaf)" "ERROR"
        Write-Log "  예상: $ExpectedHash" "ERROR"
        Write-Log "  실제: $actualHash" "ERROR"
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

    Write-Log "MSI 설치 시작: $(Split-Path $MsiPath -Leaf)" "INFO"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MsiPath`" $Arguments /log `"$LogPath`"" -Wait -PassThru

    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Log "MSI 설치 성공" "SUCCESS"
        return $true
    } else {
        Write-Log "MSI 설치 실패 (Exit Code: $($process.ExitCode))" "ERROR"
        return $false
    }
}

#endregion

#region Pre-Installation Checks

Write-Host @"
================================================================================
              에어갭 환경 통합 설치 시스템
================================================================================
  설치 경로:
    - Nginx: $NginxPath
    - Node.js: $NodePath
    - 패키지: $PackageRoot

  옵션:
    - DNS 서버: $(if($SkipDNS){"건너뛰기"}else{"설치"})
    - 방화벽: $(if($SkipFirewall){"건너뛰기"}else{"구성"})
    - Node.js: $(if($SkipNodeJS){"건너뛰기"}else{"설치"})

  [경고] 이 작업은 시스템을 변경합니다!
================================================================================
"@ -ForegroundColor Yellow

# 관리자 권한 확인
if (-not (Test-AdminRights)) {
    Write-Log "관리자 권한이 필요합니다!" "ERROR"
    Write-Log "PowerShell을 관리자 권한으로 다시 실행하세요." "ERROR"
    exit 1
}

# 패키지 디렉토리 확인
if (-not (Test-Path $Script:Config.PackageRoot)) {
    Write-Log "패키지 디렉토리를 찾을 수 없습니다: $($Script:Config.PackageRoot)" "ERROR"
    exit 1
}

# 로그 디렉토리 생성
if (-not (Test-Path $Script:Config.LogPath)) {
    New-Item -ItemType Directory -Path $Script:Config.LogPath -Force | Out-Null
}

Write-Log "설치 시작: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
Write-Log "로그 파일: $logFile" "INFO"

# 확인 메시지
if (-not $Force) {
    $confirm = Read-Host "`n계속하시겠습니까? (YES 입력)"
    if ($confirm -ne "YES") {
        Write-Log "사용자가 설치를 취소했습니다." "WARN"
        exit 0
    }
}

#endregion

#region Step 1: 체크섬 검증

Write-Log "`n=== Step 1: 파일 무결성 검증 ===" "INFO"

$checksumFile = Join-Path $Script:Config.PackageRoot "checksums.txt"
if (Test-Path $checksumFile) {
    Write-Log "checksums.txt 파일 발견" "INFO"

    $checksums = Get-Content $checksumFile | Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' }

    $verificationFailed = $false
    foreach ($line in $checksums) {
        $parts = $line -split '\t'
        if ($parts.Count -eq 2) {
            $fileName = $parts[0]
            $expectedHash = $parts[1]

            # 파일 경로 결정
            $filePath = $null
            if ($fileName -like "*.msi" -or $fileName -like "*.zip" -or $fileName -like "*.exe") {
                $filePath = Join-Path $Script:Config.InstallerPath $fileName
            } elseif ($fileName -like "*.tar.gz" -or $fileName -eq "node_modules.zip") {
                $filePath = Join-Path $Script:Config.NpmPackagesPath $fileName
            }

            if ($filePath -and (Test-Path $filePath)) {
                if (-not (Test-Checksum -FilePath $filePath -ExpectedHash $expectedHash)) {
                    $verificationFailed = $true
                }
            } else {
                Write-Log "파일 없음: $fileName (건너뜀)" "WARN"
            }
        }
    }

    if ($verificationFailed -and -not $Force) {
        Write-Log "체크섬 검증 실패! 파일이 손상되었을 수 있습니다." "ERROR"
        Write-Log "-Force 옵션으로 무시하거나 패키지를 다시 준비하세요." "ERROR"
        exit 1
    }
} else {
    Write-Log "checksums.txt가 없습니다. 검증을 건너뜁니다." "WARN"
}

#endregion

#region Step 2: Visual C++ 재배포 패키지 설치

Write-Log "`n=== Step 2: Visual C++ 재배포 패키지 설치 ===" "INFO"

$vcredistPath = Join-Path $Script:Config.InstallerPath "vcredist_x64.exe"
if (Test-Path $vcredistPath) {
    Write-Log "Visual C++ 설치 중..." "INFO"

    $vcLogPath = Join-Path $Script:Config.LogPath "vcredist-install.log"
    $process = Start-Process -FilePath $vcredistPath -ArgumentList "/install /quiet /norestart /log `"$vcLogPath`"" -Wait -PassThru

    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Log "Visual C++ 설치 완료" "SUCCESS"
    } else {
        Write-Log "Visual C++ 설치 실패 (Exit Code: $($process.ExitCode))" "WARN"
        Write-Log "이미 설치되어 있을 수 있습니다." "INFO"
    }
} else {
    Write-Log "vcredist_x64.exe를 찾을 수 없습니다. 건너뜁니다." "WARN"
}

#endregion

#region Step 3: Node.js 설치

if (-not $SkipNodeJS) {
    Write-Log "`n=== Step 3: Node.js 설치 ===" "INFO"

    # 기존 Node.js 확인
    $existingNode = Get-Command node -ErrorAction SilentlyContinue
    if ($existingNode) {
        Write-Log "Node.js가 이미 설치되어 있습니다: $(node --version)" "INFO"

        if (-not $Force) {
            $reinstall = Read-Host "재설치하시겠습니까? (Y/N)"
            if ($reinstall -ne 'Y') {
                Write-Log "Node.js 설치를 건너뜁니다." "INFO"
            } else {
                $SkipNodeJS = $false
            }
        }
    }

    if (-not $SkipNodeJS -or -not $existingNode) {
        # Node.js MSI 파일 찾기
        $nodeMsi = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "node-*.msi" | Select-Object -First 1

        if ($nodeMsi) {
            $nodeLogPath = Join-Path $Script:Config.LogPath "nodejs-install.log"

            if (Install-MSI -MsiPath $nodeMsi.FullName -LogPath $nodeLogPath) {
                # 환경변수 새로고침
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path", "User")

                # 설치 확인
                Start-Sleep -Seconds 3
                $node = Get-Command node -ErrorAction SilentlyContinue
                if ($node) {
                    Write-Log "Node.js 설치 확인: $(& node --version)" "SUCCESS"
                    Write-Log "npm 버전: $(& npm --version)" "SUCCESS"
                } else {
                    Write-Log "Node.js 설치 후 확인 실패. 재부팅이 필요할 수 있습니다." "WARN"
                }
            }
        } else {
            Write-Log "Node.js MSI 파일을 찾을 수 없습니다." "ERROR"
        }
    }
} else {
    Write-Log "`n=== Step 3: Node.js 설치 (건너뜀) ===" "INFO"
}

#endregion

#region Step 4: npm 패키지 설치 (오프라인)

Write-Log "`n=== Step 4: npm 패키지 설치 (오프라인) ===" "INFO"

$npmPackagePath = $null
$npmArchive = $null

# tar.gz 또는 zip 파일 찾기
if (Test-Path (Join-Path $Script:Config.NpmPackagesPath "node_modules.tar.gz")) {
    $npmArchive = Join-Path $Script:Config.NpmPackagesPath "node_modules.tar.gz"
    $archiveType = "tar.gz"
} elseif (Test-Path (Join-Path $Script:Config.NpmPackagesPath "node_modules.zip")) {
    $npmArchive = Join-Path $Script:Config.NpmPackagesPath "node_modules.zip"
    $archiveType = "zip"
}

if ($npmArchive) {
    Write-Log "npm 패키지 아카이브 발견: $(Split-Path $npmArchive -Leaf)" "INFO"

    # 글로벌 npm 경로 설정
    $globalNpmPath = "C:\nodejs-global"
    if (-not (Test-Path $globalNpmPath)) {
        New-Item -ItemType Directory -Path $globalNpmPath -Force | Out-Null
    }

    # 압축 해제
    Write-Log "패키지 압축 해제 중..." "INFO"
    $extractPath = $globalNpmPath

    try {
        if ($archiveType -eq "tar.gz") {
            $tarExe = Get-Command tar -ErrorAction SilentlyContinue
            if ($tarExe) {
                & tar -xzf $npmArchive -C $extractPath 2>&1 | Out-Null
                Write-Log "tar로 압축 해제 완료" "SUCCESS"
            } else {
                Write-Log "tar 명령어를 찾을 수 없습니다." "ERROR"
            }
        } else {
            Expand-Archive -Path $npmArchive -DestinationPath $extractPath -Force
            Write-Log "zip 압축 해제 완료" "SUCCESS"
        }

        # npm config 설정
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            & npm config set prefix $globalNpmPath
            Write-Log "npm 글로벌 경로 설정: $globalNpmPath" "SUCCESS"

            # 환경변수에 추가
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($currentPath -notlike "*$globalNpmPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$globalNpmPath", "Machine")
                Write-Log "PATH 환경변수 업데이트" "SUCCESS"
            }
        }

    } catch {
        Write-Log "npm 패키지 설치 실패: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "npm 패키지 아카이브를 찾을 수 없습니다. 건너뜁니다." "WARN"
}

#endregion

#region Step 5: Nginx 설치

Write-Log "`n=== Step 5: Nginx 설치 ===" "INFO"

if (Test-Path $NginxPath) {
    Write-Log "Nginx 경로가 이미 존재합니다: $NginxPath" "WARN"

    if ($Force) {
        Write-Log "기존 설치 제거 중..." "INFO"
        Remove-Item $NginxPath -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        $overwrite = Read-Host "덮어쓰시겠습니까? (Y/N)"
        if ($overwrite -eq 'Y') {
            Remove-Item $NginxPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "Nginx 설치를 건너뜁니다." "INFO"
            $skipNginx = $true
        }
    }
}

if (-not $skipNginx) {
    $nginxZip = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "nginx-*.zip" | Select-Object -First 1

    if ($nginxZip) {
        Write-Log "Nginx 압축 해제 중: $($nginxZip.Name)" "INFO"

        $tempPath = "$env:TEMP\nginx_temp_$(Get-Random)"
        Expand-Archive -Path $nginxZip.FullName -DestinationPath $tempPath -Force

        # nginx 폴더 찾기
        $nginxFolder = Get-ChildItem -Path $tempPath -Directory | Where-Object { $_.Name -like "nginx*" } | Select-Object -First 1

        if ($nginxFolder) {
            Move-Item -Path $nginxFolder.FullName -Destination $NginxPath -Force
            Write-Log "Nginx 설치 완료: $NginxPath" "SUCCESS"

            # 필요한 디렉토리 생성
            $dirs = @("conf\ssl", "conf\conf.d", "logs", "temp")
            foreach ($dir in $dirs) {
                $fullPath = Join-Path $NginxPath $dir
                if (-not (Test-Path $fullPath)) {
                    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                }
            }
            Write-Log "Nginx 디렉토리 구조 생성 완료" "SUCCESS"

        } else {
            Write-Log "Nginx 폴더를 찾을 수 없습니다." "ERROR"
        }

        # 임시 폴더 정리
        Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue

    } else {
        Write-Log "Nginx ZIP 파일을 찾을 수 없습니다." "ERROR"
    }
}

#endregion

#region Step 6: NSSM 설치

Write-Log "`n=== Step 6: NSSM 설치 ===" "INFO"

$nssmZip = Get-ChildItem -Path $Script:Config.InstallerPath -Filter "nssm-*.zip" | Select-Object -First 1

if ($nssmZip) {
    $nssmPath = Join-Path $NginxPath "nssm.exe"

    Write-Log "NSSM 압축 해제 중: $($nssmZip.Name)" "INFO"

    $tempPath = "$env:TEMP\nssm_temp_$(Get-Random)"
    Expand-Archive -Path $nssmZip.FullName -DestinationPath $tempPath -Force

    # win64 버전 찾기
    $nssmExe = Get-ChildItem -Path $tempPath -Recurse -Filter "nssm.exe" |
               Where-Object { $_.Directory.Name -eq "win64" } |
               Select-Object -First 1

    if (-not $nssmExe) {
        $nssmExe = Get-ChildItem -Path $tempPath -Recurse -Filter "nssm.exe" | Select-Object -First 1
    }

    if ($nssmExe) {
        Copy-Item $nssmExe.FullName $nssmPath -Force
        Write-Log "NSSM 설치 완료: $nssmPath" "SUCCESS"
    } else {
        Write-Log "NSSM 실행 파일을 찾을 수 없습니다." "ERROR"
    }

    # 임시 폴더 정리
    Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue

} else {
    Write-Log "NSSM ZIP 파일을 찾을 수 없습니다." "ERROR"
}

#endregion

#region Step 7: SSL 인증서 복사

Write-Log "`n=== Step 7: SSL 인증서 확인 ===" "INFO"

$sslSourcePath = $Script:Config.SSLPath
$sslDestPath = Join-Path $NginxPath "conf\ssl"

if (Test-Path $sslSourcePath) {
    $certFiles = Get-ChildItem -Path $sslSourcePath -Include "*.crt","*.pem","*.key" -Recurse

    if ($certFiles.Count -gt 0) {
        Write-Log "SSL 인증서 파일 발견: $($certFiles.Count)개" "INFO"

        if (-not (Test-Path $sslDestPath)) {
            New-Item -ItemType Directory -Path $sslDestPath -Force | Out-Null
        }

        foreach ($file in $certFiles) {
            Copy-Item $file.FullName $sslDestPath -Force
            Write-Log "복사됨: $($file.Name)" "SUCCESS"
        }
    } else {
        Write-Log "SSL 인증서 파일이 없습니다." "WARN"
    }
} else {
    Write-Log "SSL 디렉토리가 없습니다: $sslSourcePath" "WARN"
    Write-Log "나중에 수동으로 인증서를 추가하세요." "INFO"
}

#endregion

#region Step 8: DNS 서버 설치 및 구성

if (-not $SkipDNS) {
    Write-Log "`n=== Step 8: DNS 서버 설치 ===" "INFO"

    try {
        $dnsFeature = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue

        if ($dnsFeature -and $dnsFeature.InstallState -ne "Installed") {
            Write-Log "DNS 서버 기능 설치 중..." "INFO"
            Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
            Write-Log "DNS 서버 설치 완료" "SUCCESS"
        } else {
            Write-Log "DNS 서버가 이미 설치되어 있습니다." "INFO"
        }

    } catch {
        Write-Log "DNS 서버 설치 실패: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "`n=== Step 8: DNS 서버 설치 (건너뜀) ===" "INFO"
}

#endregion

#region Step 9: 방화벽 규칙 구성

if (-not $SkipFirewall) {
    Write-Log "`n=== Step 9: 방화벽 규칙 구성 ===" "INFO"

    $firewallRules = @(
        @{Name="DNS Server (TCP-In)"; Port=53; Protocol="TCP"},
        @{Name="DNS Server (UDP-In)"; Port=53; Protocol="UDP"},
        @{Name="Nginx HTTP (TCP-In)"; Port=80; Protocol="TCP"},
        @{Name="Nginx HTTPS (TCP-In)"; Port=443; Protocol="TCP"},
        @{Name="Node.js App (TCP-In)"; Port=3000; Protocol="TCP"}
    )

    foreach ($rule in $firewallRules) {
        try {
            $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Log "방화벽 규칙 존재: $($rule.Name)" "INFO"
            } else {
                New-NetFirewallRule -DisplayName $rule.Name `
                                    -Direction Inbound `
                                    -Protocol $rule.Protocol `
                                    -LocalPort $rule.Port `
                                    -Action Allow `
                                    -ErrorAction Stop | Out-Null
                Write-Log "방화벽 규칙 추가: $($rule.Name)" "SUCCESS"
            }
        } catch {
            Write-Log "방화벽 규칙 실패: $($rule.Name) - $($_.Exception.Message)" "WARN"
        }
    }
} else {
    Write-Log "`n=== Step 9: 방화벽 규칙 (건너뜀) ===" "INFO"
}

#endregion

#region Step 10: 환경변수 설정

Write-Log "`n=== Step 10: 환경변수 설정 ===" "INFO"

try {
    $pathsToAdd = @()

    if (Test-Path $NodePath) {
        $pathsToAdd += $NodePath
    }

    if (Test-Path "C:\nodejs-global") {
        $pathsToAdd += "C:\nodejs-global"
    }

    if (Test-Path $NginxPath) {
        $pathsToAdd += $NginxPath
    }

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    foreach ($path in $pathsToAdd) {
        if ($currentPath -notlike "*$path*") {
            $currentPath = "$currentPath;$path"
            Write-Log "PATH 추가: $path" "SUCCESS"
        }
    }

    [Environment]::SetEnvironmentVariable("Path", $currentPath, "Machine")
    Write-Log "환경변수 업데이트 완료" "SUCCESS"

} catch {
    Write-Log "환경변수 설정 실패: $($_.Exception.Message)" "ERROR"
}

#endregion

#region 설치 완료

Write-Log "`n=== 설치 완료 ===" "SUCCESS"

Write-Host @"

================================================================================
                    설치 완료!
================================================================================

✅ 설치된 구성요소:
  - Node.js: $(if(Get-Command node -ErrorAction SilentlyContinue){"$(node --version)"}else{"미설치"})
  - npm: $(if(Get-Command npm -ErrorAction SilentlyContinue){"$(npm --version)"}else{"미설치"})
  - Nginx: $NginxPath
  - NSSM: $(if(Test-Path "$NginxPath\nssm.exe"){"설치됨"}else{"미설치"})

📋 다음 단계:
  1. PowerShell을 재시작하여 환경변수 적용
  2. .\03-verify-installation.ps1로 설치 검증
  3. nginx-proxy-manager.ps1로 서비스 관리 시작

📁 중요 경로:
  - Nginx: $NginxPath
  - SSL: $NginxPath\conf\ssl
  - 로그: $NginxPath\logs
  - npm 글로벌: C:\nodejs-global

⚠️  주의사항:
  - SSL 인증서를 확인하세요: $NginxPath\conf\ssl
  - Nginx 서비스를 등록하고 시작하세요
  - DNS Zone 설정이 필요합니다

🔧 서비스 등록:
  cd $NginxPath
  .\nssm.exe install nginx "$NginxPath\nginx.exe"
  Start-Service nginx

================================================================================
"@ -ForegroundColor Green

Write-Log "설치 로그: $logFile" "INFO"
Write-Log "설치 완료 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"

#endregion
