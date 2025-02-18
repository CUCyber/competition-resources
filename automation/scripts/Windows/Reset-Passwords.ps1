# Reset-Passwords.ps1
# Author: Dylan Harvey
# Password reset script, will change passwords for non-excluded user accounts.

$excludedUsers = @("krbtgt", "^seccdc")
$securePassword = "NewSecurePassword123!" | ConvertTo-SecureString -AsPlainText -Force

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "Machine is a Domain Controller."

    $allUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
    $allUsers = $allUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $allUsers | ForEach-Object {
        Set-ADAccountPassword -Identity $_ -NewPassword $securePassword
        Write-Host "Password reset for: $_"
    }

    Write-Host "Passwords have been reset for domain users."
} elseif ($role -lt 4) {
    Write-Host "Machine is NOT a Domain Controller."

    $allUsers = Get-LocalUser | Select-Object -ExpandProperty Name
    $allUsers = $allUsers | ForEach-Object {
        if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
        else { $_ }
    }

    $allUsers | ForEach-Object {
        Set-LocalUser -Name $_ -Password $securePassword
        Write-Host "Password reset for: $_"
    }

    Write-Host "Passwords have been reset for local users."
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type."
    exit 2 # Manually envoked exit
}
