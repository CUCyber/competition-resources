# Author: Dylan Harvey (Modified from Aaron Sprouse's original)
# Initial password reset script, will change all passwords to the same thing for local or AD user accounts, depending on the machine.

$safeMode = $true
$excludedUsers = @("krbtgt", "gold-team", "scoring")
$defaultPassword = "NewSecurePassword123!"
$outputFile = "affectedUsers.csv"

if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}
if ($safeMode) {
    Write-Output "Safe mode is enabled, no actual changes will be made."
    Add-Content -Path $outputFile -Value "SAFE MODE ENABLED; NO CHANGES MADE"
}

# 3 Main methods to check if DC:
# 1. Check if the Get-ADUser cmdlet exists with try/catch - Using this one for now, may be worth to test/experiment with other methods
# 2. Use (Get-WindowsFeature -Name AD-Domain-Services).Installed - Note: Get-WindowsFeature is a part of the ServerManager module
# 3. Check if local accounts exist
function IsDomainController {
    try {
        Get-ADUser -Identity Administrator
        return $true
    } catch {
        return $false
    }
}

if (IsDomainController) {
    Write-Output "Machine is a Domain Controller"
    $allUsers = Get-ADUser -Filter * -Properties SamAccountName

    foreach ($user in $allUsers) {
        if ($excludedUsers -contains $user.SamAccountName) {
            Write-Output "Skipping excluded user: $($user.SamAccountName)"
            continue
        }

        if ($safeMode) {
            Write-Output "Would reset password for: $($user.SamAccountName)"
        } else {
            Set-ADAccountPassword -Identity $user.SamAccountName -NewPassword (ConvertTo-SecureString -AsPlainText $defaultPassword -Force)
            Write-Output "Password reset for: $($user.SamAccountName)"
        }
        Add-Content -Path $outputFile -Value "$($user.SamAccountName)::$defaultPassword"
    }
} else {
    Write-Output "Machine is NOT a Domain Controller"
    $allUsers = Get-LocalUser

    foreach ($user in $allUsers) {
        if ($excludedUsers -contains $user.Name) {
            Write-Output "Skipping excluded user: $($user.Name)"
            continue
        }

        if ($safeMode) {
            Write-Output "Would reset password for: $($user.Name)"
        } else {
            Set-LocalUser -Name $user.Name -Password (ConvertTo-SecureString -AsPlainText $defaultPassword -Force)
            Write-Output "Password reset for: $($user.Name)"
        }
        Add-Content -Path $outputFile -Value "$($user.Name)::$defaultPassword"
    }
}

if ($safeMode) {
    Write-Output "Safe mode is ON. No passwords were changed. Expected changes written to: $outputFile"
} else {
    Write-Output "Safe mode is OFF. Passwords have been reset for all applicable users. Changes written to: $outputFile"
}
