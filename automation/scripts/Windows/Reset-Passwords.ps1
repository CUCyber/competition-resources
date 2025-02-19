# Reset-Passwords.ps1
# Author: Dylan Harvey
# Automation version of Password reset script, will change passwords for non-excluded user accounts (LOCAL ONLY).

$excludedUsers = @("krbtgt", "blackteam_adm", "^seccdc")
$securePassword = "NewSecurePassword123!" | ConvertTo-SecureString -AsPlainText -Force

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "Machine is a Domain Controller." -ForegroundColor Cyan
    Write-Host "Skipping Machine." -ForegroundColor Magenta
} elseif ($role -lt 4) {
    Write-Host "Machine is NOT a Domain Controller." -ForegroundColor Cyan

    $allUsers = Get-LocalUser | Select-Object -ExpandProperty Name
    $allUsers = $allUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $allUsers | ForEach-Object {
        Set-LocalUser -Name $_ -Password $securePassword
        Write-Host "Password reset for: $_"
    }

    Write-Host "Passwords have been reset for local users." -ForegroundColor Green
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type."
    exit 2 # Manually envoked exit
}
