# Disable-RunKeys.ps1
# Author: Dylan Harvey - Modified by BlueNitrobotX
# Script for disabling common runkeys.

$ErrorActionPreference = 'Stop'

# SYSTEM's HKCU is its own profile. Use the loaded hives of interactive users.
$userHives = @('HKCU:')
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    $userHives = @(Get-CimInstance Win32_LogonSession -Filter 'LogonType = 2 OR LogonType = 10 OR LogonType = 11 OR LogonType = 12' |
        Get-CimAssociatedInstance -Association Win32_LoggedOnUser -ResultClassName Win32_Account |
        Select-Object -ExpandProperty SID -Unique |
        Where-Object { $_ -match '^S-1-(5-21|12-1)-' } |
        ForEach-Object { "Registry::HKEY_USERS\$_" })
}
$RunKeys = foreach ($hive in @($userHives) + 'HKLM:') {
    foreach ($key in 'Run', 'RunOnce', 'RunServices', 'RunServicesOnce', 'Policies\Explorer\Run') {
        "$hive\Software\Microsoft\Windows\CurrentVersion\$key"
    }
}

Write-Host "`n====== Checking RunKeys ======`n"

# Check each keypath
foreach ($KeyPath in $RunKeys) {
    # Only process the item if it exists
    if (Test-Path $KeyPath) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Processing: $KeyPath"
        
        $key = (Get-Item -LiteralPath $KeyPath).OpenSubKey('', $true)
        $disabledKey = $null
        try {
            $disabledKey = $key.CreateSubKey('ScriptDisabled')
            foreach ($Name in $key.GetValueNames()) {
                $Data = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
                $kind = $key.GetValueKind($Name)
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] - Disabling: $Name" -ForegroundColor Yellow

                $disabledKey.SetValue($Name, $Data, $kind)
                $key.DeleteValue($Name)
            }
        }
        finally {
            if ($disabledKey) { $disabledKey.Close() }
            if ($key) { $key.Close() }
        }
    }
}

Write-Host -ForegroundColor Cyan "`n[$(Get-Date -Format 'HH:mm:ss')] Check complete.`n"
