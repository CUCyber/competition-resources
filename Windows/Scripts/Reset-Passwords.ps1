# Reset-Passwords.ps1
# Author: Dylan Harvey
# Password reset script, will change passwords for non-excluded user accounts.

$excludedUsers = @("krbtgt", "^seccdc")
$password = "NewSecurePassword123!"
$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$outputFile = ".\affectedUsers.csv"
Out-File $outputFile # Clear file if exists, creates if not

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
        Add-Content $outputFile -Value "$_,$password"
    }

    Write-Host "Passwords have been reset for domain users. Changes written to: $outputFile"
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
        Add-Content $outputFile -Value "$_,$password"
    }

    Write-Host "Passwords have been reset for local users. Changes written to: $outputFile"
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type."
    exit 2 # Manually envoked exit
}

Write-Host "Passwords have been reset for all applicable users. Changes written to: $outputFile"
