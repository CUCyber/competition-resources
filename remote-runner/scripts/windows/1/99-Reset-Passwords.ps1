# 99-Reset-Passwords.ps1
# Author: Dylan Harvey
# Automated password reset script, will change passwords for non-excluded user accounts.

$excludedUsers = @("krbtgt", "^blackteam", "^seccdc", '\$$')  # CHANGE AS NEEDED, SUPPORTS REGEX
$password = ""  # CHANGE
$MODE = "Auto"  # Mode override, Auto, Domain, or Local

if (!$password) {
    Write-Host "ERROR: Password is not set! Aborting..."
    exit 2
} elseif (!$excludedUsers) {
    Write-Host "WARNING: Excluded users list is not set!"
    Start-Sleep 2
}

$passwordSecure = ConvertTo-SecureString $password -AsPlainText -Force

$detectedDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
if ($Mode -eq "Auto") {
    $isDC = $detectedDC
} else {
    $isDC = ($Mode -eq "Domain")
}

Write-Host "[*] Operation Mode: $(if ($isDC) {'Domain'} else {'Local'})"
if ($isDC) {
    $rawNames = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
} else {
    $rawNames = Get-LocalUser | Select-Object -ExpandProperty Name
}

$excludeRegex = $excludedUsers -join "|"

$finalList = $rawNames | Where-Object {
    if ($_ -match $excludeRegex) {
        Write-Host "[-] Skipping (Excluded): $_"
        return $false
    }
    return $true
}

foreach ($user in $finalList) {
    try {
        if ($isDC) {
            Set-ADAccountPassword -Identity $user -NewPassword $passwordSecure -Reset
        } else {
            Set-LocalUser -Name $user -Password $passwordSecure -ErrorAction Stop
        }

        Write-Host "[+] Reset: $user"
    } catch {
        Write-Host "[!] Failed: $user; $($_.Exception.Message)"
    }
}
