# Author: Aaron Sprouse
# Initial password reset script, will change all passwords to the same thing

$safeMode = $true
$excludedUsers = @("krbtgt", "gold-team", "scoring")
$defaultPassword = "NewSecurePassword123!"

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
}

if ($safeMode) {
    Write-Output "Safe mode is ON. No passwords were changed."
} else {
    Write-Output "Safe mode is OFF. Passwords have been reset for all applicable users."
}