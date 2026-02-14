# 50-Create-User.ps1
# Author: Dylan Harvey
# Description: Automated user creation script, will create and activate an admin user.

$username = ""  # CHANGE AS NEEDED
$password = ""  # CHANGE
if (!$username) {
    Write-Host "ERROR: Username is not set! Aborting..."
    exit 2
}
if (!$password) {
    Write-Host "ERROR: Password is not set! Aborting..."
    exit 2
}
$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force

$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
Write-Host "[*] Target: $(if ($isDC) {'Domain Controller'} else {'Local Machine'})"
try {
    if ($isDC) {
        New-ADUser -Name "$username" -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true | Out-Null
        Add-ADGroupMember -Identity "Domain Admins" -Members "$username"
        Add-ADGroupMember -Identity "Administrators" -Members "$username"
        Write-Host "[+] New domain user '$username' has been created."
    } else {
        New-LocalUser -Name "$username" -Password $securePassword -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member "$username"
        Write-Host "[+] New local user '$username' has been created."
    }
} catch {
    Write-Host "[!] Failed to create user: $username; $($_.Exception.Message)"
    exit 2
}
