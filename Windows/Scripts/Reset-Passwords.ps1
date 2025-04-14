# Reset-Passwords.ps1
# Author: Dylan Harvey
# Manual password reset script, will change passwords for non-excluded user accounts.

$excludedUsers = @("krbtgt", "ansible", "^seccdc") # CHANGE AS NEEDED, SUPPORTS REGEX
$password = "" # CHANGE
if (!$password) {
    Write-Host "Password is not set! Aborting..." -ForegroundColor Red
    exit 2
} elseif (!$excludedUsers) {
    Write-Host "WARNING: Excluded users list is not set!" -ForegroundColor Yellow
    Start-Sleep 2
}
$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$outputFile = ".\affectedUsers.csv"
Out-File $outputFile # Clear/create file

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "Machine is a Domain Controller." -ForegroundColor Cyan

    $allUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
    if ($excludedUsers) {
        $allUsers = $allUsers | ForEach-Object {
            if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
            else { $_ }
        }
    }

    $allUsers | ForEach-Object {
        Set-ADAccountPassword -Identity $_ -NewPassword $securePassword
        Write-Host "Password reset for: $_"
        Add-Content $outputFile -Value "$_,$password"
    }

    Write-Host "Passwords have been reset for domain users. Changes written to: $outputFile" -ForegroundColor Green
} elseif ($role -lt 4) {
    Write-Host "Machine is NOT a Domain Controller." -ForegroundColor Cyan

    $allUsers = Get-LocalUser | Select-Object -ExpandProperty Name
    if ($excludedUsers) {
        $allUsers = $allUsers | Where-Object {
            if ($_ -match ($excludedUsers -join "|")) { Write-Host "Skipping excluded user: $_" -ForegroundColor Magenta } 
            else { $_ }
        }
    }

    $allUsers | ForEach-Object {
        Set-LocalUser -Name $_ -Password $securePassword
        Write-Host "Password reset for: $_"
        Add-Content $outputFile -Value "$_,$password"
    }

    Write-Host "Passwords have been reset for local users. Changes written to: $outputFile" -ForegroundColor Green
} else { # I've never seen this happen but just in case
    Write-Host "Error determining machine type." -ForegroundColor Red
    exit 2
}

Write-Host "Passwords have been reset for all applicable users. Changes written to: $outputFile" -ForegroundColor Green
