# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Windows Air-Gap Nginx Reverse Proxy Package** - a complete offline installation package for deploying and managing Nginx reverse proxy in isolated Windows Server environments without internet access.

**Key Characteristics**:
- **Air-gap deployment**: All components bundled for offline installation (133MB package)
- **USB-transferable**: Single package contains all installers and dependencies
- **Production-ready**: Includes monitoring, automation, and operational scripts
- **Three-phase workflow**: Prepare (online) → Transfer (USB) → Install (offline)

## Critical Architecture Concepts

### Two-Environment Workflow

This project operates across **two distinct environments**:

1. **Preparation Environment** (internet-connected PC)
   - Run `01-prepare-airgap.ps1` to download and validate all components
   - Generates checksums and offline npm cache
   - Creates complete self-contained package

2. **Target Environment** (air-gapped Windows Server)
   - Run `02-install-airgap.ps1` to install from package
   - No internet access required
   - Active Directory integration mandatory

**IMPORTANT**: Scripts are environment-specific. Never run preparation scripts on target servers or installation scripts on preparation PCs.

### Package Independence Architecture

The project uses **symbolic links** to maintain package independence while avoiding duplication:

```
nginx/
├── resume/ → airgap-package/docs/         (symlink)
├── demo/ → airgap-package/configs/        (symlink)
├── xwiki/ → airgap-package/docs/          (symlink)
└── airgap-package/                        (actual files)
    ├── docs/          # Source of truth
    ├── configs/       # Source of truth
    └── scripts/       # All automation
```

**Rule**: Always edit files in `airgap-package/`, never in symlinked directories.

### Script Numbering System

Scripts follow a **sequential workflow pattern**:

**Installation Phase** (01-06):
- `01-prepare-airgap.ps1` - Download components (online environment)
- `02-install-airgap.ps1` - Install system (offline environment)
- `03-verify-installation.ps1` - Run 37 validation tests
- `04-setup-ad-integration.ps1` - Configure Active Directory
- `05-backup-restore.ps1` - Backup/restore operations
- `06-validate-enhanced-package.ps1` - Package integrity check

**Operations Phase** (07-10 + import):
- `07-health-monitor.ps1` - Real-time monitoring with auto-recovery
- `08-log-analyzer.ps1` - Log analysis and security event detection
- `09-performance-benchmark.ps1` - Performance testing and RPS measurement
- `10-auto-maintenance.ps1` - Automated log rotation and cleanup
- `import-proxies.ps1` - Bulk proxy configuration from CSV

**Naming Convention**: New operational scripts should continue numbering (11-, 12-, etc.) or use descriptive names (import-, export-, etc.).

## Common Commands

### Package Preparation (Internet-Connected PC)

```powershell
# Prepare complete air-gap package
cd airgap-package\scripts
.\01-prepare-airgap.ps1

# Validate package integrity
.\06-validate-enhanced-package.ps1

# Generate checksums
Get-FileHash -Algorithm SHA256 installers\* | Out-File checksums.txt
```

### Installation (Air-Gapped Windows Server)

```powershell
# Install complete system (requires admin)
cd C:\airgap-package\scripts
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\02-install-airgap.ps1

# Verify installation (37 automated tests)
.\03-verify-installation.ps1 -Detailed -ExportReport

# Setup Active Directory integration
.\04-setup-ad-integration.ps1
```

### Operational Management

```powershell
# Real-time health monitoring with dashboard
.\07-health-monitor.ps1 -DashboardMode -AutoRecover

# Analyze logs for security events
.\08-log-analyzer.ps1 -StartTime (Get-Date).AddHours(-24) -GenerateReport

# Performance benchmark (3 profiles: Quick, Standard, Stress)
.\09-performance-benchmark.ps1 -Profile Standard -GenerateReport

# Bulk import proxies from CSV
.\import-proxies.ps1 -CSVPath "..\configs\services.csv" -DryRun
.\import-proxies.ps1 -CSVPath "..\configs\services.csv" -Apply

# Automated maintenance
.\10-auto-maintenance.ps1 -Mode Standard -CompressOldLogs
```

### Service Management

```powershell
# Check service status
Get-Service nginx, nginx-web-ui

# Restart services
Restart-Service nginx
Restart-Service nginx-web-ui

# Validate Nginx configuration
C:\nginx\nginx.exe -t

# Reload Nginx without downtime
C:\nginx\nginx.exe -s reload

# View logs
Get-Content C:\nginx\logs\access.log -Tail 50 -Wait
Get-Content C:\nginx\logs\error.log -Tail 50 -Wait
```

### Backup and Restore

```powershell
# Create backup
.\05-backup-restore.ps1 -Mode Backup -BackupPath "D:\Backups\nginx"

# Restore from backup
.\05-backup-restore.ps1 -Mode Restore -BackupPath "D:\Backups\nginx\2025-10-21"

# Schedule automated backups (Task Scheduler)
Register-ScheduledTask -TaskName "Nginx Daily Backup" `
    -Action (New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-File C:\airgap-package\scripts\05-backup-restore.ps1 -Mode Backup") `
    -Trigger (New-ScheduledTaskTrigger -Daily -At 02:00)
```

### Package Distribution

```bash
# Generate checksums for all installers
sha256sum airgap-package/installers/* | tee airgap-package/checksums.txt

# Create distribution package
zip -r nginx-airgap-package-v1.1.0.zip airgap-package/ -x "*.git*" "airgap-package/logs/*"

# Generate package checksum
sha256sum nginx-airgap-package-v1.1.0.zip | tee nginx-airgap-package-v1.1.0.zip.sha256
```

## Component Integration

### Three Proxy Management Options

The system supports three parallel management interfaces:

1. **Web UI (Recommended)** - Port 8080
   - Node.js-based (nginx-web-ui.js)
   - localhost-only for security
   - Windows Service: `nginx-web-ui`
   - Location: `C:\nginx\web-ui\`

2. **PowerShell Scripts**
   - CSV-based bulk operations (`import-proxies.ps1`)
   - Direct nginx.conf generation
   - Automated via Task Scheduler

3. **Zoraxy GUI (Optional)** - Port 8000
   - Standalone Windows application
   - Independent execution
   - Manual installation from `installers/zoraxy_windows_amd64.exe`

**Important**: These options operate independently. Changes in one do NOT automatically sync to others.

### Windows Service Architecture

All services managed via NSSM (Non-Sucking Service Manager):

```powershell
# Service registration pattern
nssm install nginx "C:\nginx\nginx.exe"
nssm set nginx AppDirectory "C:\nginx"
nssm set nginx DisplayName "Nginx Web Server"
nssm set nginx Start SERVICE_AUTO_START

nssm install nginx-web-ui "C:\Program Files\nodejs\node.exe"
nssm set nginx-web-ui AppParameters "C:\nginx\web-ui\nginx-web-ui.js"
nssm set nginx-web-ui AppDirectory "C:\nginx\web-ui"
```

### Active Directory Integration Model

**Required AD Structure**:
```
Domain: company.local
├── OU=Service Accounts
│   └── nginx-service (service execution account)
├── OU=Security Groups
│   ├── NginxAdministrators (full admin rights)
│   └── NginxOperators (read + add proxies only)
```

**Permission Model**:
- **NginxAdministrators**: Full control over C:\nginx, service management, configuration changes
- **NginxOperators**: Read access + ability to add new proxy configurations

**Setup Command**: `.\04-setup-ad-integration.ps1` handles all AD configuration automatically.

## Development Patterns

### Adding New Operational Scripts

Follow the established pattern from 07-10 scripts:

```powershell
<#
.SYNOPSIS
    Brief description

.DESCRIPTION
    Detailed description of functionality

.PARAMETER ParameterName
    Parameter description with defaults

.EXAMPLE
    .\script-name.ps1
    Basic usage

.EXAMPLE
    .\script-name.ps1 -Param Value
    Advanced usage with parameters
#>

[CmdletBinding()]
param(
    [int]$Parameter = 30,
    [switch]$EnableFeature
)

# Standard logging function
function Write-ColorOutput {
    param([string]$Message, [string]$Level = "INFO")
    $color = @{
        INFO = "Cyan"; SUCCESS = "Green"
        WARN = "Yellow"; ERROR = "Red"
    }[$Level]
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# Main execution
try {
    # Script logic here
    Write-ColorOutput "Operation completed" "SUCCESS"
} catch {
    Write-ColorOutput "Error: $_" "ERROR"
    exit 1
}
```

### CSV-Based Configuration Pattern

For bulk operations, use CSV format following `configs/services.csv` template:

```csv
domain,upstream_host,upstream_port,ssl_enabled,ssl_cert_path,ssl_key_path,description
app.company.local,192.168.1.100,3000,true,C:\nginx\ssl\app.crt,C:\nginx\ssl\app.key,Main Application
api.company.local,192.168.1.101,8080,false,,,Internal API
```

**Processing Pattern**:
```powershell
$proxies = Import-Csv -Path $CSVPath -Encoding UTF8
foreach ($proxy in $proxies) {
    # Generate nginx config
    $config = Generate-NginxConfig -Proxy $proxy
    # Save to conf.d/
    Set-Content -Path "C:\nginx\conf.d\$($proxy.domain).conf" -Value $config
}
# Reload Nginx
C:\nginx\nginx.exe -s reload
```

### Monitoring and Alerting Pattern

All monitoring scripts (07-09) follow this pattern:

```powershell
# 1. Data Collection
$metrics = Collect-Metrics

# 2. Threshold Evaluation
$alerts = $metrics | Where-Object { $_.Value -gt $Threshold }

# 3. Auto-Recovery (if enabled)
if ($AutoRecover -and $alerts) {
    Invoke-AutoRecovery -Alerts $alerts
}

# 4. Logging/Reporting
if ($GenerateReport) {
    Export-Report -Data $metrics -Format HTML
}

# 5. Dashboard Display (if enabled)
if ($DashboardMode) {
    Show-Dashboard -Metrics $metrics
}
```

### Testing and Validation

**Pre-deployment Validation**:
```powershell
# 1. Syntax check
C:\nginx\nginx.exe -t

# 2. Service validation
Get-Service nginx | Should -Be Running

# 3. Endpoint test
Invoke-WebRequest -Uri "http://localhost" -UseBasicParsing

# 4. Full automated validation (37 tests)
.\03-verify-installation.ps1 -Detailed
```

**Validation Report Location**: `C:\nginx\reports\verification-report.html`

## File Structure Conventions

### Configuration Files
- `configs/nginx/nginx.conf` - Main Nginx configuration template
- `configs/nginx/conf.d/*.conf` - Proxy configuration examples (4 templates)
- `configs/.env.example` - Environment variable template
- `configs/services.csv` - Proxy list template for bulk import

### Documentation Structure
- `docs/architecture.md` - System architecture and component integration
- `docs/api.md` - REST API and PowerShell interface reference
- `docs/deployment.md` - Complete deployment guide
- `docs/troubleshooting.md` - Common issues and solutions
- `docs/001-009_*.md` - Operational manuals (9 documents)

### Logs
- `C:\nginx\logs\access.log` - HTTP access logs
- `C:\nginx\logs\error.log` - Nginx error logs
- `airgap-package\logs\install-*.log` - Installation logs
- `C:\nginx\reports\*.html` - Validation and monitoring reports

## Version Management

**Current Version**: v1.1.0 (고도화 버전)

**Version History**:
- **v1.1.0** (2025-10-21): Operational automation (5 new scripts)
- **v1.0.0** (2025-10-21): Initial integrated package

**When Incrementing Version**:
1. Update `README.md` version badge and changelog
2. Update `airgap-package/README.md` version reference
3. Update `airgap-package/PACKAGE-INFO.txt` metadata
4. Regenerate checksums: `sha256sum installers/* > checksums.txt`
5. Create new distribution package with version number

## Security Considerations

### Air-Gap Environment Requirements
- No outbound internet access on target servers
- All components must be pre-downloaded and validated
- Checksum verification mandatory (SHA256)
- Package integrity check before installation

### Access Control
- Web UI: localhost-only (127.0.0.1:8080) - no remote access
- Zoraxy: localhost-only (127.0.0.1:8000) - no remote access
- Nginx: External-facing (0.0.0.0:80/443) with reverse proxy rules
- AD integration required for production deployment

### Best Practices
- Always run `03-verify-installation.ps1` after installation
- Enable auto-recovery in `07-health-monitor.ps1` for production
- Schedule automated backups via `05-backup-restore.ps1`
- Monitor security events via `08-log-analyzer.ps1` (detects SQL injection, path traversal)
- Review logs regularly for suspicious patterns

## Troubleshooting Quick Reference

**Service Won't Start**:
```powershell
C:\nginx\nginx.exe -t  # Validate configuration
Get-Content C:\nginx\logs\error.log -Tail 20
```

**502 Bad Gateway**:
```powershell
Test-NetConnection -ComputerName <upstream_host> -Port <upstream_port>
Get-Content C:\nginx\logs\error.log | Select-String "upstream"
```

**Web UI Not Accessible**:
```powershell
Get-Service nginx-web-ui
Get-NetTCPConnection -LocalPort 8080
netstat -ano | findstr :8080
```

**Performance Issues**:
```powershell
.\09-performance-benchmark.ps1 -Profile Stress -GenerateReport
Get-Content C:\nginx\logs\access.log | Measure-Object -Line
```

**Complete Troubleshooting Guide**: See `docs/troubleshooting.md`
