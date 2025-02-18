# Info.ps1
# Author: Dylan Harvey
# Gathers some basic level information regarding the machine and what services its running. 
# Useful for injects/enumeration.

$outFile = ".\info.txt"

# Gather System Info
$hostname = $env:COMPUTERNAME
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
$domainRoleText = @("Standalone Workstation", "Member Workstation", "Standalone Server", "Member Server", "Backup Domain Controller", "Primary Domain Controller")[$domainRole]
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
$installedRoles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName
$services = Get-Service | Where-Object { $_.Status -eq "Running" } | Select-Object Name, DisplayName

# Check for key services
$importantServices = @("W3SVC", "DNS", "DHCPServer", "ADWS", "NTDS", "MSSQLSERVER", "WinRM", "Spooler")
$runningServices = Get-Service | Where-Object { $_.Name -in $importantServices -and $_.Status -eq "Running" } | Select-Object Name, DisplayName

# Group Policy Info
$passwordPolicy = Get-ADDefaultDomainPasswordPolicy
$gpResults = gpresult /h .\gpresult.html

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


$info | Out-File $outFile
Write-Host "Info saved to '$outFile'"
Remove-Item .\gpresult.html
