# Create-User.ps1
# Author: Dylan Harvey
# Manual user creation script, will create and activate an admin user.

$username = "dguy" # CHANGE AS NEEDED
$password = "" # CHANGE
if (!$password) {
    Write-Host "ERROR: Password is not set! Aborting..." -ForegroundColor Red
    exit 2
}
$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "Machine is a Domain Controller." -ForegroundColor Cyan
    
    New-ADUser -Name "$username" -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true | Out-Null
    Add-ADGroupMember -Identity "Domain Admins" -Members "$username"

    Write-Host "New domain user '$username' has been created." -ForegroundColor Green
} elseif ($role -lt 4) {
    Write-Host "Machine is NOT a Domain Controller." -ForegroundColor Cyan

    New-LocalUser -Name "$username" -Password $securePassword -PasswordNeverExpires | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member "$username"

    Write-Host "New local user '$username' has been created." -ForegroundColor Green
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type." -ForegroundColor Red
    exit 2
}
