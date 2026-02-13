# Create-User.ps1
# Author: Dylan Harvey
# Manual user creation script, will create and activate an admin user.
# Updated: 2026-02-12

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!!] WARNING: You must run this script as an Administrator!" -ForegroundColor Red
}

$username = Read-Host "Enter new username"

while ($true) {
    $p1 = Read-Host "Enter new password  " -AsSecureString
    $p2 = Read-Host "Confirm new password" -AsSecureString

        $plain1 = [System.Net.NetworkCredential]::new("", $p1).Password
        $plain2 = [System.Net.NetworkCredential]::new("", $p2).Password

    if ($plain1 -eq $plain2 -and $plain1.Length -gt 0) {
        $securePassword = $p1
        break
    }
    Write-Host "[-] Passwords do not match or are empty!" -ForegroundColor Red
}

$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
Write-Host "[*] Target: $(if ($isDC) {'Domain Controller'} else {'Local Machine'})" -ForegroundColor Cyan
try {
    if ($isDC) {
        New-ADUser -Name "$username" -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true | Out-Null
        Add-ADGroupMember -Identity "Domain Admins" -Members "$username"
        Add-ADGroupMember -Identity "Administrators" -Members "$username"
        #net user $username $password /add /active:yes /expires:never /domain > $null #2>&1
        #net group Administrators $username /add > $null #2>&1
        #net group "Domain Admins" $username /add > $null #2>&1

        Write-Host "[+] New domain user '$username' has been created." -ForegroundColor Green
    } else {
        New-LocalUser -Name "$username" -Password $securePassword -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member "$username"
        #net user $username $password /add /active:yes /expires:never > $null #2>&1
        #net localgroup Administrators $username /add > $null #2>&1

        Write-Host "[+] New local user '$username' has been created." -ForegroundColor Green
    }
} catch {
    Write-Host "[!] Failed to create user: $username; $($_.Exception.Message)" -ForegroundColor Red
}
