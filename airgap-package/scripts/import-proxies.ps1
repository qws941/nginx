<#
.SYNOPSIS
    CSV 파일에서 프록시 설정을 읽어 Nginx 설정 파일 자동 생성

.DESCRIPTION
    services.csv 파일을 읽어서 각 도메인별로 Nginx 프록시 설정 파일을 생성하고
    Nginx를 재시작하여 적용합니다.

    CSV 형식:
    domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path

.PARAMETER CSVPath
    프록시 목록 CSV 파일 경로

.PARAMETER NginxConfPath
    Nginx 설정 디렉토리 경로 (기본: C:\nginx\conf\conf.d)

.PARAMETER BackupExisting
    기존 설정 파일 백업 생성

.PARAMETER DryRun
    실제 변경 없이 미리보기만

.PARAMETER RestartNginx
    설정 적용 후 Nginx 재시작 (기본: true)

.EXAMPLE
    .\import-proxies.ps1 -CSVPath "C:\nginx\configs\services.csv"
    CSV에서 프록시 설정 일괄 적용

.EXAMPLE
    .\import-proxies.ps1 -CSVPath "services.csv" -DryRun
    미리보기 모드 (실제 변경 안 함)

.EXAMPLE
    .\import-proxies.ps1 -CSVPath "services.csv" -BackupExisting
    기존 설정 백업 후 적용
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$CSVPath,

    [string]$NginxConfPath = "C:\nginx\conf\conf.d",
    [switch]$BackupExisting,
    [switch]$DryRun,
    [switch]$RestartNginx = $true
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ============================================================================
# 설정
# ============================================================================

$Global:ImportStats = @{
    TotalEntries = 0
    Created = 0
    Updated = 0
    Skipped = 0
    Errors = @()
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

function Read-ProxyCSV {
    <#
    .SYNOPSIS
        CSV 파일 읽기 및 검증
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "CSV 파일을 찾을 수 없습니다: $Path"
    }

    Write-ColorOutput "CSV 파일 읽기: $Path" -Level INFO

    try {
        $data = Import-Csv -Path $Path -Encoding UTF8

        # 필수 컬럼 확인
        $requiredColumns = @("domain", "upstream_host", "upstream_port")
        $csvColumns = $data[0].PSObject.Properties.Name

        foreach ($col in $requiredColumns) {
            if ($col -notin $csvColumns) {
                throw "CSV 파일에 필수 컬럼이 없습니다: $col"
            }
        }

        # 데이터 검증
        $validated = @()
        $lineNum = 1

        foreach ($entry in $data) {
            $lineNum++

            # 기본값 설정
            $sslEnabled = if ($entry.ssl_enabled) { $entry.ssl_enabled -eq "true" } else { $false }

            # 필수 필드 확인
            if (-not $entry.domain) {
                Write-ColorOutput "줄 $lineNum`: domain 누락, 건너뜀" -Level WARNING
                $Global:ImportStats.Skipped++
                continue
            }

            if (-not $entry.upstream_host -or -not $entry.upstream_port) {
                Write-ColorOutput "줄 $lineNum`: upstream 정보 누락, 건너뜀" -Level WARNING
                $Global:ImportStats.Skipped++
                continue
            }

            # SSL 설정 검증
            if ($sslEnabled) {
                if (-not $entry.ssl_cert_path -or -not $entry.ssl_key_path) {
                    Write-ColorOutput "줄 $lineNum`: SSL 활성화되었으나 인증서 경로 누락 ($($entry.domain))" -Level WARNING
                    $Global:ImportStats.Skipped++
                    continue
                }

                # 인증서 파일 존재 확인
                if (-not (Test-Path $entry.ssl_cert_path)) {
                    Write-ColorOutput "줄 $lineNum`: SSL 인증서 파일 없음: $($entry.ssl_cert_path)" -Level WARNING
                    $Global:ImportStats.Skipped++
                    continue
                }

                if (-not (Test-Path $entry.ssl_key_path)) {
                    Write-ColorOutput "줄 $lineNum`: SSL 키 파일 없음: $($entry.ssl_key_path)" -Level WARNING
                    $Global:ImportStats.Skipped++
                    continue
                }
            }

            $validated += @{
                Domain = $entry.domain.Trim()
                UpstreamHost = $entry.upstream_host.Trim()
                UpstreamPort = [int]$entry.upstream_port
                SSLEnabled = $sslEnabled
                SSLCertPath = if ($entry.ssl_cert_path) { $entry.ssl_cert_path.Trim() } else { "" }
                SSLKeyPath = if ($entry.ssl_key_path) { $entry.ssl_key_path.Trim() } else { "" }
                LineNumber = $lineNum
            }
        }

        Write-ColorOutput "CSV 파싱 완료: $($validated.Count)개 유효 엔트리" -Level SUCCESS
        $Global:ImportStats.TotalEntries = $validated.Count

        return $validated
    } catch {
        throw "CSV 파일 읽기 실패: $_"
    }
}

function Generate-NginxConfig {
    <#
    .SYNOPSIS
        프록시 설정 객체로부터 Nginx 설정 파일 내용 생성
    #>
    param([hashtable]$Proxy)

    $config = ""

    # HTTP → HTTPS 리다이렉트 (SSL 활성화 시)
    if ($Proxy.SSLEnabled) {
        $config += @"
# $($Proxy.Domain) - HTTP to HTTPS redirect
server {
    listen 80;
    server_name $($Proxy.Domain);

    # HTTPS로 리다이렉트
    return 301 https://`$server_name`$request_uri;
}


"@
    }

    # 메인 server 블록
    if ($Proxy.SSLEnabled) {
        $config += @"
# $($Proxy.Domain) - HTTPS Proxy
server {
    listen 443 ssl http2;
    server_name $($Proxy.Domain);

    # SSL 인증서
    ssl_certificate $($Proxy.SSLCertPath);
    ssl_certificate_key $($Proxy.SSLKeyPath);

    # SSL 프로토콜 및 암호화
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # SSL 세션 캐시
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 보안 헤더
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 프록시 설정
    location / {
        proxy_pass http://$($Proxy.UpstreamHost):$($Proxy.UpstreamPort);

        # 프록시 헤더
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_set_header X-Forwarded-Host `$server_name;

        # 타임아웃 설정
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # 버퍼 설정
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # 로그
    access_log C:/nginx/logs/$($Proxy.Domain)-access.log main;
    error_log C:/nginx/logs/$($Proxy.Domain)-error.log;
}
"@
    } else {
        $config += @"
# $($Proxy.Domain) - HTTP Proxy
server {
    listen 80;
    server_name $($Proxy.Domain);

    # 프록시 설정
    location / {
        proxy_pass http://$($Proxy.UpstreamHost):$($Proxy.UpstreamPort);

        # 프록시 헤더
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;

        # 타임아웃 설정
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # 버퍼 설정
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
    }

    # 로그
    access_log C:/nginx/logs/$($Proxy.Domain)-access.log main;
    error_log C:/nginx/logs/$($Proxy.Domain)-error.log;
}
"@
    }

    return $config
}

function Save-NginxConfig {
    <#
    .SYNOPSIS
        Nginx 설정 파일 저장
    #>
    param(
        [hashtable]$Proxy,
        [string]$ConfigPath,
        [switch]$Backup
    )

    $filename = "$($Proxy.Domain).conf"
    $fullPath = Join-Path $ConfigPath $filename

    # 파일 존재 확인
    $fileExists = Test-Path $fullPath
    $action = if ($fileExists) { "업데이트" } else { "생성" }

    # 백업 (기존 파일이 있을 때만)
    if ($Backup -and $fileExists) {
        $backupPath = "$fullPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $fullPath $backupPath
        Write-ColorOutput "백업 생성: $backupPath" -Level INFO
    }

    # 설정 생성
    $config = Generate-NginxConfig -Proxy $Proxy

    if ($DryRun) {
        Write-ColorOutput "[DRY-RUN] $action`: $filename" -Level WARNING
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host $config -ForegroundColor Gray
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    } else {
        # 파일 저장
        $config | Out-File -FilePath $fullPath -Encoding UTF8 -Force
        Write-ColorOutput "$action 완료: $filename" -Level SUCCESS

        if ($fileExists) {
            $Global:ImportStats.Updated++
        } else {
            $Global:ImportStats.Created++
        }
    }
}

function Test-NginxConfig {
    <#
    .SYNOPSIS
        Nginx 설정 검증
    #>

    if (-not (Test-Path "C:\nginx\nginx.exe")) {
        Write-ColorOutput "Nginx 실행 파일을 찾을 수 없습니다" -Level WARNING
        return $false
    }

    Write-ColorOutput "Nginx 설정 검증 중..." -Level INFO

    $output = & "C:\nginx\nginx.exe" -t 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-ColorOutput "✓ Nginx 설정 검증 성공" -Level SUCCESS
        return $true
    } else {
        Write-ColorOutput "✗ Nginx 설정 오류:" -Level ERROR
        $output | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        return $false
    }
}

function Restart-NginxService {
    <#
    .SYNOPSIS
        Nginx 서비스 재시작
    #>

    Write-ColorOutput "Nginx 서비스 재시작 중..." -Level INFO

    try {
        $service = Get-Service nginx -ErrorAction SilentlyContinue

        if (-not $service) {
            Write-ColorOutput "Nginx 서비스를 찾을 수 없습니다" -Level WARNING
            return $false
        }

        if ($service.Status -eq "Running") {
            Restart-Service nginx -Force
            Start-Sleep -Seconds 3

            $newStatus = (Get-Service nginx).Status
            if ($newStatus -eq "Running") {
                Write-ColorOutput "✓ Nginx 재시작 완료" -Level SUCCESS
                return $true
            } else {
                Write-ColorOutput "✗ Nginx 재시작 실패: $newStatus" -Level ERROR
                return $false
            }
        } else {
            Start-Service nginx
            Start-Sleep -Seconds 3

            $newStatus = (Get-Service nginx).Status
            if ($newStatus -eq "Running") {
                Write-ColorOutput "✓ Nginx 시작 완료" -Level SUCCESS
                return $true
            } else {
                Write-ColorOutput "✗ Nginx 시작 실패: $newStatus" -Level ERROR
                return $false
            }
        }
    } catch {
        Write-ColorOutput "✗ Nginx 재시작 실패: $_" -Level ERROR
        return $false
    }
}

# ============================================================================
# 메인 실행
# ============================================================================

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
Write-ColorOutput "Nginx 프록시 일괄 등록 (CSV Import)" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

if ($DryRun) {
    Write-ColorOutput "모드: DRY-RUN (미리보기 전용, 실제 변경 안 함)" -Level WARNING
}

# CSV 파일 읽기
$proxies = Read-ProxyCSV -Path $CSVPath

if ($proxies.Count -eq 0) {
    Write-ColorOutput "등록할 프록시가 없습니다" -Level WARNING
    exit 0
}

# Nginx 설정 디렉토리 확인
if (-not (Test-Path $NginxConfPath)) {
    Write-ColorOutput "Nginx 설정 디렉토리가 없습니다. 생성합니다: $NginxConfPath" -Level WARNING
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $NginxConfPath -Force | Out-Null
    }
}

Write-ColorOutput "설정 파일 생성: $NginxConfPath" -Level INFO

# 각 프록시 설정 생성
foreach ($proxy in $proxies) {
    try {
        Save-NginxConfig -Proxy $proxy -ConfigPath $NginxConfPath -Backup:$BackupExisting
    } catch {
        Write-ColorOutput "✗ 실패 ($($proxy.Domain)): $_" -Level ERROR
        $Global:ImportStats.Errors += "줄 $($proxy.LineNumber): $($proxy.Domain) - $_"
    }
}

# 결과 요약
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
Write-ColorOutput "📊 작업 완료" -Level INFO
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS

Write-Host ""
Write-Host "[ 통계 ]" -ForegroundColor Yellow
Write-Host "  총 엔트리: $($Global:ImportStats.TotalEntries)"
Write-Host "  생성: $($Global:ImportStats.Created)"
Write-Host "  업데이트: $($Global:ImportStats.Updated)"
Write-Host "  건너뜀: $($Global:ImportStats.Skipped)"
Write-Host "  에러: $($Global:ImportStats.Errors.Count)"

if ($Global:ImportStats.Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "[ 에러 목록 ]" -ForegroundColor Red
    foreach ($error in $Global:ImportStats.Errors) {
        Write-Host "  $error" -ForegroundColor Red
    }
}

# Nginx 설정 검증
if (-not $DryRun) {
    Write-Host ""
    $configValid = Test-NginxConfig

    if ($configValid -and $RestartNginx) {
        $restarted = Restart-NginxService

        if ($restarted) {
            Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
            Write-ColorOutput "✓ 모든 프록시 설정이 적용되었습니다" -Level SUCCESS
            Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level SUCCESS
        } else {
            Write-ColorOutput "경고: Nginx 재시작 실패. 수동으로 재시작 필요" -Level WARNING
        }
    } elseif (-not $configValid) {
        Write-ColorOutput "경고: 설정 오류로 인해 Nginx를 재시작하지 않았습니다" -Level WARNING
        exit 1
    }
} else {
    Write-ColorOutput "DRY-RUN 모드 종료. 실제 적용을 원하시면 -DryRun 옵션을 제거하세요" -Level INFO
}
