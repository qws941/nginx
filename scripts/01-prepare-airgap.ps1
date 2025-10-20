#Requires -RunAsAdministrator
<#
.SYNOPSIS
    에어갭 환경용 설치 패키지 준비 스크립트 (인터넷 환경에서 실행)

.DESCRIPTION
    인터넷이 연결된 환경에서 실행하여 에어갭 환경에 필요한 모든 파일을 수집합니다.
    - Node.js 설치 파일
    - Nginx 압축 파일
    - NSSM 서비스 관리 도구
    - npm 패키지 (오프라인 저장소)
    - Visual C++ 재배포 패키지

.EXAMPLE
    .\01-prepare-airgap.ps1
    .\01-prepare-airgap.ps1 -NodeVersion "20.11.0" -OutputPath "D:\airgap-package"
#>

param(
    [string]$NodeVersion = "20.11.0",
    [string]$NginxVersion = "1.24.0",
    [string]$NssmVersion = "2.24",
    [string]$OutputPath = "$PSScriptRoot\..\airgap-package",
    [string[]]$NpmPackages = @(
        "express@4.18.2",
        "pm2@5.3.0",
        "dotenv@16.3.1",
        "cors@2.8.5",
        "body-parser@1.20.2",
        "helmet@7.1.0"
    )
)

#region Helper Functions

function Write-Step {
    param([string]$Message, [string]$Status = "INFO")

    $color = switch($Status) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        default   { "White" }
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Status] $Message" -ForegroundColor $color
}

function Get-FileHash256 {
    param([string]$FilePath)

    if (Test-Path $FilePath) {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
        return $hash.Hash
    }
    return $null
}

function Download-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )

    Write-Step "다운로드 중: $Description" "INFO"
    Write-Step "  URL: $Url" "INFO"
    Write-Step "  저장: $OutputPath" "INFO"

    try {
        # System.Net.WebClient 사용 (진행률 표시)
        $webClient = New-Object System.Net.WebClient

        # 진행률 이벤트 등록
        $eventName = "DownloadProgressChanged_$(Get-Random)"
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -SourceIdentifier $eventName -Action {
            $percent = $event.SourceEventArgs.ProgressPercentage
            Write-Progress -Activity "다운로드 중..." -Status "$percent% 완료" -PercentComplete $percent
        } | Out-Null

        # 다운로드 시작
        $webClient.DownloadFile($Url, $OutputPath)

        # 이벤트 정리
        Unregister-Event -SourceIdentifier $eventName -ErrorAction SilentlyContinue
        Remove-Job -Name $eventName -ErrorAction SilentlyContinue
        Write-Progress -Activity "다운로드 중..." -Completed

        $webClient.Dispose()

        Write-Step "다운로드 완료: $(Split-Path $OutputPath -Leaf)" "SUCCESS"
        return $true

    } catch {
        Write-Step "다운로드 실패: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

#endregion

#region Main Process

Write-Host @"
================================================================================
              에어갭 환경 설치 패키지 준비 도구
================================================================================
  Node.js 버전: $NodeVersion
  Nginx 버전: $NginxVersion
  NSSM 버전: $NssmVersion
  출력 경로: $OutputPath

  [중요] 인터넷 연결이 필요합니다!
================================================================================
"@ -ForegroundColor Yellow

# 출력 디렉토리 생성
Write-Step "출력 디렉토리 준비 중..." "INFO"
$directories = @(
    "$OutputPath\installers",
    "$OutputPath\npm-packages",
    "$OutputPath\scripts",
    "$OutputPath\ssl",
    "$OutputPath\configs",
    "$OutputPath\logs"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Step "생성됨: $dir" "SUCCESS"
    }
}

# 체크섬 파일 초기화
$checksumFile = "$OutputPath\checksums.txt"
if (Test-Path $checksumFile) {
    Remove-Item $checksumFile -Force
}
"# SHA256 Checksums - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" | Out-File $checksumFile -Encoding UTF8

#region Step 1: Node.js 다운로드

Write-Step "`n=== Step 1: Node.js 다운로드 ===" "INFO"

$nodeUrl = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-x64.msi"
$nodePath = "$OutputPath\installers\node-v$NodeVersion-x64.msi"

if (Download-FileWithProgress -Url $nodeUrl -OutputPath $nodePath -Description "Node.js v$NodeVersion") {
    $hash = Get-FileHash256 -FilePath $nodePath
    "node-v$NodeVersion-x64.msi`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
}

#endregion

#region Step 2: Nginx 다운로드

Write-Step "`n=== Step 2: Nginx 다운로드 ===" "INFO"

$nginxUrl = "https://nginx.org/download/nginx-$NginxVersion.zip"
$nginxPath = "$OutputPath\installers\nginx-$NginxVersion.zip"

if (Download-FileWithProgress -Url $nginxUrl -OutputPath $nginxPath -Description "Nginx v$NginxVersion") {
    $hash = Get-FileHash256 -FilePath $nginxPath
    "nginx-$NginxVersion.zip`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
}

#endregion

#region Step 3: NSSM 다운로드

Write-Step "`n=== Step 3: NSSM 다운로드 ===" "INFO"

$nssmUrl = "https://nssm.cc/release/nssm-$NssmVersion.zip"
$nssmPath = "$OutputPath\installers\nssm-$NssmVersion.zip"

if (Download-FileWithProgress -Url $nssmUrl -OutputPath $nssmPath -Description "NSSM v$NssmVersion") {
    $hash = Get-FileHash256 -FilePath $nssmPath
    "nssm-$NssmVersion.zip`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
}

#endregion

#region Step 4: Visual C++ 재배포 패키지

Write-Step "`n=== Step 4: Visual C++ 재배포 패키지 다운로드 ===" "INFO"

$vcredistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$vcredistPath = "$OutputPath\installers\vcredist_x64.exe"

if (Download-FileWithProgress -Url $vcredistUrl -OutputPath $vcredistPath -Description "Visual C++ Redistributable") {
    $hash = Get-FileHash256 -FilePath $vcredistPath
    "vcredist_x64.exe`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
}

#endregion

#region Step 5: npm 패키지 오프라인 수집

Write-Step "`n=== Step 5: npm 패키지 수집 (오프라인 저장소) ===" "INFO"

# Node.js 임시 설치 확인
$nodeExe = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeExe) {
    Write-Step "Node.js가 설치되지 않았습니다. 먼저 Node.js를 설치해주세요." "WARN"
    Write-Step "  다운로드: https://nodejs.org" "INFO"
    Write-Step "  npm 패키지 수집을 건너뜁니다." "WARN"
} else {
    Write-Step "Node.js 버전: $(node --version)" "INFO"
    Write-Step "npm 버전: $(npm --version)" "INFO"

    # 임시 작업 디렉토리
    $tempDir = "$env:TEMP\npm-offline-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Push-Location $tempDir

        # package.json 생성
        Write-Step "임시 package.json 생성 중..." "INFO"
        $packageJson = @{
            name = "airgap-packages"
            version = "1.0.0"
            description = "Offline npm packages for air-gap environment"
            dependencies = @{}
        }

        foreach ($pkg in $NpmPackages) {
            $pkgParts = $pkg -split '@'
            if ($pkgParts.Count -eq 2) {
                $packageJson.dependencies[$pkgParts[0]] = $pkgParts[1]
            } else {
                $packageJson.dependencies[$pkg] = "latest"
            }
        }

        $packageJson | ConvertTo-Json -Depth 10 | Out-File "package.json" -Encoding UTF8

        # 패키지 다운로드
        Write-Step "npm 패키지 다운로드 중 (시간이 걸릴 수 있습니다)..." "INFO"
        npm install --production --no-save 2>&1 | Out-Null

        # 패키지 압축 생성
        Write-Step "오프라인 저장소 생성 중..." "INFO"
        npm pack 2>&1 | Out-Null

        # node_modules를 tar로 압축
        $npmPackagePath = "$OutputPath\npm-packages\node_modules.tar.gz"

        # tar 사용 가능 여부 확인 (Windows 10 1803+)
        $tarExe = Get-Command tar -ErrorAction SilentlyContinue
        if ($tarExe) {
            Write-Step "node_modules 압축 중 (tar)..." "INFO"
            & tar -czf $npmPackagePath node_modules 2>&1 | Out-Null

            if (Test-Path $npmPackagePath) {
                $hash = Get-FileHash256 -FilePath $npmPackagePath
                "node_modules.tar.gz`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
                Write-Step "압축 완료: node_modules.tar.gz" "SUCCESS"
            }
        } else {
            # tar가 없으면 ZIP 사용
            Write-Step "node_modules 압축 중 (zip)..." "INFO"
            $zipPath = "$OutputPath\npm-packages\node_modules.zip"
            Compress-Archive -Path "node_modules" -DestinationPath $zipPath -Force

            if (Test-Path $zipPath) {
                $hash = Get-FileHash256 -FilePath $zipPath
                "node_modules.zip`t$hash" | Out-File $checksumFile -Append -Encoding UTF8
                Write-Step "압축 완료: node_modules.zip" "SUCCESS"
            }
        }

        # package.json과 package-lock.json 복사
        Copy-Item "package.json" "$OutputPath\npm-packages\" -Force
        if (Test-Path "package-lock.json") {
            Copy-Item "package-lock.json" "$OutputPath\npm-packages\" -Force
        }

        Write-Step "npm 패키지 수집 완료" "SUCCESS"

    } catch {
        Write-Step "npm 패키지 수집 실패: $($_.Exception.Message)" "ERROR"
    } finally {
        Pop-Location
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

#endregion

#region Step 6: 스크립트 및 설정 파일 복사

Write-Step "`n=== Step 6: 스크립트 및 설정 파일 준비 ===" "INFO"

# 현재 스크립트 디렉토리에서 필요한 파일 복사
$scriptSourceDir = $PSScriptRoot
$filesToCopy = @(
    "02-install-airgap.ps1",
    "03-verify-installation.ps1",
    "nginx-proxy-manager.ps1"
)

foreach ($file in $filesToCopy) {
    $sourcePath = Join-Path $scriptSourceDir $file
    $destPath = "$OutputPath\scripts\$file"

    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $destPath -Force
        Write-Step "복사됨: $file" "SUCCESS"
    } else {
        Write-Step "파일 없음: $file (수동으로 추가하세요)" "WARN"
    }
}

# .env.example 생성
$envExample = @"
# 프록시 서버 설정
PROXY_SERVER_IP=172.24.178.23
DNS_ZONE_NAME=nxtd.co.kr
NGINX_PATH=C:\nginx

# Node.js 설정
NODE_ENV=production
NODE_PATH=C:\Program Files\nodejs

# 로그 설정
LOG_LEVEL=info
LOG_PATH=C:\nginx\logs
"@

$envExample | Out-File "$OutputPath\configs\.env.example" -Encoding UTF8
Write-Step "생성됨: .env.example" "SUCCESS"

# services.csv.example 생성
$csvExample = @"
서비스명,ARecord,IP,Port,UseHTTPS,CustomPath,비고
메인웹서버,web1,192.168.1.10,80,N,,일반 웹서버
API서버,api1,192.168.1.20,8080,N,,REST API 서버
Node.js앱,nodeapp,127.0.0.1,3000,N,,Express 애플리케이션
관리콘솔,admin1,192.168.1.30,8443,Y,,HTTPS 관리콘솔
"@

$csvExample | Out-File "$OutputPath\configs\services.csv.example" -Encoding UTF8
Write-Step "생성됨: services.csv.example" "SUCCESS"

#endregion

#region Step 7: 패키지 정보 생성

Write-Step "`n=== Step 7: 패키지 정보 생성 ===" "INFO"

$packageInfo = @"
# 에어갭 설치 패키지 정보

## 생성 일시
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## 버전 정보
- Node.js: $NodeVersion
- Nginx: $NginxVersion
- NSSM: $NssmVersion

## 포함된 npm 패키지
$($NpmPackages | ForEach-Object { "- $_" } | Out-String)

## 설치 순서
1. 02-install-airgap.ps1 실행 (관리자 권한)
2. 03-verify-installation.ps1로 검증
3. nginx-proxy-manager.ps1로 서비스 관리

## 파일 무결성
checksums.txt 파일로 검증하세요.

## 주의사항
- Windows Server 2016 이상 필요
- 관리자 권한 필수
- 최소 10GB 여유 공간 필요

## 문제 해결
logs/ 디렉토리의 로그 파일을 확인하세요.
"@

$packageInfo | Out-File "$OutputPath\PACKAGE-INFO.txt" -Encoding UTF8
Write-Step "생성됨: PACKAGE-INFO.txt" "SUCCESS"

#endregion

#region Step 8: 최종 검증

Write-Step "`n=== Step 8: 패키지 검증 ===" "INFO"

$requiredFiles = @(
    "installers\node-v$NodeVersion-x64.msi",
    "installers\nginx-$NginxVersion.zip",
    "installers\nssm-$NssmVersion.zip",
    "installers\vcredist_x64.exe",
    "checksums.txt",
    "PACKAGE-INFO.txt"
)

$allFilesExist = $true
foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $OutputPath $file
    if (Test-Path $fullPath) {
        Write-Step "  [✓] $file" "SUCCESS"
    } else {
        Write-Step "  [✗] $file (누락됨)" "ERROR"
        $allFilesExist = $false
    }
}

# 패키지 크기 계산
$totalSize = (Get-ChildItem -Path $OutputPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalSizeGB = [math]::Round($totalSize / 1GB, 2)

Write-Step "`n패키지 총 크기: $totalSizeGB GB" "INFO"

#endregion

#region 완료 메시지

Write-Host @"

================================================================================
                    패키지 준비 완료!
================================================================================

✅ 패키지 위치: $OutputPath
✅ 총 크기: $totalSizeGB GB

📦 다음 단계:
  1. 전체 'airgap-package' 폴더를 USB/네트워크로 에어갭 서버에 전송
  2. 에어갭 서버에서 관리자 PowerShell 실행
  3. cd airgap-package\scripts
  4. .\02-install-airgap.ps1 실행

🔒 보안 권장사항:
  - 전송 전 바이러스 검사 수행
  - checksums.txt로 파일 무결성 검증
  - 전송 경로 보안 확인

================================================================================
"@ -ForegroundColor Green

# 로그 파일 생성
$logFile = "$OutputPath\logs\prepare-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Get-Content $checksumFile | Out-File $logFile -Encoding UTF8

Write-Step "로그 파일: $logFile" "INFO"

#endregion
