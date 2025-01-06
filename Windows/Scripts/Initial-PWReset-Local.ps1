# Author: Dylan Harvey (Modified from Aaron Sprouse's original)
# Initial password reset script, will change all passwords to the same thing for local user accounts

$safeMode = $true
$excludedUsers = @("krbtgt", "gold-team", "scoring")
$defaultPassword = "NewSecurePassword123!"
$outputFile = "affectedUsers.csv"

if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}
if ($safeMode) {
    Add-Content -Path $outputFile -Value "SAFE MODE ENABLED; NO CHANGES MADE"
}

$allUsers = Get-LocalUser

foreach ($user in $allUsers) {
    if ($excludedUsers -contains $user.Name) {
        Write-Output "Skipping excluded user: $($user.Name)"
        continue
    }

    if ($safeMode) {
        Write-Output "Would reset password for: $($user.Name)"
    } else {
        Set-LocalUser -Identity $user.Name -NewPassword (ConvertTo-SecureString -AsPlainText $defaultPassword -Force)
        Write-Output "Password reset for: $($user.Name)"
    }
    Add-Content -Path $outputFile -Value "$($user.Name)::$defaultPassword"
}

if ($safeMode) {
    Write-Output "Safe mode is ON. No passwords were changed. Expected changes written to: $outputFile"
} else {
    Write-Output "Safe mode is OFF. Passwords have been reset for all applicable users. Changes written to: $outputFile"
}
