<#
.SYNOPSIS
    Securely resets passwords for local or domain users.
.DESCRIPTION
    Identifies environment and resets passwords for users.
    Supports filtering and logging.
.PARAMETER Users
    Regex patterns of usernames to target. If not supplied, targets all users.
.PARAMETER Exclude
    Regex patterns of usernames to skip. If not supplied, uses defaults.
    Defaults: "krbtgt", "^blackteam", "^seccdc"
.PARAMETER Random
    Generates a unique 16-character complex password for EVERY targeted user.
.PARAMETER Test
    Simulates the reset without applying changes (Alias: WhatIf).
.PARAMETER OutputLevel
    Controls CSV output: 'None', 'UsernameOnly', or 'Verbose'.
    None: No file
    UsernameOnly: Username and time only
    Verbose: Includes passwords
.INPUTS
    None. You can't pipe objects to Reset-Passwords.ps1.
.OUTPUTS
    System.Console.WriteHost and CSV Log File.
.EXAMPLE
    .\Reset-Passwords.ps1 -Test
.EXAMPLE
    .\Reset-Passwords.ps1 -Random -OutputLevel Verbose
.EXAMPLE
    .\Reset-Passwords.ps1 -Users "Administrator"
#>
# Reset-Passwords.ps1
# Author: Dylan Harvey
# Updated: 2026-02-11
param(
    [string[]]$Users,
    [string[]]$Exclude = @("krbtgt", "^blackteam", "^seccdc"),
    [switch]$Random,
    [Alias("WhatIf")]
    [switch]$Test,
    [ValidateSet("None", "UsernameOnly", "Verbose")]
    [string]$OutputLevel = "UsernameOnly"
)

# Helper Functions
function Get-GeneratedPassword {
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lower   = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $numbers = '0123456789'.ToCharArray()
    $special = '.,@|=:;/-!'.ToCharArray()
    $all     = $upper + $lower + $numbers + $special

    $password = @(
        $upper   | Get-Random
        $lower   | Get-Random
        $numbers | Get-Random
        $special | Get-Random
    )

    for ($i = 1; $i -le 12; $i++) {
        $password += $all | Get-Random
    }

    return -join ($password | Get-Random -Count 16)
}

function Get-UserResponsePassword {
    while ($true) {
        $p1 = Read-Host "Enter new password  " -AsSecureString
        $p2 = Read-Host "Confirm new password" -AsSecureString
        
        $plain1 = [System.Net.NetworkCredential]::new("", $p1).Password
        $plain2 = [System.Net.NetworkCredential]::new("", $p2).Password

        if ($plain1 -eq $plain2 -and $plain1.Length -gt 0) { return $p1 }
        Write-Host "[-] Passwords do not match or are empty!" -ForegroundColor Red
    }
}

# Main
$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
Write-Host "[*] Target: $(if ($isDC) {'Domain Controller'} else {'Local Machine'})" -ForegroundColor Cyan
if ($Test) {
    Write-Host "[!] TEST RUN: No changes will be made." -ForegroundColor Yellow
} else {
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[!!] WARNING: You must run this script as an Administrator!" -ForegroundColor Red
    }
}

$results = @()
$staticSecurePass = $null
$staticPlainPass = $null

if (-not $Random) {
    $staticSecurePass = Get-UserResponsePassword
    $staticPlainPass = [System.Net.NetworkCredential]::new("", $staticSecurePass).Password
}

if ($isDC) {
    $rawNames = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
} else {
    $rawNames = Get-LocalUser | Select-Object -ExpandProperty Name
}

$includeRegex = $Users -join "|"
$excludeRegex = $Exclude -join "|"

$finalList = $rawNames | Where-Object {
    if ($Users -and $_ -notmatch $includeRegex) { return $false }
    if ($_ -match $excludeRegex) {
        Write-Host "[-] Skipping (Excluded): $_" -ForegroundColor Magenta
        return $false
    }
    return $true
}

foreach ($user in $finalList) {
    if ($Random) {
        $currentPlain = Get-GeneratedPassword
        $currentSecure = ConvertTo-SecureString $currentPlain -AsPlainText -Force
    } else {
        $currentPlain = $staticPlainPass
        $currentSecure = $staticSecurePass
    }

    try {
        if (-not $Test) {
            if ($isDC) {
                # Powershell command has some issues here
                #Set-ADAccountPassword -Identity $user -NewPassword $currentSecure -Reset
                net user $user $currentPlain /domain > $null #2>&1
            } else {
                #Set-LocalUser -Name $user -Password $currentSecure
                net user $user $currentPlain > $null #2>&1
            }

            if ($LASTEXITCODE -ne 0) {
                # Stderr not redirected to null so if problem arises should be able to see issue
                throw "Error Code $LASTEXITCODE"
            }

            Write-Host "[+] Reset: $user" -ForegroundColor Green
        } else {
            Write-Host "[=] TEST: $user" -ForegroundColor DarkGreen
        }

        $results += [PSCustomObject]@{
            Username = $user
            Password = $currentPlain
            Time     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    } catch {
        Write-Host "[!] Failed: $user; $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($OutputLevel -ne "None" -and $results.Count -gt 0) {
    $path = ".\affectedUsers_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"
    if ($OutputLevel -eq "UsernameOnly") {
        $results | Select-Object Username, Time | Export-Csv -Path $path -NoTypeInformation
    } else {
        $results | Export-Csv -Path $path -NoTypeInformation
    }
    Write-Host "[*] Log written to: $path" -ForegroundColor Cyan
}
