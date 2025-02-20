# Info.ps1
# Author: Dylan Harvey
# Gathers some basic level information regarding the machine and what services its running. 
# Automation Version - Useful for injects/enumeration.

# Gather System Info
$hostname = $env:COMPUTERNAME
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
$domainRoleText = @("Standalone Workstation", "Member Workstation", "Standalone Server", "Member Server", "Backup Domain Controller", "Primary Domain Controller")[$domainRole]
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
$installedRoles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName
$runningServices = Get-WmiObject Win32_Service | Where-Object { $_.State -eq "Running" } | Select-Object Name, DisplayName, ProcessId, PathName
$openPorts = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object LocalAddress, LocalPort, OwningProcess, @{Name="ExecutablePath"; Expression={(Get-WmiObject Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue).ExecutablePath}}
$establishedConnections = Get-NetTCPConnection | Where-Object { $_.State -match "^Established" } | Select-Object LocalAddress, LocalPort, OwningProcess, @{Name="ExecutablePath"; Expression={(Get-WmiObject Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue).ExecutablePath}}
$sharedFolders = Get-SmbShare | Select-Object Name, Path, Description

$passwordPolicy = Get-ADDefaultDomainPasswordPolicy

$info = @"
=== Machine Info === 
Hostname: $hostname
Domain Role: $domainRoleText
OS Information: $($os.Caption) ($($os.Version), $($os.OSArchitecture))

=== Installed Roles & Features === 
$($installedRoles.DisplayName -join "`n")

=== Running Services ===
$($runningServices.DisplayName -join "`n")

=== Listening Ports ===
$($openPorts | Format-Table -AutoSize | Out-String)

=== Established Connections ===
$($establishedConnections | Format-Table -AutoSize | Out-String)

=== Shared Folders ===
$($sharedFolders | Out-String)
"@

Write-Host $info
