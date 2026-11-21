# Author BlueNitrobotX
# Disables every ENABLED user account that is NOT in $AllowedUsers.
#   - Domain controller -> Active Directory (domain) accounts
#   - Anything else     -> local accounts
# Dry run by default: nothing changes unless you pass -Apply.
#   .\DisableUsers.ps1          (preview)
#   .\DisableUsers.ps1 -Apply   (disable accounts)
#
# EXIT CODES: 0 - success, 1 - failure, 2 - nothing to disable
param([switch]$Apply)

# ======================= EDIT BEFORE RUNNING =======================
# Account names to KEEP enabled (case-insensitive; "DOMAIN\name" is also accepted).
# Include service accounts that things depend on!
$AllowedUsers = @(
    'ExampleUser1'
    'ExampleUser2'
)

# Never disable the built-in administrator (RID 500), even if it was renamed or not listed
$ProtectBuiltinAdmin = $true
# ===================================================================

$ErrorActionPreference = 'Stop'

function Get-ShortName([string]$name) { ($name -replace '^.*\\', '').Trim().ToLower() }

# Safety: an empty list would disable everyone
$allowed = @($AllowedUsers | ForEach-Object { Get-ShortName $_ } | Where-Object { $_ })
if($allowed.Count -eq 0) {
    Write-Host -ForegroundColor Red "[$(Get-Date -Format "HH:mm:ss")] Allowed list is empty, refusing to run."
    exit 1
}

if($Apply -and ($allowed -contains 'ExampleUser1' -or $allowed -contains 'ExampleUser2')) {
    Write-Host -ForegroundColor Red "[$(Get-Date -Format "HH:mm:ss")] Replace the example accounts in the allowed list before using -Apply."
    exit 1
}

# Always protect whoever is running the script and whoever is logged on at the console
# (under PsExec the running identity is SYSTEM, so the console user must be added separately)
$cs = Get-CimInstance Win32_ComputerSystem
$allowed += Get-ShortName ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
if($cs.UserName) { $allowed += Get-ShortName $cs.UserName }
$allowed += 'krbtgt'

# DomainRole: 4/5 = domain controller. On a DC there are no local accounts, only domain ones.
$isDC = $cs.DomainRole -ge 4

try {
    if($isDC) {
        $scope = 'domain'
        Import-Module ActiveDirectory
        $accounts = Get-ADUser -Filter 'Enabled -eq $true' | ForEach-Object {
            [pscustomobject]@{ Name = $_.SamAccountName; SID = $_.SID.Value; Obj = $_ }
        }
    } else {
        $scope = 'local'
        $accounts = Get-LocalUser | Where-Object { $_.Enabled } | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; SID = $_.SID.Value; Obj = $_ }
        }
    }
}
catch {
    Write-Host -ForegroundColor Red "[$(Get-Date -Format "HH:mm:ss")] Failed to enumerate $scope accounts: $($_.Exception.Message)"
    exit 1
}

$targets = @($accounts | Where-Object {
    ($allowed -notcontains (Get-ShortName $_.Name)) -and
    -not ($ProtectBuiltinAdmin -and $_.SID -like '*-500')
})

if($targets.Count -eq 0) {
    Write-Host -ForegroundColor Green "[$(Get-Date -Format "HH:mm:ss")] No enabled $scope accounts outside the allowed list."
    exit 2
}

if(-not $Apply) {
    Write-Host -ForegroundColor Cyan "[$(Get-Date -Format "HH:mm:ss")] DRY RUN ($scope accounts): re-run with -Apply to disable."
}

$failed = 0
$logDir = Join-Path $PSScriptRoot 'WinMaster_Evidence'

foreach($target in $targets) {
    if(-not $Apply) {
        Write-Host -ForegroundColor Yellow "[$(Get-Date -Format "HH:mm:ss")] Would disable ($scope): $($target.Name)"
        continue
    }
    try {
        if($isDC) { Disable-ADAccount -Identity $target.Obj }
        else      { Disable-LocalUser -SID $target.SID }

        Write-Host -ForegroundColor Green "Disabled ($scope): $($target.Name)"
        if(Test-Path -Path $logDir -PathType Container) {
            "$(Get-Date -Format s) disabled $scope account $($target.Name) ($($target.SID))" |
                Out-File -FilePath (Join-Path $logDir "$($env:COMPUTERNAME)-DisabledUsers.txt") -Append
        }
    }
    catch {
        Write-Host -ForegroundColor Red "Failed to disable $($target.Name): $($_.Exception.Message)"
        $failed++
    }
}

if($failed -gt 0) { exit 1 }
exit 0
