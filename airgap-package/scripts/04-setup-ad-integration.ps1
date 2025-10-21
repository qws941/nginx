#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Active Directory 통합 자동화 스크립트

.DESCRIPTION
    Nginx 리버스 프록시 환경을 위한 AD 구성을 자동화합니다.

    자동 구성 항목:
    - AD 보안 그룹 생성 (NginxAdministrators, NginxOperators, NginxReadOnly)
    - 서비스 계정 생성 (nginx-service)
    - 파일 시스템 권한 설정
    - 서비스 로그온 권한 부여
    - GPO 연동 (선택)

.EXAMPLE
    .\04-setup-ad-integration.ps1
    .\04-setup-ad-integration.ps1 -DomainName "company.local" -ServiceAccountPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
    .\04-setup-ad-integration.ps1 -SkipGPO
    .\04-setup-ad-integration.ps1 -Verify

.PARAMETER Verify
    기존 AD 구성을 검증만 하고 변경하지 않습니다.
#>

param(
    [string]$DomainName = $env:USERDNSDOMAIN,
    [string]$OUPath = "",  # 비워두면 기본 Users 컨테이너 사용
    [SecureString]$ServiceAccountPassword,
    [string]$NginxPath = "C:\nginx",
    [switch]$SkipGPO,
    [switch]$Verify,
    [switch]$Force
)

#region Configuration

$Script:Config = @{
    DomainName = $DomainName
    NginxPath = $NginxPath
    Groups = @(
        @{
            Name = "NginxAdministrators"
            Description = "Full administrative access to Nginx services and configuration"
            Scope = "DomainLocal"
            Category = "Security"
        },
        @{
            Name = "NginxOperators"
            Description = "Operational access to manage Nginx proxies and view logs"
            Scope = "DomainLocal"
            Category = "Security"
        },
        @{
            Name = "NginxReadOnly"
            Description = "Read-only access to Nginx configuration and logs"
            Scope = "DomainLocal"
            Category = "Security"
        }
    )
    ServiceAccount = @{
        Name = "nginx-service"
        DisplayName = "Nginx Service Account"
        Description = "Service account for running Nginx and related Windows services"
        PasswordNeverExpires = $true
        CannotChangePassword = $true
        AccountEnabled = $true
    }
    LogPath = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $Script:Config.LogPath "ad-integration-$timestamp.log"

#endregion

#region Logger

class ADLogger {
    static [string]$LogFile

    static [void] Init([string]$logPath) {
        [ADLogger]::LogFile = $logPath
    }

    static [void] Log([string]$Message, [string]$Level) {
        $color = @{
            INFO = "Cyan"
            SUCCESS = "Green"
            WARN = "Yellow"
            ERROR = "Red"
            DEBUG = "Gray"
        }[$Level]

        $timestamp = Get-Date -Format "HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"

        Write-Host $logEntry -ForegroundColor $color

        if ([ADLogger]::LogFile) {
            Add-Content -Path ([ADLogger]::LogFile) -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }

    static [void] Info([string]$Message) { [ADLogger]::Log($Message, "INFO") }
    static [void] Success([string]$Message) { [ADLogger]::Log($Message, "SUCCESS") }
    static [void] Warn([string]$Message) { [ADLogger]::Log($Message, "WARN") }
    static [void] Error([string]$Message) { [ADLogger]::Log($Message, "ERROR") }
    static [void] Debug([string]$Message) { [ADLogger]::Log($Message, "DEBUG") }
}

#endregion

#region Helper Functions

function Test-DomainJoined {
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        return $computerSystem.PartOfDomain
    } catch {
        return $false
    }
}

function Test-ADModuleAvailable {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-DomainAdminRights {
    try {
        # Domain Admins 그룹에 속해 있는지 확인
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

        # SID로 확인 (S-1-5-21-domain-512는 Domain Admins)
        $domainAdminsSID = (Get-ADDomain).DomainSID.Value + "-512"
        $domainAdminsGroup = Get-ADGroup -Identity $domainAdminsSID -ErrorAction SilentlyContinue

        if ($domainAdminsGroup) {
            $isMember = (Get-ADGroupMember -Identity $domainAdminsGroup -Recursive |
                        Where-Object { $_.SID -eq $currentUser.User }).Count -gt 0
            return $isMember
        }

        return $false
    } catch {
        [ADLogger]::Debug("Cannot verify Domain Admin rights: $($_.Exception.Message)")
        return $false
    }
}

function New-ADSecurityGroup {
    param(
        [string]$Name,
        [string]$Description,
        [string]$GroupScope = "DomainLocal",
        [string]$GroupCategory = "Security",
        [string]$Path = ""
    )

    try {
        # 그룹 존재 확인
        $existingGroup = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue

        if ($existingGroup) {
            [ADLogger]::Info("AD Group already exists: $Name")
            return $existingGroup
        }

        # 그룹 생성
        $params = @{
            Name = $Name
            Description = $Description
            GroupScope = $GroupScope
            GroupCategory = $GroupCategory
        }

        if ($Path) {
            $params.Path = $Path
        }

        $group = New-ADGroup @params -PassThru -ErrorAction Stop
        [ADLogger]::Success("AD Group created: $Name")

        return $group
    } catch {
        [ADLogger]::Error("Failed to create AD Group '$Name': $($_.Exception.Message)")
        return $null
    }
}

function New-ADServiceAccount {
    param(
        [string]$Name,
        [string]$DisplayName,
        [string]$Description,
        [SecureString]$Password,
        [string]$Path = ""
    )

    try {
        # 계정 존재 확인
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$Name'" -ErrorAction SilentlyContinue

        if ($existingUser) {
            [ADLogger]::Info("Service account already exists: $Name")
            return $existingUser
        }

        # 계정 생성
        $params = @{
            Name = $Name
            SamAccountName = $Name
            UserPrincipalName = "$Name@$($Script:Config.DomainName)"
            DisplayName = $DisplayName
            Description = $Description
            AccountPassword = $Password
            Enabled = $true
            PasswordNeverExpires = $true
            CannotChangePassword = $true
        }

        if ($Path) {
            $params.Path = $Path
        }

        $user = New-ADUser @params -PassThru -ErrorAction Stop
        [ADLogger]::Success("Service account created: $Name")

        return $user
    } catch {
        [ADLogger]::Error("Failed to create service account '$Name': $($_.Exception.Message)")
        return $null
    }
}

function Add-ServiceAccountToGroup {
    param(
        [string]$ServiceAccountName,
        [string]$GroupName
    )

    try {
        $user = Get-ADUser -Filter "SamAccountName -eq '$ServiceAccountName'" -ErrorAction Stop
        $group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction Stop

        # 이미 멤버인지 확인
        $isMember = Get-ADGroupMember -Identity $group | Where-Object { $_.SamAccountName -eq $ServiceAccountName }

        if ($isMember) {
            [ADLogger]::Info("$ServiceAccountName is already a member of $GroupName")
            return $true
        }

        Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
        [ADLogger]::Success("Added $ServiceAccountName to $GroupName")

        return $true
    } catch {
        [ADLogger]::Error("Failed to add $ServiceAccountName to $GroupName: $($_.Exception.Message)")
        return $false
    }
}

function Grant-ServiceLogonRight {
    param([string]$AccountName)

    try {
        [ADLogger]::Info("Granting 'Log on as a service' right to $AccountName...")

        # secedit을 사용하여 권한 부여
        $tempFile = [System.IO.Path]::GetTempFileName()
        $outputFile = [System.IO.Path]::GetTempFileName()

        # 현재 보안 정책 내보내기
        & secedit /export /cfg $tempFile /quiet

        # SID 가져오기
        $user = Get-ADUser -Filter "SamAccountName -eq '$AccountName'" -ErrorAction Stop
        $sid = $user.SID.Value

        # 정책 파일 수정
        $content = Get-Content $tempFile
        $serviceLogonLine = $content | Where-Object { $_ -like "SeServiceLogonRight*" }

        if ($serviceLogonLine) {
            if ($serviceLogonLine -notlike "*$sid*") {
                $newLine = $serviceLogonLine + ",*$sid"
                $content = $content -replace [regex]::Escape($serviceLogonLine), $newLine
            } else {
                [ADLogger]::Info("Account already has service logon right")
                Remove-Item $tempFile, $outputFile -Force -ErrorAction SilentlyContinue
                return $true
            }
        } else {
            $content += "`r`nSeServiceLogonRight = *$sid"
        }

        $content | Set-Content $tempFile -Force

        # 정책 적용
        & secedit /configure /db secedit.sdb /cfg $tempFile /quiet
        & gpupdate /force /quiet

        Remove-Item $tempFile, $outputFile -Force -ErrorAction SilentlyContinue

        [ADLogger]::Success("Service logon right granted to $AccountName")
        return $true
    } catch {
        [ADLogger]::Error("Failed to grant service logon right: $($_.Exception.Message)")
        return $false
    }
}

function Set-NginxFilePermissions {
    param(
        [string]$Path,
        [string]$AdminGroupName,
        [string]$OperatorGroupName,
        [string]$ReadOnlyGroupName,
        [string]$ServiceAccountName
    )

    if (-not (Test-Path $Path)) {
        [ADLogger]::Warn("Nginx path not found: $Path")
        return $false
    }

    try {
        [ADLogger]::Info("Setting file permissions on $Path...")

        $acl = Get-Acl -Path $Path

        # Domain\GroupName 형식으로 변환
        $domain = $Script:Config.DomainName.Split('.')[0]

        # 기존 권한 제거 (선택적)
        # $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null

        # Administrators: FullControl
        $adminGroup = "$domain\$AdminGroupName"
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $adminGroup,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($adminRule)
        [ADLogger]::Success("  ✓ $adminGroup: FullControl")

        # Operators: Modify
        $operatorGroup = "$domain\$OperatorGroupName"
        $operatorRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $operatorGroup,
            "Modify",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($operatorRule)
        [ADLogger]::Success("  ✓ $operatorGroup: Modify")

        # ReadOnly: ReadAndExecute
        $readOnlyGroup = "$domain\$ReadOnlyGroupName"
        $readOnlyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $readOnlyGroup,
            "ReadAndExecute",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($readOnlyRule)
        [ADLogger]::Success("  ✓ $readOnlyGroup: ReadAndExecute")

        # Service Account: Modify (서비스 실행을 위해)
        $serviceAccount = "$domain\$ServiceAccountName"
        $serviceRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $serviceAccount,
            "Modify",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.AddAccessRule($serviceRule)
        [ADLogger]::Success("  ✓ $serviceAccount: Modify")

        # 권한 적용
        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop

        [ADLogger]::Success("File permissions configured successfully")
        return $true
    } catch {
        [ADLogger]::Error("Failed to set file permissions: $($_.Exception.Message)")
        return $false
    }
}

function Update-ServiceAccount {
    param(
        [string]$ServiceName,
        [string]$ServiceAccountName,
        [SecureString]$Password
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if (-not $service) {
            [ADLogger]::Warn("Service not found: $ServiceName")
            return $false
        }

        [ADLogger]::Info("Updating service account for $ServiceName...")

        # 서비스 중지
        if ($service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            [ADLogger]::Info("Service stopped: $ServiceName")
        }

        # Domain\Username 형식
        $domain = $Script:Config.DomainName.Split('.')[0]
        $accountName = "$domain\$ServiceAccountName"

        # 비밀번호를 일반 텍스트로 변환 (sc.exe 사용을 위해)
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

        # sc.exe로 서비스 계정 변경
        $result = & sc.exe config $ServiceName obj= $accountName password= $plainPassword

        if ($LASTEXITCODE -eq 0) {
            [ADLogger]::Success("Service account updated: $ServiceName → $accountName")

            # 서비스 시작
            Start-Service -Name $ServiceName -ErrorAction Stop
            [ADLogger]::Success("Service started: $ServiceName")

            return $true
        } else {
            [ADLogger]::Error("Failed to update service account: $result")
            return $false
        }
    } catch {
        [ADLogger]::Error("Failed to update service '$ServiceName': $($_.Exception.Message)")
        return $false
    } finally {
        # 비밀번호 메모리에서 제거
        if ($BSTR) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

function Test-ADConfiguration {
    [ADLogger]::Info("`n=== Verifying AD Configuration ===")

    $results = @{
        TotalChecks = 0
        PassedChecks = 0
        FailedChecks = 0
        Checks = @()
    }

    # Check 1: Domain joined
    $results.TotalChecks++
    $domainJoined = Test-DomainJoined
    if ($domainJoined) {
        $results.PassedChecks++
        [ADLogger]::Success("✓ Server is domain-joined")
    } else {
        $results.FailedChecks++
        [ADLogger]::Error("✗ Server is NOT domain-joined")
    }
    $results.Checks += @{ Name = "Domain Joined"; Passed = $domainJoined }

    # Check 2-4: Groups exist
    foreach ($groupConfig in $Script:Config.Groups) {
        $results.TotalChecks++
        $group = Get-ADGroup -Filter "Name -eq '$($groupConfig.Name)'" -ErrorAction SilentlyContinue
        if ($group) {
            $results.PassedChecks++
            $memberCount = (Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue).Count
            [ADLogger]::Success("✓ Group exists: $($groupConfig.Name) ($memberCount members)")
        } else {
            $results.FailedChecks++
            [ADLogger]::Error("✗ Group missing: $($groupConfig.Name)")
        }
        $results.Checks += @{ Name = "Group: $($groupConfig.Name)"; Passed = ($group -ne $null) }
    }

    # Check 5: Service account exists
    $results.TotalChecks++
    $serviceAccount = Get-ADUser -Filter "SamAccountName -eq '$($Script:Config.ServiceAccount.Name)'" -ErrorAction SilentlyContinue
    if ($serviceAccount) {
        $results.PassedChecks++
        [ADLogger]::Success("✓ Service account exists: $($Script:Config.ServiceAccount.Name)")
        [ADLogger]::Info("  UPN: $($serviceAccount.UserPrincipalName)")
        [ADLogger]::Info("  Enabled: $($serviceAccount.Enabled)")
    } else {
        $results.FailedChecks++
        [ADLogger]::Error("✗ Service account missing: $($Script:Config.ServiceAccount.Name)")
    }
    $results.Checks += @{ Name = "Service Account"; Passed = ($serviceAccount -ne $null) }

    # Check 6: Service account in NginxOperators group
    if ($serviceAccount) {
        $results.TotalChecks++
        $isMember = Get-ADGroupMember -Identity "NginxOperators" -ErrorAction SilentlyContinue |
                   Where-Object { $_.SamAccountName -eq $Script:Config.ServiceAccount.Name }
        if ($isMember) {
            $results.PassedChecks++
            [ADLogger]::Success("✓ Service account is member of NginxOperators")
        } else {
            $results.FailedChecks++
            [ADLogger]::Error("✗ Service account NOT member of NginxOperators")
        }
        $results.Checks += @{ Name = "Service Account Membership"; Passed = ($isMember -ne $null) }
    }

    # Check 7: Nginx path permissions
    if (Test-Path $Script:Config.NginxPath) {
        $results.TotalChecks++
        $acl = Get-Acl -Path $Script:Config.NginxPath -ErrorAction SilentlyContinue
        $hasPermissions = $acl.Access | Where-Object {
            $_.IdentityReference -like "*NginxAdministrators*" -or
            $_.IdentityReference -like "*NginxOperators*" -or
            $_.IdentityReference -like "*nginx-service*"
        }

        if ($hasPermissions) {
            $results.PassedChecks++
            [ADLogger]::Success("✓ Nginx directory has AD group permissions")
        } else {
            $results.FailedChecks++
            [ADLogger]::Warn("✗ Nginx directory missing AD permissions")
        }
        $results.Checks += @{ Name = "File Permissions"; Passed = ($hasPermissions -ne $null) }
    }

    # 결과 요약
    $passRate = [math]::Round(($results.PassedChecks / $results.TotalChecks) * 100, 2)

    [ADLogger]::Info("`n=== Verification Summary ===")
    [ADLogger]::Info("Total Checks: $($results.TotalChecks)")
    [ADLogger]::Success("Passed: $($results.PassedChecks)")
    if ($results.FailedChecks -gt 0) {
        [ADLogger]::Error("Failed: $($results.FailedChecks)")
    } else {
        [ADLogger]::Info("Failed: $($results.FailedChecks)")
    }
    [ADLogger]::Info("Pass Rate: $passRate%")

    return $results
}

#endregion

#region Main Execution

function Start-ADIntegration {
    try {
        # 로그 디렉토리 생성
        if (-not (Test-Path $Script:Config.LogPath)) {
            New-Item -ItemType Directory -Path $Script:Config.LogPath -Force | Out-Null
        }

        [ADLogger]::Init($logFile)

        Write-Host @"
================================================================================
          Active Directory Integration Setup
================================================================================
  Domain: $($Script:Config.DomainName)
  Nginx Path: $($Script:Config.NginxPath)

  Configuration:
  - Security Groups: 3 (Administrators, Operators, ReadOnly)
  - Service Account: $($Script:Config.ServiceAccount.Name)
  - File Permissions: Automatic
  - Service Logon Rights: Automatic

================================================================================

"@ -ForegroundColor Cyan

        # Verify 모드
        if ($Verify) {
            [ADLogger]::Info("Running in VERIFY mode (no changes will be made)")
            Test-ADConfiguration
            return
        }

        # 사전 검사
        [ADLogger]::Info("=== Pre-flight Checks ===")

        if (-not (Test-DomainJoined)) {
            throw "Server is not joined to a domain. Join the domain first."
        }
        [ADLogger]::Success("✓ Server is domain-joined: $($Script:Config.DomainName)")

        if (-not (Test-ADModuleAvailable)) {
            throw "ActiveDirectory PowerShell module not available. Install RSAT tools."
        }
        [ADLogger]::Success("✓ ActiveDirectory module available")

        if (-not (Test-DomainAdminRights)) {
            [ADLogger]::Warn("⚠ You may not have Domain Admin rights. Some operations may fail.")
        } else {
            [ADLogger]::Success("✓ Domain Admin rights confirmed")
        }

        # 비밀번호 입력 (없으면 생성)
        if (-not $ServiceAccountPassword) {
            [ADLogger]::Info("`nService account password is required.")
            $ServiceAccountPassword = Read-Host "Enter password for service account" -AsSecureString
            $confirmPassword = Read-Host "Confirm password" -AsSecureString

            $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ServiceAccountPassword)
            )
            $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)
            )

            if ($pwd1 -ne $pwd2) {
                throw "Passwords do not match"
            }
        }

        # OU Path 결정
        if (-not $OUPath) {
            $domain = Get-ADDomain
            $OUPath = $domain.UsersContainer
            [ADLogger]::Info("Using default container: $OUPath")
        }

        # Step 1: AD 그룹 생성
        [ADLogger]::Info("`n=== Step 1: Creating AD Security Groups ===")

        foreach ($groupConfig in $Script:Config.Groups) {
            $group = New-ADSecurityGroup -Name $groupConfig.Name `
                                        -Description $groupConfig.Description `
                                        -GroupScope $groupConfig.Scope `
                                        -GroupCategory $groupConfig.Category `
                                        -Path $OUPath

            if ($group) {
                [ADLogger]::Success("  ✓ $($groupConfig.Name)")
            }
        }

        # Step 2: 서비스 계정 생성
        [ADLogger]::Info("`n=== Step 2: Creating Service Account ===")

        $serviceAccount = New-ADServiceAccount -Name $Script:Config.ServiceAccount.Name `
                                               -DisplayName $Script:Config.ServiceAccount.DisplayName `
                                               -Description $Script:Config.ServiceAccount.Description `
                                               -Password $ServiceAccountPassword `
                                               -Path $OUPath

        if ($serviceAccount) {
            [ADLogger]::Success("  ✓ $($Script:Config.ServiceAccount.Name)")
        }

        # Step 3: 서비스 계정을 NginxOperators 그룹에 추가
        [ADLogger]::Info("`n=== Step 3: Adding Service Account to Groups ===")

        Add-ServiceAccountToGroup -ServiceAccountName $Script:Config.ServiceAccount.Name `
                                  -GroupName "NginxOperators"

        # Step 4: 파일 시스템 권한 설정
        [ADLogger]::Info("`n=== Step 4: Setting File System Permissions ===")

        Set-NginxFilePermissions -Path $Script:Config.NginxPath `
                                -AdminGroupName "NginxAdministrators" `
                                -OperatorGroupName "NginxOperators" `
                                -ReadOnlyGroupName "NginxReadOnly" `
                                -ServiceAccountName $Script:Config.ServiceAccount.Name

        # Step 5: 서비스 로그온 권한 부여
        [ADLogger]::Info("`n=== Step 5: Granting Service Logon Rights ===")

        Grant-ServiceLogonRight -AccountName $Script:Config.ServiceAccount.Name

        # Step 6: 서비스 계정 업데이트 (선택적)
        [ADLogger]::Info("`n=== Step 6: Updating Windows Services ===")

        $updateServices = Read-Host "Update Nginx services to use $($Script:Config.ServiceAccount.Name)? (Y/N)"
        if ($updateServices -eq 'Y') {
            # Nginx 서비스
            if (Get-Service -Name "nginx" -ErrorAction SilentlyContinue) {
                Update-ServiceAccount -ServiceName "nginx" `
                                     -ServiceAccountName $Script:Config.ServiceAccount.Name `
                                     -Password $ServiceAccountPassword
            }

            # Web UI 서비스
            if (Get-Service -Name "nginx-web-ui" -ErrorAction SilentlyContinue) {
                Update-ServiceAccount -ServiceName "nginx-web-ui" `
                                     -ServiceAccountName $Script:Config.ServiceAccount.Name `
                                     -Password $ServiceAccountPassword
            }
        } else {
            [ADLogger]::Info("Skipping service account update")
        }

        # Step 7: 검증
        [ADLogger]::Info("`n=== Step 7: Verifying Configuration ===")
        $verification = Test-ADConfiguration

        Write-Host @"

================================================================================
                    AD Integration Complete!
================================================================================

✅ Completed:
  - AD Security Groups: 3 groups created
  - Service Account: $($Script:Config.ServiceAccount.Name)
  - File Permissions: Configured
  - Service Logon Rights: Granted

📋 Next Steps:
  1. Add users to appropriate groups:
     - Add-ADGroupMember -Identity "NginxAdministrators" -Members username
  2. Verify services are running:
     - Get-Service nginx, nginx-web-ui
  3. Test authentication:
     - Log in with an account in NginxAdministrators group

📁 Groups Created:
  - NginxAdministrators: Full administrative access
  - NginxOperators: Manage proxies and view logs
  - NginxReadOnly: Read-only access

🔐 Service Account:
  - Username: $($Script:Config.ServiceAccount.Name)
  - UPN: $($Script:Config.ServiceAccount.Name)@$($Script:Config.DomainName)
  - Member of: NginxOperators

📊 Verification Results:
  - Total Checks: $($verification.TotalChecks)
  - Passed: $($verification.PassedChecks)
  - Failed: $($verification.FailedChecks)
  - Pass Rate: $([math]::Round(($verification.PassedChecks / $verification.TotalChecks) * 100, 2))%

📄 Log File: $logFile

================================================================================
"@ -ForegroundColor Green

    } catch {
        [ADLogger]::Error("AD Integration failed: $($_.Exception.Message)")
        [ADLogger]::Error("Stack Trace: $($_.ScriptStackTrace)")

        Write-Host @"

================================================================================
                    AD Integration Failed
================================================================================

❌ Error: $($_.Exception.Message)

📋 Troubleshooting:
  1. Verify you have Domain Admin rights
  2. Check domain connectivity: Test-Connection $($Script:Config.DomainName)
  3. Verify AD module: Import-Module ActiveDirectory
  4. Check log: $logFile

================================================================================
"@ -ForegroundColor Red

        exit 1
    }
}

# Entry Point
Start-ADIntegration

#endregion
