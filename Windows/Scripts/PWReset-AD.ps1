# PWReset-AD.ps1
# Author: Dylan Harvey (Modified from Aaron Sprouse's original)
# Password reset script, will change all passwords for DOMAIN user accounts.

$excludedUsers = @("krbtgt", "^seccdc", "blackteam_adm")
$defaultPassword = "NewSecurePassword123!"
$outputFile = ".\affectedUsers.csv"
if (Test-Path $outputFile) { Remove-Item $outputFile -Force }

$allUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
$allUsers = $allUsers | ForEach-Object {
    if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
    else { $_ }
}

$allUsers | ForEach-Object {
    Set-ADAccountPassword -Identity $_ -NewPassword (ConvertTo-SecureString -AsPlainText $defaultPassword -Force)
    Write-Host "Password reset for: $_"
    Add-Content -Path $outputFile -Value "$_,$defaultPassword"
}

Write-Host "Passwords have been reset for all applicable users. Changes written to: $outputFile"
