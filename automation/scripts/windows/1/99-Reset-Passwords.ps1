# 99-Reset-Passwords.ps1
# Author: Dylan Harvey
# Description: Automated password reset script, will change passwords for non-excluded user accounts.

$excludedUsers = @("krbtgt", "^blackteam", "^seccdc")  # CHANGE AS NEEDED, SUPPORTS REGEX
$password = ""  # CHANGE
if (!$password) {
    Write-Host "ERROR: Password is not set! Aborting..."
    exit 2
} elseif (!$excludedUsers) {
    Write-Host "WARNING: Excluded users list is not set!"
    Start-Sleep 2
}

$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
Write-Host "[*] Target: $(if ($isDC) {'Domain Controller'} else {'Local Machine'})"
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
            net user $user $password /domain > $null #2>&1
        } else {
            net user $user $password > $null #2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Error Code $LASTEXITCODE"
        }

        Write-Host "[+] Reset: $user"
    } catch {
        Write-Host "[!] Failed: $user; $($_.Exception.Message)"
    }
}
