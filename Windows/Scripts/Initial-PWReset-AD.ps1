# Author: Aaron Sprouse
# Initial password reset script, will change all passwords to the same thing

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

if ($safeMode) {
    Write-Output "Safe mode is ON. No passwords were changed. Expected changes written to: $outputFile"
} else {
    Write-Output "Safe mode is OFF. Passwords have been reset for all applicable users. Changes written to: $outputFile"
}
