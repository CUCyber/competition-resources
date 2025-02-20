# Create-Backup-User.ps1
# Author: Dylan Harvey
# Automation Version - Creates a backup user and grants administrator permissions.

$username = "dguy" # CHANGE
$securePassword = "NewSecurePassword123!" | ConvertTo-SecureString -AsPlainText -Force # CHANGE

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "Machine is a Domain Controller." -ForegroundColor Cyan

    New-ADUser -Name "$username" -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true 1> $Null
    Add-ADGroupMember -Identity "Domain Admins" -Members "$username"

    Write-Host "New domain user '$username' has been created." -ForegroundColor Green
} elseif ($role -lt 4) {
    Write-Host "Machine is NOT a Domain Controller." -ForegroundColor Cyan

    New-LocalUser -Name "$username" -Password $securePassword -PasswordNeverExpires 1> $Null
    Add-LocalGroupMember -Group "Administrators" -Member "$username"

    Write-Host "New local user '$username' has been created." -ForegroundColor Green
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type." -ForegroundColor Red
    exit 2 # Manually envoked exit
}
