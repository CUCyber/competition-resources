# Get-Info.ps1
# Author: Dylan Harvey
# Gathers some basic level information regarding the machine and what services its running. 
# Manual Version - Useful for injects/enumeration, writes to output file.

$outFile = ".\info.txt"

# Gather System Info
$hostname = $env:COMPUTERNAME
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
$domainRoleText = @("Standalone Workstation", "Member Workstation", "Standalone Server", "Member Server", "Backup Domain Controller", "Primary Domain Controller")[$domainRole]
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
$installedRoles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName
$runningServices = Get-Service | Where-Object { $_.Status -eq "Running" } | Select-Object Name, DisplayName
$passwordPolicy = Get-ADDefaultDomainPasswordPolicy

$info = @"
=== Machine Info === 
Hostname: $hostname
Domain Role: $domainRoleText
OS Information: $($os.Caption) ($($os.Version), $($os.OSArchitecture))

=== Installed Roles & Features === 
$($installedRoles.DisplayName -join "`n")

=== Running Important Services ===
$($runningServices.DisplayName -join "`n")

=== Password Policy ===
$($passwordPolicy | Format-List | Out-String)
"@


Write-Host $info
$info | Out-File $outFile
Write-Host "Info saved to '$outFile'" -ForegroundColor Green
