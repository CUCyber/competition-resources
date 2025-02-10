# PWReset-Smart.ps1
# Author: Dylan Harvey
# Smart password reset script, checks if the machine is a Domain Controller or not, and changes passwords accordingly.

$excludedUsers = @("krbtgt", "^seccdc", "blackteam_adm")
$defaultPassword = "NewSecurePassword123!"
$outputFile = ".\affectedUsers.csv"
if (Test-Path $outputFile) { Remove-Item $outputFile -Force }

# Checks if domain controller (4 = Backup DC, 5 = Primary DC)
if ((Get-WmiObject Win32_ComputerSystem).DomainRole -ge 4) {
    Write-Host "Machine is a Domain Controller"

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

} else {
    Write-Host "Machine is NOT a Domain Controller"

    $allUsers = Get-LocalUser | Select-Object -ExpandProperty Name
    $allUsers = $allUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $allUsers | ForEach-Object {
        Set-LocalUser -Name $_ -Password (ConvertTo-SecureString -AsPlainText $defaultPassword -Force)
        Write-Host "Password reset for: $_"
        Add-Content -Path $outputFile -Value "$_,$defaultPassword"
    }
}

Write-Host "Passwords have been reset for all applicable users. Changes written to: $outputFile"
