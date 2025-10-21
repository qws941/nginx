# Changelog

All notable changes to the Windows Nginx Air-Gap Package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2025-10-21

### Added

#### Operational Automation Scripts (5 new)
- **07-health-monitor.ps1** (22KB) - Real-time system resource monitoring
  - CPU, memory, disk usage tracking
  - Service health checks (Nginx, Web UI)
  - Proxy target connectivity testing
  - Auto-recovery capabilities (service restart, disk cleanup)
  - Dashboard mode with live updates

- **08-log-analyzer.ps1** (21KB) - Log analysis and security monitoring
  - HTTP status code statistics (200, 404, 500 series)
  - Error pattern automatic detection
  - Security event detection (SQL injection, path traversal)
  - Top IP/URL/User-Agent analysis
  - HTML report generation

- **09-performance-benchmark.ps1** (19KB) - Performance testing
  - RPS (Requests Per Second) measurement
  - Response time analysis (average, P50, P95, P99)
  - 3 profiles: Quick, Standard, Stress
  - CPU/Memory usage tracking during tests
  - Performance grade evaluation (A/B/C/D/F)

- **import-proxies.ps1** (16KB) - Bulk proxy configuration
  - CSV-based mass proxy registration
  - SSL/non-SSL automatic configuration
  - Dry-run mode for preview
  - Nginx config validation and auto-reload
  - Detailed operation logging

- **10-auto-maintenance.ps1** (16KB) - Automated maintenance
  - Log rotation and compression
  - Cache and temporary file cleanup
  - Backup retention policy management
  - Disk space monitoring and alerts
  - Task Scheduler integration support

#### Documentation
- **CLAUDE.md** - Comprehensive guidance for Claude Code instances
  - Two-environment workflow architecture
  - Script numbering conventions
  - Development patterns and best practices
  - Security considerations
  - Troubleshooting quick reference

- **DISTRIBUTION-MANIFEST.md** - Complete distribution guide
  - Package integrity verification procedures
  - Deployment workflow (3-phase)
  - Operational automation examples
  - System requirements and compatibility

- **PACKAGE-RELEASE-SUMMARY.md** - Quick deployment reference
  - Package file information and checksums
  - v1.1.0 feature highlights
  - Quick start deployment guide
  - Operational automation examples

- **010_OPERATIONS-TREE-GUIDE.xwiki** - Tree-structured operational guide
  - Daily/Weekly/Monthly operation checklists
  - Script execution workflows
  - Troubleshooting decision trees
  - Management task procedures
  - Emergency response workflows

#### Package Infrastructure
- Package compression and optimization (133MB → 75MB, 44% reduction)
- SHA256 checksums for all installer files
- `checksums.txt` for package integrity verification
- Improved `.gitignore` and `.gitattributes`
- Symbolic link structure (resume/, demo/, xwiki/ → airgap-package/docs/)

### Changed

#### Script Improvements
- **01-prepare-airgap.ps1** - Enhanced error handling and validation
- **02-install-airgap.ps1** - Improved installation stability
- **03-verify-installation.ps1** - Maintained 37 automated tests
- **download-packages.sh** - Fixed shellcheck warnings (SC2155, SC2002)

#### Project Structure
- Consolidated all scripts into `airgap-package/scripts/` directory
- Created dedicated directories with symbolic links:
  - `resume/` → `airgap-package/docs/` (architecture, API, deployment, troubleshooting)
  - `demo/` → `airgap-package/configs/` (example configurations)
  - `xwiki/` → `airgap-package/docs/` (XWiki-formatted documentation)
- Improved package organization and maintainability

#### Documentation Updates
- Updated all 10 operational manuals
- Enhanced API documentation
- Improved architecture diagrams
- Expanded troubleshooting guide

### Removed
- `scripts/00-AIRGAP-SETUP-README.md` (consolidated into main docs)
- `scripts/AIRGAP-QUICK-START.md` (replaced by PACKAGE-RELEASE-SUMMARY.md)
- Redundant backup files and old structure

### Fixed
- Shellcheck warnings in bash scripts (SC2155, SC2002, SC2124)
- Script syntax validation issues
- Package structure inconsistencies

### Security
- localhost-only Web UI binding (127.0.0.1:8080)
- Active Directory integration for role-based access
- Security event detection in log analyzer
- SHA256 package integrity verification
- No hardcoded credentials (all use SecureString or prompts)

---

## [1.0.0] - 2025-10-20

### Added
- Initial release of Windows Nginx Air-Gap Package
- Complete offline installation package (133MB)
- Core components:
  - Nginx 1.24.0 (1.7MB)
  - Node.js v20.11.0 (26MB)
  - NSSM 2.24 (344KB)
  - Visual C++ Redistributable 2015-2022 (25MB)
  - Zoraxy (80MB)

- Installation scripts:
  - `01-prepare-airgap.ps1` - Package preparation (online environment)
  - `02-install-airgap.ps1` - System installation (offline environment)
  - `03-verify-installation.ps1` - 37 automated validation tests

- Configuration management:
  - 3 proxy management options (Web UI, PowerShell, Zoraxy)
  - 4 Nginx configuration templates
  - CSV-based configuration support
  - Environment variable template (.env.example)

- Active Directory integration:
  - `04-setup-ad-integration.ps1`
  - Role-based access control (Administrators, Operators)
  - Service account management

- Backup and restore:
  - `05-backup-restore.ps1`
  - Full system backup/restore
  - Configuration preservation

- Documentation:
  - Architecture documentation
  - API reference
  - Deployment guide
  - Troubleshooting guide
  - 9 operational manuals

### Features
- Fully offline air-gap deployment
- USB-transferable package
- Windows Service integration (NSSM)
- localhost-only Web UI for security
- Three-phase workflow (Prepare → Transfer → Install)
- 37 automated validation tests
- Comprehensive error handling

---

## Release Information

**Current Version**: v1.1.0
**Release Date**: 2025-10-21
**Package File**: nginx-airgap-package-v1.1.0.zip
**Package Size**: 75MB compressed (133MB uncompressed)
**SHA256**: `8da14a3a1175dce9839b466aba7514540f7f210a0e2ed9a51c4a4a6b6a422957`

**System Requirements**:
- OS: Windows Server 2016+ (recommended: 2019/2022)
- CPU: 2 cores minimum, 4+ recommended
- RAM: 4GB minimum, 8GB+ recommended
- Disk: 10GB minimum, 20GB recommended (SSD)
- Domain: Active Directory membership required
- Permissions: Local administrator rights

**Support Period**: 2025-10-21 ~ 2026-10-21 (1 year)

---

[1.1.0]: https://github.com/qws941/nginx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qws941/nginx/releases/tag/v1.0.0
